# Navigation and Liquid Glass continuity

The reported UI symptom is a visible flash/reappearance or position jump when
changing screens, rather than saved settings reverting.

## Change

- Keep the primary roots in a native `TabView`, covered by secondary screens,
  so switching pages does not replace the entire root view hierarchy.
- Keep the top bar and a single footer mounted. The footer changes alignment
  when a game panel opens without replacing its glass container/namespace.
- Keep one native `.glass` button style for primary navigation. Selection
  changes tint and selected accessibility traits rather than replacing a
  `.glass` control with a `.glassProminent` control.
- Restore NavigationStack's game push/pop behavior, with the system's Reduce
  Motion handling. Secondary shell surfaces crossfade, with a shorter reduced
  motion transition.
- Animate footer label/layout changes while retaining controller-button IDs.
- Group Library controls and Settings navigation in shared glass containers;
  game artwork and content surfaces remain separate from navigation glass.

## Machine validation

All five changed Swift files passed frontend syntax checks and the actual
unsigned iOS release app compiled, linked and packaged successfully.
`verify-ipa` passed 87 checks with zero failures.

Candidate IPA SHA-256:
`62a8aa0a69f14335ff0c9299e898681a35ae7bba7fd96696274ed8625508de4e`

## Phone verification

Pending. There is no simulator or connected iOS UI session on this workstation.
Compilation and IPA checks do not prove visual smoothness, touch/controller
focus behavior, scroll-state retention or Reduce Motion appearance on a phone.
The owner should check Home/Library/Downloads, Settings and return, game detail
push/pop, and opening/closing game options after installing the candidate.
