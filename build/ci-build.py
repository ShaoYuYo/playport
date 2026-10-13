#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the pipeline with visible progress while stage output goes to its log."""
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time

repo = Path(__file__).resolve().parent.parent
work = Path(os.environ.get('PLAYPORT_BUILD', repo / '.work'))
work.mkdir(parents=True, exist_ok=True)
with (work / 'pp-build-console.log').open('a') as log:
    process = subprocess.Popen([str(repo / 'pp'), 'build', *sys.argv[1:]], cwd=repo,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    heartbeat = time.monotonic() + 45
    while selector.get_map():
        for key, _ in selector.select(timeout=1):
            chunk = os.read(key.fileobj.fileno(), 65536)
            if not chunk:
                selector.unregister(key.fileobj)
            else:
                text = chunk.decode('utf-8', errors='replace')
                print(text, end='', flush=True)
                log.write(text)
                log.flush()
        if time.monotonic() >= heartbeat and process.poll() is None:
            candidates = list((work / 'run/logs').glob('*.log'))
            if candidates:
                latest = max(candidates, key=lambda p: p.stat().st_mtime)
                with latest.open('rb') as stream:
                    stream.seek(max(0, latest.stat().st_size - 2048))
                    tail = stream.read().decode('utf-8', errors='replace').splitlines()[-3:]
                print(f"[build heartbeat] active log {latest.name}: {' | '.join(tail)}", flush=True)
            heartbeat = time.monotonic() + 45
    selector.close()
    sys.exit(process.wait())
