#!/usr/bin/env python3
"""Local adapters. No shell interpolation; all UI actions carry a snapshot token."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import signal
import sys
import time

ROOT = Path(os.environ.get('ATTENTION_DATA', str(Path.home() / 'Library/Application Support/AgentAttention')))
CLI_PATHS = {}

def executable_candidates(name):
    candidates = [Path.home() / '.local/bin' / name, Path('/opt/homebrew/bin') / name,
                  Path('/usr/local/bin') / name, Path.home() / '.npm-global/bin' / name]
    candidates += [Path(p) / name for p in os.get_exec_path() if p]
    return list(dict.fromkeys(str(p) for p in candidates if p.is_file() and os.access(p, os.X_OK)))

def find_executable(name, configured=''):
    configured = configured or CLI_PATHS.get(name, '')
    if configured:
        path = Path(configured).expanduser()
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
        raise RuntimeError('Указанный путь ' + name + ' недоступен: ' + str(path))
    return next(iter(executable_candidates(name)), None)

def working_executable(name):
    configured = CLI_PATHS.get(name, '')
    candidates = [find_executable(name, configured)] if configured else executable_candidates(name)
    failures = []
    for path in candidates:
        try:
            version = run([path, '--version'], timeout=3).strip()
            if version:
                return path, version[:160]
        except Exception:
            pass
        failures.append(path)
    if failures:
        raise RuntimeError('Не удалось запустить ' + name + ': ' + ', '.join(failures) + '. Укажите рабочий CLI в настройках.')
    raise RuntimeError(name + ' не найден. Установите CLI или укажите путь в настройках.')

HERDR = find_executable('herdr') or 'herdr'

def diagnostics():
    from claude_hook import installation_status
    checks = []
    for name in ('herdr', 'claude', 'codex'):
        try:
            path, version = working_executable(name)
            checks.append(dict(name=name, ready=True, detail=version + ' · ' + path))
        except Exception as error:
            checks.append(dict(name=name, ready=False, detail=str(error)))
    checks.insert(0, dict(name='Python', ready=sys.version_info >= (3, 9), detail=sys.version.split()[0] + ' · встроенный runtime'))
    checks.append(dict(name='Claude hooks', ready=installation_status(), detail='Для подключения или обновления нажмите «Подключить / обновить».'))
    return {'checks': checks}


_children = set()

def stop_children(*_):
    for child in list(_children):
        try: os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError: pass
    raise SystemExit(143)

def run(args, timeout=8, input=None):
    p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    _children.add(p)
    try:
        stdout, stderr = p.communicate(input, timeout=timeout)
        if p.returncode:
            raise RuntimeError(stderr.strip() or stdout.strip() or 'Команда завершилась с ошибкой')
        return stdout
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        raise
    finally:
        _children.discard(p)


def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_suffix('.tmp.' + str(os.getpid()))
    temp.write_text(json.dumps(value, ensure_ascii=False))
    temp.chmod(0o600)
    temp.replace(path)

def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()

def latest_assistant_text(text):
    """Separate a terminal turn using CLI message markers, not question marks."""
    # Codex renders its queued-input notice with the same bullet as assistant
    # messages. It belongs to the preceding result, not to a new assistant turn.
    starts = [match for match in re.finditer(r'(?m)^\s*[•●] ', text)
              if not re.match(r'Queued follow-up inputs[ \t]*(?:\n|$)', text[match.end():])]
    return text[starts[-1].end():].strip() if starts else text.strip()

def parse_screen(text, agent):
    """Only recognize live UI footers, never a numbered list in conversational prose."""
    text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', text).rstrip()
    tail = '\n'.join(text.splitlines()[-45:])
    working = bool(re.search(r'esc to interrupt|ctrl\+c to interrupt|Working \(', '\n'.join(text.splitlines()[-10:]), re.I))
    options = []
    approval = re.search(r'(?im)^\s*(?:›|❯)?\s*1\.\s+(Yes, proceed|Yes|Allow once)\b', tail)
    footer = re.search(r'(?i)(esc to cancel|escape to cancel|enter to confirm|enter to select)', tail[-1200:])
    if not working and approval and footer:
        for m in re.finditer(r'(?m)^\s*[›❯]?\s*(\d+)\.\s+(.+)$', tail[approval.start():]):
            options.append({'id': m[1], 'label': m[2].strip()})
    waiting = bool(options)
    question = ''
    if waiting:
        # Keep the action/command together; options are rendered separately by the app.
        prompt = tail[:approval.start()]
        headings = list(re.finditer(r'(?im)^\s*Would you like to run the following command\?', prompt))
        question = prompt[headings[-1].start():].strip() if headings else latest_assistant_text(prompt)
    # A known empty Codex composer + model footer distinguishes agent input from a shell.
    composer = re.search(r'(?m)^\s*› (?:Ask Codex to do anything|Implement \{feature\}|Find and fix a bug in @filename|Write tests for @filename|Explain this codebase|Summarize recent commits)\s*$', tail)
    model_footer = re.search(r'(?m)^\s*(?:gpt-|o[134]-|codex-).+·', tail)
    fields = []
    if not working and not waiting and agent == 'codex' and composer and model_footer:
        # Use the full visible turn so a long question is not cut at the 45-line tail.
        full_composer = list(re.finditer(composer.re, text))[-1]
        body = text[:full_composer.start()].strip()
        # A question must be in the final assistant text, not a previous tool log.
        body = latest_assistant_text(body)
        if '?' in body and not re.search(r'(?m)^\s*[│└]|^Ran |^Running ', body):
            waiting = True
            question = body
            fields = [{'id': 'text', 'label': 'Короткий ответ', 'options': [], 'multi': False}]
    return {'status': 'waiting' if waiting else ('working' if working else 'idle'),
            'question': question, 'options': options,
            'token': digest(text), 'canReply': waiting, 'kind': 'screen', 'fields': fields}

def herdr_json(*args):
    data = json.loads(run([HERDR, *args]))
    if 'error' in data:
        raise RuntimeError(str(data['error']))
    return data['result']

def send_pane_text(session, text, paste=True):
    pane = session['target']['pane']
    # Plain character bursts can swallow Enter as a pasted newline in Codex.
    # Frame text as one paste, then let the composer finish processing it.
    payload = '\x1b[200~' + text + '\x1b[201~' if paste else text
    run([HERDR, 'pane', 'send-text', pane, payload])
    time.sleep(0.3)
    current = herdr_json('pane', 'get', pane)['pane']
    if current.get('agent') != session['agent']:
        raise RuntimeError('Состояние агента изменилось во время ввода; Enter не отправлен. Проверьте исходную сессию.')
    run([HERDR, 'pane', 'send-keys', pane, 'enter'])

def base_session(sid, title, project, agent, source):
    return dict(id=sid, title=title, project=project, agent=agent, source=source,
                status='idle', question='', options=[], token='', canReply=False,
                kind='screen', updated=time.time(), target={}, detail='', fields=[])

def herdr_session(pane):
    pid = pane['pane_id']
    item = base_session('herdr:' + pid, pane.get('label') or Path(pane.get('cwd', '')).name or 'Сессия',
                        pane.get('cwd', ''), pane.get('agent') or 'Агент', 'herdr')
    item['target'] = {'pane': pid, 'tab': pane['tab_id'], 'workspace': pane['workspace_id']}
    try:
        screen = run([HERDR, 'pane', 'read', pid, '--source', 'visible', '--lines', '100'])
        item.update(parse_screen(screen, item['agent']))
        if item['status'] == 'idle' and pane.get('agent_status') == 'working':
            item['status'] = 'working'
        item['detail'] = screen[-14000:]
        item['focusedPane'] = pane.get('focused', False)
    except Exception as e:
        item['status'], item['detail'] = 'offline', str(e)
    return item

def processes():
    result = []
    for line in run(['/bin/ps', '-axo', 'pid=,ppid=,tty=,comm=']).splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) == 4:
            result.append(dict(pid=int(parts[0]), ppid=int(parts[1]), tty=parts[2], name=Path(parts[3]).name))
    return result

def warp_target(env):
    """Accept only Warp's session links, never arbitrary URLs from process data."""
    if env.get('TERM_PROGRAM') != 'WarpTerminal':
        return {}
    result = {'terminalApp': 'Warp'}
    url = env.get('WARP_FOCUS_URL', '')
    if re.fullmatch(r'(?:warp|warppreview|warposs)://session/[0-9a-f]{32}', url):
        result['focusURL'] = url
    return result

