"""Package generated artwork into the system app-icon catalog. No visual edits."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
catalog = root / '.build/PingviAssets.xcassets'
icons = catalog / 'AppIcon.appiconset'
icons.mkdir(parents=True, exist_ok=True)
(catalog / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
images = []
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        filename = f'icon_{points}x{points}@{scale}x.png'
        subprocess.run(['/usr/bin/sips', '-z', str(points * scale), str(points * scale), str(root / 'Assets/Ice.png'), '--out', str(icons / filename)], check=True, stdout=subprocess.DEVNULL)
        images.append({'idiom': 'mac', 'size': f'{points}x{points}', 'scale': f'{scale}x', 'filename': filename})
(icons / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}))
