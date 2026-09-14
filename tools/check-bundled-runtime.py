"""Exercise the distributed helper with no external Python, user site or developer paths."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='pingvi-clean-') as directory:
    temporary = Path(directory)
    app = temporary / 'Folder with spaces' / 'Pingvi.app'
    shutil.copytree(root / 'dist/Pingvi.app', app, symlinks=True)
    python = app / 'Contents/Resources/Python/bin/python3'
    script = app / 'Contents/Resources/bridge/bridge.py'
    home = temporary / 'user'
    home.mkdir()
    env = {'HOME': str(home), 'PATH': '/usr/bin:/bin', 'ATTENTION_DATA': str(home / 'data'),
           'CLAUDE_CONFIG_DIR': str(home / 'claude'), 'PYTHONHOME': '/nonexistent', 'PYTHONPATH': '/nonexistent'}
    native = subprocess.run([str(app / 'Contents/MacOS/AgentAttention'), '--check-runtime'], env=env, capture_output=True, text=True, timeout=15, check=True)
    assert json.loads(native.stdout) == {'ok': True, 'python': '3.13.15'}, native.stdout
    def call(payload):
        result = subprocess.run([str(python), '-E', '-s', '-B', str(script)], input=json.dumps(payload), text=True, capture_output=True, env=env, timeout=45, check=True)
        value = json.loads(result.stdout)
        assert 'error' not in value, value
        return value
    report = call({'action': 'diagnostics', 'herdrPath': '/missing/herdr', 'claudePath': '/missing/claude', 'codexPath': '/missing/codex'})
    checks = {c['name']: c for c in report['checks']}
    assert checks['Python']['ready']
    assert all(not checks[name]['ready'] for name in ('herdr', 'claude', 'codex'))
    assert call({'action': 'install-hooks', 'herdrPath': '/missing/herdr'})['ok']
    settings = json.loads((home / 'claude/settings.json').read_text())
    command = settings['hooks']['SessionStart'][0]['hooks'][0]['command']
    import shlex
    result = subprocess.run(shlex.split(command), input=json.dumps({'hook_event_name': 'SessionStart', 'session_id': 'smoke', 'cwd': str(home)}), text=True, capture_output=True, env=env, timeout=10)
    assert result.returncode == 0, result.stderr
    assert list((home / 'data/hooks').glob('*.json')), 'Installed hook did not run'
    # Replace the app at the same installation path, preserving all user files.
    sentinel = home / 'data/chat-ui.json'
    sentinel.write_text('{"drafts":{"one":"keep across update"}}')
    before_update = sentinel.read_bytes()
    backup = app.with_name('Previous.app')
    app.rename(backup)
    shutil.copytree(root / 'dist/Pingvi.app', app, symlinks=True)
    result = subprocess.run(shlex.split(command), input=json.dumps({'hook_event_name': 'SessionStart', 'session_id': 'after-update', 'cwd': str(home)}), text=True, capture_output=True, env=env, timeout=10)
    assert result.returncode == 0, result.stderr
    assert sentinel.read_bytes() == before_update, 'Update modified user drafts'
    assert call({'action': 'data-status', 'herdrPath': '/missing/herdr'})['processed'] == 0
    assert call({'action': 'data-clean', 'herdrPath': '/missing/herdr'}) == {'cleaned': 0}
    assert call({'action': 'uninstall-hooks', 'herdrPath': '/missing/herdr'})['ok']
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    assert not list((app / 'Contents/Resources/bridge').glob('__pycache__')), 'Helper modified the bundle'
    print('PASS: relocated app, isolated home, no external Python, invalid PYTHONHOME ignored, missing CLI diagnostics, real installed hook, replacement update, drafts preserved, cleanup, uninstall, signature intact')