def resolve_terminal_target(target, procs=None):
    target = dict(target)
    if target.get('pane') or not target.get('pid'):
        return target
    procs = processes() if procs is None else procs
    if not any(str(p['pid']) == target['pid'] and '/dev/' + p['tty'] == target.get('tty') for p in procs):
        raise RuntimeError('Исходный процесс агента завершился.')
    # Existing hooks predate terminal metadata. Recover it without restarting Claude.
    if not target.get('terminalApp'):
        raw = run(['/bin/ps', 'eww', '-p', target['pid'], '-o', 'command='])
        env = dict(re.findall(r'(?:^| )(TERM_PROGRAM|WARP_FOCUS_URL)=([^\s]+)', raw))
        target.update(warp_target(env))
    return target

def focus_terminal_target(target):
    target = resolve_terminal_target(target)
    if target.get('terminalApp') == 'Warp':
        url = warp_target({'TERM_PROGRAM': 'WarpTerminal', 'WARP_FOCUS_URL': target.get('focusURL', '')}).get('focusURL')
        if not url:
            raise RuntimeError('Warp: откройте новую вкладку в обновлённом Warp и запустите Claude — у этой сессии нет ссылки для перехода.')
        run(['/usr/bin/open', url])
    else:
        terminal('focus', target['tty'])

