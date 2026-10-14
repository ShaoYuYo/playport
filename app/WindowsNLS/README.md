# Supplemental Windows codepage data

`c_10000.nls` is copied byte-for-byte from Wine at the existing `pins.lock`
commit `455e3509b98a6919fd4ad1def4803e08c41c03b2`, path `nls/c_10000.nls`.
Wine's existing LGPL notice/source offer applies. Source:
https://github.com/wine-mirror/wine/blob/455e3509b98a6919fd4ad1def4803e08c41c03b2/nls/c_10000.nls

Size: 66,082 bytes. SHA256:
`20128ffdabfca32cc5a5a06d101a1b3316764ee282cc1193bf0e0cc2828931b2`.

The phone report requests codepage 10000 and receives missing-file errors.
The usual Wine NLS tables remain generated/staged from the pinned upstream;
this supplemental table is staged identically and covered by the resource
manifest. It is data, not a replacement conversion implementation.
