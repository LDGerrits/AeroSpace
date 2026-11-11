import AppKit
import Common

/// Hyprland's "dwindle" layout (`new-window-split = 'dwindle'`).
///
/// A new window splits the window that was most recently used, and takes the second half of it (the right half, or
/// the bottom one). Which way it splits depends on the shape of the window being split: side by side if it is wider
/// than it is tall, stacked if it is taller. So on a 16:10 screen the first three windows are left, top right and
/// bottom right, and on an ultrawide one they are three columns (the second window is still wider than it is tall),
/// and only then does the third column get stacked. The other windows keep their size.
///
/// The shape comes from the rectangle the window was last laid out in, so this works on a screen of any shape, and
/// for any window however deep in the tree it is. The new window is placed before it is ever laid out, so it appears
/// where it belongs the first time and doesn't move.
///
/// Returns nil (and the new window goes next to `target`, as usual) if `target` has not been laid out yet, or isn't
/// in a container with the `tiles` layout.
@MainActor
func dwindleBindingData(splitting target: Window, in parent: TilingContainer) -> BindingData? {
    guard parent.layout == .tiles, let rect = target.lastAppliedLayoutVirtualRect else { return nil }
    let orientation = dwindleSplitOrientation(width: rect.width, height: rect.height)
    if orientation == parent.orientation {
        // Beside it, in the same container: the two share the space the window had, nothing else changes size
        let half = target.getWeight(orientation) / 2
        target.setWeight(orientation, half)
        return BindingData(parent: parent, adaptiveWeight: half, index: target.ownIndex.orDie() + 1)
    }
    // Otherwise a new container takes the place of the window (with the weight it had), and holds it and the new window
    let binding = target.unbindFromParent()
    let container = TilingContainer(parent: parent, adaptiveWeight: binding.adaptiveWeight, orientation, .tiles, index: binding.index)
    target.bind(to: container, adaptiveWeight: WEIGHT_AUTO, index: 0)
    return BindingData(parent: container, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
}

/// Hyprland's `dwindle:split_width_multiplier`, as a percentage: a window is split side by side when
/// `width * dwindle-split-width-percent / 100 > height`. Below 100 favours stacking, above favours columns.
@MainActor
func dwindleSplitOrientation(width: CGFloat, height: CGFloat) -> Orientation {
    width * CGFloat(config.dwindleSplitWidthPercent) > height * 100 ? .h : .v
}

/// Lays out the tiled windows of a workspace from scratch, as if they had been opened one after the other: each
/// splits the one before it. AeroSpace uses it at startup, when it finds windows that are already open (upstream
/// puts them side by side, or in an accordion if there are more than three).
@MainActor
func dwindleArrange(_ workspace: Workspace) {
    let prevRoot = workspace.rootTilingContainer // Keep it in a variable so that it isn't garbage collected too early
    let windows = prevRoot.allLeafWindowsRecursive
    guard windows.count > 1 else { return }
    let rect = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
    prevRoot.unbindFromParent()
    let root = TilingContainer(parent: workspace, adaptiveWeight: 1, dwindleSplitOrientation(width: rect.width, height: rect.height), .tiles, index: INDEX_BIND_LAST)
    var last = windows[0]
    last.bind(to: root, adaptiveWeight: 1, index: INDEX_BIND_LAST)
    last.lastAppliedLayoutVirtualRect = rect
    for window in windows.dropFirst() {
        guard let lastRect = last.lastAppliedLayoutVirtualRect, let parent = last.parent as? TilingContainer,
              let data = dwindleBindingData(splitting: last, in: parent) else { break }
        window.bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
        // What the two will be laid out in, so that the next window knows which way to split
        let (first, second) = lastRect.dwindleHalves(dwindleSplitOrientation(width: lastRect.width, height: lastRect.height))
        last.lastAppliedLayoutVirtualRect = first
        window.lastAppliedLayoutVirtualRect = second
        last = window
    }
}

extension Rect {
    fileprivate func dwindleHalves(_ orientation: Orientation) -> (Rect, Rect) {
        orientation == .h
            ? (Rect(topLeftX: minX, topLeftY: minY, width: width / 2, height: height),
               Rect(topLeftX: minX + width / 2, topLeftY: minY, width: width / 2, height: height))
            : (Rect(topLeftX: minX, topLeftY: minY, width: width, height: height / 2),
               Rect(topLeftX: minX, topLeftY: minY + height / 2, width: width, height: height / 2))
    }
}
