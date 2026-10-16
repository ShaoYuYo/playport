/* Reproduce a manually loaded PE's live .data sharing a 16 KiB host page
 * with discardable .reloc. Compile the actual VM/protection headers.
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#define WOW64_VM_HELPERS_ONLY
#include "vm_test.c"

int main(void)
{
    struct rlimit core = {0, 0};
    assert(!setrlimit(RLIMIT_CORE, &core));
    bases[0] = reserve(); bases[1] = reserve();
    int owner;
    ios_wow64_windows[0].owner = &owner;
    ios_wow64_windows[0].base = bases[0];
    current_owner = &owner;
    void *image_base = (void *)(bases[0] + 0x10000000);
    size_t extent = 0x24000;
    assert(!routed(0, &image_base, &extent, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE, NULL));
    unsigned char *live = (unsigned char *)image_base + 0x1dd7c;
    unsigned char *reloc = (unsigned char *)image_base + 0x1f000;
    *live = 0xa7;
    memset(reloc, 0xcc, 0x3000);
    void *page = (char *)image_base + 0x1c000;
    size_t size = page_size;
    ULONG old;
    assert(!routed(2, &page, &size, 0, PAGE_READONLY, &old));
    unsigned live_prot = get_page_vprot(live);
    unsigned readonly_prot = get_page_vprot(page);
    page = reloc; size = 0x3000;
#ifndef WOW64_SUBPAGE_BASELINE
    fail_protect = 1;
    assert(routed(1, &page, &size, MEM_DECOMMIT, 0, NULL) == STATUS_ACCESS_DENIED);
    assert(page == reloc && size == 0x3000 && get_page_vprot(reloc) & VPROT_COMMITTED);
    fail_protect = 0;
#endif
    assert(!routed(1, &page, &size, MEM_DECOMMIT, 0, NULL));
    assert(*live == 0xa7 && get_page_vprot(live) == live_prot);
    *live = 0xb8; /* The reported CRT instruction writes here after discard. */
    assert(*live == 0xb8 && get_page_vprot((char *)image_base + 0x1c000) == readonly_prot);
    assert(page == reloc && size == 0x3000);
    for (size_t i = 0; i < size; i += page_size) assert(!get_page_vprot(reloc + i));
    /* The first host page still has writable neighbours. Even an invalid
     * intervening write cannot violate zero-on-recommit. */
    reloc[0] = 0x5a;
#ifndef WOW64_SUBPAGE_BASELINE
    fail_protect = 1;
    assert(routed(0, &page, &size, MEM_COMMIT, PAGE_READWRITE, NULL) == STATUS_ACCESS_DENIED);
    assert(!get_page_vprot(reloc) && *live == 0xb8);
    fail_protect = 0;
#endif
    assert(!routed(0, &page, &size, MEM_COMMIT, PAGE_READWRITE, NULL));
    for (size_t i = 0; i < size; i++) assert(!reloc[i]);
    assert(*live == 0xb8 && get_page_vprot(live) == live_prot);
    reloc[0] = 0x42;
    assert(!routed(0, &page, &size, MEM_COMMIT, PAGE_READWRITE, NULL));
    assert(reloc[0] == 0x42); /* Recommitting committed bytes preserves them. */
    size = 0;
    assert(!routed(1, &image_base, &size, MEM_RELEASE, 0, NULL));
    puts("WoW64 PE subpage discard/recommit: live data and protection preserved; recommit zeroed");
    return 0;
}
