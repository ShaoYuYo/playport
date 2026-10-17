/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
typedef uint32_t DWORD, UINT, ULONG;
typedef uint64_t ULONGLONG;
typedef int64_t LONGLONG;
typedef int BOOL, WAIT_TYPE;
typedef void *HANDLE;
typedef union { int64_t QuadPart; } LARGE_INTEGER;
#define TRUE 1
#define FALSE 0
#define INFINITE UINT32_MAX
#define WAIT_TIMEOUT 258u
#define WAIT_FAILED UINT32_MAX
#define WAIT_IO_COMPLETION 192u
#define MWMO_WAITALL 1u
#define MWMO_ALERTABLE 2u
#define QS_ALLINPUT 0xffffu
#define QS_SMRESULT 0x8000u
#define WaitAny 1
#define WaitAll 0
#define HIWORD(x) ((x) >> 16)
struct dispatch { int callback; };
struct thunk_lock_params { struct dispatch dispatch; DWORD locks; BOOL restore; };
static int thunk_lock_callback;
struct user_info { HANDLE idle_event; LONGLONG last_driver_time; };
static struct user_info info;
static int64_t clock_ticks, input_ms, external_ms, apc_ms;
static unsigned calls, polls, callbacks;
static int queue_ready, last_wait_type, last_alertable;
static char *no_desktop(const char *name) { (void)name; return NULL; }
#define getenv no_desktop
static void NtQuerySystemTime(LARGE_INTEGER *now) { now->QuadPart = clock_ticks; }
static struct user_info *get_user_thread_info(void) { return &info; }
static LONGLONG get_driver_check_time(void) { return clock_ticks; }
static int KeUserDispatchCallback(void *a, unsigned b, void **c, ULONG *d)
{ (void)a; (void)b; (void)c; (void)d; callbacks++; return 1; }
static void NtSetEvent(HANDLE h, void *a) { (void)h; (void)a; }
static void NtYieldExecution(void) {}
static DWORD RtlNtStatusToDosError(DWORD s) { return s; }
static void RtlSetLastWin32Error(DWORD s) { (void)s; }
static BOOL process_driver_events(UINT events, UINT wake, UINT changed)
{
    (void)events; (void)wake; (void)changed; polls++;
    if (clock_ticks >= input_ms * 10000) queue_ready = 1;
    return queue_ready;
}
static DWORD NtWaitForMultipleObjects(DWORD count, const HANDLE *handles, WAIT_TYPE type,
                                     BOOL alertable, const LARGE_INTEGER *deadline)
{
    (void)handles; calls++; assert(calls < 1000); assert(count >= 1);
    last_wait_type = type; last_alertable = alertable;
    int64_t end = deadline ? deadline->QuadPart : clock_ticks + 10000000;
    if (end < clock_ticks) end = clock_ticks;
    if (alertable && apc_ms * 10000 <= end) { clock_ticks = apc_ms * 10000; return WAIT_IO_COMPLETION; }
    if (type == WaitAll) {
        if (queue_ready && (count == 1 || external_ms * 10000 <= end)) {
            if (count > 1 && clock_ticks < external_ms * 10000) clock_ticks = external_ms * 10000;
            return 0;
        }
    } else {
        if (count > 1 && external_ms * 10000 <= end) { clock_ticks = external_ms * 10000; return 0; }
        if (queue_ready) return count - 1;
    }
    clock_ticks = end;
    return WAIT_TIMEOUT;
}
#include "actual_wait.h"
static void reset(void) {
    clock_ticks = 0; input_ms = external_ms = apc_ms = 1000000;
    calls = polls = callbacks = 0; queue_ready = 0; memset(&info, 0, sizeof(info));
}
int main(void)
{
    HANDLE handles[2] = {(void *)1, (void *)2};
    for (unsigned arrival = 1; arrival <= 128; arrival += 7) {
        reset(); input_ms = arrival;
        DWORD r = wait_message(2, handles, 200, QS_ALLINPUT, QS_ALLINPUT, 0);
        assert(r == 1 && clock_ticks >= input_ms * 10000);
        assert(clock_ticks - input_ms * 10000 <= 160000);
        assert(callbacks == 2);
    }
    for (unsigned timeout = 0; timeout <= 129; timeout += 7) {
        reset();
        DWORD r = wait_message(2, handles, timeout, QS_ALLINPUT, QS_ALLINPUT, 0);
        assert(r == WAIT_TIMEOUT && clock_ticks == (int64_t)timeout * 10000);
        assert(calls <= timeout / 16 + 1);
    }
    reset(); input_ms = 50;
    assert(wait_message(2, handles, INFINITE, QS_ALLINPUT, QS_ALLINPUT, 0) == 1);
    assert(clock_ticks == 640000);
    reset(); external_ms = 10;
    assert(wait_message(2, handles, 200, QS_ALLINPUT, QS_ALLINPUT, 0) == 0 && clock_ticks == 100000);
    reset(); input_ms = 50; external_ms = 90;
    assert(wait_message(2, handles, 200, QS_ALLINPUT, QS_ALLINPUT, MWMO_WAITALL) == 0);
    assert(clock_ticks == 900000 && last_wait_type == WaitAll);
    reset(); input_ms = 1;
    assert(wait_message(2, handles, 35, QS_ALLINPUT, QS_ALLINPUT, MWMO_WAITALL) == WAIT_TIMEOUT);
    assert(clock_ticks == 350000);
    reset(); apc_ms = 5;
    assert(wait_message(2, handles, 200, QS_ALLINPUT, QS_ALLINPUT, MWMO_ALERTABLE) == WAIT_IO_COMPLETION);
    assert(clock_ticks == 50000 && last_alertable);
    puts("iOS input wait: 43 arrival/deadline/mode cases passed; input poll <=16 ms, original deadlines, WaitAll and APC preserved");
    return 0;
}
