import gzip
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from build_wiktionary import build, digest


class WiktionaryBuildTest(unittest.TestCase):
    def test_filters_languages_preserves_senses_and_excludes_quotations(self):
        records = [
            dict(word='read', lang_code='en', pos='verb', sounds=[{'ipa': '/riːd/'}],
                 forms=[{'form': 'reads', 'tags': ['third-person']}, {'form': 'read', 'tags': ['canonical']}],
                 senses=[{'glosses': ['Test parent sense.', 'Test child sense.'], 'tags': ['transitive'],
                          'qualifier': 'test qualifier', 'examples': [
                              {'text': 'A test example.', 'type': 'example'},
                              {'text': 'A test example.', 'type': 'example'},
                              {'text': 'A quoted excerpt.', 'type': 'quotation', 'ref': 'A book'},
                              {'text': 'Attributed example.', 'type': 'example', 'ref': 'A book'},
                              {'text': 'Unclassified example.'}]},
                         {'glosses': ['Another sense.']}]),
            dict(word='read', lang_code='en', pos='noun', senses=[{'glosses': ['A noun sense.']}]),
            dict(word='reads', lang_code='en', pos='verb', senses=[{'glosses': ['A form of read.'], 'form_of': [{'word': 'read'}]}]),
            dict(word='alien', lang_code='fr', pos='noun', senses=[{'glosses': ['Not English.']}]),
            dict(word='empty', lang_code='en', senses=[{}]),
            dict(word='orphan', lang_code='en', senses=[{'glosses': ['Missing target.'], 'alt_of': [{'word': 'missing'}]}]),
        ]
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            source = tmp / 'input.jsonl'
            source.write_text(''.join(json.dumps(e) + '\n' for e in records))
            output = tmp / 'w.sqlite'
            first = build(source, output, {'license': 'CC-BY-SA-4.0', 'testFixture': True})
            with sqlite3.connect(output) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM entries').fetchone()[0], 4)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM entries WHERE word IN ("alien","empty")').fetchone()[0], 0)
                row = db.execute('SELECT gloss,tags,examples FROM senses WHERE entry_id=1 ORDER BY rank').fetchone()
                self.assertEqual(row[0], 'Test parent sense. — Test child sense.')
                self.assertEqual(json.loads(row[1]), ['transitive', 'test qualifier'])
                self.assertEqual(json.loads(row[2]), ['A test example.'])
                self.assertEqual(db.execute('SELECT form_key,lemma FROM forms').fetchall(), [('reads', 'read')])
                self.assertEqual(db.execute('SELECT is_form FROM senses WHERE entry_id=3').fetchone()[0], 1)
            self.assertEqual(gzip.decompress(output.with_suffix('.sqlite.gz').read_bytes()), output.read_bytes())
            second = build(source, output, {'license': 'CC-BY-SA-4.0', 'testFixture': True})
            self.assertEqual(first, second)
            self.assertEqual(first['sha256'], digest(output))

    def test_bad_source_keeps_previous_valid_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            source = tmp / 'bad.jsonl'
            source.write_text('{bad}\n')
            output = tmp / 'w.sqlite'
            output.write_bytes(b'previous valid dictionary')
            with self.assertRaises(json.JSONDecodeError):
                build(source, output, {})
            self.assertEqual(output.read_bytes(), b'previous valid dictionary')


if __name__ == '__main__':
    unittest.main()
