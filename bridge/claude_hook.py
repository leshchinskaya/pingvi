#!/usr/bin/env python3
"""Claude lifecycle and interactive requests, with fail-open handoff to native UI."""
import json
import os
from pathlib import Path
import shlex
import shutil
import sys
import time
import uuid
from bridge import ROOT, atomic, base_session, digest, processes, warp_target

def app_alive():
    try:
        return time.time() - json.loads((ROOT / 'app-heartbeat.json').read_text())['time'] < 15
    except (OSError, ValueError, KeyError):
        return False

def target():
    result = warp_target(os.environ)
    pane = os.environ.get('HERDR_PANE_ID')
    if pane:
        result['pane'] = pane
    try:
        procs = {p['pid']: p for p in processes()}
        pid = os.getppid()
        for _ in range(12):
            p = procs.get(pid)
            if not p:
                break
            if p['tty'] != '??':
                result['tty'] = '/dev/' + p['tty']
                if p['name'] == 'claude':
                    result['pid'] = str(p['pid'])
                    break
            pid = p['ppid']
    except Exception:
        pass
    return result

def response_for(event, answer, answers):
    name, tool = event['hook_event_name'], event.get('tool_name')
    if name == 'PreToolUse' and tool == 'AskUserQuestion':
        questions = event['tool_input']['questions']
        if any(not answers.get(q['question'], '').strip() for q in questions):
            raise ValueError('Ответьте на каждый вопрос')
        updated = dict(event['tool_input'], answers=answers)
        return {'hookSpecificOutput': {'hookEventName': name, 'permissionDecision': 'allow', 'updatedInput': updated}}
    if name == 'PermissionRequest':
        if answer not in ('allow', 'deny'):
            raise ValueError('Неизвестное решение')
        return {'hookSpecificOutput': {'hookEventName': name, 'decision': {'behavior': answer}}}
    raise ValueError('Unsupported interactive event')

def handle(event):
    sid = 'claude:' + event['session_id']
    path = ROOT / 'hooks' / (digest(sid) + '.json')
    try:
        old = json.loads(path.read_text())
    except (OSError, ValueError):
        old = {}
    name = event['hook_event_name']
    if name == 'SessionEnd':
        path.unlink(missing_ok=True)
        return None
    item = old or base_session(sid, Path(event.get('cwd', '')).name or 'Claude', event.get('cwd', ''), 'claude', 'Claude Code')
    item.update(kind='hook', target=target(), updated=time.time())
    if event.get('transcript_path'):
        item['target']['transcript'] = event['transcript_path']
    interactive = name == 'PermissionRequest' or (name == 'PreToolUse' and event.get('tool_name') == 'AskUserQuestion')
    if not interactive:
        if name == 'UserPromptSubmit' and event.get('prompt') and not old.get('named'):
            item['title'] = event['prompt'].splitlines()[0][:90]
            item['named'] = True
        if name in ('PostToolUse', 'PostToolUseFailure') and old.get('toolUseID') and event.get('tool_use_id') != old['toolUseID']:
            return None
        item.update(status='done' if name == 'Stop' else ('offline' if name == 'SessionEnd' else ('idle' if name == 'SessionStart' else 'working')),
                    canReply=False, question='', options=[], fields=[], detail='', token='', heartbeat=time.time())
        atomic(path, item)
        return None
    if not app_alive():
        return None
    token = uuid.uuid4().hex
    tool_input = event.get('tool_input', {})
    questions = tool_input.get('questions', []) if name == 'PreToolUse' else []
    fields = [{'id': q['question'], 'label': q['question'], 'options': q.get('options', []), 'multi': q.get('multiSelect', False)} for q in questions]
    item.update(status='waiting', canReply=True, token=token, heartbeat=time.time(), toolUseID=event.get('tool_use_id', ''),
                fields=fields, question='\n\n'.join(q['question'] for q in questions) if questions else 'Разрешить ' + event.get('tool_name', 'действие') + '?',
                detail=json.dumps(tool_input, ensure_ascii=False, indent=2),
                options=[] if questions else [{'id': 'allow', 'label': 'Разрешить один раз'}, {'id': 'deny', 'label': 'Отклонить'}])
    atomic(path, item)
    answer_path = ROOT / 'answers' / (token + '.json')
    try:
        deadline = time.monotonic() + 3500
        while time.monotonic() < deadline and app_alive():
            if answer_path.exists():
                try:
                    answer = json.loads(answer_path.read_text())
                except ValueError:
                    time.sleep(0.1)
                    continue
                if answer.get('token') != token:
                    return None
                result = response_for(event, answer.get('answer'), answer.get('answers', {}))
                # Only PostToolUse/Failure confirms agent execution, not this write.
                item.update(status='unconfirmed', canReply=False, heartbeat=time.time())
                atomic(path, item)
                return result
            item['heartbeat'] = time.time()
            atomic(path, item)
            time.sleep(1)
    finally:
        answer_path.unlink(missing_ok=True)
    item.update(status='offline', canReply=False, detail='Вопрос передан обратно в исходную сессию.')
    atomic(path, item)
    return None

