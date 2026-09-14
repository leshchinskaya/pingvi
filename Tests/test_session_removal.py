import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
import bridge as b
import claude_hook


class SessionRemovalTests(unittest.TestCase):
    def test_successful_empty_inventory_confirms_removal(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b, 'ROOT', Path(directory)), patch.object(b, 'processes', return_value=[]), patch.object(b, 'herdr_json', return_value={'panes': []}):
            snapshot = b.snapshot({})
            self.assertEqual(snapshot['sessions'], [])
            self.assertIn('herdr', snapshot['completeSources'])
            self.assertNotIn('Terminal', snapshot['completeSources'])

    def test_failed_inventory_does_not_confirm_removal(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b, 'ROOT', Path(directory)), patch.object(b, 'processes', return_value=[]), patch.object(b, 'herdr_json', side_effect=RuntimeError('unavailable')):
            snapshot = b.snapshot({})
            self.assertNotIn('herdr', snapshot['completeSources'])
            self.assertTrue(snapshot['errors'])

    def test_deleted_pane_does_not_reappear_from_hook_record(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b, 'ROOT', Path(directory)), patch.object(b, 'processes', return_value=[]), patch.object(b, 'herdr_json', return_value={'panes': []}):
            hook = b.base_session('claude:test', 'Test', '', 'claude', 'Claude Code')
            hook.update(kind='hook', status='done', target={'pane': 'deleted'})
            b.atomic(Path(directory) / 'hooks/test.json', hook)
            self.assertEqual(b.snapshot({})['sessions'], [])

    def test_claude_session_end_removes_hook_record(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(claude_hook, 'ROOT', Path(directory)):
            path = Path(directory) / 'hooks' / (b.digest('claude:test') + '.json')
            b.atomic(path, {'id': 'claude:test'})
            claude_hook.handle({'session_id': 'test', 'hook_event_name': 'SessionEnd'})
            self.assertFalse(path.exists())

    def test_failed_herdr_keeps_hook_with_unverified_pane(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b, 'ROOT', Path(directory)), patch.object(b, 'processes', return_value=[]), patch.object(b, 'herdr_json', side_effect=RuntimeError('unavailable')):
            hook = b.base_session('claude:test', 'Test', '', 'claude', 'Claude Code')
            hook.update(kind='hook', status='done', target={'pane': 'unverified'})
            b.atomic(Path(directory) / 'hooks/test.json', hook)
            self.assertEqual([s['id'] for s in b.snapshot({})['sessions']], ['claude:test'])

if __name__ == '__main__':
    unittest.main()
