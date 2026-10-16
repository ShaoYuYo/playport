#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile the production ARM64EC handoff block, including its validation."""
from pathlib import Path
import subprocess, sys

repo = Path(__file__).resolve().parent.parent
tree = Path(sys.argv[1])
s = (tree / 'dlls/ntdll/signal_arm64ec.c').read_text()
a = s.index('static const char *ios_fex_arena_rejection(')
b = s.index('\n}', a) + 2
helper = s[a:b]
a = s.index('            ULONG_PTR b = ios_fex_arena_base, e = ios_fex_arena_end;')
b = s.index('\n        }', a)
block = s[a:b]
out = repo / '.work/root-arena-test'; out.mkdir(parents=True, exist_ok=True)
code = '''#include <assert.h>
#include <stdint.h>
#include <stddef.h>
typedef uint64_t ULONG_PTR;
#define ERR(...) ((void)0)
''' + helper + '''
static void check(uint64_t base, uint64_t end, int accept) {
    ULONG_PTR ios_fex_arena_base=base, ios_fex_arena_end=end;
    ULONG_PTR start=123, stop=456, *band_base=&start, *band_end=&stop;
''' + block + '''
    if (accept) { assert(start==base); assert(stop==end-1); }
    else { assert(start==0); assert(stop==0); }
}
int main(void) {
    const uint64_t base=0x7138000000ULL;
    check(base,base+0x20000000,1);
    check(base,base+0x30000000,1);
    check(base,base+0x40000000,1);
    check(base,base+0x200000000ULL,1);
    check(base,base+0x1fff0000,0);
    check(0,base,0); check(base,0,0);
    check(base,base,0); check(base+0x10000,base,0);
    check(base+1,base+0x40000000,0); check(base,base+0x40000001,0);
    check(0x10000000,0x50000000,0);
}
'''
for name, body in [('after', code), ('old-floor', code.replace('e - b < 0x20000000ull', 'e - b < 0x40000000ull'))]:
    src = out / (name + '.c'); src.write_text(body)
    exe = out / name
    subprocess.run(['clang', '-O2', '-fsanitize=undefined', str(src), '-o', str(exe)], check=True)
    result = subprocess.run([str(exe)], capture_output=True)
    if (name == 'after') != (result.returncode == 0): raise RuntimeError(result.stderr.decode())
    print(name + ': ' + ('12 real handoff cases passed' if name == 'after' else 'old minimum rejects the 512 MiB arena (reproduced)'))
