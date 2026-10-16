#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Stage only the reviewed WoW64 exception diagnostic on the r7 FEX checkpoint."""
from pathlib import Path
import hashlib,importlib.util,os,shutil,struct,subprocess
REPO=Path(__file__).resolve().parent.parent
BASE='33641ad8df297ec6f3a7fcc3d93c42e443b77201'
PATCH='0036-wow64-retain-distinct-exception-and-SEH-evidence.patch'
PATCH_SHA='5676d86429ec47f98ecffbd0580cddcac8144dbf40564b4cccc1b103bc09821c'
FEX_PATCH='0025-JIT-guard-iOS-WoW64-call-return-predictions.patch'
FEX_SHA='11e175b8c4cdd372413366e973db67619540f2d04b30fdcbd57536701e34de09'
def git(*args):return subprocess.check_output(['git','-c','core.filemode=false','-C',str(REPO),*args])
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,REPO/path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def main():
    allowed={'patches/wine-pe/series','patches/wine-pe/'+PATCH,'patches/fex/series','patches/fex/'+FEX_PATCH,
             'build/rebuild-callret-checkpoint.py','build/test-wow64-callret.py','build/test-exception-evidence.py',
             'build/rebuild-exception-evidence-checkpoint.py'}
    paths=['pins.lock','patches','build','app/registry','app/WindowsNLS','app/SessionRoot','app/UrlOpener','app/PlayportJIT','app/PlayportJIT-Info.plist']
    names=set(git('diff','--name-only',BASE,'--',*paths).decode().splitlines())
    names.update(git('ls-files','--others','--exclude-standard','--',*paths).decode().splitlines())
    for name in names:
        if name in allowed or name.startswith('build/generated/'):continue
        old=subprocess.run(['git','-C',str(REPO),'show',BASE+':'+name],capture_output=True)
        actual=(REPO/name).read_bytes() if (REPO/name).is_file() else None
        if old.returncode or actual!=old.stdout:raise ValueError('unrelated native input: '+name)
    for group,name,digest in [('wine-pe',PATCH,PATCH_SHA),('fex',FEX_PATCH,FEX_SHA)]:
        if (REPO/'patches'/group/'series').read_bytes()!=git('show',BASE+':patches/'+group+'/series')+name.encode()+b'\n':raise ValueError('not the exact reviewed series append')
        if hashlib.sha256((REPO/'patches'/group/name).read_bytes()).hexdigest()!=digest:raise ValueError('unexpected reviewed patch')
    cp=module('checkpoint','build/runtime-checkpoint.py');cp.verify(REPO);before=cp.files(REPO)
    out=REPO/'.work/run/pe';env=os.environ.copy();env.update(OUT=str(out),PLAYPORT_WOW64_ONLY='1',JOBS='3')
    subprocess.run(['bash','build/stages/wine-pe.sh'],env=env,cwd=REPO,check=True)
    subprocess.run(['python3','build/test-exception-evidence.py',str(out/'wine')],cwd=REPO,check=True)
    dest=out/'wow64-exception-evidence.dll'
    subprocess.run([str(Path(env['LLVM_MINGW'])/'bin/llvm-strip'),'--strip-debug','-o',str(dest),str(out/'wine/build-macos/dlls/wow64/aarch64-windows/wow64.dll')],check=True)
    data=dest.read_bytes();pe=struct.unpack_from('<I',data,60)[0]
    if struct.unpack_from('<H',data,pe+4)[0]!=0xaa64 or b'[wow64-exception-v2]' not in data:raise ValueError('not the compiled exception evidence bridge')
    module('records','build/rebuild-win32-compat-checkpoint.py').replace_records(REPO,{'wow64.dll':dest})
    after=cp.files(REPO);delta={p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)}
    outputs={'app/artifacts.tsv','app/Sources/S1Probe/Runtime/artifacts.tsv','app/Sources/S1Probe/Runtime/aarch64-windows/wow64.dll','build/generated/wine-pe-aarch64-windows.tsv'}
    if delta-outputs:raise ValueError('unrelated checkpoint output changed: '+str(delta-outputs))
    cp.save(REPO);cp.verify(REPO)
    print('Only wow64.dll and its records changed. SHA256='+hashlib.sha256(data).hexdigest())
if __name__=='__main__':main()
