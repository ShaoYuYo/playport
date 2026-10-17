# Steam conflict choice preserves the complete remote save set

The r19 owner report confirms the new build and authoritative root. All nine
manual slots and twelve quick slots match the observed Steam SHA-1 in both
backends. The continue file and two system files have changed in the active
Steam backend since that observation. Opens of system files succeed. This is
not evidence that every slot was enumerated or semantically loaded.

A separate defect is reproduced with synthetic saves: after a baseline,
change a slot both locally and on Steam, and change system progress only
locally. Choosing Steam for the slot previously downloaded that slot while
uploading the fresh local system progress. The new regression fails four
assertions on the previous implementation, including remote progress damage.

The UI's game-wide Steam choice now re-fetches the full observed remote
snapshot without any upload, just like explicit restoration. Download hashes,
backups, canonical placement and readback checks remain in force. Local-only
files remain local. Mixed per-file choices retain their existing semantics.
A failed download prevents launch through the existing gate.

All 26 Cloud tests pass after the change. The exact failure is demonstrated;
its contribution to the owner's earlier cloud history cannot be recovered
from file hashes alone. A cloud snapshot already overwritten with fresh
progress needs a preserved prior version, not another download of that same
snapshot. No phone was connected or controlled, and original Windows saves
were only read. No source or report containing private paths is committed.
