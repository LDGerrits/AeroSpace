@MainActor
func normalizeLayoutReason() async throws {
    for workspace in Workspace.all {
        let windows: [Window] = workspace.allLeafWindowsRecursive
        try await _normalizeLayoutReason(workspace: workspace, windows: windows)
    }
    try await _normalizeLayoutReason(workspace: focus.workspace, windows: macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self))
    try await validateStillPopups()
}

@MainActor
private func validateStillPopups() async throws {
    for node in macosPopupWindowsContainer.children {
        let popup = (node as! MacWindow)
        let windowLevel = getWindowLevel(for: popup.windowId)
        if try await popup.isWindowHeuristic(windowLevel, .cancellable) {
            try await popup.relayoutWindow(on: focus.workspace, .cancellable)
            await runOnWindowDetected(ifConventional: popup)
        }
    }
}

@MainActor
private func _normalizeLayoutReason(workspace: Workspace, windows: [Window]) async throws {
    for window in windows {
        let isMacosFullscreen = try await window.isMacosFullscreen(.cancellable)
        let isMacosMinimized = try await (!isMacosFullscreen).andAsync { @MainActor @Sendable in try await window.isMacosMinimized(.cancellable) }
        let isMacosWindowOfHiddenApp = !isMacosFullscreen && !isMacosMinimized &&
            !config.automaticallyUnhideMacosHiddenApps && window.macAppUnsafe.nsApp.isHidden
        let unconventionalContainer: NonLeafTreeNodeObject? = switch true {
            case isMacosFullscreen: workspace.macOsNativeFullscreenWindowsContainer
            case isMacosMinimized: macosMinimizedWindowsContainer
            case isMacosWindowOfHiddenApp: workspace.macOsNativeHiddenAppsWindowsContainer
            default: nil
        }
        switch window.layoutReason {
            case .standard:
                guard let parent = window.parent, let unconventionalContainer else { continue }
                window.layoutReason = .macos(prevParentKind: parent.kind)
                window.bind(to: unconventionalContainer, adaptiveWeight: isMacosMinimized ? 1 : WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
            case .macos(let prevParentKind):
                if let unconventionalContainer {
                    // Something put the window back into the tree while it is still minimized, fullscreen or hidden
                    // (restoring the closed windows cache does), which left a gap where it is laid out but not shown
                    if window.parent is TilingContainer || window.parent is FloatingWindowsContainer {
                        window.bind(to: unconventionalContainer, adaptiveWeight: isMacosMinimized ? 1 : WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                    }
                } else {
                    try await exitMacOsNativeUnconventionalState(window: window, prevParentKind: prevParentKind, workspace: workspace, .cancellable)
                }
        }
    }
}

@MainActor
func exitMacOsNativeUnconventionalState(
    window: Window,
    prevParentKind: NonLeafTreeNodeKind,
    workspace: Workspace,
    _ cm: CancellationMode,
) async throws {
    window.layoutReason = .standard
    switch prevParentKind {
        case .floatingWindowsContainer:
            window.bindAsFloatingWindow(to: workspace)
        case .workspace:
            break // Not possible
        case .tilingContainer:
            try await window.relayoutWindow(on: workspace, cm, forceTile: true)
        case .macosPopupWindowsContainer: // Since the window was minimized/fullscreened it was mistakenly detected as popup. Relayout the window
            try await window.relayoutWindow(on: workspace, cm)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer: // wtf case, should never be possible. But If encounter it, let's just re-layout window
            try await window.relayoutWindow(on: workspace, cm)
    }
}
