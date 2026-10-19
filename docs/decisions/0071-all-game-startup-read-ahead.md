# 0071: Optional file read-ahead for every title

The owner requests an all-game cache switch, GetMoreRam integration and an
assessment of UTM SE or cellular-only JIT. The runtime does not gain a no-JIT
backend or a safe universal translated-code cache from a settings switch.
Decision 0056 and the native WoW64 disk-cache guard stay in force: a 32-bit
block embeds its process window base, and changing that base invalidates it.
The known warm-start failure also has no new device validation. This change
must not label FEX disk caching as active for these titles.

Expand the bounded file-header warmup from 0070 into an independent, default-off
all-game preference. Graphics settings offers one switch with an explanatory
confirmation before enabling. The selected executable's resolved parent
supplies the root, rather than Steam account metadata or an engine allowlist.
Thus Steam, GOG, Epic and manual imports use the same path. Selected executable
bytes precede other code and resource headers. Reads stop being scheduled
at the byte/time budgets (8 MiB / 0.25 seconds); an individual filesystem call
can take longer. Insufficient or unknown memory headroom skips read-ahead.

No decoded assets are retained and no files are written. iOS owns and can evict
its file cache. This is not persistent CPU translation, shader precompilation,
a promise of faster startup, or preservation of JIT permission. The UI says so.
User saves are not preloaded, symbolic files/plugin directories are skipped,
and directory entry enumeration and candidate count are bounded.

The app already requests Increased Memory Limit. Settings adds the actual
signature status and a shared GetMoreRam guide with copyable installed bundle
ID and an explicit external project link. GetMoreRam's account/provisioning
client is not embedded: changing an App ID capability still requires signing
and reinstalling with the matching account. No Apple credentials are collected,
no signing service is added, and no runtime RAM increase is claimed.

UTM SE's interpreter is a separate architecture. The current Wine ARM64EC and
FEX executable pool still require JIT. Settings explains that cellular can be
restored after successful preparation while the same process lives; own-phone
hotspot loopback and spoofed Wi-Fi are not offered as supported workarounds.
See the evidence record for primary sources and validation limits.
