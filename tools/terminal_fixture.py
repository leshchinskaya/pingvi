"""Harmless interactive transport fixture; never launches an agent or shell command."""
import json
from pathlib import Path
print('\033[2J\033[H', end='')
print('Would you like to run the following command?')
print('  $ true  # transport fixture only')
print('› 1. Yes, proceed (y)')
print('  2. No, cancel (esc)')
print('  Press enter to confirm or esc to cancel', flush=True)
answer = input()
Path(__file__).with_name('fixture-result.json').write_text(json.dumps({'received': answer}))
print('TRANSPORT_ACK:' + answer, flush=True)
