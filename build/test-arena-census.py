#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile the actual native census with an ordered-view fixture."""
from pathlib import Path
import os,subprocess,sys
r=Path(__file__).resolve().parent.parent;t=Path(sys.argv[1]).resolve()
out=r/'.work/arena-census-test';out.mkdir(parents=True,exist_ok=True);os.environ['TMPDIR']=str(out)
s=(t/'build/ntdll-unix/virtual_ios.c').read_text()
a=s.index('struct ios_band_census\n');b=s.index('/* The first view that ends above lo',a);head=s[a:b]
a=s.index('static void ios_band_census_locked(');b=s.index('\n}',a)+2;body=s[a:b]
c=r'''
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
typedef uintptr_t ULONG_PTR;
struct wine_rb_entry {struct wine_rb_entry* next;};
struct file_view {void* base;size_t size;struct wine_rb_entry entry;};
#define WINE_RB_ENTRY_VALUE(p,t,m) ((t*)((char*)(p)-offsetof(t,m)))
static struct file_view views[4];
static struct wine_rb_entry* rb_next(struct wine_rb_entry* p){return p->next;}
static struct wine_rb_entry* ios_band_first_locked(ULONG_PTR lo){(void)lo;return &views[0].entry;}
static ULONG_PTR ios_fex_arena_base_unix,ios_fex_arena_end_unix;
static unsigned long long ios_band_used_peak;
'''+head+body+r'''
int main(void){
 const ULONG_PTR M=1024*1024,base=0x100000000ULL;
 ios_fex_arena_base_unix=base;ios_fex_arena_end_unix=base+1024*M;
 views[0].base=(void*)(base+4*M);views[0].size=4*M;
 views[1].base=(void*)(base+16*M);views[1].size=4*M+8192;
 views[2].base=(void*)(base+32*M);views[2].size=2*M;
 views[3].base=(void*)(base+40*M);views[3].size=65536;
 for(int i=0;i<3;++i)views[i].entry.next=&views[i+1].entry;
 struct ios_band_census c;ios_band_census_locked(&c);
 assert(c.views==4&&c.spans==1&&c.callret==1&&c.l1==1&&c.other_bytes==65536);
 assert(c.used==10*M+8192+65536&&ios_band_used_peak==c.used);
 assert(c.largest_free==984*M-65536);
 memset(&c,0,sizeof(c));ios_band_gap(&c,base,base+13*M);
 assert(c.span_slots==3&&c.largest_free==13*M);
 puts("PASS: actual native census identifies 4-MiB stacks plus guards, with unchanged other-view accounting");
}
'''
(out/'test.c').write_text(c)
subprocess.run(['clang','-std=c11','-O1','-g','-fsanitize=address,undefined',str(out/'test.c'),'-o',str(out/'test')],check=True)
subprocess.run([str(out/'test')],check=True)
