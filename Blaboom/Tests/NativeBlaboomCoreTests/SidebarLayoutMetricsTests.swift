import Testing
@testable import NativeBlaboomCore

struct SidebarLayoutMetricsTests {
    @Test
    func maximumSidebarWidthUsesOneThirdOfWindowWidth() {
        #expect(SidebarLayoutMetrics.maximumWidth(forWindowWidth: 1200) == 400)
        #expect(SidebarLayoutMetrics.maximumWidth(forWindowWidth: 1500) == 500)
    }

    @Test
    func maximumSidebarWidthNeverDropsBelowMinimumWidth() {
        #expect(SidebarLayoutMetrics.maximumWidth(forWindowWidth: 300) == SidebarLayoutMetrics.minimumWidth)
        #expect(SidebarLayoutMetrics.maximumWidth(forWindowWidth: 600) == SidebarLayoutMetrics.minimumWidth)
    }
}
