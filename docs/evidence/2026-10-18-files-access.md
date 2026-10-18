# Files access to installed games

The owner reports that installed games cannot be browsed in Files. Both
`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` were absent
from the app plist. Enable both for the existing Documents tree; no game,
save or prefix migration is required. Games already live at
`Documents/prefix/drive_c/Games`, and sync backups at `Documents/Cloud Backups`.
The storage page now gives the navigation path.

Apple documents these declarations in
[file sharing](https://developer.apple.com/documentation/bundleresources/information-property-list/uifilesharingenabled)
and [opening in place](https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsopeningdocumentsinplace).
The package verifier now requires both booleans in the built app, so a
source-only change or stale packaging cannot silently omit Files access.
Host plist parsing and repository name, secret, patch and whitespace gates
are checked before commit. Device appearance remains untested at the
owner's request not to connect the phone; the final IPA check is recorded
with the candidate evidence.
