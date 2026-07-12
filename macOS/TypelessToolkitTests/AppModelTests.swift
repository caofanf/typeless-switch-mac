import XCTest
@testable import TypelessToolkit

@MainActor
final class AppModelTests: XCTestCase {
    func testDefaultSelectionIsOverview() {
        let model = AppModel(coreClient: MockCoreClient())

        XCTAssertEqual(model.selection, .overview)
        XCTAssertEqual(model.connectionState, .disconnected)
    }
}
