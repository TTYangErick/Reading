#!/usr/bin/env python3
"""Fetch pinned, licensed dictionary/font inputs. No credentials are needed."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
proxy = os.environ.get('READING_PROXY_URL', 'http://127.0.0.1:7897')


def get(url):
    # System curl uses macOS's configured certificate roots; never disable TLS checks.
    command = ['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '3',
               '--max-time', '180', '--user-agent', 'Reading-asset-builder']
    if proxy:
        command += ['--proxy', proxy]
    return subprocess.check_output(command + [url])


def download(url, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = get(url)
    temporary = path.with_suffix(path.suffix + '.part')
    temporary.write_bytes(data)
    temporary.replace(path)
    print(f'{path.relative_to(ROOT)}: {len(data):,} bytes', flush=True)
    return hashlib.sha256(data).hexdigest()


def main():
    lock = ROOT / 'dict_builder/source.json'
    if lock.exists():
        meta = json.loads(lock.read_text())
    else:
        commit = json.loads(get('https://api.github.com/repos/skywind3000/ECDICT/commits/master'))['sha']
        meta = {'repository': 'https://github.com/skywind3000/ECDICT', 'revision': commit,
                'url': f'https://raw.githubusercontent.com/skywind3000/ECDICT/{commit}/ecdict.csv', 'license': 'MIT'}
    csv_path = ROOT / 'dict_builder/data/ecdict.csv'
    if not csv_path.exists() or hashlib.sha256(csv_path.read_bytes()).hexdigest() != meta.get('sha256'):
        digest = download(meta['url'], csv_path)
        if meta.get('sha256') and digest != meta['sha256']:
            raise ValueError('ECDICT input checksum mismatch')
        meta['sha256'] = digest
    lock.write_text(json.dumps(meta, indent=2) + '\n')
    download(f'https://raw.githubusercontent.com/skywind3000/ECDICT/{meta["revision"]}/LICENSE', ROOT / 'app/assets/licenses/ECDICT.txt')
    for directory, name in [('literata', 'Literata'), ('sourceserif4', 'SourceSerif4'),
                            ('ebgaramond', 'EBGaramond'), ('atkinsonhyperlegible', 'AtkinsonHyperlegible')]:
        destination = ROOT / f'app/assets/fonts/{name}.ttf'
        if destination.exists():
            continue
        listing = json.loads(get(f'https://api.github.com/repos/google/fonts/contents/ofl/{directory}'))
        fonts = [x for x in listing if x['name'].endswith('.ttf') and 'italic' not in x['name'].lower()]
        font = next((x for x in fonts if 'Regular' in x['name']), fonts[0])
        download(font['download_url'], destination)
        license_file = next(x for x in listing if x['name'] == 'OFL.txt')
        download(license_file['download_url'], ROOT / f'app/assets/licenses/{name}.txt')


if __name__ == '__main__':
    main()
