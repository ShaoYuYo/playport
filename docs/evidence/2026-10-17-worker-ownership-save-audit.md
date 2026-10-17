# Native audio worker ownership, save evidence and presentation cadence

The supplied r16 report contains one early no-memory exit and a later play
with real presented frames at native resolution. The owner reports audio
breakup, slow game transitions and fresh progress after choosing Steam saves.
No phone was connected or controlled for this change. The owner installs the
candidate and validates gameplay; host results below are narrower evidence.

## Audio defect established by the report

The game creates a 48 kHz stereo float stream and starts RemoteIO. Its native
`audio_client_timer` is registered in the game's pseudo-process, but its pipe
handoff resolves a NULL PEB and the session's master socket. The server rejects
the descriptors as WRONG-PROCESS and kills that worker before `timer_loop`.
The report then repeatedly records DirectSound mix wait timeouts and underruns.
There is no audio-health timer output. Fractional resampling is not the primary
issue for this equal-rate stream.

Patch 0108 captures creator PEB/PID before pthread creation, publishes them in
native-only TLS before server initialization, and uses them only when a real
TEB cannot supply identity. Native workers still have no fake TEB; server
ownership checks remain intact. Nested native workers inherit the same owner.
The system-thread creator snapshots tid before a worker can exit, and closes
the request descriptor if spawning fails. This fixes an evidenced bootstrap
defect, not every possible cause of audio starvation. PCM precision, source
rates and the prior mixer/ring behavior are unchanged.

The actual bootstrap and identity functions pass ASan/UBSan tests with 128
child/nested workers: identity before IPC, sibling isolation, real-TEB
precedence, creator isolation and pthread-create failure cleanup.

## Steam saves

The retained logs show 25 cloud and local files, two uploads and two local
placements. The owner's earlier Steam conflict choice predates this log's
retained interval. Transfer counts do not establish what the game opened.
The patch does not invent a different save path or an unproven interface fix.

The exact bundled i386 Steam API DLL was exercised in a hidden Windows console
process with a synthetic save and an isolated save root. Both its modern flat
API and the game's observed Client017/RemoteStorage013 virtual interface
returned the same count and exact synthetic bytes. The installed plugin's
version strings and imports were inspected read-only; no game was launched.
This rules out a simple path/legacy-interface failure on native Windows; it
does not validate that ABI under the phone's translator or the real save set.
The pinned emulator's [path parser](https://raw.githubusercontent.com/Detanup01/gbe_fork/7103add7ca6ef3ef8353279219880068f2494fc8/dll/settings_parser.cpp)
and [interface dispatch](https://raw.githubusercontent.com/Detanup01/gbe_fork/7103add7ca6ef3ef8353279219880068f2494fc8/dll/dll.cpp)
were checked against this probe.

The game options now expose explicit Steam restoration. It re-downloads all
files currently on Steam even if the old baseline claims agreement, performs
no uploads, and backs up replaced local backend versions. Downloads and the
previous cloud version fetched before upload must match the changelist SHA1.
Ordinary uploads also preserve the prior cloud version, not just explicit
conflict choices. Restoration cannot recover a version Steam no longer has.
Preparation suppresses redundant background cloud work before session teardown.

Patch 0109 records at most 64 open results for four fixed save filenames,
classifying Steam/native/other without printing paths, handles or contents.
This proves an open result, not a completed semantic load of the save. The
report gains `save-backends.txt`: bounded sizes/hashes for the two directories,
anchor/config metadata and whether the emulator save root matches the expected
path. It excludes account INIs and save contents. The classifier's exact-name,
case, non-NUL slice, bounds and privacy cases pass ASan/UBSan.

## Presentation, warmup and UI

The report contains native 2532 by 1170 presentation, sustained samples around
40--41 FPS and gaps exceeding half a second before menu interaction. Drawable
acquisition is usually only a few milliseconds. Later low-FPS samples follow
menu activity and cannot by themselves attribute all delays to rendering.
Memory pressure includes substantial compression; unused nominal RAM is not
proof that translated game work fits a display refresh budget.

Small limiter overruns now retain the fixed cadence instead of moving the next
deadline on every late arrival. A full missed interval still resyncs without
catch-up bursts. New health fields separately measure actual limiter sleep and
drawable wait. This is a timing correction, not a measured FPS improvement.

Before this title starts, a bounded warmup reads DLL/executable prefixes and
XP3 headers/index prefixes into the OS cache. It does not decode protected
indexes, precompute animations, compile arbitrary game code or retain assets.
Limits are 64 candidates, 8 MiB total, 512 KiB per binary and 128 KiB per index,
with a 250 ms monotonic time budget checked between operations. One filesystem
operation can exceed the remaining time. It skips links and unrelated files,
and is skipped when the reported app budget has less than 128 MiB remaining.
A read-only probe against the installed desktop game warmed 512 KiB and stopped
after about 266 ms; that host/filesystem result does not predict phone speed.
The existing normal engine caches and 64 MiB graphics cache remain. Persistent
FEX cache is still disabled because its prior correctness issue is unresolved.

The game sidebar keeps a stable overlay host so removal can animate. The scrim
fades, the rounded glass panel slides from the left, and Reduce Motion uses a
short fade. Row gaps separate controls. Closed/editing overlays do not capture
game input. UI compilation passes; appearance and touch behavior await the owner.

## Candidate and checks

- 49 HostIOKit tests passed, including cadence under 120 small overruns.
- 21 cloud tests and 13 Steam API swap tests passed, including forced repair,
  divergent local copies, changed-download refusal and prior-version backups.
- 14 selected PlayportKit tests passed; warmup cases were rerun after making
  metadata checks lazy. They cover byte/time limits, links, malformed index
  offsets, and metadata reports without contents or credentials.
- Native migration compiled the actual iOS objects and verified the checkpoint
  of 1615 files. Four archive members change: thread, env, virtual and server;
  the other 31 members and the stable launch DLLs remain byte-identical.
- Release IPA validation: 87 checks passed.

`libntdll_unix.a` SHA256:
`c32057edf9035f00fd9a54cfbd40ee0896efb6d661ec9577e8e92f3741d6991f`.
The single migration helper describes both reviewed patches against the r16
archive. The runtime was migrated in two verified steps during development;
archive recomposition verifies the same final four-member result.

IPA SHA256: `59d1a308cbde8c292f6a390631cea077e96bc20f6798912964e3f3059d70dbba`

Pending owner validation: sidebar animation, actual save slots, audible output,
transition latency and sustained FPS/thermals. This record makes no claim of a
successful live-account round trip or sustained native-refresh gameplay.
