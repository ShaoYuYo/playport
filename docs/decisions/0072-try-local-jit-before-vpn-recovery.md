# 0072: Attempt local JIT before VPN recovery

The owner reports that an offline launch can work while LocalDevVPN stays on,
but switching the VPN off is rejected before an actual attempt. They explicitly
request trying the launch first, then presenting VPN recovery only if necessary.

Two independent preflights used the same route snapshot to gate Play:
SetupChecklist.beforeLaunch returned fixesItself(vpn), and JitSetup.ensureReady
required both an existing pairing and LocalDevVPN.tunnelUp. Remove those route
gates for paired launches. Keep pairing, signature and actual debugger/pool
protocol checks. A missing pairing still uses the existing setup flow.
The explicit setup checklist retains its connection step; it is not proof that
a launch must be vetoed solely because a utun route was not observed.

After a game, AppRestart also tries the real CoreDevice request first. Only an
actual failed request, with the route down and no recovery attempted yet, opens
LocalDevVPN. Recovery is bounded to once. A successful service response must not
be resent just because the sender has not exited yet. No unsafe second Wine
session is introduced into the same process.

Log launch-direct-v1 at the setup bypass, JIT handshake and restart attempt and
recovery. Preserve the helper's detailed failures in the existing report.
Do not persist a ready boolean, reserve another JIT pool in the library, or
pretend a disk cache restores executable permissions in a new process.

The actual helper may still require a local tunnel when it needs to attach a
debugger. This decision removes a premature rejection; it does not establish
that VPN-free activation works on every iOS version or that a no-JIT execution
backend exists. Device behavior requires owner testing without workstation
phone access.
