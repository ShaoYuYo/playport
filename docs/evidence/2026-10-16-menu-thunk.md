# Senren Banka reaches menu creation, then an unaudited thunk

The owner-supplied 181333 report identifies r4 and the exact rebuilt native
archive. The fresh run after the r4 marker reserves and publishes a 1 GiB
host arena, initializes FEX and starts the i386 game. It successfully
decommits guest `1001f000` through `10022000` with neighbouring data retained.
The earlier fault at `1000f9d4` does not recur. Multiple game archives and
audio plug-ins load, followed by menu creation.

The process then terminates at win32u syscall `15d0`, which the actual
generated syscall table names `NtUserThunkedMenuItemInfo`. The unaudited
thunk gate deliberately ends the process with `STATUS_NOT_SUPPORTED`
(`c00000bb`). No first frame is recorded. The run selected 1,024 MiB RAM
headroom; there are no memory admission denials in this run. Earlier
Unicode and session-root failures in the accumulated report are separate
launches and are not its terminal cause.

## Audited conversion

Wine PE patch 0034 translates the menu item's nested `dwTypeData` string
buffer into the owned guest window on insert/set and A/W query, and
translates returned string pointers back to guest addresses. Legacy bitmap
results remain bitmap handles. Item data remains an opaque scalar, submenu
and checkmark fields retain handle semantics, and `HBMMENU_CALLBACK` keeps
its signed `-1` representation. The optional UNICODE_STRING uses the
existing window-aware helper. The ordinary/native no-window path retains
its identity behavior.

The adjacent `NtUserThunkedMenuInfo` setter already widens its structure,
handles and opaque data correctly, and `NtUserGetMenuBarInfo` already
widens its structure and copies the returned rectangle, handles and flags
back correctly. Their complete thunks were reviewed and tested alongside
the item thunk. Only these three named calls are added to the audited
list. The general unaudited-call termination gate remains active.

At most 16 menu-operation records report method, mask, position and result.
Reports now identify `i386-menu-v5` and include the actual wow64win module
fingerprint. The public build marker also records the module's artifact
hash, alongside the unchanged native VM archive identity.

## Verification

`build/test-menu-thunk.py` compiles the complete production thunks and
actual window/Unicode helpers, with a mock native menu backend, under
UndefinedBehaviorSanitizer. It covers the recorded insert-call shape,
set, A/W query and output text, legacy bitmaps, callback sentinel, opaque
item data, radio/default scalar methods, null optional parameters, native
no-window scalar behavior, menu-info fields, menu-bar result layout and
invalid sizes. Replacing the item thunk with its original implementation
reproduces the nested-string-pointer assertion. The new implementation
passes. Only structure definitions and the native backend are modeled;
this is not an end-to-end iOS menu or rendering test.

The pinned production Wine PE recipe rebuilt the real aarch64 wow64win
module. The checkpoint migration replaces only that DLL and its records;
all other checked artifact paths retain their bytes. DLL SHA256:
`0ecdfe9e2adcee454b2cd75e2b94ee340648129002c522d7669bf6605da00e5d`.
No pins changed. The existing memory setting is retained.

The final unsigned release IPA passes all 87 verifier checks. SHA256:
`63eecd43aac225f67d8b0af74f459f54b33c0a330861e0dc30a91067975dc68d`. The packaged DLL hash and log marker
were checked directly, and the executable contains the r5/v5 identity
and bridge fingerprint path. All 25 selected Swift route, diagnostic
and memory-policy tests pass. Previously recorded broad tooling failures
remain unresolved; no full-suite pass is claimed. First frame
and on-device behavior of this candidate remain unverified. The owner
continues side-loading; no phone connection or control was used.
