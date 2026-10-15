# Windows compatibility and Liquid Glass audit — 2026-10-14

## Baseline and device evidence

The ordinary-chat handoff is source `62f9877af5225d7e11d0c6a48edfc26c0f8e37d2`
on `fix/senren-japanese-wine-locale-20261014`. It retains the ten follow-up
commits after main `59922e4`: Japanese startup locale, per-game ASCII display
persona, actual patched-Wine MessageBox parsing, required-file probes and tests.
Private workflow `52e1e3e4f6fcf287eaf02b1a213cd1c1565d2c3b`, run
[38574001127](https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38574001127),
succeeded. **That does not demonstrate a successful game launch.**

The owner supplied `Playport-report-app-1144400-20261014-222857.zip`.
The 22:28 launch exits with code zero after approximately one second and
`first_frame=0`. The Japanese Windows dialog says that a string cannot be
converted to Unicode because it contains characters that cannot be interpreted.
The dialog itself returns -1. The C++ exception is handled; this is an early
game termination, not proof that the app or a successful game crashed.
Raw logs, account identifiers, tickets and container paths remain uncommitted.

## Comparison with Windows

| Area | Actual evidence / difference | Action and remaining limit |
| --- | --- | --- |
| CPU / PE architecture | Genuine game is i386 (COFF 014c); iPhone host is arm64. Windows ordinarily executes x86 directly or via Microsoft WoW64. PlayPort uses Wine WoW64 and FEX. | Preserve both translation layers. Previous arena reservation / FEX handoff passes on this phone; this launch is no longer an allocation-exhaustion failure. |
| ACP and string encoding | Japanese locale is requested before Wine; codepage 932 loads in both root and child. Steam persona is ASCII for this title. The reference engine also contains its own Shift-JIS converter. | Preserve these corrections. Do not claim that locale alone fixes all game strings or that the public reference exactly equals the commercial engine revision. |
| Codepage availability | Several accesses to `C:\\windows\\system32\\c_10000.nls` fail with STATUS_OBJECT_NAME_NOT_FOUND. The bundle did not contain that table. | Add exact Wine 11.19 Mac Roman table; positively verify packaging and link bundled NLS to system32/syswow64/sysarm64. Missing table is a confirmed defect, but causation of the final engine exception still needs an updated phone run. |
| USER32 class atoms | The generic patched `unicode_str_32to64` added the FEX window base to every Buffer. Windows permits zero-length class-name strings with a 16-bit integer atom. `get_int_atom_value` tests the integer range before dereferencing. | PE patch 0032 preserves NULL and zero-length integer atoms; actual helper tests cover boundaries and real pointers. Phone logs have repeated create-window error 6. This is a confirmed conversion bug, not proof of every observed window failure. |
| Game data | Direct stat finds SenrenBanka.exe (4,412,928), data.xp3 (1,007,286,279), patch.xp3 (291,227,767), scn.xp3 (149,277,264) and plugin directory. URL metadata enumeration produced an empty inventory. | Use bounded path enumeration with direct metadata, retaining title-specific fallback probes. Presence and size do not prove every depot chunk / plugin / script is correct. No game content or saves are exported. |
| Windows loader and DLL search | A missing DLL in the game directory followed by a successful system-directory search is normal. Native iOS frameworks replace host services; a complete Windows service environment is not present. | Retain existing PE sets and native bridge libraries. Do not misdiagnose ordinary search misses or unsupported optional calls as the fatal cause. |
| Graphics and windows | iPhone uses the existing Metal/DXMT/Vulkan/WinIOS bridge instead of Windows desktop display drivers. No first drawable is observed in this launch. | Keep the graphics path. A build/self-check or a process exit cannot substitute for a rendered first frame and continued play. |
| Steam client / game API | See below: account/service operations work, but the game uses the existing emulated Steam API bridge rather than a Windows Steam desktop process. | Preserve real ownership and ticket services; do not claim full Steamworks equivalence or replace failures with fabricated tickets. |

