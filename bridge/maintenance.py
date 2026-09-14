"""Explicit local cleanup; delivery identities and pending receipts survive."""
from contextlib import contextmanager
import fcntl
import json
import os
import bridge as b

@contextmanager
def guard(exclusive=False):
    b.ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (b.ROOT / 'maintenance.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
        yield


def records():
    for path in (b.ROOT / 'chat-requests').glob('*.json'):
        if path.is_symlink():
            continue
        try:
            item = json.loads(path.read_text())
            if isinstance(item, dict):
                yield path, item
        except (OSError, ValueError):
            continue


def status():
    processed = pending = 0
    for _, item in records():
        if item.get('kind') != 'send' or item.get('redacted'):
            continue
        if item.get('state') in ('observed', 'checked'):
            processed += 1
        else:
            pending += 1
    size = 0
    for directory, dirs, files in os.walk(b.ROOT, followlinks=False):
        from pathlib import Path
        for name in files:
            path = Path(directory) / name
            if not path.is_symlink():
                try: size += path.stat().st_size
                except OSError: pass
    return {'bytes': size, 'processed': processed, 'pending': pending}


def clean():
    count = 0
    for path, item in records():
        if item.get('kind') != 'send' or item.get('state') not in ('observed', 'checked') or item.get('redacted'):
            continue
        # Keep an idempotency tombstone: replaying the same request ID must not send again.
        tombstone = {key: item[key] for key in ('id', 'kind', 'sessionKey', 'state', 'time') if key in item}
        tombstone.update(redacted=True, text='')
        b.atomic(path, tombstone)
        count += 1
    return {'cleaned': count}
