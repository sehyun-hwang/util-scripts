import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'swiftbar_status', Path(__file__).resolve().parents[1] / 'swiftbar/status.1m.py')
status = importlib.util.module_from_spec(spec)
spec.loader.exec_module(status)


class TimeMachineTests(unittest.TestCase):
    def test_raw_status_only(self):
        raw = 'Backup session status:\n{\n    Running = 0;\n}\n'
        with patch.object(status, 'run', return_value=subprocess.CompletedProcess([], 0, raw)) as run:
            self.assertEqual(status.tm_section(), raw)
        run.assert_called_once_with(['/usr/bin/tmutil', 'status'], timeout=5)

    def test_idle_status_with_nonzero_exit(self):
        raw = 'Backup session status:\n{\n    Percent = "-1";\n    Running = 0;\n}\n'
        with patch.object(status, 'run', return_value=subprocess.CompletedProcess([], 80, raw)):
            self.assertEqual(status.tm_section(), raw)

    def test_failure(self):
        for result in (None, subprocess.CompletedProcess([], 1, ''),
                       subprocess.CompletedProcess([], 0, '   \n')):
            with self.subTest(result=result), patch.object(status, 'run', return_value=result):
                self.assertIsNone(status.tm_section())

    def test_raw_menu_output(self):
        output = io.StringIO()
        with patch.object(status, 'CACHE_DIR'), patch.object(status, 'aws_section', return_value=None), \
                patch.object(status, 'resilio_section', return_value=None), \
                patch.object(status, 'tm_section', return_value='    Running = 1;\na|b\n'), \
                patch.object(status, 'tm_latest_backup', return_value='/backup/2026-09-29'), \
                contextlib.redirect_stdout(output):
            status.main()
        self.assertIn('--    Running = 1; | trim=false', output.getvalue())
        self.assertIn('--a¦b | trim=false', output.getvalue())
        self.assertIn('--Last backup: /backup/2026-09-29', output.getvalue())

    def test_latest_backup_live(self):
        with patch.object(status, 'run', return_value=subprocess.CompletedProcess([], 0, '/backup/latest\n')) as run:
            self.assertEqual(status.tm_latest_backup(), '/backup/latest')
        run.assert_called_once_with(['/usr/bin/tmutil', 'latestbackup'], timeout=5)

    def test_latest_backup_unavailable(self):
        for result in (None, subprocess.CompletedProcess([], 1, 'error'),
                       subprocess.CompletedProcess([], 0, '')):
            with self.subTest(result=result), patch.object(status, 'run', return_value=result):
                self.assertIsNone(status.tm_latest_backup())

    def test_resilio_queries_each_time_without_cache(self):
        results = [subprocess.CompletedProcess([], 0, '{"folders": []}'),
                   subprocess.CompletedProcess([], 0, '{"folders": [{"path": "/data"}]}')]
        with patch.object(status, 'run', side_effect=results) as run, \
                patch.object(status, 'CACHE_DIR') as cache:
            self.assertEqual(status.resilio_section(), [])
            self.assertEqual(status.resilio_section(), [{'path': '/data', 'paused': False}])
            self.assertEqual(run.call_count, 2)
            self.assertEqual(cache.mock_calls, [])


if __name__ == '__main__':
    unittest.main()
