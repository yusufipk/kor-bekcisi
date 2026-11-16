import json, struct, sys
for path in sys.argv[1:]:
    data = open(path, 'rb').read()
    magic, ver, length = struct.unpack_from('<III', data, 0)
    clen, ctype = struct.unpack_from('<II', data, 12)
    js = json.loads(data[20:20+clen])
    tris = 0
    for m in js.get('meshes', []):
        for p in m['primitives']:
            if 'indices' in p:
                tris += js['accessors'][p['indices']]['count'] // 3
            else:
                tris += js['accessors'][p['attributes']['POSITION']]['count'] // 3
    imgs = [(i.get('mimeType'), js['bufferViews'][i['bufferView']]['byteLength']) for i in js.get('images', []) if 'bufferView' in i]
    print(path, 'tris', tris, 'meshes', len(js.get('meshes', [])), 'mats', len(js.get('materials', [])), 'imgs', imgs,
          'skins', len(js.get('skins', [])), 'anims', [a.get('name') for a in js.get('animations', [])],
          'nodes', len(js.get('nodes', [])))
