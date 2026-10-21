# 0073: Reliable surface readiness and embedded Apple memory capability setup

Date: 2026-10-20
Status: implemented; verification recorded in the companion evidence record

Riddle Joker's r32 report identifies nil drawable polling and repeated scans
above the kernel VA ceiling. Honor the kernel's valid bound, wait for a usable
Metal surface, back off failed acquisitions, and distinguish acquisition from
confirmed presentation. Native pins remain frozen.

Provide Apple account setup inside the app rather than sending the owner to a
separate memory-rights app. Use an ephemeral account session, SRP-6a with server
proof verification, six-digit trusted-device/SMS verification, exact installed
bundle-ID selection, and complete capability readback before and after updating.
Preserve all existing capabilities and opaque settings. Refuse incomplete or
paginated snapshots. Only the requested Increased Memory Limit capability is
enabled after a confirmation in the app.

Apple credentials and account tokens are not persisted or logged. The only
persisted record is the anisette device identity in Keychain. The UI discloses
the SideStore anisette endpoint; it receives provisioning data, never Apple
credentials or account tokens. HTTPS redirects cannot cross origins. Closing
the sheet cancels pending verification and clears the account session.

The portal setting and the installed executable's signed entitlement are
separate states. Success at the portal still requires re-signing and upgrading
in place with the original sideload tool. This cannot add physical RAM or bypass
iOS process limits. No private account was used for automated validation.

Use pinned MIT BigInt and zlib CryptoSwift for account arithmetic/cryptography;
no OpenSSL-linked SRP dependency is shipped. Account work runs only during setup,
not while rendering. Preserve the complete corresponding notices and licence
attribution to the SRP protocol reference.

Rewriting the closed Windows executable as Swift is not available without its
source or a compatible replacement engine. Wine/FEX/graphics host code already
runs as native ARM64; Swift host logic optimizations address actual waits and
work rather than claiming that a language change removes x86 translation.

Authentication transport also accounts for the September 2026 GrandSlam edge
regression: normalize the GSA client token while preserving hardware/OS fields,
and use a throwaway ephemeral session for each GSA request. Other origins keep
their original descriptor. HTTP errors surface only the numeric status, never
the response body or account tokens. References:
- https://github.com/altstoreio/AltStore/pull/1790
- https://github.com/pwnapplehat/iPASide/issues/7

GrandSlam wire encoding uses minimal big-endian A, raw received B in proofs,
and SHA-256 of minimal S; only the scrambling/multiplier inputs use group-width
padding. Regression transcripts include short A, short B and a short S to avoid
intermittent proof/session failures. Protocol cross-check:
https://github.com/xtool-org/xtool/blob/main/Sources/XKit/GrandSlam/Crypto/SRPClient.swift