# User strings are arguments to the script, never executable AppleScript source.
TERMINAL_SCRIPT = '''on run argv
set actionName to item 1 of argv
set targetTTY to item 2 of argv
tell application "Terminal"
repeat with w in windows
repeat with t in tabs of w
if tty of t is targetTTY then
if actionName is "read" then
return contents of t
else if actionName is "focus" then
set selected tab of w to t
set index of w to 1
activate
return "ok"
else if actionName is "send" then
do script (item 3 of argv) in t
return "ok"
end if
end if
end repeat
end repeat
end tell
error "Нужная вкладка Terminal не найдена"
end run'''

def terminal(action, tty, text='', paste=True):
    # Terminal's `do script` appends Return itself. Explicit paste framing keeps
    # that Return outside the character burst so Codex treats it as submission.
    if action == 'send' and paste:
        text = '\x1b[200~' + text + '\x1b[201~'
    return run(['/usr/bin/osascript', '-e', TERMINAL_SCRIPT, action, tty, text])

def terminal_sessions(procs):
    items = []
    # Herdr owns PTYs that are not ordinary Terminal tabs. Missing tabs are ignored.
    for p in procs:
        if p['name'] not in ('codex', 'claude') or p['tty'] == '??':
            continue
        tty = '/dev/' + p['tty']
        try:
            screen = terminal('read', tty)
        except RuntimeError as e:
            if '-1743' in str(e):
                raise RuntimeError('Terminal: разрешите Automation → Terminal в настройках macOS.')
            continue
        item = base_session('terminal:' + str(p['pid']), p['name'] + ' · ' + p['tty'], '', p['name'], 'Terminal')
        item.update(parse_screen(screen, p['name']))
        item['target'] = {'tty': tty, 'pid': str(p['pid'])}
        item['detail'] = screen[-14000:]
        items.append(item)
    return items

def hook_sessions():
    result = []
    for path in (ROOT / 'hooks').glob('*.json'):
        try:
            d = json.loads(path.read_text())
            if d.get('status') == 'waiting' and time.time() - d.get('heartbeat', 0) > 12:
                d.update(status='offline', canReply=False)
            result.append(d)
        except (ValueError, OSError) as error:
            raise RuntimeError('Не удалось прочитать сессию Claude: ' + str(error)) from error
    return result

