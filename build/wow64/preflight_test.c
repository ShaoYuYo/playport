/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Exercise production early-window functions with a constrained VM model. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <signal.h>

typedef unsigned short USHORT;
typedef int NTSTATUS;
#define STATUS_SUCCESS 0
#define STATUS_NO_MEMORY 1
#define STATUS_CONFLICTING_ADDRESSES 2
#define IMAGE_FILE_MACHINE_I386 0x14c
#define IOS_WOW64_WINDOW_SIZE UINT64_C(0x100000000)
struct file_view { void *base; };
static USHORT ios_title_machine;
static struct file_view *ios_wow64_title_window;
static int virtual_mutex, maps, deletes;
static uint64_t free_bytes;
static struct file_view allocated;
static void server_enter_uninterrupted_section(int *m, sigset_t *s) { (void)m; (void)s; }
static void server_leave_uninterrupted_section(int *m, sigset_t *s) { (void)m; (void)s; }
static int ios_wow64_valid_base(uintptr_t b) { return b >= IOS_WOW64_WINDOW_SIZE && !(b & 0xffff); }
static NTSTATUS map_view(struct file_view **v, void *b, uint64_t size,
                         unsigned a, unsigned p, uintptr_t l, uintptr_t h, size_t mask)
{
    (void)b; (void)a; (void)p; (void)l; (void)h; (void)mask;
    maps++;
    if (size > free_bytes) return STATUS_NO_MEMORY;
    free_bytes -= size;
    *v = &allocated;
    return 0;
}
static void delete_view(struct file_view *v) { (void)v; deletes++; free_bytes += IOS_WOW64_WINDOW_SIZE; }
#include "preflight_api.h"

static void reset(USHORT machine, uintptr_t base)
{
    ios_wow64_title_window = NULL;
    maps = deletes = 0;
    free_bytes = UINT64_C(0x150000000); /* 5.25 GiB actually mappable */
    allocated.base = (void *)base;
    ios_set_title_machine(machine);
}
int main(void)
{
    struct file_view *view = NULL;
    reset(0x14c, UINT64_C(0x7020000000));
    assert(!ios_wow64_prepare_title_window());
    assert(maps == 1 && free_bytes == UINT64_C(0x50000000));
    assert(!ios_wow64_prepare_title_window() && maps == 1); /* idempotent */
    /* A 1 GiB FEX arena fits after the full 4 GiB window; the old 4 GiB
     * FEX-first order leaves no capacity for the guest. */
    assert(free_bytes >= UINT64_C(0x40000000));
    free_bytes -= UINT64_C(0x40000000);
    assert(!ios_wow64_take_title_window(&view) && view == &allocated && maps == 1);
    assert(!ios_wow64_title_window); /* one owner, no second consumption */
    assert(ios_wow64_take_title_window(&view) == STATUS_NO_MEMORY && maps == 2);

    reset(0x8664, UINT64_C(0x7020000000));
    assert(!ios_wow64_prepare_title_window() && maps == 0);
    assert(!ios_wow64_take_title_window(&view) && maps == 1); /* i386 child of x64 */
    reset(0, UINT64_C(0x7020000000));
    assert(!ios_wow64_prepare_title_window() && maps == 0);
    reset(0x14c, UINT64_C(0x200000));
    assert(ios_wow64_prepare_title_window() == STATUS_CONFLICTING_ADDRESSES);
    assert(!ios_wow64_title_window && deletes == 1);
    reset(0x14c, UINT64_C(0x7020000000));
    free_bytes = UINT64_C(0x80000000);
    assert(ios_wow64_prepare_title_window() == STATUS_NO_MEMORY);
    assert(!ios_wow64_title_window && deletes == 0);
    puts("WoW64 early reservation: constrained capacity, one-owner handoff, failures and x64 passed");
    return 0;
}
