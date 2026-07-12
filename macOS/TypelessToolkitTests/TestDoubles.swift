import Foundation
@testable import TypelessToolkit

@MainActor
final class MockCoreClient: CoreClientProtocol {
    var overview = SystemOverview.empty

    func getOverview() async throws -> SystemOverview {
        overview
    }
}
