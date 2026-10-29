"""Build the app's image resources from the original Quincy bitmaps.

Everything is scaled nearest-neighbour so the 16px Win2000 artwork stays crisp
on Retina. Run from the project root; writes into resources/.  The app icon is not
made here: it is drawn as SVG layers in resources/Quincy.icon (see build.sh).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'reference', 'res_png')
DST = os.path.join(ROOT, 'resources')


def dekey(w, h, rgba, key=(192, 192, 192)):
    """Make the Win2000 transparency colour transparent."""
    for i in range(w * h):
        if tuple(rgba[i * 4:i * 4 + 3]) == key:
            rgba[i * 4 + 3] = 0
    return rgba


def emit(name, w, h, rgba):
    png.write(os.path.join(DST, name + '.png'), w, h, rgba)
    w2, h2, r2 = png.scale(w, h, rgba, 2)
    png.write(os.path.join(DST, name + '@2x.png'), w2, h2, r2)


def main():
    os.makedirs(DST, exist_ok=True)

    # Toolbar strip: 27 buttons of 16x16, grey background knocked out.
    w, h, rgba = png.read(os.path.join(SRC, 'BITMAP_128_1033.png'))
    emit('toolbar', w, h, dekey(w, h, rgba))

    # Editor gutter glyphs: breakpoint hand, current-line arrow, both.
    for res, name in (('172', 'gutter_arrow'), ('174', 'gutter_break'),
                      ('175', 'gutter_both')):
        w, h, rgba = png.read(os.path.join(SRC, 'BITMAP_%s_1033.png' % res))
        emit(name, w, h, dekey(w, h, rgba))

    # Dr. Dobb's logo on the About box (white background, keep as is).
    w, h, rgba = png.read(os.path.join(SRC, 'BITMAP_137_1033.png'))
    emit('ddj', w, h, rgba)

    # Cat and project-file icons.
    for src, name in (('icon128_32.png', 'cat'), ('icon129_32.png', 'proj')):
        w, h, rgba = png.read(os.path.join(SRC, src))
        emit(name, w, h, rgba)


if __name__ == '__main__':
    main()
