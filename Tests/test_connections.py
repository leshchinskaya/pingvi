import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
import bridge
import claude_hook

class ConnectionsTests(unittest.TestCase):
    def test_explicit_executable_path_with_spaces(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'my herdr'
            path.write_text('#!/bin/sh\necho test\n'); path.chmod(0o700)
            self.assertEqual(bridge.find_executable('herdr', str(path)), str(path))
            self.assertEqual(bridge.run([str(path)]).strip(), 'test')
            with self.assertRaises(RuntimeError):
                bridge.find_executable('herdr', str(path) + '-missing')

    def test_install_update_and_uninstall_preserve_other_hooks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / 'claude' / 'settings.json'
            config.parent.mkdir()
            other = {'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': 'echo other'}]}
            config.write_text(json.dumps({'theme': 'dark', 'hooks': {'PreToolUse': [other]}}))
            with patch.dict(os.environ, {'CLAUDE_CONFIG_DIR': str(config.parent)}), patch.object(claude_hook, 'ROOT', root / 'data'):
                claude_hook.install(); claude_hook.install()
                self.assertTrue(claude_hook.installation_status())
                settings = json.loads(config.read_text())
                self.assertEqual(len(settings['hooks']['PermissionRequest']), 1)
                claude_hook.uninstall()
                self.assertFalse(claude_hook.installation_status())
                settings = json.loads(config.read_text())
                self.assertEqual(settings['theme'], 'dark')
                self.assertEqual(settings['hooks']['PreToolUse'], [other])
                self.assertEqual(len(list(config.parent.glob('settings.json.attention-backup-*'))), 3)

    def test_command_timeout_returns_control(self):
        import subprocess
        with self.assertRaises(subprocess.TimeoutExpired):
            bridge.run(['/bin/sh', '-c', 'sleep 10'], timeout=0.05)
        self.assertEqual(bridge.run(['/bin/echo', 'recovered']).strip(), 'recovered')

    def test_broken_candidate_does_not_hide_working_cli(self):
        with patch.object(bridge, 'executable_candidates', return_value=['/broken', '/working']), patch.object(bridge, 'run', side_effect=[RuntimeError('missing binary'), 'codex 1.0']):
            self.assertEqual(bridge.working_executable('codex'), ('/working', 'codex 1.0'))

    def test_explicit_broken_cli_does_not_fall_back_silently(self):
        with patch.dict(bridge.CLI_PATHS, {'codex': '/chosen'}), patch.object(bridge, 'find_executable', return_value='/chosen'), patch.object(bridge, 'run', side_effect=RuntimeError('broken')) as run:
            with self.assertRaises(RuntimeError):
                bridge.working_executable('codex')
            self.assertEqual(run.call_count, 1)

    def test_bad_herdr_path_does_not_block_other_diagnostics(self):
        with patch.dict(bridge.CLI_PATHS, {'herdr': '/missing/herdr'}), patch.object(bridge, 'executable_candidates', return_value=['/working']), patch.object(bridge, 'run', return_value='version 1'), patch.object(claude_hook, 'installation_status', return_value=False):
            checks = {c['name']: c for c in bridge.diagnostics()['checks']}
            self.assertFalse(checks['herdr']['ready'])
            self.assertTrue(checks['claude']['ready'])

    def test_outdated_hook_is_not_reported_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.dict(os.environ, {'CLAUDE_CONFIG_DIR': str(root / 'claude')}), patch.object(claude_hook, 'ROOT', root / 'data'):
                claude_hook.install()
                self.assertTrue(claude_hook.installation_status())
                (root / 'data/integration/bridge.py').write_text('# obsolete helper')
                self.assertFalse(claude_hook.installation_status())
                claude_hook.install()
                self.assertTrue(claude_hook.installation_status())
