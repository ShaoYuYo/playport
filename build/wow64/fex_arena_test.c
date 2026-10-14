/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <assert.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include "wow64_fex_arena.h"
static uint64_t ios_fex_arena_base_unix, ios_fex_arena_end_unix;
static size_t host_page_mask = 255;
static int protections, fail_protection;
#define PROT_READ 1
#define PROT_WRITE 2
static int mock_protect(void *p, size_t size, int prot)
{
    (void)p; assert(size == 256 && prot == 3); protections++;
    return fail_protection && protections == fail_protection ? -1 : 0;
}
#define mprotect mock_protect
static const char *ios_pe_module_name(const void *image, size_t size)
{
    (void)image; (void)size; return "libwow64fex.dll";
}
#include "seed_api.h"

static void put32(unsigned char *b, size_t off, uint32_t x) { memcpy(b + off, &x, 4); }
static void put16(unsigned char *b, size_t off, uint16_t x) { memcpy(b + off, &x, 2); }
static void fixture(unsigned char *b)
{
    memset(b, 0, 4096); memcpy(b, "MZ", 2); put32(b, 60, 128);
    memcpy(b + 128, "PE\0\0", 4); put16(b, 132, 0xaa64); put16(b, 134, 1);
    put16(b, 148, 240); put16(b, 152, 0x20b); put32(b, 128 + 0x84, 16);
    put32(b, 128 + 0x88, 0x300); put32(b, 128 + 0x8c, 0x200);
    put32(b, 392 + 8, 0x200); put32(b, 392 + 12, 0x800); put32(b, 392 + 36, 0xc0000040);
    put32(b, 0x300 + 20, 2); put32(b, 0x300 + 24, 2);
    put32(b, 0x300 + 28, 0x400); put32(b, 0x300 + 32, 0x420); put32(b, 0x300 + 36, 0x430);
    put32(b, 0x400, 0x800); put32(b, 0x404, 0x900);
    put32(b, 0x420, 0x500); put32(b, 0x424, 0x520); put16(b, 0x430, 0); put16(b, 0x432, 1);
    strcpy((char *)b + 0x500, "ios_fex_band_base"); strcpy((char *)b + 0x520, "ios_fex_band_end");
    protections = fail_protection = 0;
}
int main(void)
{
    unsigned char backing[4096], copy[4096]; uint32_t slots[2] = {99, 100}; uint64_t base, end;
    fixture(backing);
    assert(ios_wow64_fex_arena_slots(backing, sizeof(backing), slots));
    assert(slots[0] == 0x800 && slots[1] == 0x900);
    ios_fex_arena_base_unix = UINT64_C(0x7138000000);
    ios_fex_arena_end_unix = UINT64_C(0x7178000000);
    assert(ios_wow64_seed_fex_arena(backing, sizeof(backing)) && protections == 2);
    memcpy(copy, backing, sizeof(copy)); /* actual loader handoff precedes JIT copy */
    memcpy(&base, copy + slots[0], 8); memcpy(&end, copy + slots[1], 8);
    assert(base == ios_fex_arena_base_unix && end == ios_fex_arena_end_unix - 1);
    int selector_calls = 0;
    if (!base) selector_calls++; /* rpmalloc's existing first-allocation guard */
    assert(!selector_calls && end - base + 1 == UINT64_C(0x40000000));
    fixture(backing); fail_protection = 2;
    assert(!ios_wow64_seed_fex_arena(backing, sizeof(backing)));
    memcpy(&base, backing + 0x800, 8); memcpy(&end, backing + 0x900, 8); assert(!base && !end);
    for (int kind = 0; kind < 7; kind++) {
        fixture(backing); slots[0] = 99; slots[1] = 100;
        if (kind == 0) put32(backing, 0x404, 0x800); /* same data slot */
        if (kind == 1) put32(backing, 0x400, 0x350); /* forwarder */
        if (kind == 2) put16(backing, 0x430, 2); /* bad ordinal */
        if (kind == 3) put32(backing, 392 + 36, 0x60000020); /* executable section */
        if (kind == 4) put32(backing, 0x300 + 32, 4095); /* names table OOB */
        if (kind == 5) backing[0x520] = 'x'; /* missing second export */
        if (kind == 6) put32(backing, 0x400, 4096); /* data OOB */
        assert(!ios_wow64_fex_arena_slots(backing, sizeof(backing), slots));
        assert(slots[0] == 99 && slots[1] == 100);
    }
    fixture(backing);
    for (size_t size = 0; size < 152; size++) assert(!ios_wow64_fex_arena_slots(backing, size, slots));
    assert(!ios_wow64_fex_arena_valid(0, 0));
    assert(!ios_wow64_fex_arena_valid(UINT64_C(0x7138000000), UINT64_C(0x7138000000)));
    assert(!ios_wow64_fex_arena_valid(UINT64_C(0x7138000001), UINT64_C(0x7178000000)));
    assert(!ios_wow64_fex_arena_valid(UINT64_C(0x7138000000), UINT64_C(0x7138010000)));
    puts("WoW64 FEX pre-CRT handoff: native/backing/copy agree; invalid DATA exports and partial writes rejected");
    return 0;
}