The supplemental `c_10000.nls` is copied unchanged from pinned
[Wine 11.19](https://github.com/wine-mirror/wine/blob/455e3509b98a6919fd4ad1def4803e08c41c03b2/nls/c_10000.nls):
66,082 bytes; SHA256 `20128ffdabfca32cc5a5a06d101a1b3316764ee282cc1193bf0e0cc2828931b2`.
Its header identifies codepage 10000; actual table checks include ASCII A and
Mac Roman byte 80 -> U+00C4. Existing Wine licensing notices remain included.

## Steam audit

This report demonstrates CM session restoration/login, owned license/library
listing, Steam Cloud enumeration/synchronization, stats/achievement retrieval,
a 178-byte ownership ticket and ten game-connect tokens being armed. The
installed assets and previous installer tests support download operation.
The encrypted-app-ticket request returns EResultFail. That is recorded as an
unresolved service/API capability, not silently converted to a success.
The log does **not** demonstrate this game calling or completing SteamAPI_Init.

Valve's [initialization guidance](https://partner.steamgames.com/doc/sdk/api)
requires the app identity, an appropriate Steam client environment and ownership;
`steam_appid.txt` by itself does not provide the Steamworks interfaces.
[RestartAppIfNecessary](https://partner.steamgames.com/doc/api/steam_api#SteamAPI_RestartAppIfNecessary)
can legitimately terminate a process. An emulated replacement is an explicit
compatibility difference, not a complete Windows Steam installation.
PlayPort already prepares launch data with a throwing/fail-closed path; a
rejected preparation must reach the player-visible failure panel.
New report metadata lists steam_api.dll / steam_api64.dll and original backups,
their byte counts and actual PE architecture without reading secrets. This
helps distinguish a wrong DLL architecture from an unobserved API call.

## Checkpoint-safe build

The complete, checksum-verified parent native cache is
`playport-native-ios26.5-swift64-clang22-mingw20260922-v1-ea40aa39a41a054f38899634b21b9ba6432a1059881cdb6a508c70b88a353f9f`.
The older 5bcd cache predates the verified arena ABI and is **not** a valid
migration parent for this change.

`build/rebuild-win32-compat-checkpoint.py` validates the exact native-source
delta, Wine pin, PE recipe and resource/verifier delta. It invokes the real
Wine recipe to compile only aarch64 wow64.dll and wow64win.dll, strips debug
information and checks actual PE headers. Only these two bridge resources,
their generated records, the new NLS table and artifact manifests may change.
All checked native Wine/FEX archives, renderers, i386 DLLs and Steam binaries
must retain their old SHA256. The old immutable cache is never overwritten.
All IPA checks remain enabled; an additional positive NLS gate is added.

## Liquid Glass and motion

The owner also requested Apple's design style, rules and animations. The review
uses Apple's [Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials),
[Motion HIG](https://developer.apple.com/design/human-interface-guidelines/motion)
and [custom Liquid Glass guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).
Artwork/content stays in the content layer; navigation and action controls use
native regular Liquid Glass. Top navigation, Settings and footer actions adopt
native glass/glassProminent button styles and system pressed feedback.
Related footer controls retain stable glass identities inside their existing
GlassEffectContainer, with a short smooth transition. Hit areas are at least
44 points. The keyboard uses a fade rather than a slide with Reduce Motion;
switch indicators use native Toggle styling (the controller-focusable row still
handles activation), and existing launch zoom/blur respects that setting.
Reduce Transparency uses an opaque surface/bordered controls, including the
previously translucent-tint fallback. No custom imitation shader is introduced.

This audit and compile checks do not certify actual iPhone layout, VoiceOver,
contrast, frame pacing or animation appearance. Those require a device run.

## Validation and next observation

The complete Wine port/Valve/PE patch series applies to the exact pinned tree.
Host C tests exercise the production NLS link helpers and the actual patched
Unicode-string helper; new migration tests validate resource-record updates and
reject unrelated native input changes. Swift diagnostic tests inspect actual
synthetic PE/header bytes and exclude private config from report metadata.
Local shell syntax / Python / resource checks precede CI. CI must compile real
SwiftUI and both bridge DLLs, verify the full checkpoint and unsigned IPA, and
produce a nonempty downloadable IPA. Build facts will be appended after that run.

The owner must upgrade in place to retain the app container, then play the same
title. The useful next observation is first_frame=1 with continued play, or a
new bounded report containing Windows dialog, NLS probes and Steam DLL metadata.
Until then, title 1144400 remains **Broken on the last observed phone build**.
Do not disable the hourly repair watch merely because IPA compilation succeeds.

## Cloud attempt and local check limits (23:23 Taipei)

Source `f7168612b50b249c83643c3a14f58703ebce2948`, private workflow
`9ec597c23b1025e94ee54908c0246907bc2da46d`,
[run 31 / 38588812883](https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38588812883)
was created at 15:23:00 UTC and ended at 15:23:04 UTC. Both Ubuntu preflight jobs
failed before any steps were recorded; build-ipa was skipped. The job log fetch
returns BlobNotFound. Check metadata reports one annotation for each failed
preflight, but the available connector rejects the annotations endpoint.
**The exact runner-side explanation is not yet readable; do not infer a billing
failure or a compiler error from this alone.** No new IPA exists for this source.

22 focused production-C/Python tests pass. A broader local `pp test --quick`
ran 538 tool tests but did not fully pass: three sanitizer probes fail because
this executor cannot read process task metadata, four phone-mux socket tests
cannot create AF_UNIX sockets, and the WoW64 build gate / host C commands need
clang, which is not installed in this pruned workspace. Three tests were skipped
by their existing prerequisites. Do not mark the full suite as green.
The new patch's Class label was corrected to the permitted `ios-port` value;
the patch body and tested conversion are unchanged. Public source-only CI and
real Apple/PE compilation remain separate required observations.
The failed jobs' raw API data confirms runner_id=0, empty runner_name and zero
steps. GitHub's public status at 23:35 Taipei reports all systems operational;
this does not identify the account/repository-specific pre-run error. This
public repository is a fork and has no recorded Actions runs, including after
the follow-up source push; no public CI result can be claimed either. Enabling
fork Actions or changing account billing requires administrative access that
the connected tools do not expose; neither setting was changed.


## Latest source confirmation — run 32 (23:56 Taipei)

After the owner's request to continue, the workflow was pinned once to
`3981c2e3c10b94cb171d5c746f17816ded2b6df6`, which includes the corrected patch
classification, native Toggle indicators, localized accessible control state and
latest Liquid Glass changes. Workflow commit
`7d29e5e9452f881482ba0454d925b3b111db1cfd` changes only
`.github/workflows/build-playport.yml` (the source pin); no StikDebug app file
or upstream repository changed.

[Run 32 / 38593715876](https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38593715876)
was created at 15:56:14 UTC. Both preflight jobs ended at 15:56:17 UTC with
runner_id=0 and steps=[]; build-ipa was skipped. No artifact exists.
The failed check outputs have no summary/text and one annotation each. The
connector still does not expose the annotation text, so the exact refusal
cannot be attributed to a billing issue, SDK, compiler or source code.
The previous run and other jobs in this private repository show the same
absence of an allocated runner. No further unchanged attempt is justified
until new evidence or runner availability changes.

The repeated focused local resource/production helper checks passed (11 tests).
There is still no real SwiftUI/PE compilation for this source and no new phone
play result. Keep the complete parent checkpoint and all verification gates;
do not replace the requested game runtime with a reduced build to obtain a
nominal success. The owner's latest instruction forbids Apple-account login;
no further browser credential entry or new-account workaround is part of this
continuation.

## Automatic Action retry requested — 2026-10-15

The owner explicitly requested that Actions run automatically. Private workflow
commit `e703112812de5765276e9ed8f466d2ab8259d492` adds an hourly
`17 * * * *` schedule on the default branch and an `auto-build` decision job.
The source pin remains `3981c2e3c10b94cb171d5c746f17816ded2b6df6`.
Push/manual requests build immediately; scheduled requests inspect prior runs
for the same workflow HEAD. They retain active builds, avoid rebuilding when a
nonempty, unexpired PlayPort-unsigned-IPA exists on a successful run, and stop
automatic compilation when a build job actually executed and failed. Pre-run
allocation failures may be retried on the hourly schedule. This supersedes the
earlier instruction against unchanged allocation retries for this explicit request.

The decision script passed nine executed mock-API scenarios, including skipped
guard-only runs, expired artifacts, current versus old revisions, an active
build, allocation refusal, and an executed compilation failure. YAML dependency
checks passed. An exact reconstruction check confirmed that every existing
compile/cache/verification/upload step is unchanged. The private compare shows
only 83 added lines in `.github/workflows/build-playport.yml`; the original
StikDebug app remains unchanged. Read-only checks permission supports retrieving
the previous failed check's annotation once a runner executes the decision job.

The push actually triggered [run 33 / 38652811870](https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38652811870).
Its auto-build job 116155425762 again failed with runner_id=0, empty runner_name,
and steps=[]; both preflight jobs and the IPA job were skipped. This is evidence
that the trigger works, while runner execution is still unavailable. It does not
demonstrate that the decision script executed in GitHub, that the first scheduled
event occurred, or that an updated IPA exists. GitHub schedules may be delayed.
Do not count a later guard-only success as an IPA build success: require the
actual build-ipa job and all verification/upload evidence.

Windows runtime, checkpoint hashes, Steam, game data and saves are unchanged.
Actual iPhone first frame, SteamAPI initialization, and Liquid Glass appearance
remain unverified for the new source.

## Owner clarification: agent checks, no workflow cron — 2026-10-15

The owner clarified that the assistant should inspect results each hour and
follow the previously successful method. Commit
`9009c5e188df9684a3f6ef459d814fa5b29160b9` removes the scheduled retries and
auto-build decision job. The workflow file is byte-for-byte restored to
`7d29e5e9452f881482ba0454d925b3b111db1cfd` (blob
`f2d2e638ea9708216b9e9847e1841987a45e10d8`), with source3981 and its required
checkpoint migration retained. The preceding automatic-Action policy is
superseded: the assistant's existing hourly watch reads actual results and
fixes evidenced failures; GitHub itself no longer has an hourly cron.

The last successful build was checked again: run38574001127 has successful
Mesa, Swift and IPA jobs, nonempty unexpired IPA artifact11900547076
(673,566,091 archive bytes) and build-evidence artifact11900467368.
The successful job log confirms the same actual SDK/XDG configuration and
successful artifact uploads. The old source62f IPA does not fix the phone game;
retain the current Windows compatibility corrections instead of rolling back
the game code to that older build.

The restoration push triggered
[run34 / 38653459914](https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38653459914).
Its Mesa/Swift preflights again failed with runner_id=0 and steps=[]; build-ipa
was skipped. Returning to the original direct job topology therefore did not
resolve the pre-run allocation failure. No new compilation or IPA is claimed,
and the exact platform refusal annotation is still needed to identify the cause.

## Explicit recovery retry — 2026-10-15 16:12 Taipei

After the owner's renewed request to continue with the previously successful
method, the GitHub rerun-failed-jobs operation was called for run38653459914.
The connector returned success=true; the run actually advanced to attempt2,
rather than only rereading attempt1. No workflow or game source changed.

Attempt2 completed at 08:12:15 UTC. Swift job116318712129 and Mesa
job116318712332 failed with runner_id=0 and steps=[]; IPA job116318736902
was skipped. Swift job-log retrieval returns404 BlobNotFound. This new retry
therefore still did not reach checkout, tests, SDK preflight or compilation.
The failed check metadata has an annotation, but the connector continues to
reject annotation GET endpoints. The specific platform refusal remains unknown;
do not attribute it to billing, SDK or game code.

This was an explicitly requested recovery attempt, not a new hourly GitHub retry
policy. Keep the agent's hourly inspection and restored workflow, and preserve
all current source fixes, native checkpoints and verification gates.

## Exact successful-revision control — 2026-10-15 16:19 Taipei

The owner's request to inspect the earlier successful method was checked against
the prior conversation and the actual run, not just the latest failing snapshot.
Run38574001127 attempt1 still reports success at workflow commit
52e1e3e4f6fcf287eaf02b1a213cd1c1565d2c3b and source62f9877. Its Swift test job
115886213048 had runner1000000149 and five steps; the IPA job had42 steps.

A single-job rerun of that exact Swift job was requested as a control. GitHub
accepted it (success=true), creating attempt2 of the same run and same workflow
commit; no source or workflow was edited for this test. On 08:19:55 UTC,
Swift job116321719499 failed with runner_id=0 and steps=[]; the dependent IPA
was skipped. The retained Mesa result is copied from attempt1 (its timestamps
are Oct14), not a newly executed successful Mesa job. Swift log fetch returns
404 BlobNotFound.

Consequently, the new Windows/NLS/UI changes cannot explain this control's
pre-run refusal: even the exact previously successful revision now cannot start
a runner. This does not identify which account/repository/platform condition
changed, and no billing or administrative cause is established. Preserve the
historical success with the explicit attempt1 URL:
https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38574001127/attempts/1
The run's latest attempt now reports failure; do not erase or mislabel either
observation. No new IPA or new phone-play result exists.
