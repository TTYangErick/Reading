"""Build deterministic, original EPUB acceptance samples (no external content)."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1] / 'app/test/fixtures/epub'
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
# Original, visibly recognizable image: warm background and three blue bars.
raw = bytearray()
for y in range(240):
    raw.append(0)
    for x in range(480):
        bar = 40 < y < 200 and any(left < x < right for left, right in [(60, 130), (200, 270), (340, 410)])
        raw.extend((51, 100, 135) if bar else (246, 235, 215))
PNG = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 480, 240, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
def make(version):
    nav = '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="text/first.xhtml#start">First lesson</a><ol><li><a href="text/first.xhtml#table">Word table</a></li></ol></li><li><a href="text/second.xhtml#next">Second lesson</a></li></ol></nav></body></html>'''
    ncx = '''<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap><navPoint id="n1"><navLabel><text>First lesson</text></navLabel><content src="text/first.xhtml#start"/><navPoint id="n2"><navLabel><text>Word table</text></navLabel><content src="text/first.xhtml#table"/></navPoint></navPoint><navPoint id="n3"><navLabel><text>Second lesson</text></navLabel><content src="text/second.xhtml#next"/></navPoint></navMap></ncx>'''
    opf = f'''<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="{version}.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">reading-test-{version}</dc:identifier><dc:title>Reading EPUB {version} sample</dc:title><dc:language>en</dc:language></metadata><manifest><item id="second" href="text/second.xhtml" media-type="application/xhtml+xml"/><item id="first" href="text/first.xhtml" media-type="application/xhtml+xml"/><item id="picture" href="images/lesson%20image.png" media-type="image/png"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest><spine toc="toc"><itemref idref="first"/><itemref idref="second"/></spine></package>'''
    if version == 2: opf = opf.replace(' properties="nav"', '')
    first = '''<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Hidden title</title><style>p{color:red}</style></head><body><h1 id="start">Chapter One</h1><p>Tomorrow is another <em>day</em>. Reading is a quiet pleasure.</p><p>Words &amp; pictures.</p><figure><img src="../images/lesson%20image.png" alt="Lesson image"/><figcaption>A small original image.</figcaption></figure><table id="table"><caption>Vocabulary</caption><thead><tr><th>Word</th><th>Meaning</th></tr></thead><tbody><tr><td>Tomorrow</td><td>The next day</td></tr><tr><td>Reading</td><td>Learning from books</td></tr></tbody></table><p>Continue to the next lesson.</p></body></html>'''
    second = '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1 id="next">Chapter Two</h1>' + ''.join(f'<p>Lesson paragraph {i}. Tomorrow we will keep reading books.</p>' for i in range(1, 51)) + '</body></html>'
    files = {'mimetype': 'application/epub+zip', 'META-INF/container.xml': '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>', 'OPS/book.opf': opf, 'OPS/nav.xhtml': nav, 'OPS/toc.ncx': ncx, 'OPS/text/first.xhtml': first, 'OPS/text/second.xhtml': second, 'OPS/images/lesson image.png': PNG}
    ROOT.mkdir(parents=True, exist_ok=True)
    with ZipFile(ROOT / f'lesson-epub{version}.epub', 'w') as archive:
        for name, data in files.items():
            info = ZipInfo(name, date_time=(2026, 9, 30, 0, 0, 0))
            info.compress_type = 0 if name == 'mimetype' else ZIP_DEFLATED
            archive.writestr(info, data)

if __name__ == '__main__':
    make(2)
    make(3)
