# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
class ClassAtoms(unittest.TestCase):
    def test_actual_patched_unicode_helper_preserves_atoms_and_translates_strings(self):
        patch = REPO / 'patches/wine-pe/0032-wow64-preserve-class-atoms-in-unicode-strings.patch'
        lines = [line[1:] for line in patch.read_text().splitlines() if line.startswith(('+', ' ')) and not line.startswith('+++')]
        signature = 'static inline UNICODE_STRING *unicode_str_32to64( UNICODE_STRING *str, const UNICODE_STRING32 *str32 )'
        start = lines.index(signature); end = lines.index('}', start)
        helper = '\n'.join(lines[start:end+1])
        source = '''#include <assert.h>
#include <stdint.h>
#include <stddef.h>
typedef struct { uint16_t Length, MaximumLength; void *Buffer; } UNICODE_STRING;
typedef struct { uint16_t Length, MaximumLength; uint32_t Buffer; } UNICODE_STRING32;
#define ULongToPtr(x) ((void *)(uintptr_t)(x))
static uint64_t window_base = UINT64_C(0x7038000000);
static void *wow64_to_host(uint32_t guest) { return guest ? (void *)(uintptr_t)(window_base + guest) : NULL; }
'''+helper+'''
int main(void) {
    UNICODE_STRING output;
    UNICODE_STRING32 input = {0, 0, 0xc010};
    assert(unicode_str_32to64(&output, NULL) == NULL);
    assert(unicode_str_32to64(&output, &input) == &output);
    assert((uintptr_t)output.Buffer == 0xc010); /* native IS_INTRESOURCE true */
    input.Buffer = 0; unicode_str_32to64(&output, &input); assert(output.Buffer == NULL);
    input.Buffer = 0xffff; unicode_str_32to64(&output, &input); assert((uintptr_t)output.Buffer == 0xffff);
    input.Buffer = 0x10000; unicode_str_32to64(&output, &input); assert((uintptr_t)output.Buffer == window_base + 0x10000);
    input.Length = 12; input.MaximumLength = 14; input.Buffer = 0x400020;
    unicode_str_32to64(&output, &input);
    assert((uintptr_t)output.Buffer == window_base + 0x400020 && output.Length == 12 && output.MaximumLength == 14);
    window_base = 0; unicode_str_32to64(&output, &input); assert((uintptr_t)output.Buffer == 0x400020);
    return 0;
}
'''
        scratch = REPO / '.work/tests'; scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            c = Path(tmp) / 'atoms.c'; c.write_text(source); exe = Path(tmp) / 'atoms'
            subprocess.run(['cc', '-Wall', '-Werror', str(c), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)
