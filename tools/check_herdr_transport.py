import json
from pathlib import Path
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'bridge'))
import bridge

pane_id = sys.argv[1]
pane = bridge.herdr_json('pane', 'get', pane_id)['pane']
workspace = bridge.herdr_json('workspace', 'get', pane['workspace_id'])
assert 'Attention integration check' in json.dumps(workspace), 'Refusing a non-test workspace'
screen = bridge.run([bridge.HERDR, 'pane', 'read', pane_id, '--source', 'visible', '--lines', '100'])
assert 'transport fixture only' in screen, 'Refusing a non-test prompt'
s = bridge.base_session('transport-test', 'Transport test', '', pane.get('agent'), 'herdr')
s.update(bridge.parse_screen(screen, pane.get('agent')))
s['target'] = {'pane': pane_id}
assert s['canReply'], 'Fixture not recognized'
result = bridge.reply({'session': s, 'answer': '1'})
assert result == {'ok': True, 'confirmed': False}
path = Path(__file__).with_name('fixture-result.json')
for _ in range(30):
    if path.exists(): break
    time.sleep(.1)
assert json.loads(path.read_text()) == {'received': '1'}
print('PASS: exact test pane received 1; transport write was not treated as agent confirmation')
