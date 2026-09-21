import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

NIX_DIR = Path(__file__).resolve().parents[2]
REPO = NIX_DIR.parent
SCRIPTS = NIX_DIR / 'assets' / 'scripts'
INVENTORY_MAKEFILE = NIX_DIR / 'assets' / 'backup.mk'
WIP = SCRIPTS / 'backup-git-wip.sh'
WORKFLOW = SCRIPTS / 'backup-workflow.sh'


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / 'home'
        self.home.mkdir()
        self.out = self.base / 'output'
        self.out.mkdir()
        self.env = dict(os.environ, HOME=str(self.home))
        self.repo = self.home / 'project'
        self.repo.mkdir()
        self.git('init', '-b', 'main')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'user.name', 'Test')
        self.git('remote', 'add', 'origin', 'https://example.invalid/team/project.git')
        (self.repo / 'tracked').write_text('baseline\n')
        self.git('add', '.')
        self.git('commit', '-m', 'baseline')

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.repo), *args], env=self.env,
                              check=True, capture_output=True, text=True)

    def run_wip(self, *args):
        return subprocess.run(['bash', str(WIP), '--home', str(self.home), *args],
                              cwd=self.out, env=self.env, check=True,
                              capture_output=True, text=True)

    def test_wip_script_unchanged(self):
        self.assertEqual(hashlib.sha256(WIP.read_bytes()).hexdigest(),
                         '13aeccfbb8aa49eb6d177f0a0d1213446b156928ee2ec5466a5167585450234e')

    def test_snapshot_retirement_and_dry_run(self):
        (self.repo / 'tracked').write_text('staged\n')
        self.git('add', 'tracked')
        (self.repo / 'tracked').write_text('working tree\n')
        (self.repo / 'space name').write_text('untracked\n')
        (self.repo / '.gitignore').write_text('ignored\n')
        (self.repo / 'ignored').write_text('excluded\n')
        self.run_wip('--dry-run')
        self.assertEqual(list(self.out.iterdir()), [])
        self.run_wip()
        snapshot = next(self.out.glob('*/example.invalid/team/project/main'))
        self.assertEqual((snapshot / 'tracked').read_text(), 'working tree\n')
        self.assertTrue((snapshot / 'space name').exists())
        self.assertFalse((snapshot / 'ignored').exists())
        (self.repo / 'space name').unlink()
        self.run_wip()
        self.assertTrue((snapshot / 'space name.backup').exists())
        self.run_wip()
        self.assertFalse((snapshot / 'space name.backup.backup').exists())

    def test_branch_encoding_symlinks_and_clean_retention(self):
        self.git('checkout', '-b', 'feature/test')
        (self.repo / 'tracked').write_text('snapshot\n')
        (self.repo / 'link').symlink_to('tracked')
        self.run_wip()
        snapshot = next(self.out.glob('*/example.invalid/team/project/feature%2Ftest'))
        self.assertTrue((snapshot / 'link').is_symlink())
        self.assertEqual(os.readlink(snapshot / 'link'), 'tracked')
        self.git('add', '.')
        self.git('commit', '-m', 'now clean')
        self.run_wip()
        self.assertEqual((snapshot / 'tracked').read_text(), 'snapshot\n')

    def test_destination_collision_rejected(self):
        other = self.home / 'duplicate'
        shutil.copytree(self.repo, other)
        (self.repo / 'tracked').write_text('changed')
        result = subprocess.run(['bash', str(WIP), '--home', str(self.home)],
                                cwd=self.out, env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(list(self.out.iterdir()), [])

    def test_make_backup_refreshes_configs_without_venv(self):
        checkout = self.base / 'inventory-checkout'
        checkout.mkdir()
        shutil.copyfile(INVENTORY_MAKEFILE, checkout / 'backup.mk')
        ssh = self.home / '.ssh'
        ssh.mkdir()
        (ssh / 'config').write_text('Host test\n')
        settings = self.home / 'Library/Application Support/Code/User'
        settings.mkdir(parents=True)
        (settings / 'settings.json').write_text('{"test": true}\n')
        fakebin = self.base / 'bin'
        fakebin.mkdir()
        for name, output in [('brew', 'brew-item'), ('pnpm', 'pnpm-item'), ('yarn', 'yarn-item')]:
            p = fakebin / name
            p.write_text('#!/bin/sh\nprintf "%s\\n" "' + output + '"\n')
            p.chmod(0o755)
        env = dict(self.env, PATH=str(fakebin) + os.pathsep + self.env['PATH'])
        result = subprocess.run(['make', '-C', str(checkout), '-f', 'backup.mk', 'backup'], env=env,
                                check=True, capture_output=True, text=True)
        self.assertNotIn('PYTHON_VENV', result.stdout)
        self.assertEqual((checkout / 'backup/ssh-config.txt').read_text(), 'Host test\n')
        self.assertEqual((checkout / 'backup/vscode.jsonc').read_text(), '{"test": true}\n')
        (ssh / 'config').write_text('Host changed\n')
        subprocess.run(['make', '-C', str(checkout), '-f', 'backup.mk', 'backup'], env=env,
                       check=True, capture_output=True)
        self.assertEqual((checkout / 'backup/ssh-config.txt').read_text(), 'Host changed\n')

    def test_inventory_destination_rejected(self):
        checkout = self.base / 'unsafe-checkout'
        makefile = checkout / 'nix/assets/backup.mk'
        makefile.parent.mkdir(parents=True)
        makefile.write_text('backup:\n\tfalse\n')
        result = subprocess.run(['bash', str(WORKFLOW), '--repo', str(checkout),
                                 '--destination', str(checkout / 'backup/nested')],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('Destination cannot be inside', result.stderr)
        self.assertFalse((checkout / 'backup').exists())

    def test_inventory_failure_stops_snapshot(self):
        checkout = self.base / 'broken-checkout'
        makefile = checkout / 'nix/assets/backup.mk'
        makefile.parent.mkdir(parents=True)
        makefile.write_text('backup:\n\tfalse\n')
        result = subprocess.run(['bash', str(WORKFLOW), '--repo', str(checkout),
                                 '--destination', str(self.out),
                                 '--home', str(self.home)], env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.out.iterdir()), [])

    def test_inventory_then_wip(self):
        checkout = self.base / 'checkout'
        makefile = checkout / 'nix/assets/backup.mk'
        makefile.parent.mkdir(parents=True)
        makefile.write_text('backup:\n\tmkdir -p backup\n\tprintf inventory > backup/inventory.txt\n')
        (self.repo / 'tracked').write_text('changed')
        cmd = ['bash', str(WORKFLOW), '--repo', str(checkout),
               '--destination', str(self.out), '--home', str(self.home)]
        subprocess.run(cmd + ['--dry-run'], env=self.env, check=True, capture_output=True)
        self.assertFalse((checkout / 'backup').exists())
        subprocess.run(cmd, env=self.env, check=True, capture_output=True)
        inventory = next(self.out.glob('*/_system/backup/inventory.txt'))
        self.assertEqual(inventory.read_text(), 'inventory')
        self.assertTrue(list(self.out.glob('*/example.invalid/team/project/main/tracked')))


if __name__ == '__main__':
    unittest.main()
