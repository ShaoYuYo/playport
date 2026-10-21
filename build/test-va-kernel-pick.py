#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile the production map_view fallback/clamp policy, including lower task ceilings."""
from pathlib import Path
import subprocess,sys,tempfile

def policy(path,name):
 s=Path(path).read_text();start=s.index('int ceiling_relaxable',s.index('static NTSTATUS map_view('))
 end=s.index('size_t host_size',start)
 return "int "+name+"(uintptr_t limit_low,uintptr_t limit_high,uintptr_t size,uintptr_t kernel,uintptr_t ios_furniture_ceiling) { void *address_space_start=(void*)0x10000; void *end=(void*)kernel;\n"+s[start:end]+"\nreturn ceiling_relaxable; }\n"

source='#include <assert.h>\n#include <stdint.h>\n#include <stdio.h>\ntypedef uintptr_t ULONG_PTR;\n'+policy(sys.argv[1],'current')
checks="""
int main(void) {
 const uintptr_t kernel=0x7180000000ULL, ceiling=0x73ffff0000ULL, stack=0x800000;
 assert(current(0x100000000ULL,0,stack,kernel,ceiling)); /* reported lower task bound */
 assert(current(0x100000000ULL,0,stack,0x8000000000ULL,ceiling)); /* clamp still active */
 assert(current(0x100000000ULL,0,stack,kernel,0)); /* no furniture reservation */
 assert(current(0,0,stack,kernel,ceiling)); /* absent floor */
 assert(current(0x100010000ULL,0,stack,kernel,ceiling)); /* existing advisory boundary */
 assert(!current(0x100010001ULL,0,stack,kernel,ceiling)); /* explicit higher floor */
 assert(!current(0,0xffffffffULL,stack,kernel,ceiling)); /* strict 32-bit ceiling */
 assert(!current(0x100000000ULL,kernel-1,stack,kernel,ceiling)); /* caller-supplied high bound */
 BASELINE
 puts("VA kernel pick: eight production-policy cases passed.");
}
"""
if len(sys.argv)>2:
 source+=policy(sys.argv[2],'baseline')
 checks=checks.replace('BASELINE','assert(!baseline(0x100000000ULL,0,stack,kernel,ceiling)); puts("Baseline reproduced: lower task ceiling wrongly refused kernel fallback.");')
else:checks=checks.replace('BASELINE','')
r=Path(__file__).resolve().parent.parent;(r/'.work').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=r/'.work') as temp:
 p=Path(temp);(p/'check.c').write_text(source+checks)
 subprocess.run(['cc','-std=c11',str(p/'check.c'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check')],check=True)
