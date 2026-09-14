"""Sign nested Mach-O code before sealing the app bundle."""
import os
from pathlib import Path
import subprocess
import sys
app = Path(sys.argv[1])
identity = os.environ.get('SIGNING_IDENTITY', '-')
options = ['--options', 'runtime', '--timestamp'] if identity != '-' else []
magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
for path in sorted(app.rglob('*')):
    if path == app / 'Contents/MacOS/AgentAttention' or path.is_symlink() or not path.is_file():
        continue
    with path.open('rb') as f:
        macho = f.read(4) in magic
    if macho:
        subprocess.run(['codesign', '--force', '--sign', identity, *options, str(path)], check=True)
subprocess.run(['codesign', '--force', '--sign', identity, *options, '--entitlements', 'tools/Pingvi.entitlements', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
