"""Minimal PNG reader/writer (8-bit RGB/RGBA, no interlace) + nearest-neighbour scaling."""
import struct, zlib


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read(path):
    """-> (w, h, bytearray of RGBA rows)"""
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    pos, idat, pal, trns = 8, b'', None, None
    w = h = depth = ctype = 0
    while pos < len(data):
        ln, typ = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', body[:10])
        elif typ == b'PLTE':
            pal = body
        elif typ == b'tRNS':
            trns = body
        elif typ == b'IDAT':
            idat += body
        elif typ == b'IEND':
            break
    assert depth == 8, 'only 8-bit PNGs supported'
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * nch
    out = bytearray(stride * h)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ft = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if ft == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                c = prev[i - nch] if i >= nch else 0
                line[i] = (line[i] + _paeth(a, prev[i], c)) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    # expand to RGBA
    rgba = bytearray(w * h * 4)
    for i in range(w * h):
        if ctype == 6:
            rgba[i * 4:i * 4 + 4] = out[i * 4:i * 4 + 4]
        elif ctype == 2:
            rgba[i * 4:i * 4 + 3] = out[i * 3:i * 3 + 3]
            rgba[i * 4 + 3] = 255
        elif ctype == 3:
            ix = out[i]
            rgba[i * 4:i * 4 + 3] = pal[ix * 3:ix * 3 + 3]
            rgba[i * 4 + 3] = trns[ix] if trns and ix < len(trns) else 255
        elif ctype == 0:
            rgba[i * 4] = rgba[i * 4 + 1] = rgba[i * 4 + 2] = out[i]
            rgba[i * 4 + 3] = 255
        else:  # 4: gray+alpha
            g = out[i * 2]
            rgba[i * 4] = rgba[i * 4 + 1] = rgba[i * 4 + 2] = g
            rgba[i * 4 + 3] = out[i * 2 + 1]
    return w, h, rgba


def write(path, w, h, rgba):
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        rows += rgba[y * w * 4:(y + 1) * w * 4]
    def chunk(typ, body):
        return struct.pack('>I', len(body)) + typ + body + \
               struct.pack('>I', zlib.crc32(typ + body) & 0xffffffff)
    out = b'\x89PNG\r\n\x1a\n'
    out += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
    out += chunk(b'IDAT', zlib.compress(bytes(rows), 9))
    out += chunk(b'IEND', b'')
    open(path, 'wb').write(out)


def scale(w, h, rgba, n):
    """Nearest-neighbour integer upscale by n."""
    nw, nh = w * n, h * n
    out = bytearray(nw * nh * 4)
    for y in range(nh):
        sy = y // n
        for x in range(nw):
            sx = x // n
            s = (sy * w + sx) * 4
            d = (y * nw + x) * 4
            out[d:d + 4] = rgba[s:s + 4]
    return nw, nh, out
