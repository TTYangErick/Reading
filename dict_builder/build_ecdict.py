#!/usr/bin/env python3
"""Compile the pinned ECDICT CSV to the app's versioned offline dictionary."""
import argparse
import csv
import hashlib
import json
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POS = re.compile(r'^(?P<pos>(?:(?:n|v|vt|vi|a|adj|ad|adv|prep|pron|conj|interj|int|num|art|aux|det|abbr|pl)\.[ /]*)+)\s*', re.I)


def senses(text):
    """Keep source ordering; POS and domain markers are not standalone senses."""
    result, seen = [], set()
    for line in text.replace('\\n', '\n').splitlines():
        line = line.strip()
        if not line:
            continue
        match = POS.match(line)
        pos = match.group('pos').strip() if match else ''
        body = line[match.end():] if match else line
        body = re.sub(r'^\[[^]]+\]\s*', '', body)
        for gloss in re.split(r'[;；，]|,\s*', body):
            gloss = gloss.strip()
            if gloss and gloss not in seen:
                seen.add(gloss)
                result.append((pos, gloss))
    return result


def build(source, output, metadata):
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_suffix('.building')
    if temp.exists():
        temp.unlink()
    db = sqlite3.connect(temp)
    db.executescript('''
      PRAGMA journal_mode=OFF;
      PRAGMA synchronous=OFF;
      PRAGMA user_version=1;
      CREATE TABLE entries(headword TEXT PRIMARY KEY COLLATE NOCASE, phonetic TEXT NOT NULL,
        pos TEXT NOT NULL, full_gloss TEXT NOT NULL, definition TEXT NOT NULL, freq INTEGER NOT NULL) WITHOUT ROWID;
      CREATE TABLE senses(headword TEXT NOT NULL COLLATE NOCASE, rank INTEGER NOT NULL,
        pos TEXT NOT NULL, gloss_zh TEXT NOT NULL, PRIMARY KEY(headword,rank)) WITHOUT ROWID;
      CREATE TABLE forms(form TEXT NOT NULL COLLATE NOCASE, lemma TEXT NOT NULL COLLATE NOCASE,
        PRIMARY KEY(form,lemma)) WITHOUT ROWID;
    ''')
    with source.open(encoding='utf-8-sig', newline='') as stream:
        for row in csv.DictReader(stream):
            word = row['word'].strip().lower()
            if not word:
                continue
            gloss = row.get('translation', '').replace('\\n', '\n')
            english = row.get('definition', '').replace('\\n', '\n')
            freq = int(row.get('frq') or row.get('bnc') or 0)
            inserted = db.execute('INSERT OR IGNORE INTO entries VALUES(?,?,?,?,?,?)',
                                 (word, row.get('phonetic', ''), row.get('pos', ''), gloss, english, freq))
            if inserted.rowcount:
                db.executemany('INSERT INTO senses VALUES(?,?,?,?)',
                               [(word, i, pos, g) for i, (pos, g) in enumerate(senses(gloss))])
            for exchange in row.get('exchange', '').split('/'):
                if ':' not in exchange:
                    continue
                kind, forms = exchange.split(':', 1)
                if kind == '1':
                    continue
                for form in forms.split(','):
                    form = form.strip().lower()
                    if not form or form == word:
                        continue
                    pair = (word, form) if kind == '0' else (form, word)
                    db.execute('INSERT OR IGNORE INTO forms VALUES(?,?)', pair)
    db.execute('DELETE FROM forms WHERE lemma NOT IN (SELECT headword FROM entries)')
    counts = {table: db.execute(f'SELECT count(*) FROM {table}').fetchone()[0] for table in ['entries', 'senses', 'forms']}
    db.commit()
    assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    db.close()
    temp.replace(output)
    manifest = {'schemaVersion': 1, 'id': 'ecdict-en-zh', 'name': 'ECDICT 英汉词典',
                'language': 'en', 'targetLanguage': 'zh', 'file': output.name,
                'source': metadata, 'counts': counts, 'bytes': output.stat().st_size,
                'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
    (output.parent / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT / 'dict_builder/data/ecdict.csv')
    parser.add_argument('--output', type=Path, default=ROOT / 'app/assets/dictionaries/ecdict.sqlite')
    args = parser.parse_args()
    metadata = json.loads((ROOT / 'dict_builder/source.json').read_text())
    digest = hashlib.sha256(args.source.read_bytes()).hexdigest()
    if digest != metadata['sha256']:
        raise SystemExit('Source checksum mismatch; fetch the pinned CSV again.')
    build(args.source, args.output, metadata)
