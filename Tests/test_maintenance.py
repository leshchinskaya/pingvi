import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
import bridge as b
import chat
import maintenance

class MaintenanceTests(unittest.TestCase):
    def test_cleanup_keeps_pending_and_duplicate_protection(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b, 'ROOT', Path(directory)):
            records = {}
            for state in ('observed', 'checked', 'uncertain', 'submitted'):
                ident = str(uuid.uuid4())
                records[state] = {'id': ident, 'kind': 'send', 'sessionKey': 'pane', 'state': state, 'time': 1, 'text': 'private text', 'scope': '/private/project', 'baselineIDs': ['secret'], 'error': 'sensitive error'}
                b.atomic(chat.request_path(ident), records[state])
            with maintenance.guard(exclusive=True):
                self.assertEqual(maintenance.clean(), {'cleaned': 2})
            for state, record in records.items():
                saved = json.loads(chat.request_path(record['id']).read_text())
                if state in ('uncertain', 'submitted'):
                    self.assertEqual(saved, record)
                else:
                    self.assertTrue(saved['redacted'])
                    self.assertEqual(saved['text'], '')
                    self.assertNotIn('scope', saved)
                    self.assertNotIn('error', saved)
            session = {'id': 's', 'target': {'pane': 'pane'}}
            with patch.object(chat, 'history', side_effect=AssertionError('Duplicate must not reach transport')):
                receipt = chat.send({'session': session, 'text': 'private text', 'requestID': records['observed']['id']})
                self.assertTrue(receipt['redacted'])
            self.assertEqual(len(chat.receipts(session)), 2)
            self.assertEqual(maintenance.status()['pending'], 2)
            self.assertEqual(maintenance.status()['processed'], 0)
            self.assertEqual(maintenance.clean(), {'cleaned': 0})

    def test_cleanup_does_not_follow_symlinks_or_touch_other_records(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b, 'ROOT', Path(directory) / 'data'):
            external = Path(directory) / 'outside.json'
            external.write_text('{"kind":"send","state":"checked","text":"keep"}')
            requests = b.ROOT / 'chat-requests'; requests.mkdir(parents=True)
            (requests / 'link.json').symlink_to(external)
            (requests / 'broken.json').write_text('{')
            b.atomic(requests / 'create.json', {'kind': 'create', 'state': 'launched', 'project': 'keep'})
            original = external.read_bytes()
            self.assertEqual(maintenance.clean(), {'cleaned': 0})
            self.assertEqual(external.read_bytes(), original)

    def test_exclusive_cleanup_waits_for_active_chat_operation(self):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, ATTENTION_DATA=directory, PYTHONPATH=str(Path(b.__file__).parent))
            holder = subprocess.Popen([sys.executable, '-c', 'import maintenance,sys\nwith maintenance.guard():\n print("locked", flush=True)\n sys.stdin.readline()'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)
            cleaner = None
            try:
                self.assertEqual(holder.stdout.readline().strip(), 'locked')
                cleaner = subprocess.Popen([sys.executable, b.__file__], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)
                cleaner.stdin.write('{"action":"data-clean"}'); cleaner.stdin.close(); cleaner.stdin = None
                time.sleep(0.1)
                self.assertIsNone(cleaner.poll())
                holder.communicate('\n', timeout=3)
                output, _ = cleaner.communicate(timeout=3)
                self.assertEqual(json.loads(output), {'cleaned': 0})
            finally:
                for process in (holder, cleaner):
                    if process and process.poll() is None: process.kill(); process.wait()
