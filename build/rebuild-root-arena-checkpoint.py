#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rebuild only the ARM64EC ntdll handoff on the verified r5 checkpoint."""
from pathlib import Path
import hashlib, importlib.util, os, shutil, struct, subprocess

REPO = Path(__file__).resolve().parent.parent
BASE = '2670b571224d50997dabd5426aac3e73e76c8e18'
PATCH = '0035-ntdll-accept-owned-sub-gigabyte-arenas-in-the-root.patch'
PATCH_SHA = 'da660311882c281b4f9147fc15036bc423340f97477b1282d21fc6f567d03c37'
STAGE_SHA = '22ad57bfd4b202f7c3ca14abeda96fa397192a1274ecde6be8a017163bf05d5c'

def git(*args):
    return subprocess.check_output(['git','-c','core.filemode=false','-C',str(REPO),*args])

def main():
    paths = ['pins.lock','patches','build','app/registry','app/WindowsNLS','app/SessionRoot','app/UrlOpener','app/PlayportJIT','app/PlayportJIT-Info.plist']
    allowed = {'patches/wine-pe/series','patches/wine-pe/'+PATCH,'build/test-root-arena.py','build/rebuild-root-arena-checkpoint.py','build/stages/wine-pe.sh','build/test-menu-thunk.py'}
    names = set(git('diff','--name-only',BASE,'--',*paths).decode().splitlines())
    names.update(git('ls-files','--others','--exclude-standard','--',*paths).decode().splitlines())
    for name in names:
        if name in allowed or name.startswith('build/generated/'): continue
        old = subprocess.run(['git','-C',str(REPO),'show',BASE+':'+name],capture_output=True)
        actual = (REPO/name).read_bytes() if (REPO/name).is_file() else None
        if old.returncode or actual != old.stdout: raise ValueError('unrelated native input: '+name)
    if (REPO/'patches/wine-pe/series').read_bytes() != git('show',BASE+':patches/wine-pe/series')+PATCH.encode()+b'\n':
        raise ValueError('not the exact handoff patch append')
    if hashlib.sha256((REPO/'patches/wine-pe'/PATCH).read_bytes()).hexdigest()!=PATCH_SHA:
        raise ValueError('unexpected handoff patch')
    if hashlib.sha256((REPO/'build/stages/wine-pe.sh').read_bytes()).hexdigest()!=STAGE_SHA:
        raise ValueError('unexpected selective ntdll recipe')
    spec=importlib.util.spec_from_file_location('checkpoint',REPO/'build/runtime-checkpoint.py')
    cp=importlib.util.module_from_spec(spec);spec.loader.exec_module(cp)
    cp.verify(REPO); before=cp.files(REPO)
    out=REPO/'.work/run/pe'; wine=out/'wine'
    env=os.environ.copy();env.update(OUT=str(out),PLAYPORT_ROOT_NTDLL_ONLY='1',JOBS='3')
    subprocess.run(['bash','build/stages/wine-pe.sh'],env=env,cwd=REPO,check=True)
    subprocess.run(['python3','build/test-root-arena.py',str(wine)],cwd=REPO,check=True)
    build=wine/'build-arm64ec'; target='dlls/ntdll/arm64ec-windows/ntdll.dll'
    dest=out/'ntdll-root-arena.dll'
    subprocess.run([str(Path(env['LLVM_MINGW'])/'bin/llvm-strip'),'--strip-debug','-o',str(dest),str(build/target)],check=True)
    data=dest.read_bytes(); pe=struct.unpack_from('<I',data,60)[0]
    if struct.unpack_from('<H',data,pe+4)[0]!=0x8664 or b'handoff-v2' not in data:
        raise ValueError('not the compiled ARM64EC handoff image')
    rel='Runtime/arm64ec-windows/ntdll.dll'; manifest=REPO/'app/artifacts.tsv'
    rows=manifest.read_text().splitlines(); count=0
    digest=hashlib.sha256(data).hexdigest(); size=str(len(data))
    for i,row in enumerate(rows):
        fields=row.split('\t')
        if fields[1:2]==[rel]:fields[2:4]=[size,digest];rows[i]='\t'.join(fields);count+=1
    if count!=1: raise ValueError('expected one ntdll resource')
    manifest.write_text('\n'.join(rows)+'\n')
    shutil.copyfile(manifest,REPO/'app/Sources/S1Probe/Runtime/artifacts.tsv')
    shutil.copyfile(dest,REPO/'app/Sources/S1Probe'/rel)
    generated=REPO/'build/generated/wine-pe-arm64ec-windows.tsv'; rows=generated.read_text().splitlines();count=0
    for i,row in enumerate(rows):
        fields=row.split('\t')
        if fields[0]==target:fields[1:3]=[size,digest];rows[i]='\t'.join(fields);count+=1
    if count!=1: raise ValueError('expected one generated ntdll record')
    generated.write_text('\n'.join(rows)+'\n')
    after=cp.files(REPO)
    outputs={'app/artifacts.tsv','app/Sources/S1Probe/Runtime/artifacts.tsv','app/Sources/S1Probe/'+rel,'build/generated/wine-pe-arm64ec-windows.tsv'}
    delta={p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)}
    if delta-outputs: raise ValueError('unrelated output changed: '+str(delta-outputs))
    cp.save(REPO);cp.verify(REPO)
    print('Only ARM64EC ntdll.dll and its records changed. SHA256='+digest)

if __name__=='__main__': main()
