#!/usr/bin/env python3
"""Download the pinned compressed dump without buffering it into memory."""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'dict_builder'))
from build_wiktionary import digest


def main():
    meta = json.loads((ROOT / 'dict_builder/wiktionary-source.json').read_text())
    destination = ROOT / 'dict_builder/data' / meta['file']
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and digest(destination) == meta['sha256']:
        print('Pinned Wiktionary snapshot already present.')
        return
    partial = destination.with_suffix(destination.suffix + '.part')
    command = ['curl', '--fail', '--location', '--retry', '2', '--connect-timeout', '30',
               '--max-time', '3600', '--output', str(partial)]
    proxy = os.environ.get('READING_PROXY_URL', 'http://127.0.0.1:7897')
    if proxy:
        command += ['--proxy', proxy]
    subprocess.run(command + [meta['url']], check=True)
    if digest(partial) != meta['sha256']:
        raise SystemExit('Source changed or download corrupt. Preserve the old snapshot; review a new version explicitly.')
    partial.replace(destination)
    print(f'Verified {destination.name}: {destination.stat().st_size:,} bytes')


if __name__ == '__main__':
    main()