def snapshot(options):
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    sessions, errors, complete_sources = [], [], []
    panes = None
    try:
        procs = processes()
    except Exception:
        procs = None
    try:
        panes = herdr_json('pane', 'list')['panes']
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            sessions.extend(pool.map(herdr_session, [p for p in panes if p.get('agent')]))
        complete_sources.append('herdr')
    except Exception as e:
        errors.append('herdr: ' + str(e))
    if options.get('terminal'):
        try:
            sessions.extend(terminal_sessions(procs if procs is not None else processes()))
            complete_sources.append('Terminal')
        except Exception as e:
            errors.append(str(e))
    try:
        hooks = hook_sessions()
        complete_sources.append('Claude Code')
    except Exception as e:
        hooks = []
        errors.append(str(e))
    for h in hooks:
        # Native hook is authoritative over screen-derived state for the same pane/TTY.
        target = h.get('target', {})
        if target.get('pane', '').startswith('p_'):
            try: target['pane'] = herdr_json('pane', 'get', target['pane'])['pane']['pane_id']
            except Exception: pass
        # Only successful inventories can establish that the source was removed.
        if panes is not None and target.get('pane') and not target['pane'].startswith('p_'):
            if not any(p['pane_id'] == target['pane'] and p.get('agent') == h['agent'] for p in panes):
                continue
        if procs is not None and target.get('pid'):
            if not any(str(p['pid']) == target['pid'] and p['name'] == h['agent'] for p in procs):
                continue
            try:
                h['target'] = target = resolve_terminal_target(target, procs)
            except Exception as error:
                errors.append(str(error))
        duplicate = next((s for s in sessions if
                          (target.get('pane') and target.get('pane') == s['target'].get('pane')) or
                          (target.get('tty') and target.get('tty') == s['target'].get('tty'))), None)
        if duplicate:
            sessions.remove(duplicate)
            h['target'] = {**duplicate['target'], **target}
            h['focusedPane'] = duplicate.get('focusedPane', False)
        sessions.append(h)
    front_tty = ''
    if options.get('terminal'):
        try:
            front_tty = run(['/usr/bin/osascript', '-e', 'tell application "Terminal"\nif frontmost and (count windows) > 0 then return tty of selected tab of front window\nreturn ""\nend tell']).strip()
        except Exception:
            pass
    herdr_front = any(p['name'] == 'herdr' and '/dev/' + p['tty'] == front_tty for p in (procs or []))
    for s in sessions:
        s['atSource'] = bool(front_tty and ((s['target'].get('tty') == front_tty) or (s['target'].get('pane') and s.get('focusedPane') and herdr_front)))
    return {'sessions': sessions, 'errors': errors, 'completeSources': complete_sources}

