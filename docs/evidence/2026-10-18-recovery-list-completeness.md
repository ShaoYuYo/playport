# Show every retained recovery point

IPA SHA256: `efa15be97b42c38ccc1ba4d795e344f804875c3b0533aa5604825dfad838b129`

The owner supplied the retained cloud-backup archive for data recovery. Its
50 recognized recovery points included a single original system-progress copy
at position 50. `Cloud.Backups.recoveryPoints` already returns up to 128 bounded
points, but the UI truncated that result to 40. Remove the extra UI truncation
so the oldest valid backup can be selected without re-importing it or renaming
its original timestamp. Existing source labels, file limits, backup-before-write
and explicit recovered-version conflict choices remain in place.

The recovery investigation strictly parsed 42 distinct system-file versions as
bounded literals without evaluating code. In an isolated private-desktop run,
the actual Windows game's full bootstrap loaded the original system pair via
its Steam storage plugin. It retained 2,441 global fields and 611 read-scene
entries, with all 21 manual/quick bookmarks valid and game IDs matching. The
test exited before rendering. Those counts establish a usable recovery
candidate; they do not recover a missing historical Continue file or establish
that the phone or live cloud was restored. Private save bytes, logs, paths and
the supplied archive remain outside version control and are never published.

The r22 app build validates the list change and retains the previously tested
save-restoration implementation. This UI-only change does not alter native
runtime/audio outputs. The existing 121 host regression results still apply to
the unchanged core; they were not rerun as new phone evidence. Release
compilation and 88 IPA checks pass, with the unchanged 1615-file native
checkpoint and packaged file/hash checks recorded in the local delivery receipt.
No phone connection or remote Steam write is made. The owner performs the
explicit backup selection and chooses the recovered phone version for upload.
