"""Chat transport: exact process bindings, read-only transcripts, idempotent sends."""
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sys
import time
import uuid
import bridge as b

PLACEHOLDERS = r'(?:Ask Codex to do anything|Implement \{feature\}|Find and fix a bug in @filename|Write tests for @filename|Explain this codebase|Summarize recent commits)'

def clean(text):
    return re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', text).rstrip()

def ready(screen, agent, status='idle'):
    tail = clean(screen).splitlines()[-16:]
    text = '\n'.join(tail)
    if status in ('working', 'blocked', 'waiting', 'offline', 'checking', 'unconfirmed'):
        return False
    if re.search(r'esc to interrupt|ctrl\+c to interrupt|enter to confirm|esc to cancel|enter to select', text, re.I):
        return False
    if agent == 'codex':
        return bool(re.search(r'(?m)^\s*›(?:\s*|\s+' + PLACEHOLDERS + r')$', text) and re.search(r'(?m)^\s*(?:gpt-|o[134]-|codex-).+·', text))
    if agent == 'claude':
        return bool(re.search(r'(?m)^\s*❯\s*$', text) and re.search(r'shortcuts|bypass permissions|accept edits|Claude Code|shift.tab', text, re.I))
    return False

def validate_text(text):
    if not isinstance(text, str) or not text.strip():
        raise ValueError('Напишите сообщение.')
    if len(text) > 32000 or any(ord(c) < 32 and c not in '\n\t' for c in text) or '\x7f' in text:
        raise ValueError('Сообщение слишком длинное или содержит управляющие символы.')
    if text.lstrip().startswith('/'):
        raise ValueError('Команды / выполняйте в исходной сессии; здесь отправляются сообщения.')
    return text.strip()

def key(session):
    t = session.get('target', {})
    return t.get('pane') or t.get('tty') or session['id']

def request_path(request_id):
    return b.ROOT / 'chat-requests' / (str(uuid.UUID(request_id)) + '.json')

def live(session):
    t = session['target']
    if t.get('pane'):
        pane = b.herdr_json('pane', 'get', t['pane'])['pane']
        if pane.get('agent') != session['agent']:
            raise RuntimeError('Агент в панели изменился. Откройте исходную сессию.')
        text = b.run([b.HERDR, 'pane', 'read', t['pane'], '--source', 'visible', '--lines', '100'])
        return text, pane.get('agent_status', 'unknown')
    if not any(str(p['pid']) == t.get('pid') and '/dev/' + p['tty'] == t.get('tty') and p['name'] == session['agent'] for p in b.processes()):
        raise RuntimeError('Не удалось подтвердить процесс агента. Откройте исходную сессию.')
    session['target'] = t = b.resolve_terminal_target(t)
    if t.get('terminalApp') == 'Warp':
        return '', session.get('status', 'idle')
    return b.terminal('read', t['tty']), 'idle'

def exact_process(session):
    t = session['target']
    if not t.get('pane'):
        return int(t['pid']) if t.get('pid') else None
    matches = []
    for p in b.processes():
        if p['name'] != session['agent']:
            continue
        try:
            env = b.run(['/bin/ps', 'eww', '-p', str(p['pid']), '-o', 'command='])
            alias = re.search(r'(?:^| )HERDR_PANE_ID=([^ ]+)', env)
            if alias and b.herdr_json('pane', 'get', alias[1])['pane']['pane_id'] == t['pane']:
                matches.append(p['pid'])
        except Exception:
            continue
    return matches[0] if len(matches) == 1 else None

def transcript(session):
    roots = [Path.home() / '.claude/projects', Path.home() / '.codex/sessions']
    supplied = session['target'].get('transcript')
    if supplied and session['agent'] == 'claude':
        path = Path(supplied).resolve()
        if any(root.resolve() in path.parents for root in roots) and path.is_file():
            return path
    pid = exact_process(session)
    if not pid:
        return None
    try:
        output = b.run(['/usr/sbin/lsof', '-a', '-p', str(pid), '-Fn'], timeout=5)
        paths = set()
        for line in output.splitlines():
            if line.startswith('n') and line.endswith('.jsonl'):
                path = Path(line[1:]).resolve()
                if any(root.resolve() in path.parents for root in roots) and path.is_file():
                    paths.add(path)
        return next(iter(paths)) if len(paths) == 1 else None
    except Exception:
        return None

