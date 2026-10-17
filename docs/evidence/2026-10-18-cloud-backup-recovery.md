# Cloud backup recovery and visible slot inventory

The owner report's manual slots share the filename group 0010 and its quick
slots remain intact. The launcher now shows manual and quick counts after
synchronization. This is filename inventory, not proof of semantic game loading. The UI consolidates sync, full Steam restore
and backup recovery into one management entry.

A full Steam download cannot restore history that is already overwritten on
Steam. Existing sync backups now have a UI recovery picker with time, source,
file count and a filename preview. These are partial replacement
backups, explicitly described as such. Only the verified title's fixed save
names qualify. Symlinks, other titles, unknown filenames, traversal IDs,
files over 2 MiB and sets over 32 MiB are rejected or omitted.

Recovery keeps both current local copies before replacing either. It writes
and persists unresolved conflicts before any save replacement; a kill during
replacement therefore cannot make the next sync silently upload a recovered
version. The player explicitly chooses the phone's recovered contents before
uploading them. Failed state persistence prevents all replacements. Readback
must match the selected bytes. Steam is never changed by recovery itself.
A per-title actor gate prevents sync and recovery from overlapping.

Each backup operation now uses a unique snapshot directory, so retries in the
same second cannot replace a prior backup with the same filename. Existing
second-resolution folder names remain readable; retention parses both forms.

All 29 Cloud tests pass, including restore/no-upload/conflict persistence,
retaining current copies, same-second uniqueness, size/path/link rejection
and raw filename grouping (not an assumed in-game page mapping). The release app compiles and passes 87 IPA checks using
the unchanged 1615-file native checkpoint. No phone was controlled. Actual
old progress availability depends on which prior versions were preserved.
