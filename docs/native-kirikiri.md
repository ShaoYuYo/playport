# Native KiriKiri2 launch path (Steam downloads without Wine)

Status: **prototype / not yet a playable engine** (2026-10-13).
Scope: iOS PlayPort; owned Steam games downloaded with the existing native Swift SteamClientKit.

## Goal

Keep the current Steam login (QR or credentials), ownership-aware library, CDN downloads,
download journals, game folder and receipts. When an installed game contains legitimate
KiriKiri2 / KiriKiriZ XP3 content, allow an opt-in **Native KRKR2** launch which never
runs the 32-bit Windows .exe, Wine, FEX or the SteamStub loader.

Senren＊Banka is App ID **1144400**, Steam depot **1144401**, approximately **7.54 GiB**
installed. Steam's depot is not split into 32-bit and 64-bit depots, so *do not* change
Steam download selection rules just for this game.

## Existing implementation

- Steam login/download: app/SteamClient and app/Sources/S1Probe/UI/SteamInstalls.swift.
- Game folder: PlayportPaths.games (InstallLayout.gamesRoot), receipts and TitleInstaller.
- Safe XP3 sniffing: app/PlayportKit/Sources/PlayportKit/KirikiriProbe.swift; no game
  archive is loaded in memory. It reads only the 11-byte magic header, prefers
  data.xp3 over other non-patch archives, rejects links, and does not claim
  commercial-game compatibility.
- InstalledTitle.kirikiriData(in:) finds a candidate beneath the existing game root.
  It does *not* mark the title Ready or replace the existing Wine launch.

## Native engine selection

1. **Kirikiroid2** (zeas2/Kirikiroid2): a more suitable compatibility starting point
   for legacy commercial KRKR2/XP3 data. The historical iOS port is no longer
   demonstrably compatible with iOS 27.2; port and test the actual C++ sources,
   dependencies, rendering, audio, font, input, video and save paths.
2. **Kirikiri SDL2** (krkrsdl2/krkrsdl2): supported iOS build path and permissive
   core license, but upstream explicitly does *not* support unmodified commercial
   games. It is a useful renderer reference, not a claim that Senren＊Banka boots.
3. The WebAssembly/browser version is **not** the primary iOS solution: WebKit's
   missing JSPI on iOS is a documented blocker, and multi-gigabyte games should
   not be duplicated in browser linear memory.

Before vendoring or statically linking either engine, audit all third-party source
licenses and ship required notices. Only use code and game assets whose distribution
or use is authorized; never ship Steam user credentials or game content inside an IPA.

## Required implementation before enabling Native KRKR2 Play

- A dedicated, *separate* native-only iOS target and build workflow: build an
  arm64 engine linked with a minimal SwiftUI launcher, SteamClientKit, ContentKit,
  and PlayportKit. Do not depend on Wine, FEX, DXMT, llvm-mingw or JIT. Keep the
  current Wine IPA pipeline intact until native has passed a phone smoke test.
- A typed engine launch API passing the **directory containing all game data**
  and a verified XP3 entrypoint; do not attempt to run data.xp3 as a Unix
  executable and do not copy 7.54 GiB of assets into an app resource bundle.
- On-device games and save data must remain in the app's persistent writable
  container, survive SideStore resigning, and use sandbox-safe paths.
- Detect runtime requirements beyond XP3: TJS startup scripts, Windows DLL
  extensions, proprietary archive filters and video decoders. Display
  unsupported details instead of claiming success. A valid XP3 magic does *not*
  prove that encrypted resources or custom plug-ins are compatible.
- Respect Steam-owned base-game and DLC licenses. The downloader keeps DLC
  ownership checks; native execution must not pretend the user owns unlicensed
  content or silently modify DRM-protected executables.
- Boot and test on **iOS 27.2** with actual game files and user consent.
  Acceptance: account login, correct title/depot, completed 7.54 GiB install,
  KRKR2 native boot, title/first scene, sound/video, save/reload, language and
  any *owned* DLC. This acceptance test has **not** been passed.

## Build-time objective

A native-only IPA should avoid the current 3+ hour Wine/FEX/DXMT compilation
pipeline. Building the ported KRKR engine is still a substantial task, but it
should have its own isolated CMake/Swift cache and produce a separate unsigned
IPA test artifact. Do **not** replace or cancel an in-progress Wine build just
to run a native prototype.

Upstream references:
- https://github.com/zeas2/Kirikiroid2
- https://github.com/krkrsdl2/krkrsdl2
- https://steamdb.info/app/1144400/depots/
