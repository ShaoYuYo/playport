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

## Follow-up: PE subpage decommit and SteamGlass r3

The subsequent report reaches CPU-brand initialization, then faults on the
instruction at guest `1000f9d4`, writing guest `1001dd7c`. A manually loaded
PE has live `.data` starting at `1b000` and discardable `.reloc` at `1f000`.
The old VM helper rounds a guest decommit outward to a 16 KiB host page,
revoking the live CRT data in the same page. The terminal `c0000409` is the
later fast-fail outcome; no game frame was drawn.

Madeira patch 0101 keeps explicit commit/decommit ranges on 4 KiB guest
boundaries. Partial host pages keep their backing and use the existing
logical protection/host permission union. Recommit zeros only previously
uncommitted guest pages. Whole host-page replacement and release retain
their original behavior. Partial decommit can retain physical backing
until recommit or release; it does not promise immediate reclamation.

The regression compiles the production VM/protection headers with real
16 KiB mappings. It models the reported PE layout, writes live CRT data
after discarding relocation pages, preserves a read-only logical neighbour,
checks failure rollback, zero-on-recommit and committed-byte preservation.
Reversing the patch reproduces SIGSEGV on live data with the same test.
The focused WoW64 suite, including audio, passes. The two existing Wine-cache
dependent resolver/CREATESTRUCT tests are skipped in this environment.

The production Darwin recipe rebuilt only `virtual.o`. All 34 other archive
members remained byte-identical. The final native archive SHA256 is
`d977b7a974b23cf40ec1728eab25592a4a0ca66f20e56f8051a2b2484db10cb8`.
Partial decommits now emit at most 24 `wow64-subpage-v1` records with the
guest range, host page size and operation status.

The new shell has one glass rail at the upper left, with a sliding selection
inside a shared capsule. Persistent roots replace TabView entirely, removing
the possible second system tab surface. Roots keep scroll/navigation state
while hiding inactive hit targets and focus preferences. Page changes fade
and move slightly; secondary navigation and settings controls animate their
insertion/removal, with shorter fades under Reduced Motion. Full-screen
ambient art continues under the header and footer, without opaque strips or
the footer separator. Controller hints appear only with a controller.
Home and Library use portrait game covers. Primary and secondary action
backgrounds follow text padding, and settings sidebar rows have separate
rounded backgrounds and 10-point gaps.

The supplied 221210 report identifies `i386-compat-v1`; the delivered
`7c2d9bd4` executable contains `i386-cpuid-v2` and the new cover homepage,
and contains neither the old diagnostic marker nor old hero heading. Thus
that report does not establish a run of that delivered binary. The reason
for this mismatch is unknown. r3 adds its public revision at process start,
in About, and in `build-info.txt` in every report, plus the bundled native
archive record. Reports identify `i386-subpage-v3` and retain the two FEX
module fingerprints. None of this exports game contents or credentials.

Final unsigned r3 IPA SHA256:
`769b48d9de1cb18577c58e7646930daedcda3e7ad0c013cbc6f4f2e081ec92f0`.
All 87 IPA verifier checks and all 23 AppRoutes/LaunchDiagnostics tests pass.
An additional binary audit confirms the r3 revision, single-rail marker,
v3 diagnostics and native subpage log string are in the actual packaged
executable; the packaged manifest names the rebuilt native and FEX hashes.

No successful iOS first frame or current UI/animation verification is claimed.
At the owner's request, USB observation/control stopped; the owner will
test the new IPA and return its report. Source checks are evidence of the
repair's scope, not proof of game compatibility.

The broader `pp test --quick` is not green. A Linux-filesystem replay runs
538 tools tests with 6 failures, 7 errors and 6 skips. These include a Unix
socket path-length limit, historical checkpoint guards rejecting later
native deltas, class-atom patch extraction, rebase fixtures, and a WoW64
build-verifier fixture. The Windows-mounted replay additionally cannot
create FIFOs or use the notices publication primitive. The Linux replay
passes the host log, title path, self-check, session, ticket, URL and WoW64
C checks. No full-suite pass is claimed; these broader tooling failures
remain unresolved and do not substitute for the owner's next game run.
