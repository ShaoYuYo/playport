# PlayPort IPA repair, Chinese support and Liquid Glass

## User outcome and scope

Produce a verified unsigned release IPA for iPhone sideloading, keeping the
Windows/Wine/FEX/ARM64EC/WoW64 runtime and Steam sign-in/downloads. The user
cancelled the native KiriKiri2 direction: its recently added probe and design
have been removed without rewriting history. Only the user's PlayPort source
and the PlayPort workflow in StikDebug-Modified are in scope; do not change
StikDebug's application or other projects. This scope excludes upstream issue
or Linear writes. The user is away and has authorized ordinary fixes, commits,
pushes and builds without additional confirmations.

Target: **2026-10-14 17:00 Asia/Taipei**, not a license to waive checks.

## Observed failure

The failing workflow was run `38381528717`, job `115247622482`, on StikDebug
commit `42f3bdae3c668f587f38a15f40d4c09932645b74`.

- Wine, FEX, DXMT, Vulkan, Steam API, idevice, staging and notices completed.
- `swift sdk list` had already printed **No Swift SDKs are currently installed**.
- The final app stage failed immediately with **Error: Operation unsupported**
  and **Now generating the Darwin SDK**. No final IPA was produced.
- This points to SDK discovery/setup before compilation, not a runtime compiler
  error. The previous workflow moved a prebuilt SDK to a guessed home directory
  but never checked that xtool could discover it.

## Implemented changes and follow-up verification

- Set a repository-local `XDG_CONFIG_HOME` explicitly and use the actual pinned
  xtool SDK installer. Assert metadata, `xtool sdk status` and SwiftPM discovery.
- Before expensive CRT/Wine work, compile and link a real small iOS SwiftUI IPA.
  The probe compiles the production Liquid Glass modifier and game-language
  mapping. **Its cloud result still needs to be checked.**
- Pin all workflow jobs to a single PlayPort source SHA.
- Save all completed staged native resources/libraries/frameworks/notices and
  the DXMT PE verification inputs **before** app compilation. A frozen source
  cache key excludes generated records/bytecode; every restored file's SHA-256
  and size must match `build/runtime-checkpoint.py` before resuming at `app`.
- Emit progress heartbeats during long pipeline stages. Keep successful LLVM
  static-library caches and remove disposable native intermediates only after
  the completed snapshot is saved and re-verified.
- Add English, Traditional Chinese and Simplified Chinese UI/permission
  resources (206 UI keys per language), including dynamic control labels.
- Add a Steam game-language choice, defaulted from iPhone language; respect
  owned depots, use an available English fallback, and retain the actual
  selected language in the install receipt for Steam API settings. Older
  receipts remain readable.
- Stage GBK, Big5, Japanese and Korean codepage tables. Link the iPhone's own
  PingFang font through CoreText's reported URL before GDI starts, without
  redistributing Apple font data or replacing user font files/registry values.
- Use native Liquid Glass for navigation and primary controls; retain flat
  game/content surfaces, controller focus/navigation, and accessibility
  adaptations for reduced transparency and motion.
- Extend IPA verification to require packaged Chinese and English resources.

## Validation so far

- Eight focused Python tests passed: checkpoint tampering/missing/extra files,
  localization data/packaging, and font staging.
- 92 related release, UI, notices and source-payload tests passed (one skipped).
- `pp test --quick`: names, secrets and patch gates passed. Of 523 Python tests,
  seven hit this sandbox's unsupported Unix sockets / sanitizer-under-ptrace;
  host C tests were blocked by missing `clang`, and two pads tests by the
  uninitialized Madeira submodule. **Do not report the full suite as passed.**
- All workflow shell blocks and YAML were parsed; early SDK and checkpoint
  ordering were checked. Cloud Swift/depot/locale tests, real SDK probe, full
  app compilation and `verify-ipa` remain required.
- No phone is attached here. **Chinese game rendering, runtime compatibility,
  font-file accessibility and final Liquid Glass appearance are not yet tested
  on the user's iPhone.** Build success is not a claim that every Windows game
  works, nor that a game gains a translation it does not ship.

## Autonomous continuation

An enabled hourly task titled **完成 PlayPort 建置** continues this work. Do not
start a second writer on the same source. Read the current pinned source SHA,
latest matching workflow run and jobs first. If queued/in progress, preserve
that run; do not cancel or blindly restart a long build. If failed, fetch the
completed job log/diagnostic artifact, fix the actual cause, run relevant tests,
push the corrected source, update the workflow's pinned SHA and build again.
Reuse a verified native checkpoint whenever its input identity is unchanged.

Completion requires all requested changes present, the matching workflow
actually successful, `verify-ipa` passed and a nonempty downloadable
`PlayPort-unsigned-IPA` artifact. Then report the run/artifact and source SHA and
disable this hourly task. Do not turn a running job or SDK probe into a claim
of final success. Automated checks cannot be scheduled more than hourly here;
there is no separate ten-minute ordinary-Chat process.

## Run 20: SDK discovery passed; Swift builtin headers corrected

- Run [38419518137](https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38419518137)
  used source `5b590e68c4606ed1533e68291d91783ef6f5e93e` and workflow
  `4cca2a6506ddf8290e3011527cb2d0d72db47a9d`.
- Cloud Swift SteamStub/depot/GameLanguage tests and the eight Python tests
  passed. Mesa preflight passed. Both xtool SDK status and SwiftPM SDK discovery
  now passed under the same repository-local XDG configuration directory.
- At 2026-10-13 15:21 UTC, the real SwiftUI probe failed before native compilation:
  `_Builtin_intrinsics` / `arm_neon.h` emitted `__builtin_bit_cast` size errors.
  The importer referenced the SDK's `usr/lib/clang/21/include/module.modulemap`.
- This matches [xtool issue 273](https://github.com/xtool-org/xtool/issues/273):
  pinned xtool 1.20.1 installs PATH Clang 22 headers, while Swift 6.4 embeds
  Clang 21. [Upstream fix 274](https://github.com/xtool-org/xtool/pull/274) derives
  the builtin headers from `swiftc -print-target-info` instead.
- `build/toolchain/sdk-clang-headers.py` applies that header selection without
  changing the native LLVM 22 compiler. It replaces stale existing headers at
  both the Swift resource path and canonical versioned Clang module-map path.
  The SDK probe and normal pipeline use the same helper; the prior pipeline
  only copied versioned headers when missing, leaving stale existing files.
- Regression coverage exercises existing incompatible files, symlinked resource
  paths, obsolete-file removal, repeated setup and missing-header rejection.
  Cloud compilation is still required: local fixtures do not prove SwiftUI
  linking or final IPA success. Keep the hourly task enabled.
