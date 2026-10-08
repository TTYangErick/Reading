"""Build small, deterministic shelf acceptance books from owned lesson content.

No reader content, links or source anchors are added by the cover metadata.
"""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import struct
import zlib

from make_epub_fixture import chunk

ROOT = Path(__file__).resolve().parents[1] / 'app/test/fixtures/epub'
COVER_PATH = 'OPS/images/shelf cover.png'


def cover_png():
    # Original portrait cover: warm paper, brown border and a simple open book.
    width, height = 320, 480
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            border = x < 12 or x >= width - 12 or y < 12 or y >= height - 12
            page = 64 <= x < 156 and 172 <= y < 296 or 164 <= x < 256 and 172 <= y < 296
            line = page and y in range(196, 278, 20) and (80 <= x < 140 or 180 <= x < 240)
            spine = 154 <= x < 166 and 170 <= y < 306
            color = (131, 92, 62) if border or line or spine else (255, 249, 239) if page else (230, 213, 188)
            raw.extend(color)
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def make(kind):
    assert kind in {'cover', 'missing', 'broken'}
    with ZipFile(ROOT / 'lesson-epub3.epub') as source:
        files = {name: source.read(name) for name in source.namelist()}
    opf = files['OPS/book.opf'].decode('utf-8')
    opf = opf.replace('reading-test-3', f'reading-shelf-{kind}')
    opf = opf.replace('Reading EPUB 3 sample', f'Reading shelf — {kind}')
    opf = opf.replace('</metadata>', '''<dc:creator id="author">Reading Sample Author</dc:creator>
<meta refines="#author" property="role" scheme="marc:relators">aut</meta></metadata>''')
    opf = opf.replace('</manifest>', '''<item id="shelf-cover" href="images/shelf%20cover.png"
media-type="image/png" properties="cover-image"/></manifest>''')
    files['OPS/book.opf'] = opf.encode('utf-8')
    if kind != 'missing':
        files[COVER_PATH] = cover_png() if kind == 'cover' else b'not a decodable image'
    with ZipFile(ROOT / f'shelf-{kind}.epub', 'w') as output:
        for name, data in files.items():
            info = ZipInfo(name, date_time=(2026, 10, 8, 0, 0, 0))
            info.compress_type = 0 if name == 'mimetype' else ZIP_DEFLATED
            output.writestr(info, data)


if __name__ == '__main__':
    for kind in ('cover', 'missing', 'broken'):
        make(kind)
