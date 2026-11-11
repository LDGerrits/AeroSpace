@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class NormalizeLayoutReasonTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.automaticallyUnhideMacosHiddenApps = true // TestApp has no NSRunningApplication to ask
    }

    func testMinimizedWindowLeavesTheTree() async throws {
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let minimized = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        minimized.isMacosMinimizedForTest = true

        try await normalizeLayoutReason()

        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))
        XCTAssertTrue(minimized.parent === macosMinimizedWindowsContainer)
    }

    // Restoring the closed windows cache binds windows back into the tree without looking at whether they are
    // minimized. A window that was already minimized then stayed in the layout as a gap.
    func testMinimizedWindowPutBackIntoTheTreeLeavesItAgain() async throws {
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let minimized = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        minimized.isMacosMinimizedForTest = true
        try await normalizeLayoutReason()

        minimized.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        try await normalizeLayoutReason()

        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))
        XCTAssertTrue(minimized.parent === macosMinimizedWindowsContainer)
    }

    func testUnminimizedWindowComesBack() async throws {
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let window = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        window.isMacosMinimizedForTest = true
        try await normalizeLayoutReason()

        window.isMacosMinimizedForTest = false
        try await normalizeLayoutReason()

        XCTAssertTrue(window.parent is TilingContainer)
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId).sorted(), [1, 2])
    }
}
