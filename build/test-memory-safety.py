#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Production commit admission with mocked OS availability and Wine page state."""
from pathlib import Path
import subprocess,sys
r=Path(__file__).resolve().parent.parent;t=Path(sys.argv[1]);out=r/'.work/memory-safety-test';out.mkdir(parents=True,exist_ok=True)
source=(t/'build/ntdll-unix/virtual_ios.c').read_text();a=source.index('static int ios_memory_allow_allocation(');b=source.index('\n}',a)+2
prefix=r'''
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stddef.h>
#include <limits.h>
typedef int sigset_t;
typedef size_t SIZE_T;
static size_t page_mask=4095,page_size=4096;
#define VPROT_COMMITTED 0x10
static unsigned char pages[8];
static uint64_t availability;
static int virtual_mutex,lock_count;
static uint64_t os_proc_available_memory(void){return availability;}
static void server_enter_uninterrupted_section(int *a,int *b){(void)a;(void)b;lock_count++;}
static void server_leave_uninterrupted_section(int *a,int *b){(void)a;(void)b;lock_count--;}
static void *find_view(void *addr,size_t size){
 uintptr_t base=(uintptr_t)addr;return base>=0x10000 && base<0x18000 && size<=0x18000-base ? pages:NULL;
}
static unsigned get_page_vprot(void *addr){return pages[((uintptr_t)addr-0x10000)/4096];}
#include "ios_memory_safety.h"
'''
suffix=r'''
int main(void){
 const uint64_t MB=1ULL<<20;
 assert(ios_memory_admit_commit(2*MB,0)); /* untouched default before UI config */
 ios_memory_configure(100);
 assert(ios_memory_admit_commit(100*MB,200*MB));
 assert(!ios_memory_admit_commit(100*MB+1,200*MB));
 assert(!ios_memory_admit_commit(SIZE_MAX,200*MB));
 assert(ios_memory_admit_commit(0,0));
 availability=100*MB+4096;
 pages[0]=VPROT_COMMITTED;
 assert(ios_memory_allow_allocation((void *)0x10000,8192));
 assert(!ios_memory_allow_allocation((void *)0x10000,8193));
 availability=0;
 assert(ios_memory_allow_allocation((void *)0x10000,4096)); /* no double charge */
 assert(!ios_memory_allow_allocation(NULL,4096));
 ios_memory_configure(2048);assert(atomic_load(&ios_memory_margin_mb)==1024);
 ios_memory_configure(0);assert(ios_memory_admit_commit(1,1));
 assert(!lock_count && ios_memory_denials()==4);
 puts("Production RAM admission: bounds, exact margin, overflow, zero availability and existing commitments pass");
}
'''
(out/'ios_memory_safety.h').write_bytes((t/'build/ntdll-unix/ios_memory_safety.h').read_bytes())
(out/'test.c').write_text(prefix+source[a:b]+suffix)
subprocess.run(['clang','-std=c11','-D_GNU_SOURCE','-O2','-Wall','-Wextra','-Werror',str(out/'test.c'),'-o',str(out/'test')],check=True)
subprocess.run([str(out/'test')],check=True)
