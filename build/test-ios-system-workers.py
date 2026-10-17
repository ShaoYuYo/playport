#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the actual native-worker bootstrap with real pthreads and mocked Wine IPC."""
import argparse, subprocess, tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('tree',type=Path);a=p.parse_args()
repo=Path(__file__).resolve().parents[1]
text=(a.tree/'build/ntdll-unix/thread_ios.c').read_text()
start=text.index('static _Thread_local void *ios_native_owner_peb;')
end=text.index('#endif',start)
owned=text[start:end]
start=text.index('static NTSTATUS spawn_thread(');end=text.index('\n\n/***********************************************************************',start)
spawn=text[start:end]
env=(a.tree/'build/ntdll-unix/env_ios.c').read_text();start=env.index('DWORD ios_current_pid(void)');end=env.index('\n#endif',start)
pid=env[start:end]
virtual=(a.tree/'build/ntdll-unix/virtual_ios.c').read_text();start=virtual.index('void *ios_jit_current_peb(void)\n{');end=virtual.index('\n/* Owner-aware',start)
peb=virtual[start:end]
asm='''        __asm__ volatile("mrs %0, TPIDRRO_EL0" : "=r"(tsd_base));'''
assert asm in peb;peb=peb.replace(asm,'        tsd_base = 0; /* raw ARM64 slot disabled in this host harness */')
with tempfile.TemporaryDirectory(prefix='worker-test-',dir=repo/'.work') as d:
    root=Path(d);(root/'actual_worker.h').write_text(owned+'\n'+spawn+'\n'+pid+'\n'+peb)
    exe=root/'workers'
    subprocess.run(['clang','-std=c11','-D_GNU_SOURCE','-DWINE_IOS','-O1','-g','-pthread',
        '-fsanitize=address,undefined','-fno-sanitize-recover=all','-I',str(root),
        str(repo/'build/tests/system_worker_test.c'),'-o',str(exe)],check=True)
    subprocess.run([str(exe)],check=True)
