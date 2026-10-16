# 0069: A smaller memory profile for the measured i386 title

**Status:** accepted, 2026-10-16. Amends [0036](0036-one-512-mib-jit-pool.md)
only for the recognized i386 Steam app 1144400. See the
[evidence](../evidence/2026-10-16-memory-economy.md).

The owner requested lower RAM consumption. A default-enabled Graphics setting,
**遊戲省記憶體模式**, applies this profile on the next launch:

- A 256 MiB JIT pool, instead of the general 512 MiB budget. Pool blessing
  charges the full fixed allocation. The supplied startup report used 26 MiB
  of head and 33 MiB of tail. The new budget still accommodates a normal
  128 MiB translator buffer with about 100 MiB for later growth beyond that
  recorded head. It cannot grow during a launch.
- Existing Wine `cpu-count=2`, unless the game's explicit runtime settings
  override it. This reduces automatic worker fleets and their per-thread FEX
  heaps, call-return stacks and lookup caches. It changes the processor count
  reported by Wine; it does not set CPU affinity or alter the host CPU.
- KiriKiri `-memusage=low -drawthread=2`, unless the player supplied either
  option. These use the engine's cache policy, without rewriting game files.

Other titles retain 0036's budget. Turning the switch off restores the general
budget and removes these automatic overrides. Dev simulation and explicit
launch pool overrides retain precedence. The existing configurable memory
safety margin stays independent and never preallocates its margin in RAM.

The tradeoff is more image reloads and possibly slower effects. Later scenes
could exhaust the smaller executable pool; that remains a reported outcome,
and the switch permits retrying with the original pool. There is no claim of
a measured full-game iOS peak or successful first frame for this candidate.

Live game data is not manually compressed or discarded. iOS manages page
compression; release diagnostics report compressed pages separately without
adding them to the footprint a second time.
