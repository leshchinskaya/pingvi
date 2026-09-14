"""Render app icons with the same transparent margins used by the Dock."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
catalog = root / '.build/PingviAssets.xcassets'
icons = catalog / 'AppIcon.appiconset'
icons.mkdir(parents=True, exist_ok=True)
renderer = root / '.build/render-icon'
subprocess.run(['swiftc', str(root / 'Sources/AgentAttention/AppIconLayout.swift'),
                str(root / 'tools/icon-renderer/main.swift'), '-o', str(renderer)], check=True)
(catalog / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
images = []
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        filename = f'icon_{points}x{points}@{scale}x.png'
        subprocess.run([str(renderer), str(root / 'Assets/Ice.png'), str(icons / filename), str(points * scale)], check=True)
        images.append({'idiom': 'mac', 'size': f'{points}x{points}', 'scale': f'{scale}x', 'filename': filename})
(icons / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}))
