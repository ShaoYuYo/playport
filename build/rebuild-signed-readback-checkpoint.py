#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rebuild the three kernelbase images; retain every other checkpoint byte."""
import hashlib,importlib.util,io,os,tarfile
from pathlib import Path
import shutil,struct,subprocess

REPO=Path(__file__).resolve().parent.parent
BASE='4e1c89cc7a47f417d0366bada17ef91f3cb28b34'
PATCH='0037-kernelbase-preserve-signed-original-data-reads.patch'

def main():
    def git(*args):return subprocess.check_output(['git','-c','core.filemode=false','-C',str(REPO),*args])
    allowed={'patches/wine-pe/series','patches/wine-pe/'+PATCH,
             'build/rebuild-signed-readback-checkpoint.py','build/test-signed-readback.py','build/test-signed-originals.py'}
    # The cached runner can have an older index while containing the current
    # release's source files. Compare actual bytes to the baseline tree rather
    # than interpreting an untracked-but-present file as a deletion.
    archive=git('-c','core.autocrlf=false','archive',BASE,'--','pins.lock','patches','build',
                'app/registry','app/WindowsNLS','app/SessionRoot','app/PlayportJIT')
    with tarfile.open(fileobj=io.BytesIO(archive)) as baseline:
        for member in baseline:
            if not member.isfile() or member.name in allowed or member.name.startswith('build/generated/'):continue
            p=REPO/member.name
            if not p.is_file() or p.read_bytes()!=baseline.extractfile(member).read():
                raise ValueError('unrelated native input differs: '+member.name)
    if (REPO/'patches/wine-pe/series').read_bytes()!=git('show',BASE+':patches/wine-pe/series')+PATCH.encode()+b'\n':
        raise ValueError('not the exact one-patch append')
    spec=importlib.util.spec_from_file_location('checkpoint',REPO/'build/runtime-checkpoint.py')
    cp=importlib.util.module_from_spec(spec);spec.loader.exec_module(cp)
    cp.verify(REPO);before=cp.files(REPO)
    out=REPO/'.work/run/pe';wine=out/'wine'
    env=os.environ.copy();env.update(OUT=str(out),PLAYPORT_WOW64_ONLY='1')
    subprocess.run(['bash','build/stages/wine-pe.sh'],cwd=REPO,env=env,check=True)
    allowed_outputs={'app/artifacts.tsv','app/Sources/S1Probe/Runtime/artifacts.tsv'}
    images=[]
    for arch,tree,machine in [('i386','build-macos','I386'),('aarch64','build-macos','ARM64'),('arm64ec','build-arm64ec','ARM64EC')]:
        relative=f'dlls/kernelbase/{arch}-windows/kernelbase.dll'
        subprocess.run(['make','-j3',relative],cwd=wine/tree,check=True)
        output=out/f'kernelbase-readback-{arch}.dll'
        subprocess.run([str(Path(env['LLVM_MINGW'])/'bin/llvm-strip'),'--strip-debug','-o',str(output),str(wine/tree/relative)],check=True)
        data=output.read_bytes()
        # ARM64EC uses an AMD64 COFF header plus CHPE metadata. Use the same
        # metadata-aware reader as wine-pe-manifest.py, not a raw-header guess.
        headers=subprocess.check_output([str(Path(env['LLVM_MINGW'])/'bin/llvm-readobj'),'--file-headers',str(output)],text=True)
        if ('Machine: IMAGE_FILE_MACHINE_'+machine+' ') not in headers or b'[signed-readback-v1]' not in data:
            raise ValueError('wrong kernelbase output: '+arch)
        images.append((arch,relative,output,data))
    # No checkpoint byte is replaced until every image has passed validation.
    for arch,relative,output,data in images:
        size,digest=str(len(data)),hashlib.sha256(data).hexdigest()
        for name,column,value in [('app/artifacts.tsv',1,f'Runtime/{arch}-windows/kernelbase.dll'),
            (f'build/generated/wine-pe-{arch}-windows.tsv',0,relative)]:
            p=REPO/name;rows=p.read_text().splitlines();count=0
            for i,row in enumerate(rows):
                parts=row.split('\t')
                if len(parts)>column and parts[column]==value:
                    parts[column+1:column+3]=[size,digest];rows[i]='\t'.join(parts);count+=1
            if count!=1:raise ValueError('expected exactly one record: '+name)
            p.write_text('\n'.join(rows)+'\n');allowed_outputs.add(name)
        dest=REPO/f'app/Sources/S1Probe/Runtime/{arch}-windows/kernelbase.dll'
        shutil.copyfile(output,dest);allowed_outputs.add(str(dest.relative_to(REPO)))
    shutil.copyfile(REPO/'app/artifacts.tsv',REPO/'app/Sources/S1Probe/Runtime/artifacts.tsv')
    after=cp.files(REPO)
    delta={p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)}
    if delta-allowed_outputs:raise ValueError('unrelated native outputs changed: '+str(delta-allowed_outputs))
    cp.save(REPO);cp.verify(REPO)
    print('Three kernelbase images rebuilt; every other checkpoint output retained.')

if __name__=='__main__':main()
