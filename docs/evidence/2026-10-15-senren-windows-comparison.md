# Senren Banka: Windows comparison and bounded i386 evidence

The owner's 18:22 report repeats the Unicode conversion dialog, a failed
dialog window creation (error 6), and exit zero without a first frame after
about one second. The current short log is the restarted app; the failure
is in the preceding log's latest launch, not evidence of a new successful run.
Codepage 932 was requested and mapped in both the session root and i386 child.
Raw reports, executable copies and memory dumps remain private build scratch.

## Host comparison

The owner supplied a locally installed Windows game for comparison. Its
original executable is 4,583,168 bytes; Playport's production SteamStub
implementation produces a 4,412,928-byte executable, matching the phone's
reported size. The 221-byte configuration is ASCII. The reported archive
and plugin sizes agree with the Windows inventory. Size agreement alone
does not establish byte equality with the phone, hence the new fingerprints.

On Windows, the unwrapped executable with the original Steam DLL created a
responding game window. Replacing only the scratch copy's Steam DLL with
Playport's actual i386 emulator also created a responding game window with
the English title. These bounded seven-second observations are not a full
play, first-frame measurement or phone result. The standalone protected
executable exited with code 53; that invocation did not establish a working
Steam-launch environment. Installed game binaries were not replaced.

Background desktop Wine 9.0, in a private prefix and Xvfb display, passed the
phone's Unicode failure point and reached a later DirectX initialization
dialog. It was stopped after 25 seconds. This is not the same Wine version,
processor architecture or iOS guest-window implementation as the phone.
After the owner's clarification, any further game launch must use an
invisible desktop/display, with no windows on the owner's current desktop.

The actual Windows MultiByteToWideChar(932) API was compared against the
bundled CP932 data and the pinned Wine decoding/invalid-character rules:
all 256 single-byte inputs and 65,536 two-byte inputs, with flags zero and
MB_PRECOMPOSED|MB_ERR_INVALID_CHARS, total 131,584 cases. Returned length,
UTF-16 output on success, and error on failure matched. This is a host
algorithm/table comparison, not execution of the phone's i386 DLL.

The engine source distinguishes older Win32-API conversion from the newer
[in-engine Shift-JIS decoder](https://github.com/krkrz/krkrz/blob/fd5c4baa6a2ef5978db1bd043634351f48667daf/tjs2/tjsConfig.cpp).
[TextStream](https://github.com/krkrz/krkrz/blob/fd5c4baa6a2ef5978db1bd043634351f48667daf/base/TextStream.cpp)
can also raise the same error during UTF-8 or Shift-JIS decoding. Consequently
the dialog alone cannot identify MultiByteToWideChar or justify changing the
game's encoding, script data or selected Steam language.

## Candidate changes and next required observation

Wine PE patch 0033 adds i386-only, error-path evidence in kernelbase:

- At most eight failed conversions: API parameters, last-error and caller,
  without logging any input string or file contents.
- At most three C++ exception reports: actual guest ACP/OEMCP, a fixed public
  CP932 sample (Japanese), thread desktop validity, and up to 16 guest frames.
- Last-error restored after diagnostic work; normal conversion, exception
  propagation, encoding choices and game files are unchanged.

The actual extracted helper was cross-compiled as an i386 Windows program
with warnings treated as errors. It ran without visible UI and converted the
sample to U+65E5 U+672C U+8A9E, returned four units including the terminator,
and found a valid desktop. Five calls produced only three reports; all five
preserved a preloaded last-error value. The actual Wine kernelbase DLL also
compiled and linked from the patched source.

The report now includes hashes for only five named executable/config/runtime
files, with a 16 MiB limit and symlink exclusion. It never gathers saves,
account settings, tickets or file contents. This establishes the phone's
actual executable and diagnostic DLL on the next report.

`rebuild-i386-diagnostics-checkpoint.py` accepts only the exact diagnostic
append and the already reviewed 0032 context normalization, verifies the
entire existing checkpoint, invokes the unchanged Wine recipe to validate
all series/configuration, and builds one real i386 kernelbase. Only its DLL,
generated record and artifact manifests may change. It then saves and
reverifies the complete checkpoint. Other native binaries keep their bytes.

The existing Liquid Glass/navigation candidate is retained. No new phone UI
or launch validation occurred here. **The game's phone startup is still
unresolved.** The next actual phone launch must provide the bounded guest
checks and call stack before a root cause or working-game claim is possible.

## Build result

The full 1,615-file checkpoint verified after replacing only the i386 DLL
and its records. All nine LaunchDiagnostics tests passed, including the
fingerprint test excluding symlinks, account files, save content and paths.
The release app compiled and linked with the prior Liquid Glass changes.
Final IPA verification: **87 passed, zero failed**.

IPA SHA-256:
`4b2435259a8525d8dd97aeafdccb5226f7282cb2f7943b6e2b5519d26741f3f0`.

The generated aarch64 records also retain the earlier verified 0032 bridge
rebuild, which had not yet been committed with the UI-only source chunk.
The bounded diagnostic migration itself left those DLLs unchanged.
This candidate still needs an in-place phone upgrade and one fresh report.
