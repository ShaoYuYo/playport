#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Replace only audio_null_ios.o after applying the reviewed iOS audio patch."""
import hashlib,importlib.util,os,shutil,subprocess
from pathlib import Path
REPO=Path(__file__).resolve().parents[1]
BASE='c7d09cc338e405a87c51324d7cd1b17eabd7eefe'
PATCH='0107-audio-preserve-stream-phase-and-bound-starvation-recov.patch'
PATCH_SHA='09df7dbeb96e59d89c85cecac650dcf6b3e1a5a8508803fcf08c0a88af728792'
OLD_ARCHIVE='b38a4a8221159aa31ea6ab1b873df3bfb7dcc88a4871f732711f63c69f01367f'
def git(*args): return subprocess.check_output(['git','-c','core.filemode=false','-C',str(REPO),*args])
def main():
    protected=['pins.lock','patches','build','app/registry','app/WindowsNLS','app/SessionRoot','app/UrlOpener','app/PlayportJIT']
    paths=set(git('diff','--name-only',BASE,'--',*protected).decode().splitlines())
    paths.update(git('ls-files','--others','--exclude-standard','--',*protected).decode().splitlines())
    allowed={'patches/madeira-unix/series','patches/madeira-unix/'+PATCH,
        'build/rebuild-audio-checkpoint.py','build/test-ios-audio-mixer.py','build/tests/audio_mixer_test.c'}
    for p in paths:
        if p.startswith('build/generated/'): continue
        old=subprocess.run(['git','-C',str(REPO),'show',BASE+':'+p],capture_output=True)
        actual=(REPO/p).read_bytes() if (REPO/p).is_file() else None
        if (old.returncode or old.stdout!=actual) and p not in allowed: raise ValueError('unrelated native input: '+p)
    if (REPO/'patches/madeira-unix/series').read_bytes()!=git('show',BASE+':patches/madeira-unix/series')+PATCH.encode()+b'\n':raise ValueError('unexpected series')
    if hashlib.sha256((REPO/'patches/madeira-unix'/PATCH).read_bytes()).hexdigest()!=PATCH_SHA:raise ValueError('patch changed')
    spec=importlib.util.spec_from_file_location('checkpoint',REPO/'build/runtime-checkpoint.py')
    cp=importlib.util.module_from_spec(spec);spec.loader.exec_module(cp)
    cp.verify(REPO);before=cp.files(REPO)
    root=REPO/'.work/run/unix';tree=root/'mythic';env=os.environ.copy()
    env['SRC_WINE']=str(REPO/'.work/run/pe/wine')
    subprocess.run(['bash','build/stages/unix.sh',str(root),'clones','shims'],env=env,check=True)
    build=tree/'build/ntdll-unix';recipe=(build/'build.sh').read_text()
    start=recipe.index('compile_one() {');end=recipe.index('\n}\n',start)+3
    script=root/'compile-audio.sh'
    script.write_text('set -e\nBUILD_DIR="'+str(build)+'"\nREPO_ROOT="'+str(tree)+'"\n'
        'WINE_SRC="$REPO_ROOT/wine"\nWINE_BUILD="$WINE_SRC/build-macos"\n'
        'NTDLL_SHIMS="$REPO_ROOT/build/ntdll-unix/shims"\nSDK=$(xcrun --sdk iphoneos --show-sdk-path)\n'
        'OBJ_DIR="$BUILD_DIR/obj"\nmkdir -p "$OBJ_DIR"\nSUCCEEDED=0\nFAILED=0\nFAILED_FILES=""\n'+recipe[start:end]+
        '\ncompile_one "$BUILD_DIR/audio_null_ios.c" audio_null_ios\n'
        'if [ "$FAILED" != 0 ]; then cat "$OBJ_DIR/audio_null_ios.err"; exit 1; fi\n')
    env['PATH']=str(root/'shims')+':'+env['PATH']
    subprocess.run(['bash',str(script)],env=env,check=True)
    staged=REPO/'app/Staged/lib/libntdll_unix.a'
    if hashlib.sha256(staged.read_bytes()).hexdigest()!=OLD_ARCHIVE:raise ValueError('unexpected starting archive')
    members=subprocess.check_output(['llvm-ar','t',str(staged)]).decode().splitlines()
    if members.count('audio_null_ios.o')!=1 or len(members)!=len(set(members)):raise ValueError('ambiguous archive')
    old={m:subprocess.check_output(['llvm-ar','p',str(staged),m]) for m in members}
    output=root/'libntdll-audio-recovery.a';shutil.copyfile(staged,output)
    subprocess.run(['llvm-ar','rcsD',str(output),str(build/'obj/audio_null_ios.o')],check=True)
    if subprocess.check_output(['llvm-ar','t',str(output)]).decode().splitlines()!=members:raise ValueError('archive ordering')
    for m in members:
        data=subprocess.check_output(['llvm-ar','p',str(output),m])
        if (m=='audio_null_ios.o') == (data==old[m]):raise ValueError('unexpected member change: '+m)
    digest=hashlib.sha256(output.read_bytes()).hexdigest();size=str(output.stat().st_size)
    records=REPO/'app/artifacts.tsv';rows=records.read_text().splitlines();found=0
    for i,row in enumerate(rows):
        fields=row.split('\t')
        if len(fields)>3 and fields[1]=='lib/libntdll_unix.a':
            fields[2:4]=[size,digest];rows[i]='\t'.join(fields);found+=1
    if found!=1:raise ValueError('missing archive record')
    records.write_text('\n'.join(rows)+'\n')
    shutil.copyfile(records,REPO/'app/Sources/S1Probe/Runtime/artifacts.tsv')
    shutil.copyfile(output,staged);shutil.copyfile(output,tree/'app/Madeira/libntdll_unix.a')
    after=cp.files(REPO)
    changed={p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)}
    if changed-{'app/Staged/lib/libntdll_unix.a','app/artifacts.tsv','app/Sources/S1Probe/Runtime/artifacts.tsv'}:raise ValueError('unrelated native output')
    cp.save(REPO);cp.verify(REPO)
    print('Only audio_null_ios.o changed; '+str(len(members)-1)+' other members preserved; SHA256='+digest)
if __name__=='__main__':main()
