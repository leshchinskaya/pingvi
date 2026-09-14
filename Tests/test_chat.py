import json
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
import bridge as b
import chat

READY = 'Assistant reply\n› Ask Codex to do anything\n  gpt-6 medium · ~'

class ChatTests(unittest.TestCase):
    def session(self):
        s = b.base_session('herdr:x', 'Test', '/tmp', 'codex', 'herdr')
        s['target'] = {'pane': 'x'}
        return s

    def test_readiness_never_accepts_busy_prompt_or_typed_draft(self):
        self.assertTrue(chat.ready(READY, 'codex'))
        self.assertFalse(chat.ready(READY, 'codex', 'working'))
        self.assertFalse(chat.ready(READY.replace('Ask Codex to do anything', 'my existing draft'), 'codex'))
        self.assertFalse(chat.ready(READY + '\nPress enter to confirm or esc to cancel', 'codex'))
        self.assertFalse(chat.ready('user@machine % ', 'codex'))
        self.assertTrue(chat.ready('❯\n? for shortcuts', 'claude'))
        self.assertFalse(chat.ready('❯ already typing\n? for shortcuts', 'claude'))

    def test_controls_cannot_escape_paste_or_invoke_slash_commands(self):
        self.assertEqual(chat.validate_text(' hello\nworld '), 'hello\nworld')
        for value in ('', '\x1b[201~rm bad', '/clear', 'text\x00', 'x' * 32001):
            with self.assertRaises(ValueError): chat.validate_text(value)

    def test_parser_filters_instructions_and_tools_and_tolerates_partial_write(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'history.jsonl'
            def msg(role, text, ordinal): return {'ordinal': ordinal, 'type': 'response_item', 'payload': {'type': 'message', 'role': role, 'content': [{'type': 'input_text', 'text': text}]}}
            records = [msg('developer', 'private instructions', 1), msg('user', '<environment_context>metadata</environment_context>', 2), msg('user', 'Hello', 3), msg('assistant', 'Hi', 4), {'type': 'compacted', 'payload': {}}]
            path.write_text('\n'.join(json.dumps(r) for r in records) + '\n{"partial":')
            messages, partial = chat.read_messages(path, 'codex')
            self.assertEqual([m['text'] for m in messages], ['Hello', 'Hi'])
            self.assertTrue(partial)
            self.assertEqual(chat.read_messages(path, 'codex')[0], messages)

    def test_claude_tool_results_are_not_user_messages(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'history.jsonl'
            rows = [{'uuid':'a','type':'user','message':{'role':'user','content':'Hello'}}, {'uuid':'b','type':'user','message':{'role':'user','content':[{'type':'tool_result','content':'secret tool output'}]}}, {'uuid':'c','type':'assistant','message':{'role':'assistant','content':[{'type':'text','text':'Answer'}]}}]
            path.write_text('\n'.join(json.dumps(r) for r in rows))
            self.assertEqual([m['text'] for m in chat.read_messages(path, 'claude')[0]], ['Hello','Answer'])

    def test_changed_screen_does_not_send(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b,'ROOT',Path(directory)), patch.object(chat,'history',return_value={'canSend':True,'token':'new','messages':[]}), patch.object(b,'run') as run:
            with self.assertRaises(RuntimeError): chat.send({'session':self.session(),'text':'Hi','token':'old','requestID':str(uuid.uuid4())})
            run.assert_not_called()

    def test_send_is_idempotent_and_multiline_paste_is_framed(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b,'ROOT',Path(directory)), patch.object(chat,'history',return_value={'canSend':True,'token':'t','messages':[]}), patch.object(b,'herdr_json',return_value={'pane':{'agent':'codex'}}), patch.object(b,'run',return_value='ok') as run:
            request = {'session':self.session(),'text':'first\nsecond','token':'t','requestID':str(uuid.uuid4())}
            self.assertEqual(chat.send(request)['state'],'submitted')
            self.assertEqual(chat.send(request)['state'],'submitted')
            self.assertEqual(run.call_count,2)
            self.assertEqual(run.call_args_list[0].args[0][-1],'\x1b[200~first\nsecond\x1b[201~')
            self.assertEqual(run.call_args_list[1].args[0][-1],'enter')

    def test_terminal_paste_frames_multiline_as_one_message(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b,'ROOT',Path(directory)), patch.object(chat,'history',return_value={'canSend':True,'token':'t','messages':[]}), patch.object(b,'run',return_value='ok') as run:
            session=self.session();session['target']={'tty':'/dev/ttys-test','pid':'123'}
            request={'session':session,'text':'first\nsecond','token':'t','requestID':str(uuid.uuid4())}
            self.assertEqual(chat.send(request)['state'],'submitted')
            run.assert_called_once()
            self.assertEqual(run.call_args.args[0][-3:], ['send','/dev/ttys-test','\x1b[200~first\nsecond\x1b[201~'])

    def test_transport_timeout_cannot_auto_retry(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b,'ROOT',Path(directory)), patch.object(chat,'history',return_value={'canSend':True,'token':'t','messages':[]}), patch.object(b,'run',side_effect=RuntimeError('timeout')) as run:
            request={'session':self.session(),'text':'Hi','token':'t','requestID':str(uuid.uuid4())}
            self.assertEqual(chat.send(request)['state'],'uncertain')
            self.assertEqual(chat.send(request)['state'],'uncertain')
            self.assertEqual(run.call_count,1)

    def test_agent_change_after_paste_never_sends_enter_or_retries(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b,'ROOT',Path(directory)), patch.object(chat,'history',return_value={'canSend':True,'token':'t','messages':[]}), patch.object(b,'herdr_json',return_value={'pane':{'agent':None}}), patch.object(b,'run',return_value='ok') as run, patch.object(b.time,'sleep'):
            request={'session':self.session(),'text':'Hi','token':'t','requestID':str(uuid.uuid4())}
            receipt = chat.send(request)
            self.assertEqual(receipt['state'],'uncertain')
            self.assertIn('Enter не отправлен',receipt['error'])
            self.assertEqual(chat.send(request),receipt)
            self.assertEqual(run.call_count,1)
            self.assertEqual(run.call_args.args[0][2],'send-text')

    def test_activity_during_paste_does_not_suppress_submit_for_same_agent(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b,'ROOT',Path(directory)), patch.object(chat,'history',return_value={'canSend':True,'token':'t','messages':[]}), patch.object(b,'herdr_json',return_value={'pane':{'agent':'codex','agent_status':'working'}}), patch.object(b,'run',return_value='ok') as run, patch.object(b.time,'sleep'):
            receipt=chat.send({'session':self.session(),'text':'Hello','token':'t','requestID':str(uuid.uuid4())})
            self.assertEqual(receipt['state'],'submitted')
            self.assertEqual(run.call_args.args[0][-1],'enter')

    def test_old_identical_message_does_not_confirm_new_send(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b,'ROOT',Path(directory)):
            session=self.session(); ident=str(uuid.uuid4()); history_file=Path(directory)/'history.jsonl';history_file.write_text('')
            receipt={'id':ident,'kind':'send','sessionKey':'x','text':'Same','state':'submitted','time':1,'baselineIDs':['old'],'scope':str(history_file)}
            b.atomic(chat.request_path(ident),receipt)
            old={'id':'old','role':'user','text':'Same','state':'received'}
            with patch.object(chat,'live',return_value=(READY,'idle')), patch.object(chat,'transcript',return_value=history_file), patch.object(chat,'read_messages',return_value=([old],False)):
                result=chat.history({'session':session})
                self.assertTrue(result['pending']);self.assertFalse(result['canSend'])
            new=dict(old,id='new')
            with patch.object(chat,'live',return_value=(READY,'idle')), patch.object(chat,'transcript',return_value=history_file), patch.object(chat,'read_messages',return_value=([old,new],False)):
                result=chat.history({'session':session})
                self.assertFalse(result['pending']);self.assertTrue(result['canSend'])
                self.assertEqual(json.loads(chat.request_path(ident).read_text())['state'],'observed')

    def test_process_mapping_uses_pane_identity_not_project_directory(self):
        procs=[{'pid':1,'name':'codex'},{'pid':2,'name':'codex'}]
        def run(args, **kwargs): return 'codex HERDR_PANE_ID=p_' + args[3]
        def lookup(*args): return {'pane':{'pane_id':'other' if args[2]=='p_1' else 'x'}}
        with patch.object(b,'processes',return_value=procs),patch.object(b,'run',side_effect=run),patch.object(b,'herdr_json',side_effect=lookup):
            self.assertEqual(chat.exact_process(self.session()),2)

    def test_creation_is_idempotent_and_prompt_is_not_shell_source(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(b,'ROOT',Path(directory)), patch.object(chat,'executable',return_value='/bin/echo'):
            def server(*args):
                if args[:2]==('workspace','create'): return {'workspace':{'workspace_id':'w'}}
                if args[:2]==('pane','list'): return {'panes':[{'pane_id':'p','tab_id':'t','workspace_id':'w'}]}
                return {'ok':True}
            with patch.object(b,'herdr_json',side_effect=server) as transport, patch.object(b,'run',return_value='') as execute:
                request={'agent':'claude','project':directory,'text':'hello\n$(touch /tmp/never) "quotes"','requestID':str(uuid.uuid4())}
                created=chat.create(request)
                self.assertEqual(chat.create(request),created)
                self.assertEqual(transport.call_count,2)
                self.assertEqual(execute.call_count,1)
                command=execute.call_args.args[0][-1]
                self.assertNotIn('$(touch',command)
                launch=json.loads(next((Path(directory)/'chat-launches').glob('*.json')).read_text())
                self.assertEqual(launch['argv'][-1],request['text'])

if __name__=='__main__': unittest.main()