def read_messages(path, agent):
    messages = []
    limit = 4 * 1024 * 1024
    partial = path.stat().st_size > limit
    with path.open('rb') as f:
        if partial:
            f.seek(-limit, os.SEEK_END); f.readline()
        for index, raw in enumerate(f):
            try:
                item = json.loads(raw)
            except (ValueError, UnicodeDecodeError):
                continue  # Last record may still be being written.
            if item.get('type') == 'compacted':
                partial = True
            message = item.get('payload', {}) if agent == 'codex' else item.get('message', {})
            if agent == 'codex' and (item.get('type') != 'response_item' or message.get('type') != 'message'):
                continue
            if agent == 'claude' and item.get('type') not in ('user', 'assistant'):
                continue
            role = message.get('role', item.get('type'))
            if role not in ('user', 'assistant') or item.get('isMeta') or item.get('isSidechain'):
                continue
            content = message.get('content', [])
            text = content if isinstance(content, str) else '\n'.join(c.get('text', '') for c in content if c.get('type') in ('text', 'input_text', 'output_text'))
            if not text.strip() or text.lstrip().startswith(('<environment_context>', '<user_instructions>', '<permissions instructions>', '<system-reminder>', '<local-command')):
                continue
            # Stream revisions of one assistant item replace its previous contents.
            ident = item.get('uuid') or message.get('id') or b.digest(str(item.get('ordinal', item.get('timestamp', ''))) + role + text)
            record = dict(id=ident, role=role, text=text, state='received')
            old = next((i for i, m in enumerate(messages) if m['id'] == ident), None)
            if old is None: messages.append(record)
            else: messages[old] = record
    return messages[-200:], partial or len(messages) > 200

def question_context(data):
    """Read native messages only; never reconcile receipts or send terminal input."""
    session = data['session']
    path = transcript(session)
    if path is None:
        return dict(user='', assistant='', partial=True)
    messages, partial = read_messages(path, session['agent'])
    # Do not borrow an assistant response from a previous user turn.
    start = next((i for i in range(len(messages) - 1, -1, -1)
                  if messages[i]['role'] == 'user'), None)
    user = messages[start]['text'] if start is not None else ''
    candidates = messages[start + 1:] if start is not None else messages
    questions = [session.get('question', '')] + [f.get('label', '') for f in session.get('fields', [])]
    assistant = ''
    for message in candidates:
        if message['role'] != 'assistant':
            continue
        text = message['text'].strip()
        offsets = [text.find(q.strip()) for q in questions if q.strip() and q.strip() in text]
        if offsets:
            text = text[:min(offsets)].strip()
            if text:
                assistant = text
            break  # Never include text after the current question.
        assistant = text
    return dict(user=user, assistant=assistant, partial=partial)


def receipts(session):
    result = []
    for path in (b.ROOT / 'chat-requests').glob('*.json'):
        try:
            item = json.loads(path.read_text())
            if item.get('sessionKey') == key(session) and item.get('kind') == 'send' and not item.get('redacted'):
                result.append(item)
        except (OSError, ValueError): pass
    return sorted(result, key=lambda x: x['time'])[-30:]

def history(data):
    session = data['session']
    screen, status = live(session)
    path = transcript(session)
    messages, partial = read_messages(path, session['agent']) if path else ([], True)
    context = ''
    if path is None:
        if session['target'].get('pane'):
            context = b.run([b.HERDR, 'pane', 'read', session['target']['pane'], '--source', 'recent-unwrapped', '--lines', '300'])
        else: context = screen
    pending = False
    for receipt in receipts(session):
        state = receipt['state']
        if path and receipt.get('scope') and receipt['scope'] != str(path):
            continue
        # Confirm only a new native user item, never an old identical message.
        baseline = receipt.get('baselineIDs', [])
        observed = any(m['role'] == 'user' and m['text'].strip() == receipt['text'] and m['id'] not in baseline for m in messages)
        if observed:
            if state != 'observed':
                receipt['state'] = 'observed'; b.atomic(request_path(receipt['id']), receipt)
            continue
        if state == 'observed': continue
        messages.append(dict(id=receipt['id'], role='user', text=receipt['text'], state=state))
        pending |= state in ('submitted', 'uncertain')
    blocked = session.get('status') in ('working', 'checking', 'unconfirmed', 'offline') or (session.get('kind') == 'hook' and session.get('status') == 'waiting') or bool(session.get('options'))
    available = not blocked and not pending and ready(screen, session['agent'], status)
    reason = ('Проверьте последнее сообщение в исходной сессии.' if pending else
              'Агент работает. Черновик сохранится до ручной отправки.' if status == 'working' or session.get('status') == 'working' else
              'Сначала ответьте на запрос агента или освободите поле ввода в исходной сессии.')
    if session['target'].get('terminalApp') == 'Warp' and not session['target'].get('pane'):
        available = False
        reason = 'Новые сообщения вводите во вкладке Warp. На вопросы Claude можно отвечать в очереди Pingvi.'
    return dict(messages=messages, partial=partial, context=context, canSend=available, busy=status == 'working', reason='' if available else reason, token=b.digest(screen), pending=pending, scope=str(path) if path else '')

