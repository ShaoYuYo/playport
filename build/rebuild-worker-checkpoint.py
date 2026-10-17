#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Migrate the r16 checkpoint: four objects, worker ownership and save evidence."""
import hashlib,importlib.util,os,shutil,subprocess
from pathlib import Path
REPO=Path(__file__).resolve().parents[1]
BASE='0623bda7d6d89b1e4ebaab6261cb8561d994bbba'  # r16 tree, independent of local commit metadata
PATCH='0108-ntdll-inherit-process-ownership-in-native-system-work.patch'
PATCH_SHA='9a911566a0d8a30a6b7cbe18d3e287f5b5b83c382bfc1b5f9bce6b4fd4284854'
AUDIT='0109-ntdll-record-bounded-save-backend-open-results.patch'
AUDIT_SHA='70a979a0b50ec02d144c60f1a606e84d5e4114c60ed90c37595f6d6e5f84d687'
MEMBERS=['thread.o','env.o','virtual.o','server.o']
OLD_ARCHIVE='02afde4867ebbac70cab30883a0b3a129718b137f198c19707bf0b87481260cd'
def git(*args): return subprocess.check_output(['git','-c','core.filemode=false','-C',str(REPO),*args])
def main():
    protected=['pins.lock','patches','build','app/registry','app/WindowsNLS','app/SessionRoot','app/UrlOpener','app/PlayportJIT']
    paths=set(git('diff','--name-only',BASE,'--',*protected).decode().splitlines())
    paths.update(git('ls-files','--others','--exclude-standard','--',*protected).decode().splitlines())
    allowed={'patches/madeira-unix/series','patches/madeira-unix/'+PATCH,'patches/madeira-unix/'+AUDIT,
        'build/rebuild-worker-checkpoint.py','build/test-ios-system-workers.py','build/tests/system_worker_test.c',
        'build/test-ios-save-probe.py'}
    for p in paths:
        if p.startswith('build/generated/'): continue
        old=subprocess.run(['git','-C',str(REPO),'show',BASE+':'+p],capture_output=True)
        actual=(REPO/p).read_bytes() if (REPO/p).is_file() else None
        if (old.returncode or (actual is None or old.stdout.splitlines()!=actual.splitlines())) and p not in allowed: raise ValueError('unrelated native input: '+p)
    if (REPO/'patches/madeira-unix/series').read_bytes()!=git('show',BASE+':patches/madeira-unix/series')+(PATCH+'\n'+AUDIT+'\n').encode():raise ValueError('unexpected series')
    if hashlib.sha256((REPO/'patches/madeira-unix'/PATCH).read_bytes()).hexdigest()!=PATCH_SHA:raise ValueError('patch changed')
    if hashlib.sha256((REPO/'patches/madeira-unix'/AUDIT).read_bytes()).hexdigest()!=AUDIT_SHA:raise ValueError('audit patch changed')
    staged=REPO/'app/Staged/lib/libntdll_unix.a'
    if hashlib.sha256(staged.read_bytes()).hexdigest()!=OLD_ARCHIVE:raise ValueError('expected the r16 starting archive')
    spec=importlib.util.spec_from_file_location('checkpoint',REPO/'build/runtime-checkpoint.py')
    cp=importlib.util.module_from_spec(spec);spec.loader.exec_module(cp)
    cp.verify(REPO);before=cp.files(REPO)
    root=REPO/'.work/run/unix';tree=root/'mythic';env=os.environ.copy()
    env['SRC_WINE']=str(REPO/'.work/run/pe/wine')
    subprocess.run(['bash','build/stages/unix.sh',str(root),'clones','shims'],env=env,check=True)
    build=tree/'build/ntdll-unix';recipe=(build/'build.sh').read_text()
    start=recipe.index('compile_one() {');end=recipe.index('\n}\n',start)+3
    script=root/'compile-workers.sh'
    script.write_text('set -e\nBUILD_DIR="'+str(build)+'"\nREPO_ROOT="'+str(tree)+'"\n'
        'WINE_SRC="$REPO_ROOT/wine"\nWINE_BUILD="$WINE_SRC/build-macos"\n'
        'NTDLL_SHIMS="$REPO_ROOT/build/ntdll-unix/shims"\nSDK=$(xcrun --sdk iphoneos --show-sdk-path)\n'
        'OBJ_DIR="$BUILD_DIR/obj"\nmkdir -p "$OBJ_DIR"\nSUCCEEDED=0\nFAILED=0\nFAILED_FILES=""\n'+recipe[start:end]+
        '\ncompile_one "$BUILD_DIR/thread_ios.c" thread\ncompile_one "$BUILD_DIR/env_ios.c" env\ncompile_one "$BUILD_DIR/virtual_ios.c" virtual\ncompile_one "$BUILD_DIR/server_ios.c" server\n'
        'if [ "$FAILED" != 0 ]; then cat "$OBJ_DIR/thread.err" "$OBJ_DIR/env.err" "$OBJ_DIR/virtual.err" "$OBJ_DIR/server.err"; exit 1; fi\n')
    env['PATH']=str(root/'shims')+':'+env['PATH']
    subprocess.run(['bash',str(script)],env=env,check=True)
    members=subprocess.check_output(['llvm-ar','t',str(staged)]).decode().splitlines()
    if any(members.count(m)!=1 for m in MEMBERS) or len(members)!=len(set(members)):raise ValueError('ambiguous archive')
    old={m:subprocess.check_output(['llvm-ar','p',str(staged),m]) for m in members}
    output=root/'libntdll-worker-ownership.a';shutil.copyfile(staged,output)
    subprocess.run(['llvm-ar','rcsD',str(output),*[str(build/'obj'/m) for m in MEMBERS]],check=True)
    if subprocess.check_output(['llvm-ar','t',str(output)]).decode().splitlines()!=members:raise ValueError('archive ordering')
    for m in members:
        data=subprocess.check_output(['llvm-ar','p',str(output),m])
        if (m in MEMBERS) == (data==old[m]):raise ValueError('unexpected member change: '+m)
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
    print('Only '+','.join(MEMBERS)+' changed; '+str(len(members)-len(MEMBERS))+' other members preserved; SHA256='+digest)
if __name__=='__main__':main()
