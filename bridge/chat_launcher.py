"""Start the selected agent without placing user messages in shell source."""
import json
import os
from pathlib import Path
import sys
path = Path(sys.argv[1])
request = json.loads(path.read_text())
path.unlink()
os.chdir(request['cwd'])
os.execv(request['argv'][0], request['argv'])
