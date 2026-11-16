"""Downscale embedded GLB textures to max 1024 px and re-pack the binary chunk."""
import io, json, struct, sys
from PIL import Image

def shrink(src, dst, maxdim=1024):
    data = open(src, 'rb').read()
    clen, _ = struct.unpack_from('<II', data, 12)
    js = json.loads(data[20:20 + clen])
    off = 20 + clen
    blen, _ = struct.unpack_from('<II', data, off)
    bin_ = data[off + 8: off + 8 + blen]
    views = js['bufferViews']
    chunks = [bin_[v.get('byteOffset', 0): v.get('byteOffset', 0) + v['byteLength']] for v in views]
    for img in js.get('images', []):
        if 'bufferView' not in img:
            continue
        bv = img['bufferView']
        im = Image.open(io.BytesIO(chunks[bv]))
        has_alpha = im.mode in ('RGBA', 'LA') and im.getextrema()[-1][0] < 250
        im.thumbnail((maxdim, maxdim), Image.LANCZOS)
        out = io.BytesIO()
        if has_alpha:
            im.save(out, 'PNG', optimize=True)
            img['mimeType'] = 'image/png'
        else:
            im.convert('RGB').save(out, 'JPEG', quality=90)
            img['mimeType'] = 'image/jpeg'
        chunks[bv] = out.getvalue()
    newbin = bytearray()
    for v, c in zip(views, chunks):
        while len(newbin) % 4:
            newbin.append(0)
        v['byteOffset'] = len(newbin)
        v['byteLength'] = len(c)
        newbin += c
    while len(newbin) % 4:
        newbin.append(0)
    js['buffers'][0]['byteLength'] = len(newbin)
    jb = json.dumps(js, separators=(',', ':')).encode()
    while len(jb) % 4:
        jb += b' '
    total = 12 + 8 + len(jb) + 8 + len(newbin)
    with open(dst, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(jb), 0x4E4F534A)); f.write(jb)
        f.write(struct.pack('<II', len(newbin), 0x004E4942)); f.write(newbin)

if __name__ == '__main__':
    shrink(sys.argv[1], sys.argv[2])
