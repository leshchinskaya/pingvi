"""Embed the pinned, checksum-verified standalone runtime. Build-time only."""
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile

root = Path(__file__).resolve().parents[1]
lock = json.loads((root / 'tools/python-runtime.lock.json').read_text())
if platform.machine() != lock['architecture']:
    raise SystemExit('This runtime is pinned for Apple Silicon; add a reviewed lock for other architectures.')
archive = root / '.build/python-runtime.tar.gz'
if not archive.exists():
    subprocess.run(['curl', '-fLsS', lock['url'], '-o', str(archive)], check=True)
if hashlib.sha256(archive.read_bytes()).hexdigest() != lock['sha256']:
    raise SystemExit('Python runtime checksum mismatch. Archive not used.')
legacy = Path(sys.argv[1]) / 'Contents/Frameworks/Python'
if legacy.exists():
    shutil.rmtree(legacy)
destination = Path(sys.argv[1]) / 'Contents/Resources/Python'
if destination.exists():
    shutil.rmtree(destination)  # Only the generated runtime, never user files.
destination.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(dir=root / '.build', prefix='python-extract-') as temporary:
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            parts = Path(member.name).parts
            if not parts or parts[0] != 'python' or '..' in parts:
                raise SystemExit('Unexpected runtime archive path')
        tar.extractall(temporary, filter='data')
    shutil.copytree(Path(temporary) / 'python', destination, symlinks=True)
# The app needs the interpreter, not pip/IDLE/pydoc command wrappers.
for command in (destination / 'bin').iterdir():
    if command.name not in ('python3', 'python3.13'):
        command.unlink()
shutil.copy2(root / 'tools/python-runtime.lock.json', destination / 'pingvi-runtime.json')
shutil.copytree(root / 'Assets/PythonLicenses', destination / 'licenses', dirs_exist_ok=True)
print('Embedded Python ' + lock['version'])
