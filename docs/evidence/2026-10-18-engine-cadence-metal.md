# Engine cadence and explicit Metal translation route

The r19 report renders at 2338x1080, unlimited on a 60 Hz panel. Its sampled
presentation rate varies from 20.4 to 58.1 FPS; launcher limiter waits are
approximately zero. The owner observes about 30 FPS on title/settings screens
and 60 after loading a save. These observations do not establish a global
30 FPS cap or identify every source of scene-transition stalls.

## Actual engine probe, hidden Windows desktop

The retained game executable was run with an original synthetic startup
script, a hidden window object and an isolated data directory, on a private
desktop that was never displayed. No game assets or scripts were extracted
for this probe. Original Windows install and saves were not modified.
The existing `-startup`, `-datapath` and `-contfreq` options were used; these
are scratch experiments, not product entry points.

| contfreq | Callbacks | Duration | Process CPU seconds |
| --- | ---: | ---: | ---: |
| 0 | 18,916,780 | 4000 ms | 4.078 |
| 30 | 122 | 4016 ms | 0.172 |
| 60 | 241 | 4001 ms | 0.297 |

This proves the actual engine accepts the rate option and can otherwise busy
spin in a minimal continuous-handler workload. It is not a game FPS benchmark
and does not predict that percentage of CPU savings in gameplay. The
[pinned engine implementation](https://github.com/krkrz/krkrz/blob/fd5c4baa6a2ef5978db1bd043634351f48667daf/base/win32/EventImpl.cpp)
uses a timed thread for nonzero contfreq; a window's waitVSync mode or a runtime
script may instead control scheduling.

The title profile now supplies contfreq matching the panel-clamped launch
limit. Thirty, sixty and higher supported rates remain distinct; zero stays
unlimited. Explicit arguments are preserved, and the title profile opt-out
remains available. The in-game limiter still changes immediately; engine
cadence applies on the next launch. Native audio and all native images stay
unchanged. No guessed legacy renderer switch or unsafe memory-ordering
relaxation is introduced.

Frame diagnostics now include average producer request interval separately
from drawable and limiter waits. The display sheet shows the latest measured
pre-menu sample. Resuming the app menu starts a new measurement window, so
intentional pause time does not become a reported game stall. No duplicate
frames or requested-limit value is presented as measured FPS.

## DX12 to Metal

The bundle already contains vkd3d-proton d3d12/d3d12core ARM64EC DLLs and the
KosmicKrisp framework. Its route is D3D12 -> vkd3d-proton -> Vulkan -> Metal,
not DXMT (which handles D3D10/11). The
[Mesa documentation](https://docs.mesa3d.org/drivers/kosmickrisp.html) describes
that Vulkan-on-Metal driver. This change does not claim a new direct DX12
compiler or support for every DX12 feature/game.

Availability now checks required DLL headers and machine types, nonempty
bundled components and the Metal driver, once per process. An empty overlay
directory cannot advertise a working translation stack. The existing launch
gate rejects an incomplete backend before spending JIT. Labels, descriptions
and launch diagnostics show Metal as the final target and distinguish the
current 32-bit D3D9 component from the 64-bit DX12 stack.

51 HostIOKit, 43 Cloud/Steam API, 17 selected title/diagnostic and 5 Direct3D12
tests pass. Release compilation and 87 IPA checks pass on the unchanged
1615-file native checkpoint. This intermediate unsigned IPA has SHA256
`ef764bf73ae9eb7d35bf41f52bca55dcb4671e23a59e931b726d1f638bde6f15`.
No phone was connected; improvement of the owner's 30 FPS scene remains
unverified on that phone.
