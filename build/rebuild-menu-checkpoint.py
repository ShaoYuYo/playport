#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile and stage only the audited wow64win menu bridge."""
from pathlib import Path
import hashlib,importlib.util,os,subprocess,shutil,struct
REPO=Path(__file__).resolve().parent.parent
BASE='cae0acb24771dac1a37a62f3a2cc7bd21e014ceb'
PATCH='0034-wow64win-convert-and-audit-menu-item-info.patch'
PATCH_SHA='864757925840829344c76775e17c3e277a93eeb7466dbaee329ce95172031be0'
def git(*args):return subprocess.check_output(['git','-c','core.filemode=false','-C',str(REPO),*args])
def validate():
 paths=['pins.lock','patches','build','app/registry','app/WindowsNLS','app/SessionRoot','app/UrlOpener','app/PlayportJIT','app/PlayportJIT-Info.plist']
 changed=set(git('diff','--name-only',BASE,'--',*paths).decode().splitlines())
 changed.update(git('ls-files','--others','--exclude-standard','--',*paths).decode().splitlines())
 allowed={'patches/wine-pe/series','patches/wine-pe/'+PATCH,'build/rebuild-menu-checkpoint.py','build/test-menu-thunk.py'}
 for name in changed:
  if name.startswith('build/generated/') or name in allowed:continue
  old=subprocess.run(['git','-C',str(REPO),'show',BASE+':'+name],capture_output=True)
  actual=(REPO/name).read_bytes() if (REPO/name).is_file() else None
  if old.returncode or actual!=old.stdout:raise ValueError('unrelated native input: '+name)
 if (REPO/'patches/wine-pe/series').read_bytes()!=git('show',BASE+':patches/wine-pe/series')+PATCH.encode()+b'\n':raise ValueError('not the exact menu patch append')
 if hashlib.sha256((REPO/'patches/wine-pe'/PATCH).read_bytes()).hexdigest()!=PATCH_SHA:raise ValueError('unexpected menu patch')
def module(name,path):
 spec=importlib.util.spec_from_file_location(name,REPO/path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def main():
 validate();cp=module('checkpoint','build/runtime-checkpoint.py');cp.verify(REPO);before=cp.files(REPO)
 out=REPO/'.work/run/pe';wine=out/'wine';env=os.environ.copy();env.update(OUT=str(out),PLAYPORT_WOW64_ONLY='1',JOBS='3')
 subprocess.run(['bash','build/stages/wine-pe.sh'],env=env,cwd=REPO,check=True)
 built=wine/'build-macos/dlls/wow64win/aarch64-windows/wow64win.dll';dest=out/'wow64win-menu.dll'
 subprocess.run([str(Path(env['LLVM_MINGW'])/'bin/llvm-strip'),'--strip-debug','-o',str(dest),str(built)],check=True)
 data=dest.read_bytes();pe=struct.unpack_from('<I',data,60)[0]
 if struct.unpack_from('<H',data,pe+4)[0]!=0xaa64 or b'[wow64-menu-v1]' not in data:raise ValueError('not the compiled aarch64 menu bridge')
 module('records','build/rebuild-win32-compat-checkpoint.py').replace_records(REPO,{'wow64win.dll':dest})
 after=cp.files(REPO)
 allowed={'app/artifacts.tsv','app/Sources/S1Probe/Runtime/artifacts.tsv','build/generated/wine-pe-aarch64-windows.tsv','app/Sources/S1Probe/Runtime/aarch64-windows/wow64win.dll'}
 delta={p for p in before.keys()|after.keys() if before.get(p)!=after.get(p)}
 if delta-allowed:raise ValueError('unrelated checkpoint artifact changed: '+str(delta-allowed))
 cp.save(REPO);cp.verify(REPO)
 print('Only wow64win.dll and its records changed. SHA256='+hashlib.sha256(data).hexdigest())
if __name__=='__main__':main()
