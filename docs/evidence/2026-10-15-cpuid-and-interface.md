# iOS CPUID bounds and a simpler app shell

The new Senren Banka (Steam 1144400) diagnostic report passed its fixed
CP932 sample and desktop-window validity check, but threw during startup.
Mapping the executable's stack identifies the narrow-string constructor
called while appending the CPUID brand name. The early error-122 conversion
messages are the engine's expected insufficient-buffer retry, not the fatal
conversion itself.

## Runtime defect and change

The current iOS host creates exactly one synthetic MIDR. The Windows FEX
build's `getcpu` uses Wine's current processor number, which may be nonzero.
CPUID's brand leaves index `PerCPUData` with that value without a bounds
check. The game's startup probes processor affinities. This is a concrete
out-of-bounds defect consistent with the phone stack; the phone's actual
corrupt brand bytes have not been captured.

FEX patch 0024 makes current-CPU queries select the existing synthetic entry
on iOS, and prevents the TPIDRRO path from overriding that selection. It
does not constrain Wine's scheduling or change non-iOS CPU selection. No
component pins changed. Both actual FEX modules were rebuilt with the
unchanged stage recipe; a checked checkpoint migration preserved every
other runtime artifact byte.

Actual output SHA256:

- WoW64 `xtajit.dll`: `d3a06c68396268d00734402f1723e5ba83f4d628b25a657b66789312c5a2ca4b`
- ARM64EC `xtajit64.dll`: `f766155d8dc12db5a4fe0e41357a27a19735b8063c39e78db9bebd731afccf8f`

The report fingerprint whitelist now includes both modules. It still
excludes saves, account files, symlinks and file contents.

## Background game comparison

The installed Windows game was unwrapped using the production helper in a
scratch copy, with the same Playport Steam emulator. It was launched on a
new private Win32 desktop, never switched into the interactive desktop.
After 12 seconds its main game window still existed and its CPU brand was
valid ASCII. Only the created game process was terminated afterward.

A second scratch copy changed only the CPU-brand conversion input to an
invalid CP932 string. It displayed the fatal dialog `Cannot convert given
narrow string to wide string`, matching the class of phone failure. Neither
run changed the installed Steam executable, configuration or archives.
Game bytes, memory captures, artwork and private logs remain uncommitted.
This checks startup behavior; it does not establish playable scenes or
successful iOS rendering.

## Interface

- Keep the shell header at one height on main pages and secondary pages.
- Put Home, Library and Downloads in one glass navigation surface; remove
  the on-screen LB/RB buttons and disconnected-controller status.
- Add a direct Back control for secondary pages, using the existing route
  stack and first-run departure guard.
- Show the controller footer and focus outline only with a connected
  controller. Hardware mappings remain available.
- Hide empty download/queue cards and the repeated Find games tile on Home.
- Replace the library chip row with one filter/sort selector, Search and
  Add. Remove the repeated Add tile and empty-state Add button; provide a
  touch Clear search control.
- Use plain settings rows, one selection background, a scrollable sidebar,
  and system-width typography. Remove the repeated Settings heading and
  connected-controller reassurance. Only full-controller-support games
  retain the disconnected-controller launch note.

The persistent root TabView and native game NavigationStack remain the
owners of page and navigation state. Reduced Motion retains the short
opacity transition. Phone layout, animation continuity and game first frame
have **not** been checked on an attached phone.

## Checks

`build/test-ios-cpuid.py` compiles the actual production selector and all
three brand leaves with AddressSanitizer. Against the one-entry host model,
the original code reports heap-buffer-overflow at CPU 1. The patched code
passes all 64 host indices; the non-iOS build retains each native index and
also passes all 64.

The actual unsigned release IPA passed all 87 verifier checks. Its SHA256
is `556ad20e6eae094ffacaa731e08d288b58cff3a092b34aae658391f6105edcbd`.
All 14 AppRoutes and 9 LaunchDiagnostics Swift tests passed.
