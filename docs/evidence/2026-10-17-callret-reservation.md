# Senren Banka: r11 exhausts per-thread prediction reservations

## New device result

The report ending `20261017-125257` contains two new r11 launches, with the
expected FEX and host hashes. They pass the r10 span-alignment failure and
reach 34 initialized prediction stacks. Both still exit `0xc0000017`, with
no first frame, when another call-return reservation of `0x1002000` bytes
cannot fit. The 1,024 MiB host arena reaches about 1,002 MiB used, 22 MiB
free and a largest gap of 13 MiB. Physical RAM admission reports zero
denials; the JIT pool still has about 70 MiB room. This is another concrete
host-arena failure, not evidence of a game deliberately rejecting Windows
emulation or a proven rendering failure.

Each successful prediction reservation consumes 16 MiB plus guards. Thirty-
four therefore retain about 544 MiB before guard/granularity overhead. The
reduced rpmalloc geometry lets execution progress far enough to expose this
next per-thread cost. No game success is inferred from the higher thread
count.

## Consistent reservation and guard geometry

`fex/0027` reserves 8 MiB per iOS call-return prediction stack. The existing
CALL/RET guard window remains `[base+2 MiB, base+6 MiB)`, and the default
pointer remains `base+4 MiB`. Named offsets no longer derive from total
reservation size, and the Windows initializer plus C++ recovery/diagnostic
paths use the named default. Non-iOS reservation geometry remains 16 MiB.
The guest architectural stack and game allocation sizes are unchanged.

This change is paired with callback protection. The prior ARM64EC callback
sentinel guard admitted the full 16 MiB range, including the base itself
before a predecrement store; the WoW64 callback push had no such guard.
Both iOS callback emitters now enforce the existing CALL/RET window before
storing the sentinel. Shrinking only the allocation without changing that
path would permit writes outside the new reservation. The predictor is a
return-target cache, not the guest return stack; a reset loses prediction
history rather than changing the guest stack.

`ResetCallRetStack` still decommits/recommits the entire reservation, now
8 MiB. It is not clipped to the hot window: full reset is needed to reclaim
all allocated pages and stale entries. Allocation failure cleanup remains
active. The configured host arena, JIT pool and RAM safety margin are not
silently increased or disabled.

For the reported 34 initialized stacks, the reservation reduction is
272 MiB before identical guard overhead. This is a change in reserved
address-space demand, not a measured reduction in game physical RAM or a
guarantee about how many further threads the game will create.

`madeira-unix/0105` updates the native diagnostic shape classifier to count
4 MiB spans, 8 MiB prediction allocations and 4 MiB aligned free slots.
The census ABI is unchanged. Shape classification remains approximate;
use the request size/alignment, view map and total usage together.

## Tests and build

`build/test-callret-reservation.py` compiles the actual Windows namespace
through `DestroyThread`: geometry, `GetInfoThread`, injection, allocation,
initialization and cleanup. OS mapping, logging and surrounding thread-
state layout are modeled. A 1 GiB mapping backend holds 460 MiB of other
users constant. The r11 initializer fits 35 of 64 attempted stacks; the new
initializer fits all 64. These are prediction allocations, not 64 complete
FEX/game threads. Reserve and commit failure injection both clean up, and
the next initialization succeeds. Default pointer, full reserved extent
and published frame fields are checked under ASan/UBSan.

The original 120 actual AArch64 CALL/RET guard cases still pass.
`build/test-wow64-callret.py` additionally emits the production callback
guard and its following sentinel `stp` for WoW64 and ARM64EC. Twenty-four
boundary cases execute under Unicorn with memory outside the 8 MiB region
unmapped. Invalid pointers reset before the store, valid pointers retain
their position, the store lands inside the reservation, and flags survive.
This does not execute a complete translated callback or iOS exception path.

`build/test-arena-census.py` compiles the actual native census loop and gap
calculation against ordered view fixtures. It verifies the updated span,
stack and L1 classification, other bytes, totals, largest gap and aligned
slot count under ASan/UBSan.

The two production FEX DLLs rebuild through pinned recipes. Existing pool
ownership, full WoW64 init failure handling and CPUID regression pass.
The production native recipe recompiles `virtual.o`; all 34 other archive
members are verified byte-identical. Guarded migrations verify the full
1,615-file native checkpoint, permitting only that archive, two FEX images
and their manifests to change.

| Image | SHA256 |
| --- | --- |
| aarch64 xtajit.dll | `b856877627b9ab30bb25f2b772223052c956f7a5cbb00a82249ec6bdd365201a` |
| ARM64EC xtajit64.dll | `b4884ba3a05d8b4eb2a696056510e54b3efaf7c21d706cc4a8f5aec6389c4fdb` |
| libntdll_unix.a | `b38a4a8221159aa31ea6ab1b873df3bfb7dcc88a4871f732711f63c69f01367f` |

No phone connection/control or Windows game launch was used. Static private
binary inspection did not change the game or saves, and no private game
bytes, report text, account data or device identifiers are committed.

The bounded arena, JIT capacity, physical memory pressure, callbacks and
graphics/video startup remain possible subsequent constraints. This fixes
the observed reservation failure in host tests; successful game execution
still requires an owner side-load run. No full repository-suite or iOS
gameplay pass is claimed.

The unsigned `SteamGlass-20261017-r12` IPA passes all 87 package checks.
Its losslessly compressed archive is 182,719,225 bytes. Packaged FEX and
native archive manifest hashes match the table; the other Wine PE hashes
remain unchanged. IPA SHA256:
`3190b9e5bc4f895ab238ae8e5cd923a135fcccf383dca95ba8bebebd37aef21b`.
