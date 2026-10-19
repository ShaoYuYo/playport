# Persistent JIT feasibility

Reviewed for the r30 source and IPA SHA256 `51ef853f7c5a04ab0d6284e8f573ab8de418b2ec6a7acd810f7a7aecb98aae44`.
This is a source/documentation assessment, not an iPhone experiment.

## Result

Saving translated instructions does not preserve permission to execute them
in a future application process. The current non-jailbroken iOS runtime cannot
provide permanent no-activation startup by saving its JIT pool to a file.

Apple documents [mandatory executable code signing](https://support.apple.com/guide/security/sec7c917bf14/web)
and [runtime executable-memory controls](https://support.apple.com/en-au/guide/security/sec15bfe098e/web).
Those restrictions concern execution, regardless of whether code bytes arrived
from a file or were just generated. The conclusion about this application's
next launch follows from those rules and the concrete activation implementation.

`JitProvider.acquire` obtains an RX/RW memory pool for the current PID.
`playport-universal.js` prepares its memory pages through debugserver and then
detaches. `WineHostRuntime` starts only after acquiring that pool. The
architecture's JIT activation contract explicitly scopes the blessing to the
process. A disk file preserves bytes, not the old process's mappings and page
state. Reusing the same pairing record does not preserve that page state.
The pool also carries Wine ARM64EC image code, not just FEX translations;
saving only the FEX database leaves that activation dependency in place.

JIT compilation itself runs locally on the phone. It is not cloud compilation
of the game. The helper uses a local debug tunnel; missing developer-disk
components may need a network download. Steam/cloud networking is separate.

| Item | Can persist? | What it changes |
| --- | --- | --- |
| Pairing record | Already kept in Keychain | Avoids pairing again; not per-process activation |
| Developer-disk files | Already cached in the helper's Library | Avoids downloading again; the mount is normally reusable until device reboot |
| Graphics shader caches | Already stored under app caches, subject to iOS eviction and user cleanup | Can avoid rebuilding shaders; not CPU executable-memory permission |
| FEX translated-code database | A separate potential warm-start optimization | Not currently enabled because of the known warm-start corruption issue; not safe to re-enable as an activation workaround |
| The active process's prepared JIT pool | Usable while that process remains alive | Does not require a permanent debugger connection after the protocol detaches |
| Prepared JIT permissions after process exit | Not preserved by a saved code file | A new process still needs its own activation |

Returning from the background can retain the active pool if iOS kept the same
process alive. This is not guaranteed after memory pressure, force-close or
reboot. The existing architecture ends each game by restarting the application,
so another game normally has a new process and needs fresh activation. Keeping
an otherwise idle game process alive solely to retain its pool also conflicts
with the request to reduce RAM and battery use. No background-lifetime trick
or new repeated activation is added by this assessment.

A static AOT/native-game approach would need a different execution path,
relocations/import handling and signed executable packaging; simply loading a
saved FEX blob is not such an implementation. It would also need to handle
code and plugins discovered during gameplay. It is not a supported general
backend in this app and is not presented as a working no-JIT option.

The practical current behavior is to reuse the existing safe pairing/DDI/shader
caches and activate the pool for each new process. The known cellular loopback
limitation remains as documented by the [runtime upstream](https://github.com/willfaust/Madeira/blob/main/docs/JIT.md).
Successful activation detaches before the game starts, so the JIT mechanism
itself does not continuously require internet while that same process runs;
networked game services and the post-game restart have their own requirements.
