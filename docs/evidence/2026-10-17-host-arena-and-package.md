# Senren Banka: bounded FEX arena exhaustion after r8

## Report and compatibility audit

The owner supplied the report ending `20261016-235621`. Its current log is
the app restart; the previous log contains three r8 launches, with matching
native and PE artifact hashes. Each launch proceeds beyond the draw-worker
self-suspend issue: bounded `suspend-gate-v1` wait/resume messages are paired.
The game continues initializing workers and then the FEX arena cannot place
another allocation. The largest reported gap is 0xf70000 bytes, below the
requested 16 MiB scratch block; another prediction-stack reservation of
0x1002000 also fails. The arena is 768 MiB. This is exhaustion/fragmentation
of the translator's reserved virtual-address region, not evidence that iOS
RAM admission denied the game's next allocation.

WoW64 initialization then ignores the failed prediction-stack initializer
and enters translated code with a missing stack. Another worker's missing
thread state is dereferenced before validation. The later host faults
include addresses `0x3ffff0`, zero and `0x40`, and a recursive delivery storm
ends the app. The report identifies a concrete translator allocation/error
handling defect; it does not identify a game check deliberately rejecting
a non-Windows host.

The current i386 compatibility probe reports ACP/OEM 932, the expected CP932
conversion and a valid desktop handle. The CPUID regression still passes.
The early C++ `e06d7363` exception is recovered from before the game reaches
the workers; treating it as a fatal anti-emulator check would be incorrect.
The source was also checked for the display-primary warnings: Wine's
depth-query path can fall back to 32 bpp without a primary source, while
other display queries have their own failure contracts. No invented display
device, CPU features or generic success return was added to mask such
queries. Graphics startup still needs a successful owner run.

No phone connection/control or Windows game launch was used. Private game
bytes, report contents, account/device identifiers and external paths are
not committed.

## Scratch ownership and failure handling

`fex/0026` lets the pool reclaim a DISOWNED compiler buffer immediately on
iOS rather than retaining each worker's copy for five seconds. Its existing
DISOWNED-to-FREE compare/exchange still arbitrates a concurrent reownership;
OWNED memory is never taken. Decoder, IR and temporary emission capacities
are unchanged, and compiled game code is not removed. The non-iOS five-second
policy remains unchanged. This addresses the observed repeated 8/16 MiB
scratch mappings without shrinking instruction/IR limits or prediction
stack geometry.

The WoW64 initialization entry also checks the two observed failures. On a
missing thread state it releases CRT resources; on a failed prediction stack
it additionally releases the GDT and thread state. Both paths unlock the
creation mutex before ending that Wine guest with `STATUS_NO_MEMORY`.
Neither publishes half-initialized TLS or enters the translator with a
NULL stack. The ABI remains void and the normal initialization path is
unchanged. The containment call is a guest process termination, not a host
app abort. Its complete device behavior remains unverified.

## Host checks

`build/test-ios-scratch-pool.py` compiles the actual complete pool header
with ASan/UBSan and a modeled backing allocator. Twenty-four hot disowned
16 MiB clients retain 24 mappings under the non-iOS policy; iOS reuses one.
Eight concurrent owners remain distinct through 500 synchronized reclaim
rounds each. This exercises client destruction, invalidated ownership and
reuse; it does not measure the game's RAM reduction.

The same test extracts the entire actual `BTCpuThreadInit` function and
injects thread-state and prediction-stack failure. Both clean up before
the modeled guest termination; the mutex is unlocked and TLS/registry are
unpublished. Successful initialization still publishes a complete state.
Termination, OS mappings and the surrounding FEX context are modeled.

The two real FEX images rebuild with the pinned production recipes. The
120 AArch64 guard instruction tests and CPUID ASan regression pass. The
guarded migration changes only those two PE images and their records;
all 1,615 checkpoint outputs are verified. SHA256:

| Image | SHA256 |
| --- | --- |
| aarch64 xtajit.dll | `02ffaa3b5c9107eb20af4d7a063c4468da9bf8a292e9698f9156be627f9b1df6` |
| ARM64EC xtajit64.dll | `31ad6691aa9327b11596b5394774b7e91c2909a44768125b3a04f6bd26d37f39` |

## Lossless IPA compression

The app stage now deflates the outer IPA ZIP after xtool creates it and
before checksumming/verifying the delivery. `build/compress-ipa.py` compares
every extracted entry's SHA256, size, permissions, timestamps, comments and
extra data before replacing the original container. Code signatures and
bundle resources are preserved as bytes. Only STORED and DEFLATE are
accepted by the verifier; other compression methods remain rejected.
This reduces transfer/archive size, not the installed bundle size. No DLL,
language data, license, game support or application data is removed.

The app revision is `SteamGlass-20261017-r9`, with scratch/init markers.
Successful game launch still needs an owner side-load run. No full-tooling
suite or iOS play pass is claimed.

The unsigned IPA passes all 87 verification checks after compression.
It changes from 674,096,128 stored bytes to 182,716,744 bytes (72.9% smaller),
with the entry content/metadata inventory unchanged. IPA SHA256:
`184e6b375695144c9b840b368fb73a61bb3f4b9915ade10af507cee8cd68fad5`.
