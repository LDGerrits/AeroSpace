@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class DwindleTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.newWindowSplit = .dwindle
    }

    private func rect(_ width: CGFloat, _ height: CGFloat) -> Rect {
        Rect(topLeftX: 0, topLeftY: 0, width: width, height: height)
    }

    /// "h[1,v[2,3]]": the tree, as a container with its orientation and children
    private func shape(_ node: TreeNode) -> String {
        if let window = node as? Window { return String(window.windowId) }
        let container = node as! TilingContainer
        return (container.orientation == .h ? "h" : "v") + "[" + container.children.map(shape).joined(separator: ",") + "]"
    }

    /// Open a window the way AeroSpace does: it is not in the tree yet when the place is worked out
    @discardableResult
    private func open(_ id: UInt32, splitting target: Window, in workspace: Workspace, laidOutAs newRect: Rect? = nil) -> TestWindow {
        let data = dwindleBindingData(splitting: target, in: target.parent as! TilingContainer)!
        let window = TestWindow.new(id: id, parent: workspace.rootTilingContainer)
        window.bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
        window.lastAppliedLayoutVirtualRect = newRect
        return window
    }

    func testWideWindow_newWindowGoesBesideIt() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer, adaptiveWeight: 1)
        first.lastAppliedLayoutVirtualRect = rect(1920, 1200)
        open(2, splitting: first, in: workspace)
        assertEquals(shape(workspace.rootTilingContainer), "h[1,2]")
    }

    func testTallWindow_newWindowGoesBelowIt() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        first.lastAppliedLayoutVirtualRect = rect(960, 1200)
        open(2, splitting: first, in: workspace)
        assertEquals(shape(workspace.rootTilingContainer), "h[v[1,2]]")
    }

    func testSquareWindow_isStacked() {
        // Hyprland splits side by side only when the window is wider than it is tall
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        first.lastAppliedLayoutVirtualRect = rect(1000, 1000)
        open(2, splitting: first, in: workspace)
        assertEquals(shape(workspace.rootTilingContainer), "h[v[1,2]]")
    }

    func testBesideIt_shareTheWeightOfTheWindow_othersKeepTheirs() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer, adaptiveWeight: 3)
        let other = TestWindow.new(id: 2, parent: workspace.rootTilingContainer, adaptiveWeight: 1)
        first.lastAppliedLayoutVirtualRect = rect(2000, 1000)
        let third = open(3, splitting: first, in: workspace)
        assertEquals(shape(workspace.rootTilingContainer), "h[1,3,2]")
        assertEquals(first.getWeight(.h), 1.5)
        assertEquals(third.getWeight(.h), 1.5)
        assertEquals(other.getWeight(.h), 1)
    }

    func testNested_containerTakesTheWindowsPlaceAndWeight() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer, adaptiveWeight: 3)
        let other = TestWindow.new(id: 2, parent: workspace.rootTilingContainer, adaptiveWeight: 1)
        first.lastAppliedLayoutVirtualRect = rect(500, 1000)
        let third = open(3, splitting: first, in: workspace)
        assertEquals(shape(workspace.rootTilingContainer), "h[v[1,3],2]")
        let container = first.parent as! TilingContainer
        assertEquals(container.getWeight(.h), 3)
        assertEquals(other.getWeight(.h), 1)
        // and they share the container evenly
        assertEquals(first.getWeight(.v), third.getWeight(.v))
    }

    func testUltrawide_firstThreeWindowsAreThreeColumns_thenTheThirdIsStacked() {
        let workspace = Workspace.get(byName: name)
        let w1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        w1.lastAppliedLayoutVirtualRect = rect(3420, 1390)

        // 3420x1390 is wide: 1 | 2, 1710x1390 each. Each new window splits the one before it
        let w2 = open(2, splitting: w1, in: workspace)
        w1.lastAppliedLayoutVirtualRect = rect(1710, 1390)
        w2.lastAppliedLayoutVirtualRect = rect(1710, 1390)
        assertEquals(shape(workspace.rootTilingContainer), "h[1,2]")

        // 1710x1390 is still wider than it is tall: 1 | 2 | 3, with 2 and 3 a quarter each
        let w3 = open(3, splitting: w2, in: workspace)
        w2.lastAppliedLayoutVirtualRect = rect(855, 1390)
        w3.lastAppliedLayoutVirtualRect = rect(855, 1390)
        assertEquals(shape(workspace.rootTilingContainer), "h[1,2,3]")
        assertEquals(w1.getWeight(.h), 0.5)
        assertEquals(w2.getWeight(.h), 0.25)
        assertEquals(w3.getWeight(.h), 0.25)

        // 855x1390 is taller than it is wide: the next one is stacked below
        open(4, splitting: w3, in: workspace)
        assertEquals(shape(workspace.rootTilingContainer), "h[1,2,v[3,4]]")
    }

    func testClassicScreen_firstThreeWindowsAreLeftTopRightBottomRight() {
        let workspace = Workspace.get(byName: name)
        let w1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        w1.lastAppliedLayoutVirtualRect = rect(1900, 1180)
        let w2 = open(2, splitting: w1, in: workspace) // 1900x1180 is wide: side by side
        w1.lastAppliedLayoutVirtualRect = rect(950, 1180)
        w2.lastAppliedLayoutVirtualRect = rect(950, 1180)
        open(3, splitting: w2, in: workspace) // 950x1180 is tall: stacked
        assertEquals(shape(workspace.rootTilingContainer), "h[1,v[2,3]]")
    }

    func testSplitWidthPercent_belowAHundredFavoursStacking() {
        config.dwindleSplitWidthPercent = 50
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        first.lastAppliedLayoutVirtualRect = rect(1500, 1000) // wide, but not twice as wide
        open(2, splitting: first, in: workspace)
        assertEquals(shape(workspace.rootTilingContainer), "h[v[1,2]]")
    }

    func testSplitWidthPercent_aboveAHundredFavoursColumns() {
        config.dwindleSplitWidthPercent = 200
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        first.lastAppliedLayoutVirtualRect = rect(600, 1000) // tall, but more than half as wide as tall
        open(2, splitting: first, in: workspace)
        assertEquals(shape(workspace.rootTilingContainer), "h[1,2]")
    }

    func testInAVerticalContainer_beingStackedIsBesideIt() {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.changeOrientation(.v)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        first.lastAppliedLayoutVirtualRect = rect(1000, 1800) // tall: stacked, which is the container's own direction
        open(2, splitting: first, in: workspace)
        assertEquals(shape(workspace.rootTilingContainer), "v[1,2]")
    }

    func testNotLaidOutYet_fallsBackToAsUsual() {
        let workspace = Workspace.get(byName: name)
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        XCTAssertNil(dwindleBindingData(splitting: first, in: workspace.rootTilingContainer))
    }

    func testAccordion_fallsBackToAsUsual() {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .accordion
        let first = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        first.lastAppliedLayoutVirtualRect = rect(1000, 1000)
        XCTAssertNil(dwindleBindingData(splitting: first, in: workspace.rootTilingContainer))
    }

    func testWorksDeepInTheTree() {
        let workspace = Workspace.get(byName: name)
        var inner: TestWindow!
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1, index: INDEX_BIND_LAST).apply {
                TestWindow.new(id: 2, parent: $0)
                inner = TestWindow.new(id: 3, parent: $0)
            }
        }
        inner.lastAppliedLayoutVirtualRect = rect(1000, 500) // wide: beside it, inside its own container, which is vertical
        open(4, splitting: inner, in: workspace)
        assertEquals(shape(workspace.rootTilingContainer), "h[1,v[2,h[3,4]]]")
    }
}
