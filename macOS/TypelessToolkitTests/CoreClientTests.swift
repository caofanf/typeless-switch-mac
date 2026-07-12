import XCTest
@testable import TypelessToolkit

final class CoreClientTests: XCTestCase {
    func testListAccountsDecodesSanitizedDTO() async throws {
        let transport = MockRPCTransport(
            result: .object([
                "accounts": .array([
                    .object([
                        "user_id": .string("u1"),
                        "nickname": .string("N"),
                        "has_snapshot": .bool(true),
                        "future_field": .string("ignored")
                    ])
                ])
            ])
        )
        let client = LiveCoreClient(transport: transport)

        let accounts = try await client.listAccounts()

        XCTAssertEqual(accounts.first?.id, "u1")
        XCTAssertEqual(accounts.first?.nickname, "N")
        XCTAssertEqual(accounts.first?.hasSnapshot, true)
        let lastMethod = await transport.lastMethod
        XCTAssertEqual(lastMethod, "accounts.list")
    }
    func testPrepareOperationDecodesMillisecondExpiryAndSendsTypedParameters() async throws {
        let transport = MockRPCTransport(result: .object([
            "confirmation_token": .string("once"),
            "expires_at": .number(1_800_000_000_000),
            "summary": .object(["title": .string("危险操作")])
        ]))
        let client = LiveCoreClient(transport: transport)

        let confirmation = try await client.prepareOperation(
            method: "device.reset",
            params: .object([:]),
            summary: .object(["title": .string("危险操作")])
        )

        XCTAssertEqual(confirmation.token, "once")
        XCTAssertEqual(confirmation.expiresAt.timeIntervalSince1970, 1_800_000_000, accuracy: 0.001)
        let lastMethod = await transport.lastMethod
        XCTAssertEqual(lastMethod, "operations.prepare")
    }

    func testUnknownRemoteErrorPreservesCodeAndRecoveryDetails() async {
        let transport = FailingRPCTransport(payload: JSONRPCErrorPayload(
            code: "FUTURE_ERROR",
            message: "未来错误",
            details: .object([
                "recoverable": .bool(true),
                "suggested_action": .string("diagnostics.run"),
                "context": .object(["source": .string("test")])
            ])
        ))
        let client = LiveCoreClient(transport: transport)

        do {
            _ = try await client.versionStatus()
            XCTFail("Expected remote error")
        } catch let CoreError.unknown(code, message, details) {
            XCTAssertEqual(code, "FUTURE_ERROR")
            XCTAssertEqual(message, "未来错误")
            XCTAssertTrue(details.recoverable)
            XCTAssertEqual(details.suggestedAction, "diagnostics.run")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

}

private actor MockRPCTransport: RPCTransportProtocol {
    let result: JSONValue
    private(set) var lastMethod: String?

    init(result: JSONValue) {
        self.result = result
    }

    func call(method: String, params: JSONValue) async throws -> JSONValue {
        lastMethod = method
        return result
    }

    func close() async {}
}


private actor FailingRPCTransport: RPCTransportProtocol {
    let payload: JSONRPCErrorPayload

    init(payload: JSONRPCErrorPayload) { self.payload = payload }

    func call(method: String, params: JSONValue) async throws -> JSONValue {
        throw IPCTransportError.remote(payload)
    }

    func close() async {}
}
