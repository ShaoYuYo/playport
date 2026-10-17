#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rebuild the two FEX images for the reviewed iOS live-heap capacity fix."""
from pathlib import Path
import hashlib, importlib.util, os, shutil, struct, subprocess
REPO=Path(__file__).resolve().parent.parent
BASE='a5b812dcd5ce938208b209dbecbcd88200966fa3'  # r17 tree
PATCHES={'0010-Bound-live-iOS-heaps-with-2-MiB-owner-units.patch': 'ca18d70fded179ea1c90b689f5139aa4efc3f5d0a659eea2d094b8e0ee7a5782'}

def git(*args):return subprocess.check_output(['git','-c','core.filemode=false','-C',str(REPO),*args])
def main():
    allowed={'patches/rpmalloc/series','build/test-ios-rpmalloc.py','build/rebuild-live-heap-checkpoint.py'} | {'patches/rpmalloc/'+p for p in PATCHES}
    paths=['pins.lock','patches','build','app/registry','app/WindowsNLS','app/SessionRoot','app/UrlOpener','app/PlayportJIT','app/PlayportJIT-Info.plist']
    names=set(git('diff','--name-only',BASE,'--',*paths).decode().splitlines())
    names.update(git('ls-files','--others','--exclude-standard','--',*paths).decode().splitlines())
    for name in names:
        if name in allowed or name.startswith('build/generated/'):continue
        old=subprocess.run(['git','-C',str(REPO),'show',BASE+':'+name],capture_output=True)
        data=(REPO/name).read_bytes() if (REPO/name).is_file() else None
        if old.returncode or data!=old.stdout:raise ValueError('unrelated native input: '+name)
    if (REPO/'patches/rpmalloc/series').read_bytes()!=git('show',BASE+':patches/rpmalloc/series')+''.join(p+'\n' for p in PATCHES).encode():raise ValueError('not the exact allocator patch append')
    for p,digest in PATCHES.items():
        if hashlib.sha256((REPO/'patches/rpmalloc'/p).read_bytes()).hexdigest()!=digest:raise ValueError('unexpected allocator patch: '+p)
    spec=importlib.util.spec_from_file_location('checkpoint',REPO/'build/runtime-checkpoint.py');cp=importlib.util.module_from_spec(spec);spec.loader.exec_module(cp)
    cp.verify(REPO);before=cp.files(REPO)
    root=REPO/'.work/run/fex'
    subprocess.run(['bash','build/stages/fex.sh',str(root),'arm64ec wow64'],cwd=REPO,check=True)
    python=os.environ.get('PLAYPORT_GUARD_TEST_PYTHON',str(REPO/'.work/guard-test-python/bin/python'))
    subprocess.run(['python3','build/test-ios-rpmalloc.py',str(root/'fex/External/rpmalloc')],cwd=REPO,check=True)
    subprocess.run(['python3','build/test-ios-scratch-pool.py',str(root/'fex')],cwd=REPO,check=True)
    subprocess.run([python,'build/test-wow64-callret.py',str(root/'fex')],cwd=REPO,check=True)
    subprocess.run(['python3','build/test-ios-cpuid.py',str(root/'fex')],cwd=REPO,check=True)
    replacements=[('build-arm64ec/Bin/libarm64ecfex.dll','arm64ec-windows/xtajit64.dll',0x8664),
                  ('build-wow64/Bin/libwow64fex.dll','aarch64-windows/xtajit.dll',0xaa64)]
    manifest=REPO/'app/artifacts.tsv';rows=manifest.read_text().splitlines()
    outputs={'app/artifacts.tsv','app/Sources/S1Probe/Runtime/artifacts.tsv'}
    for output,target,machine in replacements:
        p=root/'fex'/output;data=p.read_bytes();pe=struct.unpack_from('<I',data,60)[0]
        if data[:2]!=b'MZ' or struct.unpack_from('<H',data,pe+4)[0]!=machine:raise ValueError('unexpected FEX image')
        digest=hashlib.sha256(data).hexdigest();count=0
        for i,row in enumerate(rows):
            fields=row.split('\t')
            if fields[1:2]==['Runtime/'+target]:fields[2:4]=[str(len(data)),digest];rows[i]='\t'.join(fields);count+=1
        if count!=1:raise ValueError('expected one FEX resource row')
        dest=REPO/'app/Sources/S1Probe/Runtime'/target;shutil.copyfile(p,dest);outputs.add(str(dest.relative_to(REPO)))
        print(target,hashlib.sha256(data).hexdigest())
    manifest.write_text('\n'.join(rows)+'\n');shutil.copyfile(manifest,REPO/'app/Sources/S1Probe/Runtime/artifacts.tsv')
    after=cp.files(REPO);delta={p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)}
    if delta-outputs:raise ValueError('unrelated output changed: '+str(delta-outputs))
    cp.save(REPO);cp.verify(REPO);print('Only the two FEX images and their records changed.')
if __name__=='__main__':main()
