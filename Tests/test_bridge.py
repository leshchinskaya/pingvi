import importlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
import bridge
import claude_hook

APPROVAL = '''Would you like to run the following command?
  $ touch /tmp/attention-test
› 1. Yes, proceed (y)
  2. Yes, and don't ask again (p)
  3. No, and tell Codex what to do differently (esc)
  Press enter to confirm or esc to cancel'''

class ParserTests(unittest.TestCase):
    def test_text_reply_submits_instead_of_becoming_a_pasted_newline(self):
        for target in ({'pane': 'test'}, {'tty': '/dev/test', 'pid': '123'}):
            with self.subTest(target=target):
                screen = 'Which option do you prefer?\n› Ask Codex to do anything\n  gpt-6 medium · ~'
                s = bridge.base_session('x', 'x', '', 'codex', 'herdr')
                s.update(bridge.parse_screen(screen, 'codex')); s['target'] = target
                # Codex suppresses Enter for 120 ms after a burst of plain characters.
                # Model the receiving composer rather than merely checking bytes were written.
                now = [0.0]; suppress_until = [0.0]; draft = ['']; submitted = []
                def receive(args, **kwargs):
                    action = args[-3] if args[0] == '/usr/bin/osascript' else args[2]
                    if action == 'read': return screen
                    if action in ('send-text', 'send'):
                        text = args[-1]
                        if text.startswith('\x1b[200~') and text.endswith('\x1b[201~'):
                            draft[0] += text[6:-6]
                        else:
                            draft[0] += text
                            suppress_until[0] = now[0] + 0.120
                    if action in ('send-keys', 'send'):
                        if now[0] < suppress_until[0]: draft[0] += '\n'
                        else: submitted.append(draft[0]); draft[0] = ''
                    return 'ok'
                def advance(seconds): now[0] += seconds
                with patch.object(bridge, 'processes', return_value=[{'pid': 123, 'tty': 'test', 'name': 'codex'}]), patch.object(bridge, 'herdr_json', return_value={'pane': {'agent': 'codex'}}), patch.object(bridge, 'run', side_effect=receive), patch.object(bridge.time, 'sleep', side_effect=advance):
                    bridge.reply({'session': s, 'answers': {'text': 'Второй вариант'}})
                self.assertEqual(submitted, ['Второй вариант'])
                self.assertEqual(draft[0], '')

    def test_only_live_approval(self):
        self.assertTrue(bridge.parse_screen(APPROVAL, 'codex')['canReply'])
        self.assertFalse(bridge.parse_screen('Here is a plan:\n1. Yes\n2. No', 'codex')['canReply'])
        self.assertFalse(bridge.parse_screen(APPROVAL + '\n• Working (esc to interrupt)', 'codex')['canReply'])

    def test_changed_screen_never_sends(self):
        s = bridge.base_session('x', 'x', '', 'codex', 'herdr')
        s.update(bridge.parse_screen(APPROVAL, 'codex')); s['target'] = {'pane': 'test'}
        with patch.object(bridge, 'herdr_json', return_value={'pane': {'agent': 'codex'}}), patch.object(bridge, 'run', return_value=APPROVAL + '\nchanged') as run:
            with self.assertRaisesRegex(RuntimeError, 'Экран изменился'):
                bridge.reply({'session': s, 'answer': '1'})
            self.assertEqual(run.call_count, 1)

    def test_response_not_in_options_never_sends(self):
        s = bridge.base_session('x', 'x', '', 'codex', 'herdr')
        s.update(bridge.parse_screen(APPROVAL, 'codex')); s['target'] = {'pane': 'test'}
        with patch.object(bridge, 'herdr_json', return_value={'pane': {'agent': 'codex'}}), patch.object(bridge, 'run', return_value=APPROVAL) as run:
            with self.assertRaises(RuntimeError): bridge.reply({'session': s, 'answer': 'rm anything'})
            self.assertEqual(run.call_count, 1)

class HookTests(unittest.TestCase):
    def test_structured_answers_preserve_original_questions(self):
        event = {'hook_event_name': 'PreToolUse', 'tool_name': 'AskUserQuestion', 'tool_input': {'questions': [{'question': 'Which?', 'options': [{'label': 'A'}]}]}}
        result = claude_hook.response_for(event, '', {'Which?': 'A'})['hookSpecificOutput']
        self.assertEqual(result['updatedInput']['questions'], event['tool_input']['questions'])
        self.assertEqual(result['updatedInput']['answers'], {'Which?': 'A'})
        with self.assertRaises(ValueError): claude_hook.response_for(event, '', {})

    def test_live_hook_roundtrip_and_duplicate_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            bridge.atomic(root / 'app-heartbeat.json', {'time': time.time()})
            event = {'session_id': 'test', 'hook_event_name': 'PermissionRequest', 'tool_name': 'Bash', 'tool_input': {'command': 'true'}, 'cwd': d, 'tool_use_id': 'tool1'}
            p = subprocess.Popen([sys.executable, str(Path(claude_hook.__file__))], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env={**os.environ, 'ATTENTION_DATA': d})
            p.stdin.write(json.dumps(event)); p.stdin.close()
            path = root / 'hooks' / (bridge.digest('claude:test') + '.json')
            try:
                for _ in range(60):
                    if path.exists(): break
                    time.sleep(.05)
                session = json.loads(path.read_text())
                with patch.object(bridge, 'ROOT', root):
                    self.assertFalse(bridge.reply({'session': session, 'answer': 'allow'})['confirmed'])
                    with self.assertRaises((FileExistsError, RuntimeError)):
                        bridge.reply({'session': session, 'answer': 'allow'})
                p.wait(timeout=5)
                result = json.loads(p.stdout.read())
                self.assertEqual(result['hookSpecificOutput']['decision']['behavior'], 'allow')
                self.assertEqual(json.loads(path.read_text())['status'], 'unconfirmed')
            finally:
                if p.poll() is None: p.kill(); p.wait()
                p.stdout.close()

    def test_expired_hook_no_reply(self):
        with tempfile.TemporaryDirectory() as d, patch.object(bridge, 'ROOT', Path(d)):
            s = {'id': 'test', 'kind': 'hook', 'token': 'dead', 'status': 'waiting', 'heartbeat': time.time() - 60}
            bridge.atomic(Path(d) / 'hooks' / (bridge.digest('test') + '.json'), s)
            with self.assertRaises(RuntimeError): bridge.reply({'session': s, 'answer': 'allow'})

if __name__ == '__main__': unittest.main()
