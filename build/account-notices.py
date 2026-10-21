#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Extend one checksum-pinned, reviewed native notice checkpoint with account notices.

Offline checkpoint builds only. Clean builds collect the same notices via
notices-assemble.sh. No status override: the normal reviewed selection stages
all files, and the existing native pin set must match the reviewed checkpoint.
"""
import hashlib, importlib.util, json, shutil, sys, tempfile
from pathlib import Path
R = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('selection', R/'build/notices-app.py')
a = importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
b = a.bundle

def inventory(path):
    files = sorted(p for p in path.rglob('*') if p.is_file() and p.name not in b.MANIFESTS)
    data = dict(schema=1, status='checkpoint-collection', files=[dict(name=p.relative_to(path).as_posix(),size=p.stat().st_size,sha256=b.digest(p)) for p in files])
    (path/'inventory.json').write_text(json.dumps(data,indent=2)+'\n')
    sums = files + [path/'inventory.json']
    (path/'SHA256SUMS').write_text(''.join(f'{b.digest(p)}  ./{p.relative_to(path).as_posix()}\n' for p in sorted(sums)))

def extend(destination):
    lock = json.loads((R/'build/apple-account-deps.lock.json').read_text())
    assert hashlib.sha256((R/'pins.lock').read_bytes().replace(b'\r\n',b'\n')).hexdigest()==lock['native_pins_sha256'], 'native pins differ'
    b.check(destination, distribution=True)
    old = json.loads((destination/'inventory.json').read_text())
    if b.digest(destination/'inventory.json') != lock['baseline_inventory_sha256']:
        # Repeated staging is allowed only for this exact previous extension.
        assert old.get('account_extension') == b.digest(R/'build/apple-account-deps.lock.json'), 'unrecognized notice checkpoint'
        for entry in lock['files']: assert b.digest(destination/entry['name'])==entry['sha256']
    with tempfile.TemporaryDirectory(dir=destination.parent,prefix='.account-notices-') as tmp:
        collection=Path(tmp)/'collection';collection.mkdir()
        for entry in old['files']:
            if entry['name'] not in ['CREDITS.txt','components.json']:
                target=collection/entry['name'];target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(destination/entry['name'], target)
        for entry in lock['files']:
            source=R/'build/notices-extra'/entry['name']
            assert b.digest(source)==entry['sha256'], entry['name']
            shutil.copyfile(source,collection/entry['name'])
        inventory(collection)
        chosen=Path(tmp)/'chosen';a.select(collection,chosen)
        data=json.loads((chosen/'inventory.json').read_text())
        data['account_extension']=b.digest(R/'build/apple-account-deps.lock.json')
        (chosen/'inventory.json').write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
        names=b.walk(chosen)
        (chosen/'SHA256SUMS').write_text(''.join(f'{b.digest(chosen/n)}  ./{n}\n' for n in names if n!='SHA256SUMS'))
        b.check(chosen,distribution=True);b.stage(chosen,destination)
    print('Reviewed account notices added; native checkpoint and every payload verified.')
if __name__=='__main__': extend(Path(sys.argv[1]))
