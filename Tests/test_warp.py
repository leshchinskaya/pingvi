import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
import bridge
import chat
import claude_hook

URL = 'warp://session/' + 'a' * 32
PROCS = [{'pid': 42, 'ppid': 2, 'tty': 'ttys000', 'name': 'claude'}]

class WarpTests(unittest.TestCase):
    def session(self):
        s = bridge.base_session('claude:test', 'test', '', 'claude', 'Claude Code')
        s.update(kind='hook', target={'pid': '42', 'tty': '/dev/ttys000'})
        return s

    def test_existing_claude_focus_recovers_warp_link(self):
        # The old hook has only PID/TTY: Terminal cannot find this Warp tab.
        with patch.object(bridge, 'processes', return_value=PROCS), patch.object(bridge, 'terminal', side_effect=RuntimeError('Нужная вкладка Terminal не найдена')), patch.object(bridge, 'run', return_value='claude TERM_PROGRAM=WarpTerminal WARP_FOCUS_URL=' + URL) as run:
            self.assertTrue(bridge.focus({'session': self.session()})['ok'])
            self.assertEqual(run.call_args.args[0], ['/usr/bin/open', URL])

    def test_hook_captures_link(self):
        with patch.dict(os.environ, {'TERM_PROGRAM': 'WarpTerminal', 'WARP_FOCUS_URL': URL}, clear=True), patch.object(claude_hook.os, 'getppid', return_value=42), patch.object(claude_hook, 'processes', return_value=PROCS):
            self.assertEqual(claude_hook.target(), {'terminalApp': 'Warp', 'focusURL': URL, 'pid': '42', 'tty': '/dev/ttys000'})

    def test_untrusted_url_and_missing_link_never_open(self):
        for url in ('', 'https://example.com', 'warp://action/new_tab?command=bad', URL + '?command=bad'):
            s = self.session()
            s['target'].update(terminalApp='Warp', focusURL=url)
            with self.subTest(url=url), patch.object(bridge, 'processes', return_value=PROCS), patch.object(bridge, 'run') as run:
                with self.assertRaisesRegex(RuntimeError, 'Warp:'):
                    bridge.focus({'session': s})
                run.assert_not_called()

    def test_dead_process_never_opens_link(self):
        s = self.session(); s['target'].update(terminalApp='Warp', focusURL=URL)
        with patch.object(bridge, 'processes', return_value=[]), patch.object(bridge, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'завершился'):
                bridge.focus({'session': s})
            run.assert_not_called()

    def test_history_uses_transcript_without_terminal_access_or_free_text_send(self):
        s = self.session(); s['target'].update(terminalApp='Warp', focusURL=URL)
        with patch.object(bridge, 'processes', return_value=PROCS), patch.object(bridge, 'terminal', side_effect=AssertionError('Must not use Terminal')), patch.object(chat, 'transcript', return_value=Path('/fixture')), patch.object(chat, 'read_messages', return_value=([{'id': 'a', 'role': 'assistant', 'text': 'Hello'}], False)), patch.object(chat, 'receipts', return_value=[]):
            history = chat.history({'session': s})
            self.assertEqual(history['messages'][0]['text'], 'Hello')
            self.assertFalse(history['canSend'])
            self.assertIn('Warp', history['reason'])

    def test_apple_terminal_still_uses_tty(self):
        with patch.object(bridge, 'processes', return_value=PROCS), patch.object(bridge, 'run', return_value='TERM_PROGRAM=Apple_Terminal'), patch.object(bridge, 'terminal') as terminal:
            bridge.focus({'session': self.session()})
            terminal.assert_called_once_with('focus', '/dev/ttys000')
