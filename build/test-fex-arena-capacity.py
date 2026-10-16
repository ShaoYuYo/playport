#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the actual complete selector with a deterministic Mach VA model."""
from pathlib import Path
import subprocess,sys
r=Path(__file__).resolve().parent.parent
t=Path(sys.argv[1]);out=r/'.work/arena-capacity-test';out.mkdir(parents=True,exist_ok=True)
source=(t/'build/ntdll-unix/virtual_ios.c').read_text()
start=source.index('void ios_reserve_fex_arena(void)');end=source.index('\n}',start)+2
body=source[start:end]
prefix=r'''
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef uint64_t ULONG_PTR, SIZE_T, mach_vm_address_t, mach_vm_size_t;
typedef int kern_return_t, NTSTATUS, mach_msg_type_number_t;
typedef void *task_info_t;
typedef struct { uint64_t max_address; } task_vm_info_data_t;
typedef struct { void *LowestStartingAddress, *HighestEndingAddress; uint64_t Alignment; } MEM_ADDRESS_REQUIREMENTS;
typedef struct { int Type; void *Pointer; } MEM_EXTENDED_PARAMETER;
#define ARRAY_SIZE(x) (sizeof(x)/sizeof(x[0]))
#define IMAGE_FILE_MACHINE_I386 0x14c
#define TASK_VM_INFO_COUNT 1
#define TASK_VM_INFO 1
#define KERN_SUCCESS 0
#define KERN_FAILURE 5
#define VM_FLAGS_ANYWHERE 1
#define VM_FLAGS_FIXED 0
#define MEMORY_OBJECT_NULL 0
#define PROT_NONE 0
#define VM_PROT_ALL 7
#define VM_INHERIT_COPY 1
#define MEM_RESERVE 1
#define MEM_RESERVE_PLACEHOLDER 2
#define PAGE_NOACCESS 1
#define MemExtendedParameterAddressRequirements 1
#define ERR(...) fprintf(stderr, __VA_ARGS__)
static unsigned ios_title_machine;
static unsigned long long ios_layerkit_hi, ios_layerkit_lo;
static uint64_t ios_fex_arena_base_unix, ios_fex_arena_end_unix;
static uint64_t gap_lo, gap_hi, held_base, held_size;
static int guest_held, registered, reject_registration;
static int mach_task_self(void) { return 1; }
static int NtCurrentProcess(void) { return 1; }
static int ios_wow64_prepare_title_window(void) { guest_held = ios_title_machine == 0x14c; return 0; }
static int task_info(int a,int b,task_info_t data,int *count) {
 (void)a;(void)b;(void)count; ((task_vm_info_data_t *)data)->max_address=UINT64_C(0x7180000000);return 0;
}
static long long madeira_cfg_int(const char *key,int fallback) { (void)key;return fallback; }
static int NtAllocateVirtualMemoryEx(int a,void **b,uint64_t *c,int d,int e,MEM_EXTENDED_PARAMETER *f,int g) {
 (void)a;(void)b;(void)c;(void)d;(void)e;(void)f;(void)g;assert(0);return 1;
}
static int mach_vm_map(int task,uint64_t *addr,uint64_t size,uint64_t mask,int flags,
 int object,int offset,int copy,int prot,int maxprot,int inherit) {
 (void)task;(void)object;(void)offset;(void)copy;(void)prot;(void)maxprot;(void)inherit;
 uint64_t value=flags==VM_FLAGS_ANYWHERE && *addr<gap_lo ? gap_lo:*addr;
 value=(value+mask)&~mask;
 if (held_size || value<gap_lo || value>gap_hi || size>gap_hi-value) return 3;
 held_base=*addr=value;held_size=size;return 0;
}
static int mach_vm_deallocate(int task,uint64_t addr,uint64_t size) {
 (void)task;assert(addr==held_base && size==held_size);held_size=0;return 0;
}
static int mmap_add_fex_reserved_area(void *base,uint64_t size) {
 assert((uintptr_t)base==held_base && size==held_size);
 if(reject_registration)return 0;registered++;return 1;
}
'''
suffix=r'''
int main(int argc,char **argv) {
 assert(argc==4);
 uint64_t free_mb=strtoull(argv[1],0,0),expected=strtoull(argv[3],0,0);
 ios_title_machine=strcmp(argv[2],"x64") ? 0x14c:0x8664;
 reject_registration=!strcmp(argv[2],"reject");
 gap_lo=UINT64_C(0x7138000000);gap_hi=gap_lo+(free_mb<<20);
 if(!strcmp(argv[2],"large")){gap_lo=UINT64_C(0x400000000);gap_hi=gap_lo+(free_mb<<20);}
 ios_reserve_fex_arena();
 assert(guest_held==(ios_title_machine==0x14c));
 assert(held_size==(expected<<20));
 if(expected) {
  assert(registered==1 && ios_fex_arena_base_unix==held_base && ios_fex_arena_end_unix==held_base+held_size);
  assert(ios_fex_arena_base_unix>=gap_lo && ios_fex_arena_end_unix<=gap_hi);
  assert(getenv("WINE_IOS_FEX_ARENA_VERSION") && !strcmp(getenv("WINE_IOS_FEX_ARENA_VERSION"),"1"));
 } else assert(!registered && !ios_fex_arena_base_unix && !getenv("WINE_IOS_FEX_ARENA_BASE"));
 puts("Actual arena selector: ownership, bounded placement and publication agree");
}
'''
for label,code,cases in [
 ('before',body.replace('        { 0x0200000000ull, 0x0fbfffffffull, 0x030000000ull, "768MB WoW64 host fallback" },\n','').replace('        { 0x0200000000ull, 0x0fbfffffffull, 0x020000000ull, "512MB WoW64 host fallback" },\n',''),[(904,'i386',0)]),
 ('after',body,[(904,'i386',768),(600,'i386',512),(500,'i386',0),(904,'x64',0),(8192,'large',8192),(904,'reject',0)])]:
 p=out/(label+'.c');p.write_text(prefix+code+suffix);exe=out/label
 subprocess.run(['clang','-std=c11','-D_GNU_SOURCE','-O2',str(p),'-o',str(exe)],check=True)
 for free,mode,want in cases:
  result=subprocess.run([str(exe),str(free),mode,str(want)],capture_output=True,text=True)
  (out/f'{label}-{mode}-{free}.log').write_text(result.stdout+result.stderr)
  if result.returncode:raise RuntimeError(result.stderr)
  print(label,free,mode,'=>',want,'MiB')
