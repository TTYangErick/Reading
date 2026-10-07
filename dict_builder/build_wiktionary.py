#!/usr/bin/env python3
"""Stream a pinned raw Wiktextract dump into a separate CC BY-SA dictionary."""
import argparse
import gzip
import hashlib
import json
import sqlite3
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def key(text):
    return text.replace('’', "'").lower()


def senses(entry):
    """Preserve sense order, hierarchy and qualifiers; exclude quoted examples."""
    for sense in entry.get('senses', []):
        glosses = [s.strip() for s in sense.get('glosses', []) if isinstance(s, str) and s.strip()]
        if not glosses:
            continue
        tags = list(dict.fromkeys(entry.get('tags', []) + sense.get('tags', [])))
        if sense.get('qualifier'):
            tags.append(sense['qualifier'])
        examples = [e['text'] for e in sense.get('examples', [])
                    if e.get('type') == 'example' and e.get('text')
                    and not any(e.get(k) for k in ('ref', 'reference', 'author', 'title', 'source'))]
        yield (' — '.join(glosses), json.dumps(tags, ensure_ascii=False),
               json.dumps(list(dict.fromkeys(examples)), ensure_ascii=False),
               int(bool(sense.get('form_of') or sense.get('alt_of'))))


def build(source, output, metadata):
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix('.building')
    temporary.unlink(missing_ok=True)
    db = sqlite3.connect(temporary)
    try:
        db.executescript('''
          PRAGMA journal_mode=OFF;
          PRAGMA synchronous=OFF;
          PRAGMA user_version=1;
          CREATE TABLE entries(id INTEGER PRIMARY KEY,word TEXT NOT NULL,word_key TEXT NOT NULL,
            pos TEXT NOT NULL,ipa TEXT NOT NULL);
          CREATE TABLE senses(entry_id INTEGER NOT NULL,rank INTEGER NOT NULL,gloss TEXT NOT NULL,
            tags TEXT NOT NULL,examples TEXT NOT NULL,is_form INTEGER NOT NULL,
            PRIMARY KEY(entry_id,rank)) WITHOUT ROWID;
          CREATE TABLE forms(form_key TEXT NOT NULL,lemma TEXT NOT NULL,
            PRIMARY KEY(form_key,lemma)) WITHOUT ROWID;
        ''')
        opener = gzip.open if source.suffix == '.gz' else open
        english_records = 0
        with opener(source, 'rt', encoding='utf-8') as stream:
            for line in stream:
                entry = json.loads(line)
                if entry.get('lang_code') != 'en' or not entry.get('word'):
                    continue
                word = entry['word']
                rows = list(senses(entry))
                if not rows:
                    continue
                ipa = next((s['ipa'] for s in entry.get('sounds', []) if s.get('ipa')), '')
                cursor = db.execute('INSERT INTO entries(word,word_key,pos,ipa) VALUES(?,?,?,?)',
                                    (word, key(word), entry.get('pos', ''), ipa))
                db.executemany('INSERT INTO senses VALUES(?,?,?,?,?,?)',
                               [(cursor.lastrowid, i, *row) for i, row in enumerate(rows)])
                for form in entry.get('forms', []):
                    text = form.get('form', '')
                    if text and key(text) != key(word) and 'table-tags' not in form.get('tags', []):
                        db.execute('INSERT OR IGNORE INTO forms VALUES(?,?)', (key(text), word))
                for sense in entry.get('senses', []):
                    for ref in sense.get('form_of', []) + sense.get('alt_of', []):
                        if ref.get('word') and key(ref['word']) != key(word):
                            db.execute('INSERT OR IGNORE INTO forms VALUES(?,?)', (key(word), ref['word']))
                english_records += 1
                if english_records % 100000 == 0:
                    print(f'English records: {english_records:,}', flush=True)
        db.execute('CREATE INDEX entries_key ON entries(word_key)')
        db.execute('CREATE INDEX entries_word ON entries(word)')
        db.execute('DELETE FROM forms WHERE lemma NOT IN (SELECT word FROM entries)')
        counts = {table: db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]
                  for table in ('entries', 'senses', 'forms')}
        counts['words'] = db.execute('SELECT COUNT(DISTINCT word) FROM entries').fetchone()[0]
        if not counts['words']:
            raise ValueError('No English entries in source')
        db.commit()
        if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise ValueError('Dictionary integrity check failed')
    finally:
        db.close()
    temporary.replace(output)
    packed = output.with_suffix(output.suffix + '.gz')
    with output.open('rb') as source_stream, packed.open('wb') as target:
        with gzip.GzipFile(filename='', mode='wb', fileobj=target, mtime=0) as compressed:
            shutil.copyfileobj(source_stream, compressed, 1024 * 1024)
    manifest = dict(schemaVersion=1, id='wiktionary-en-en', name='Wiktionary 英英词典',
                    language='en', targetLanguage='en', file=output.name, source=metadata,
                    counts=counts, bytes=output.stat().st_size, sha256=digest(output),
                    compressedFile=packed.name, compressedBytes=packed.stat().st_size,
                    compressedSha256=digest(packed))
    output.with_name('wiktionary-manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(manifest, ensure_ascii=False, indent=2), flush=True)
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT / 'dict_builder/data/wiktionary-20261003.jsonl.gz')
    parser.add_argument('--output', type=Path, default=ROOT / 'app/assets/dictionaries/wiktionary.sqlite')
    args = parser.parse_args()
    metadata = json.loads((ROOT / 'dict_builder/wiktionary-source.json').read_text())
    if digest(args.source) != metadata['sha256']:
        raise SystemExit('Wiktionary source checksum mismatch; keep the pinned snapshot, do not silently update it.')
    build(args.source, args.output, metadata)
