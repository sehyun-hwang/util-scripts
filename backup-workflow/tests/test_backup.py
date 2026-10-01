import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
BACKUP_WORKFLOW = REPO / 'backup-workflow'
INVENTORY_MAKEFILE = BACKUP_WORKFLOW / 'backup.mk'
WIP = BACKUP_WORKFLOW / 'backup-git-wip.sh'
WORKFLOW = BACKUP_WORKFLOW / 'backup-workflow.sh'


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
        return subprocess.run(['bash', str(WIP), '--git', str(self.home), *args],
                              cwd=self.out, env=self.env, check=True,
                              capture_output=True, text=True)

    def test_removed_options_rejected(self):
        for script, option in [(WIP, '--home'), (WORKFLOW, '--home'), (WORKFLOW, '--repo')]:
            with self.subTest(script=script, option=option):
                result = subprocess.run(['bash', str(script), option, str(self.home)],
                                        env=self.env, capture_output=True)
                self.assertNotEqual(result.returncode, 0)

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
        result = subprocess.run(['bash', str(WIP), '--git', str(self.home)],
                                cwd=self.out, env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(list(self.out.iterdir()), [])

    def test_unknown_remote_uses_local_folder(self):
        self.git('remote', 'remove', 'origin')
        (self.repo / 'tracked').write_text('local changes')
        for mode in ('missing', 'ambiguous', 'unsupported'):
            with self.subTest(mode=mode):
                if mode == 'ambiguous':
                    self.git('remote', 'add', 'first', 'https://example.invalid/first.git')
                    self.git('remote', 'add', 'second', 'https://example.invalid/second.git')
                elif mode == 'unsupported':
                    self.git('remote', 'add', 'origin', '/local/repository')
                self.run_wip()
                snapshot = next(self.out.glob('*/_local/project/main/tracked'))
                self.assertEqual(snapshot.read_text(), 'local changes')
        self.assertFalse(list(self.out.glob('*/example.invalid')))

    def test_local_folder_collision_rejected(self):
        self.git('remote', 'remove', 'origin')
        other = self.home / 'nested/project'
        shutil.copytree(self.repo, other)
        (self.repo / 'tracked').write_text('changed')
        result = subprocess.run(['bash', str(WIP), '--git', str(self.home)],
                                cwd=self.out, env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(list(self.out.iterdir()), [])

    def test_single_non_origin_remote_retains_identity(self):
        self.git('remote', 'rename', 'origin', 'upstream')
        (self.repo / 'tracked').write_text('changed')
        self.run_wip()
        self.assertTrue(list(self.out.glob('*/example.invalid/team/project/main/tracked')))
        self.assertFalse(list(self.out.glob('*/_local')))

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

    def workflow_fixture(self, recipe):
        bundle = self.base / 'standalone bundle'
        bundle.mkdir()
        for source in (WORKFLOW, WIP):
            shutil.copyfile(source, bundle / source.name)
        (bundle / 'backup.mk').write_text(recipe)
        return ['bash', str(bundle / WORKFLOW.name), '--destination', str(self.out),
                '--git', str(self.home)]

    def test_inventory_failure_stops_snapshot(self):
        cmd = self.workflow_fixture('backup:\n\tfalse\n')
        (self.repo / 'tracked').write_text('changed')
        result = subprocess.run(cmd, cwd=self.base, env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.out.iterdir()), [])

    def test_inventory_then_wip_without_checkout_or_staging(self):
        cmd = self.workflow_fixture(
            'backup:\n\tmkdir -p "$(BACKUP_DIR)"\n'
            '\tprintf inventory > "$(BACKUP_DIR)/inventory.txt"\n')
        (self.repo / 'tracked').write_text('changed')
        subprocess.run(cmd + ['--dry-run'], cwd=self.base, env=self.env,
                       check=True, capture_output=True)
        self.assertEqual(list(self.out.iterdir()), [])
        subprocess.run(cmd, cwd=self.base, env=self.env, check=True, capture_output=True)
        inventory = next(self.out.glob('*/_system/backup/inventory.txt'))
        self.assertEqual(inventory.read_text(), 'inventory')
        self.assertFalse((self.base / 'backup').exists())
        self.assertFalse((self.base / 'standalone bundle/backup').exists())
        self.assertTrue(list(self.out.glob('*/example.invalid/team/project/main/tracked')))

    def test_dry_run_does_not_create_destination(self):
        self.out = self.base / 'missing destination'
        cmd = self.workflow_fixture('backup:\n\tfalse\n')
        subprocess.run(cmd + ['--dry-run'], cwd=self.base, env=self.env,
                       check=True, capture_output=True)
        self.assertFalse(self.out.exists())


if __name__ == '__main__':
    unittest.main()
