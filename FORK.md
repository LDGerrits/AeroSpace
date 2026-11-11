# This fork

[AeroSpace](https://github.com/nikitabobko/AeroSpace) (MIT) with Hyprland's "dwindle" placement for new windows,
so that a window opens split the way Omarchy / Hyprland would split it, on a screen of any shape.

```toml
new-window-split = 'dwindle'        # default 'sibling': upstream's behaviour
dwindle-split-width-percent = 100   # Hyprland's split_width_multiplier, as a percentage
```

A new window splits the window that was most recently used and takes the right or bottom half. It goes side by side
if that window is wider than it is tall, and stacked if it is taller. So on a 16:10 screen the first three windows are
left, top right, bottom right, and on an ultrawide they are three columns (the second window is still wider than it
is tall); only then does the third column get stacked. The shape is that of the rectangle the window was last laid out
in, so it works for windows deep in the tree, and the other windows keep their size. The window is placed before it is
ever drawn, so it appears where it belongs and doesn't move. It is `Sources/AppBundle/layout/dwindle.swift`, called
from the one place AeroSpace decides where a new window goes (`MacWindow.swift`); with `new-window-split = 'sibling'`
nothing changes.

With `new-window-split = 'dwindle'`, the windows that are already open when AeroSpace starts are laid out the same
way, as if they had been opened one after the other (`dwindleArrange`), instead of upstream's row, or accordion past
three windows.

Not tied to the option:

- A window that is put back into the tree while it is still minimized, fullscreen or hidden (restoring the closed
  windows cache does that) is taken out again. Upstream left it there, as an empty gap in the layout, until it was
  unminimized (`normalizeLayoutReason.swift`).
- It builds with the Swift 6.2 of the Xcode command line tools: one upstream `defer` that calls an async function
  (Swift 6.3) is written out (`MacWindow.swift`).

## Building without Xcode

Upstream's release build needs Xcode. `./build-local-app.sh` needs only the command line tools: it builds the app and
the CLI with SwiftPM and puts `AeroSpace.app` together by hand (`--install` replaces `/Applications/AeroSpace.app` and
the CLI, replacing a Homebrew cask install).

macOS ties AeroSpace's Accessibility permission to whoever signed the app. `script/create-local-codesign-cert.sh`
makes a self-signed certificate once, and every build is signed with it, so a rebuilt app keeps the permission. The
first time you switch from a released build you grant it again. (The first signing asks for your login keychain
password; choose Always Allow.)

## Staying up to date

`dwindle` takes upstream in with merges (GitHub's Sync fork does it), `upstream` being nikitabobko/AeroSpace:

```sh
git fetch upstream
git merge upstream/main
```

The tests are in `Sources/AppBundleTests/tree/DwindleTest.swift` and `NormalizeLayoutReasonTest.swift` (XCTest, so
they need Xcode to run).