def send(data):
    session = data['session']; text = validate_text(data['text']); path = request_path(data['requestID'])
    locks = b.ROOT / 'chat-locks'; locks.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (locks / b.digest(key(session))).open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if path.exists(): return json.loads(path.read_text())
        h = history({'session': session})
        if not h['canSend'] or h['token'] != data.get('token'):
            raise RuntimeError('Состояние диалога изменилось. Черновик сохранён; дождитесь обновления.')
        receipt = dict(id=data['requestID'], kind='send', sessionKey=key(session), text=text, state='uncertain', time=time.time(), baselineIDs=[m['id'] for m in h['messages']], scope=h.get('scope', ''))
        b.atomic(path, receipt)  # Reserve before touching the transport; never auto-retry.
        try:
            target = session['target']
            if target.get('pane'):
                b.send_pane_text(session, text)
            else:
                b.terminal('send', target['tty'], text)
            receipt['state'] = 'submitted'
        except Exception as error:
            receipt['error'] = str(error)
        b.atomic(path, receipt)
        return receipt

def acknowledge(data):
    path = request_path(data['requestID']); receipt = json.loads(path.read_text())
    if receipt.get('sessionKey') != key(data['session']): raise RuntimeError('Другой диалог.')
    receipt['state'] = 'checked'; b.atomic(path, receipt)
    return {'ok': True}

def executable(agent):
    return b.working_executable(agent)[0]

def create(data):
    agent = data['agent']; text = validate_text(data['text']); project = Path(data['project']).expanduser().resolve()
    if agent not in ('codex', 'claude') or not project.is_dir(): raise ValueError('Выберите агента и существующую папку проекта.')
    binary = executable(agent); path = request_path(data['requestID'])
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    # A retry of the same creation never creates a second workspace.
    fd = None
    try: fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        previous = json.loads(path.read_text())
        if previous.get('session'): return previous
        raise RuntimeError('Этот запуск уже запрошен. Проверьте herdr перед новым запуском.')
    with os.fdopen(fd, 'w') as f: json.dump({'kind': 'create', 'state': 'starting'}, f)
    record = dict(kind='create', state='starting', project=str(project), agent=agent)
    try:
        result = b.herdr_json('workspace', 'create', '--cwd', str(project), '--label', text.splitlines()[0][:45], '--no-focus')
        workspace = result.get('workspace', result)
        wid = workspace.get('workspace_id')
        if not wid: raise RuntimeError('herdr не вернул рабочее пространство.')
        record['workspace'] = wid; b.atomic(path, record)
        panes = b.herdr_json('pane', 'list', '--workspace', wid)['panes']
        if len(panes) != 1: raise RuntimeError('Не удалось однозначно определить новую панель.')
        pane = panes[0]
        launcher = b.ROOT / 'chat-launches' / (data['requestID'] + '.json')
        argv = [binary]
        if agent == 'claude': argv += ['--session-id', data['requestID']]
        argv += ['--', text]
        b.atomic(launcher, {'argv': argv, 'cwd': str(project)})
        command = 'exec ' + shlex.join([sys.executable, '-E', '-s', '-B', str(Path(__file__).with_name('chat_launcher.py')), str(launcher)])
        b.run([b.HERDR, 'pane', 'run', pane['pane_id'], command])
        session = b.base_session('herdr:' + pane['pane_id'], text.splitlines()[0][:90], str(project), agent, 'herdr')
        session.update(status='working', target={'pane': pane['pane_id'], 'tab': pane['tab_id'], 'workspace': wid})
        record.update(state='launched', session=session); b.atomic(path, record)
        return record
    except Exception as error:
        record.update(state='uncertain', error=str(error)); b.atomic(path, record)
        raise RuntimeError('Запуск не подтверждён. Проверьте herdr: ' + str(error))