def reply(data):
    session = data['session']
    if session['kind'] == 'hook':
        path = ROOT / 'hooks' / (digest(session['id']) + '.json')
        current = json.loads(path.read_text())
        if current['token'] != session['token'] or current['status'] != 'waiting' or time.time() - current.get('heartbeat', 0) > 12:
            raise RuntimeError('Вопрос уже изменился или связь потеряна.')
        response = {'token': session['token'], 'answer': data.get('answer', ''), 'answers': data.get('answers', {})}
        answer_path = ROOT / 'answers' / (session['token'] + '.json')
        answer_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        # O_EXCL prevents duplicate submissions across processes.
        fd = os.open(answer_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as f:
            json.dump(response, f)
        return {'ok': True, 'confirmed': False}
    target = session['target']
    if target.get('pane'):
        pane = herdr_json('pane', 'get', target['pane'])['pane']
        if pane.get('agent') != session['agent']:
            raise RuntimeError('Агент в панели изменился.')
        screen = run([HERDR, 'pane', 'read', target['pane'], '--source', 'visible', '--lines', '100'])
    else:
        if not any(str(p['pid']) == target.get('pid') and '/dev/' + p['tty'] == target.get('tty') and p['name'] == session['agent'] for p in processes()):
            raise RuntimeError('Исходный процесс агента завершился.')
        screen = terminal('read', target['tty'])
    parsed = parse_screen(screen, session['agent'])
    if not parsed['canReply'] or parsed['token'] != session['token']:
        raise RuntimeError('Экран изменился. Обновите вопрос перед ответом.')
    answer = data.get('answer', '')
    if parsed['fields']:
        answer = data.get('answers', {}).get('text', '').strip()
        if not answer or len(answer) > 4000 or any(ord(c) < 32 and c not in '\n\t' for c in answer) or '\x7f' in answer:
            raise RuntimeError('Введите ответ до 4000 символов, без управляющих символов.')
    elif answer not in [o['id'] for o in parsed['options']]:
        raise RuntimeError('Ответ не соответствует вариантам текущего запроса.')
    if target.get('pane'):
        send_pane_text(session, answer, paste=bool(parsed['fields']))
    else:
        terminal('send', target['tty'], answer, paste=bool(parsed['fields']))
    return {'ok': True, 'confirmed': False}

def focus(data):
    t = data['session']['target']
    if t.get('pane'):
        pane = herdr_json('pane', 'get', t['pane'])['pane']
        herdr_json('workspace', 'focus', pane['workspace_id'])
        herdr_json('tab', 'focus', pane['tab_id'])
        # 0.5.8 exposes tab focus but no pane focus. Do not claim an exact transition.
        procs = processes()
        herdr_targets = [{'tty': '/dev/' + p['tty'], 'pid': str(p['pid'])} for p in procs if p['name'] == 'herdr' and p['tty'] != '??']
        opened = False
        for target in herdr_targets:
            try:
                focus_terminal_target(target)
                opened = True
                break
            except Exception:
                pass
        current = herdr_json('pane', 'get', t['pane'])['pane']
        if not opened:
            raise RuntimeError('Вкладка herdr выбрана, но исходное окно открыть не удалось. Проверьте Terminal или ссылку сессии Warp.')
        if not current.get('focused'):
            raise RuntimeError('Открыта вкладка herdr. В версии 0.5.8 нужную панель внутри неё выберите вручную.')
    elif t.get('tty'):
        focus_terminal_target(t)
    else:
        raise RuntimeError('Исходная вкладка не определена.')
    return {'ok': True}

def main():
    global HERDR
    try:
        data = json.load(sys.stdin)
        CLI_PATHS.update({name: data.get(name + 'Path', '') for name in ('herdr', 'claude', 'codex')})
        action = data.get('action', 'snapshot')
        if action not in ('diagnostics', 'install-hooks', 'uninstall-hooks', 'runtime-check', 'data-status', 'data-clean'):
            HERDR = find_executable('herdr') or 'herdr'
        if action == 'runtime-check':
            result = {'ok': True, 'python': sys.version.split()[0]}
        elif action == 'diagnostics':
            result = diagnostics()
        elif action in ('data-status', 'data-clean'):
            import maintenance
            with maintenance.guard(exclusive=action == 'data-clean'):
                result = maintenance.clean() if action == 'data-clean' else maintenance.status()
        elif action == 'uninstall-hooks':
            from claude_hook import uninstall
            result = uninstall()
        elif action == 'snapshot':
            result = snapshot(data)
        elif action in ('question-context', 'chat-history', 'chat-send', 'chat-create', 'chat-acknowledge'):
            import chat
            import maintenance
            with maintenance.guard():
                result = {'question-context': chat.question_context, 'chat-history': chat.history, 'chat-send': chat.send, 'chat-create': chat.create, 'chat-acknowledge': chat.acknowledge}[action](data)
        elif action == 'reply':
            result = reply(data)
        elif action == 'focus':
            result = focus(data)
        elif action == 'install-hooks':
            from claude_hook import install
            result = install()
        else:
            raise ValueError('Неизвестное действие')
        print(json.dumps(result, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({'error': str(e)}, ensure_ascii=False))

if __name__ == '__main__':
    signal.signal(signal.SIGTERM, stop_children)
    main()
