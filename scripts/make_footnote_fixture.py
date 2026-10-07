"""Build original EPUB 2/3 samples for native footnote acceptance."""
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

from make_epub_fixture import PNG, ROOT


def make(version):
    def page(body):
        return ('<html xmlns="http://www.w3.org/1999/xhtml" '
                'xmlns:epub="http://www.idpf.org/2007/ops"><body>'
                + body + '</body></html>')

    ref = ' epub:type="noteref"' if version == 3 else ''
    back = ' epub:type="backlink"' if version == 3 else ''
    intro = ''.join(
        f'<p>Opening paragraph {i}. Tomorrow we will read a little more. '
        'Keep this place when visiting a note.</p>' for i in range(1, 9))
    body = page(
        '<h1 id="start">Footnote practice</h1>' + intro
        + '<h2 id="practice">Links and return</h2>'
        + f'<p>Tomorrow is another day. <a id="ref" href="notes.xhtml#one"{ref}>[1]</a></p>'
        + '<p><a id="inline-ref" href="#inline-note">[2] Note in this chapter</a></p>'
        + f'<p><a id="wide-ref" href="notes.xhtml#wide"{ref}>'
        '[3] This deliberately long footnote marker wraps across several lines '
        'so that every part can be tapped.</a></p>'
        + '<p><a href="missing.xhtml#none">Missing note</a> / '
        '<a href="https://example.invalid/">Outside link</a></p>'
        + ''.join(f'<p>Reading paragraph {i}. Books offer a quiet moment every day.</p>'
                  for i in range(1, 21))
        + '<h2 id="inline-note">Same chapter note</h2>'
        + '<p>This note belongs to the continuous body.</p>'
        + f'<p><a href="body.xhtml#inline-ref"{back}>Return to [2]</a></p>')
    notes = page(
        '<h1 id="one">Independent note one</h1>'
        '<p>Tomorrow means the next day. Tap Tomorrow to look it up. '
        'Hold this sentence and release to copy it.</p>'
        f'<p><a href="body.xhtml#ref"{back}>Return to [1]</a></p>'
        '<p><a id="nested-ref" href="extra.xhtml#extra">Open nested note</a></p>'
        '<img src="images/bars.png" alt="Three blue bars"/>'
        '<table><tr><th>Word</th><th>Meaning</th></tr>'
        '<tr><td>Tomorrow</td><td>The next day</td></tr></table>'
        '<h2 id="wide">Wrapped marker destination</h2>'
        '<p>The wide link arrived here.</p>'
        f'<p><a href="body.xhtml#wide-ref"{back}>Return to [3]</a></p>')
    extra = page(
        '<h1 id="extra">Nested note</h1><p>This page is outside the spine.</p>'
        f'<p><a href="notes.xhtml#nested-ref"{back}>Return one level</a></p>'
        f'<p><a href="body.xhtml#ref"{back}>Return directly to [1]</a></p>'
        '<p><a href="extra.xhtml#extra">Open this note again</a></p>')
    nav = page('<nav epub:type="toc"><ol>'
               '<li><a href="body.xhtml#start">Opening</a></li>'
               '<li><a href="body.xhtml#practice">Links and return</a></li>'
               '</ol></nav>')
    ncx = ('<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>'
           '<navPoint id="start"><navLabel><text>Opening</text></navLabel>'
           '<content src="body.xhtml#start"/></navPoint>'
           '<navPoint id="practice"><navLabel><text>Links and return</text></navLabel>'
           '<content src="body.xhtml#practice"/></navPoint></navMap></ncx>')
    nav_property = ' properties="nav"' if version == 3 else ''
    opf = f'''<package xmlns="http://www.idpf.org/2007/opf" version="{version}.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">reading-footnotes-{version}</dc:identifier><dc:title>Reading footnotes EPUB {version}</dc:title><dc:language>en</dc:language></metadata>
<manifest><item id="body" href="body.xhtml" media-type="application/xhtml+xml"/>
<item id="notes" href="notes.xhtml" media-type="application/xhtml+xml"/>
<item id="extra" href="extra.xhtml" media-type="application/xhtml+xml"/>
<item id="image" href="images/bars.png" media-type="image/png"/>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml"{nav_property}/>
<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>
<spine toc="ncx"><itemref idref="body"/><itemref idref="notes" linear="no"/></spine></package>'''
    files = {
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
        'OPS/book.opf': opf, 'OPS/body.xhtml': body, 'OPS/notes.xhtml': notes,
        'OPS/extra.xhtml': extra, 'OPS/nav.xhtml': nav, 'OPS/toc.ncx': ncx,
        'OPS/images/bars.png': PNG,
    }
    ROOT.mkdir(parents=True, exist_ok=True)
    with ZipFile(ROOT / f'footnotes-epub{version}.epub', 'w') as archive:
        for name, data in files.items():
            info = ZipInfo(name, date_time=(2026, 10, 3, 0, 0, 0))
            info.compress_type = 0 if name == 'mimetype' else ZIP_DEFLATED
            archive.writestr(info, data)


if __name__ == '__main__':
    make(2)
    make(3)
