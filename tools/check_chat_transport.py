"""Real herdr transport smoke test, using a recorder instead of an AI agent."""
import json
import os
from pathlib import Path
import sys
import tempfile
import time
from unittest.mock import patch
import uuid
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'bridge'))
import bridge as b
import chat

with tempfile.TemporaryDirectory(prefix='pingvi-chat-smoke-') as directory:
    root=Path(directory)
    fake=root/'recorder'
    fake.write_text('''#!/usr/bin/python3
import os,sys,json,tty,time
from pathlib import Path
root=Path(__file__).parent
(root/'argv.json').write_text(json.dumps(sys.argv[1:]))
tty.setraw(sys.stdin.fileno())
os.write(1,b'\\r\\nWhich test option do you prefer?\\r\\n\xe2\x80\xba Ask Codex to do anything\\r\\n  gpt-test medium \xc2\xb7 ~\\r\\n')
buf=b''
while True:
 chunk=os.read(0,4096);buf+=chunk
 (root/'input.bin').write_bytes(buf)
 if buf.endswith(b'\\r'): break
time.sleep(20)
'''.replace('\xe2\x80\xba','\\xe2\\x80\\xba').replace('\xc2\xb7','\\xc2\\xb7'))
    fake.chmod(0o700)
    wid=None
    real_json=b.herdr_json
    with patch.object(b,'ROOT',root),patch.object(chat,'executable',return_value=str(fake)):
        try:
            request={'agent':'codex','project':directory,'text':'First line\nSecond line with $ and quotes "','requestID':str(uuid.uuid4())}
            created=chat.create(request)
            s=created['session'];wid=s['target']['workspace'];s['status']='idle'
            for _ in range(40):
                if (root/'argv.json').exists(): break
                time.sleep(.15)
            assert json.loads((root/'argv.json').read_text())==['--',request['text']]
            def simulated_agent(*args):
                value=real_json(*args)
                if args[:2]==('pane','get') and args[2]==s['target']['pane']:
                    value['pane']['agent']='codex';value['pane']['agent_status']='idle'
                return value
            with patch.object(b,'herdr_json',side_effect=simulated_agent),patch.object(chat,'transcript',return_value=None):
                h=chat.history({'session':s})
                assert h['canSend'],h['reason']
                text='One\nTwo with $ and "quotes"'
                if '--reply' in sys.argv:
                    text='Second option'
                    screen=b.run([b.HERDR,'pane','read',s['target']['pane'],'--source','visible','--lines','100'])
                    s.update(b.parse_screen(screen,'codex'))
                    receipt=b.reply({'session':s,'answers':{'text':text}})
                    assert receipt['ok'],receipt
                else:
                    receipt=chat.send({'session':s,'text':text,'token':h['token'],'requestID':str(uuid.uuid4())})
                    assert receipt['state']=='submitted',receipt
                for _ in range(30):
                    if (root/'input.bin').exists() and (root/'input.bin').read_bytes().endswith(b'\r'):break
                    time.sleep(.1)
                received=(root/'input.bin').read_bytes()
                expected=b'\x1b[200~'+text.encode()+b'\x1b[201~\r'
                assert received==expected,repr(received)
            print('PASS: create, argument quoting, bracketed paste, single Enter (' + ('question reply' if '--reply' in sys.argv else 'multiline chat') + ')')
        finally:
            if not wid:
                for record_path in (root/'chat-requests').glob('*.json'):
                    wid=json.loads(record_path.read_text()).get('workspace') or wid
            if wid: b.run([b.HERDR,'workspace','close',wid])
