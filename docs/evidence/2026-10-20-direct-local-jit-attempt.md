# Direct local JIT attempts before VPN recovery

IPA SHA256: `4ad2d7574566f0463d02a21a79db870fafdac40ed0bcd5237a8d91c6a64ec4bb`
Decision: [0072](../decisions/0072-try-local-jit-before-vpn-recovery.md).

The owner clarified that they want an actual launch attempt before any VPN
prompt. An offline launch with the tunnel still enabled is not proof that a
new process can obtain executable permissions without a local connection.

Both paired-launch route gates are removed. SetupChecklist checks missing
pairing only; JitSetup with stored pairing proceeds without tunnelUp. JitProvider
still invokes the helper and native debugger/prepare/detach handshake and the
runtime still validates the resulting pool. Existing detailed errors remain
in the report. launch-direct-v1 identifies the real attempt, PID and restart
recovery. A missing pairing continues to the existing setup/import flow.

AppRestart sends CoreDevice first. The pure recovery policy only permits VPN
recovery after a failed real request, with a down route and no previous recovery.
Successful responses are never retried on route evidence. Single-session Wine
lifecycle and the restart record are retained. No preallocated extra pool,
persisted readiness bit, cache safety override or signature bypass is added.

Validation:
- 21 focused XCTest cases pass against complete production storage, memory,
  setup, method and recovery models, including four new preflight regressions.
  Fixtures and source hashes are checked against the tested bytes. The existing
  monolithic checklist fixture also expects paired down/unknown routes to go.
- Release compilation and 88 IPA checks pass.
- 220 production sources match the reviewed
  bytes; IPA ZIP CRC, r32 marker and Files App flags are verified independently.
- Native artifacts and retained runtime DLLs are byte-identical to r31.

The reinstalled workstation's missing frozen Madeira submodule was restored
at 8c050d0. Builds used the preserved headless Linux overlay; no phone was
connected, no Windows game launched and no live cloud/save data changed.
No public IPA upload or public download link was generated.

Owner testing is still required to establish actual VPN-off launch success.
A real tunnel failure can still need VPN; this is not a no-JIT backend.
Embedded GetMoreRam account/provisioning management and interpreter execution
remain unimplemented. No Riddle Joker Access Violation/script error, frame-rate,
heat or memory-footprint improvement is claimed by this startup-order change.
The pre-reinstall recovery snapshot is preserved separately.
