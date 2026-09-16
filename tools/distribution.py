"""Release preflight: local test images are distinct from distributable releases."""
import argparse
import json
import os
from pathlib import Path
import platform
import subprocess


def problems(mode, environment, architecture, runtime_architecture, identities):
    errors = []
    if architecture != runtime_architecture:
        errors.append('This build requires Apple Silicon (arm64); its bundled Python cannot run on Intel.')
    if mode == 'release':
        identity = environment.get('SIGNING_IDENTITY', '').strip()
        if not identity or identity == '-':
            errors.append('SIGNING_IDENTITY must select a Developer ID Application certificate; ad-hoc signing is not a distributable release.')
        elif not any(identity in line and '"Developer ID Application:' in line for line in identities.splitlines()):
            errors.append('The selected Developer ID Application identity is not available in the signing keychain.')
        if not environment.get('NOTARY_PROFILE', '').strip():
            errors.append('NOTARY_PROFILE is required for notarization. Configure it with notarytool store-credentials.')
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['release', 'local', 'adhoc'])
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    runtime = json.loads((root / 'tools/python-runtime.lock.json').read_text())
    identities = ''
    if args.mode == 'release':
        result = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'], capture_output=True, text=True)
        identities = result.stdout if result.returncode == 0 else ''
    errors = problems(args.mode, os.environ, platform.machine(), runtime['architecture'], identities)
    if errors:
        for error in errors:
            print('ERROR: ' + error)
        print('Use --local only for an explicitly unsigned local test image; do not publish it as a verified release.')
        raise SystemExit(1)
    print('Preflight OK: ' + args.mode)


if __name__ == '__main__':
    main()