def install():
    config_dir = Path(os.environ.get('CLAUDE_CONFIG_DIR', str(Path.home() / '.claude')))
    config_dir.mkdir(parents=True, exist_ok=True)
    config = config_dir / 'settings.json'
    settings = json.loads(config.read_text()) if config.exists() else {}
    if config.exists():
        shutil.copy2(config, config.with_name('settings.json.attention-backup-' + str(time.time_ns())))
    dest = ROOT / 'integration'
    dest.mkdir(parents=True, exist_ok=True, mode=0o700)
    for name in ('bridge.py', 'claude_hook.py'):
        shutil.copy2(Path(__file__).parent / name, dest / name)
    cmd = shlex.join([sys.executable, '-E', '-s', '-B', str(dest / 'claude_hook.py')])
    hooks = settings.setdefault('hooks', {})
    for event in ('SessionStart', 'UserPromptSubmit', 'PermissionRequest', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'Stop', 'SessionEnd'):
        entries = hooks.setdefault(event, [])
        # Replace only our own hook, preserve unrelated hooks and matchers.
        for entry in entries:
            entry['hooks'] = [h for h in entry.get('hooks', []) if str(dest / 'claude_hook.py') not in h.get('command', '')]
        entries[:] = [e for e in entries if e.get('hooks')]
        entry = {'hooks': [{'type': 'command', 'command': cmd, 'timeout': 3600 if event in ('PermissionRequest', 'PreToolUse') else 5}]}
        if event == 'PreToolUse':
            entry['matcher'] = 'AskUserQuestion'
        entries.append(entry)
    atomic(config, settings)
    return {'ok': True, 'message': 'Интеграция Claude установлена. Перезапустите существующие сессии Claude для загрузки hooks.'}

def installation_status():
    config = Path(os.environ.get('CLAUDE_CONFIG_DIR', str(Path.home() / '.claude'))) / 'settings.json'
    try:
        settings = json.loads(config.read_text())
        dest = ROOT / 'integration'
        command = shlex.join([sys.executable, '-E', '-s', '-B', str(dest / 'claude_hook.py')])
        files_current = all((dest / name).read_bytes() == (Path(__file__).parent / name).read_bytes() for name in ('bridge.py', 'claude_hook.py'))
        return files_current and all(any(command == h.get('command', '') for e in settings.get('hooks', {}).get(event, []) for h in e.get('hooks', [])) for event in ('SessionStart', 'UserPromptSubmit', 'PermissionRequest', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure', 'Stop', 'SessionEnd'))
    except (OSError, ValueError):
        return False


def uninstall():
    config = Path(os.environ.get('CLAUDE_CONFIG_DIR', str(Path.home() / '.claude'))) / 'settings.json'
    if not config.exists():
        return {'ok': True}
    settings = json.loads(config.read_text())
    shutil.copy2(config, config.with_name('settings.json.attention-backup-' + str(time.time_ns())))
    command = str(ROOT / 'integration' / 'claude_hook.py')
    for entries in settings.get('hooks', {}).values():
        for entry in entries:
            entry['hooks'] = [h for h in entry.get('hooks', []) if command not in h.get('command', '')]
        entries[:] = [e for e in entries if e.get('hooks')]
    atomic(config, settings)
    return {'ok': True}


if __name__ == '__main__':
    try:
        result = handle(json.load(sys.stdin))
        if result:
            print(json.dumps(result, ensure_ascii=False))
    except Exception:
        # No decision means native permission/question handling remains in force.
        pass
