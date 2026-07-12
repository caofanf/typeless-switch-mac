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

    func testDiagnosticsDecodesDetailedSanitizedStatus() async throws {
        let transport = MockRPCTransport(result: .object([
            "typeless": .object([
                "app_path": .string("/Applications/Typeless.app"), "app_found": .bool(true),
                "bin_path": .string("/Typeless"), "bin_found": .bool(true),
                "asar_path": .string("/app.asar"), "asar_found": .bool(true),
                "info_plist": .string("/Info.plist"), "info_plist_found": .bool(true),
                "user_data_dir": .string("/user-data"), "user_data_found": .bool(true)
            ]),
            "cdp": .object(["port": .number(9222), "reachable": .bool(false), "state": .string("disconnected")]),
            "data": .object([
                "dir": .string("/toolkit"), "code_dir": .string("/code"), "writable": .bool(true),
                "migration": .object(["status": .string("none")]),
                "accounts_file": .string("/accounts.json"), "accounts_count": .number(2),
                "profiles_dir": .string("/profiles"), "runtime_backups_dir": .string("/backups"),
                "backup": diagnosticBackupJSON
            ]),
            "connection": diagnosticConnectionJSON,
            "version": .object(["current": .string("1.2.3"), "last_seen": .string("1.2.3"), "drifted": .bool(false)]),
            "backup": diagnosticBackupJSON,
            "patch": .object(["exists": .bool(true), "patched": .bool(true)])
        ]))
        let client = LiveCoreClient(transport: transport)

        let report = try await client.diagnostics()

        XCTAssertTrue(report.typeless.appFound)
        XCTAssertFalse(report.cdp.reachable)
        XCTAssertEqual(report.data.directory, "/toolkit")
        XCTAssertEqual(report.data.accountCount, 2)
        XCTAssertEqual(report.data.migration.objectValue?["status"]?.stringValue, "none")
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

    private var diagnosticConnectionJSON: JSONValue {
        .object(["state": .string("disconnected"), "port": .number(9222), "cdp_reachable": .bool(false)])
    }

    private var diagnosticBackupJSON: JSONValue {
        .object([
            "status": .string("no_data"), "backed_up": .bool(false), "has_data": .bool(false),
            "sources": .array([]), "backup_dir": .string("/backups")
        ])
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
