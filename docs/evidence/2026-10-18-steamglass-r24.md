# SteamGlass r24: Busy cloud reads and explicit phone-save offline launch

IPA SHA256: `c303c3e274039f67e6fd35b9ab458cde130c7249e914a3e9a7cbc27cd8585150`

The supplied screenshots show `Cloud.ClientFileDownload#1: EResult Busy` while
choosing a recovered phone backup, followed by the release build's generic
launch-preparation alert. This identifies a pre-launch cloud failure, not an
observed renderer/runtime crash. No new report or phone connection was used.

## Bounded read retry

Steam's [EResult documentation](https://partner.steamgames.com/doc/api/steam_api#EResult)
defines Busy (10) as a refused operation, with no action taken. One per-sync
retry actor now retries only Busy cloud reads: the file list, file downloads,
and the read that backs up the previous cloud file before uploading a phone
choice. Its three backoffs are 0.5, 1 and 2 seconds, shared across all files in
the sync. Cancellation stops backoff/request repetition. Permission, timeout,
integrity and duplicate-result errors are not replayed; no upload batch or
commit is automatically retried. Losing-version backup and SHA-1 verification
remain mandatory before any overwrite.

Previously, a failed explicit choice could change a planned conflict into an
upload, fail while reading the losing cloud version, then persist an empty
conflict list. Failed chosen transfers now retain their conflict and recovered
backup marker. An ordinary retry/restart asks for a choice rather than silently
uploading. The optional record version also prevents automatic Senren uploads
from older records which may already have lost that marker. Existing equal
files need no new choice; after a successful choice normal later-play syncing
continues. A missing old recovery marker is not reconstructed as evidence that
a particular historical backup was restored.

## Explicit offline launch

The Senren conflict screen and a cloud-specific launch-error alert offer
"使用手機存檔離線啟動". Only a player action takes this path. It skips the current
cloud gate, not setup/JIT or the normal game launch. It neither completes a sync
nor changes the stored cloud preference.

Before starting, the service checks the stored account, refuses an incomplete
Steam restore, enumerates the fixed recognised game save names, requires system
progress, and checks regular bounded files with equal bytes in the Steam-facing
and native game-facing folders. It then durably records unresolved choices for
these current phone files, preserving genuine recovery markers when present.
This also covers an older app which already dropped its marker, or has no saved
sync record. No remote call, cloud write, save-content replacement or agreement
baseline update occurs. Missing/divergent copies or failure to persist the
pending choices blocks launch. The next ordinary sync must still ask which
version to keep, protecting cloud progress from an automatic offline upload.

The release alert now displays the explicitly user-facing cloud explanation;
unrelated raw launch/path errors keep their previous generic presentation.
Cloud Busy errors retain their result name rather than becoming a download
message. The existing r23 display, RAM-banner and continuous-work fixes remain.

## Validation and limits

59 selected Cloud/Steam API host tests pass, including Busy
recovery in both directions, shared retry exhaustion, cancellation, preserving
the losing cloud version, retaining failed choices across a service restart,
legacy marker-loss migration, offline preparation without remote requests,
missing/divergent local copies, incomplete Steam restore, and durable-state
failure. The fixtures use synthetic bytes and a fake Steam backend; no live
Steam account or owner save is read or modified by the tests.

Release compilation and 88 IPA checks pass. The final package is
independently checked for the new revision/retry/offline/preference markers,
production-source copy equality, Files flags and unchanged native runtime/audio
hashes. The 1615-file native checkpoint remains unchanged. R23's 79 unrelated
host results are not counted as new r24 tests.

No phone connection, public IPA upload, usage reset, shutdown or remote save
mutation occurs. The new UI and an actual phone launch/cloud round trip remain
unverified until the owner's sideload test. Server availability is not controlled
by this change, and the offline action is not reported as cloud-sync success.
