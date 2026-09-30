import csv
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from dict_builder.build_ecdict import build, senses


class DictionaryBuildTests(unittest.TestCase):
    def test_senses_order_and_pos(self):
        self.assertEqual(senses('n. 明天, 未来\\nadv. 明天, 未来地'), [('n.', '明天'), ('n.', '未来'), ('adv.', '未来地')])

    def test_schema_inflections_and_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            source, output = path/'source.csv', path/'dict.sqlite'
            with source.open('w') as stream:
                writer = csv.DictWriter(stream, fieldnames=['word','translation','exchange'])
                writer.writeheader()
                writer.writerows([{'word':'go','translation':'vi. 去, 走','exchange':'p:went/d:gone/i:going/s:goes'}, {'word':'went','translation':'go的过去式','exchange':'0:go/1:p'}])
            build(source, output, {'revision':'test'})
            db = sqlite3.connect(output)
            self.assertEqual(db.execute('select lemma from forms where form="went"').fetchall(), [('go',)])
            self.assertEqual(db.execute('select gloss_zh from senses where headword="go" order by rank').fetchall(), [('去',),('走',)])
            self.assertEqual(db.execute('pragma integrity_check').fetchone()[0], 'ok')
            db.close()
            manifest = json.loads((path/'manifest.json').read_text())
            self.assertEqual(manifest['counts']['entries'], 2)
            self.assertEqual(manifest['bytes'], output.stat().st_size)


if __name__ == '__main__':
    unittest.main()
