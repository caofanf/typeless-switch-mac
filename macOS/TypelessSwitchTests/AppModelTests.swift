import XCTest
@testable import TypelessSwitch

@MainActor
final class AppModelTests: XCTestCase {
    func testAccountLayoutLeavesRoomForPrimarySidebarAtMinimumWindowWidth() {
        let remainingWidth = AppLayout.mainMinimumWidth
            - AppLayout.primarySidebarMinimumWidth
            - AppLayout.accountListMinimumWidth
            - AppLayout.accountDetailMinimumWidth

        XCTAssertGreaterThanOrEqual(
            remainingWidth,
            AppLayout.splitViewSafetyMargin,
            "账号页不应通过内部最小宽度挤压主导航侧栏"
        )
    }

    func testAppRuntimeRoutesModelCallsThroughLiveTransportAndClosesIt() async {
        let transport = RuntimeRecordingTransport()
        let runtime = AppRuntime(
            preferences: AppPreferences(defaults: isolatedDefaults()),
            transport: transport
        )

        await runtime.model.refreshAccounts()
        await runtime.shutdown()

        let calledMethods = await transport.calledMethods()
        let wasClosed = await transport.wasClosed()
        XCTAssertEqual(calledMethods, ["accounts.list"])
        XCTAssertTrue(wasClosed)
        XCTAssertNil(runtime.model.lastErrorMessage)
    }

    func testDefaultSelectionIsAccountsAndSidebarUsesPrimaryOrder() {
        let model = AppModel(coreClient: MockCoreClient())

        XCTAssertEqual(model.selection, .accounts)
        XCTAssertEqual(
            SidebarDestination.allCases,
            [.accounts, .masterDictionary, .backupRestore, .settings]
        )
        XCTAssertEqual(model.connectionState, .disconnected)
    }

    func testAdvancedSettingsNavigationSelectsSettingsAndCreatesOneShotRequest() {
        let model = AppModel(coreClient: MockCoreClient())

        model.navigateToAdvancedSettings()

        XCTAssertEqual(model.selection, .settings)
        XCTAssertEqual(model.requestedSettingsSection, .advanced)

        model.clearSettingsNavigationRequest()
        XCTAssertNil(model.requestedSettingsSection)
    }

    func testRefreshOverviewUpdatesAllLightweightStatus() async {
        let client = MockCoreClient()
        client.overview = makeOverview()
        let model = AppModel(coreClient: client)

        await model.refreshOverview()

        XCTAssertEqual(model.overview.accountCount, 1)
        XCTAssertEqual(model.connectionState, .connected)
        XCTAssertEqual(model.overview.backup.status, .backedUp)
        XCTAssertEqual(model.overview.version.current, "1.2.3")
        XCTAssertEqual(model.activeTasks.map(\.id), ["task-1"])
        XCTAssertFalse(model.isStale)
        XCTAssertNil(model.lastErrorMessage)
    }

    func testEstablishConnectionRefreshesOverviewAfterConnecting() async {
        let client = MockCoreClient()
        client.connection = .init(state: .connected, port: 9222, cdpReachable: true)
        client.overview = makeOverview()
        let model = AppModel(coreClient: client)

        await model.establishConnection()

        XCTAssertEqual(client.establishConnectionCallCount, 1)
        XCTAssertEqual(model.connectionState, .connected)
        XCTAssertEqual(model.overview.accountCount, 1)
        XCTAssertNil(model.lastErrorMessage)
    }

    func testSyncAllAddsReturnedTaskToActivity() async {
        let client = MockCoreClient()
        client.syncTask = .init(
            id: "sync-1",
            type: "dictionaries.syncAll",
            state: .queued,
            cancellable: true,
            progress: nil,
            result: nil,
            error: nil
        )
        let model = AppModel(coreClient: client)

        await model.syncAllDictionaries()

        XCTAssertEqual(client.syncAllCallCount, 1)
        XCTAssertEqual(model.activeTasks.map(\.id), ["sync-1"])
        XCTAssertNil(model.lastErrorMessage)
    }

    func testRefreshOverviewFailureKeepsLastSnapshotAndMarksItStale() async {
        let client = MockCoreClient()
        client.overview = makeOverview()
        let model = AppModel(coreClient: client)
        await model.refreshOverview()
        let lastSnapshot = model.overview

        client.overviewError = CoreError.transport(message: "offline")
        await model.refreshOverview()

        XCTAssertEqual(model.overview, lastSnapshot)
        XCTAssertEqual(model.connectionState, .connected)
        XCTAssertEqual(model.activeTasks.map(\.id), ["task-1"])
        XCTAssertTrue(model.isStale)
        XCTAssertNotNil(model.lastErrorMessage)
    }

    func testAddAccountWorkflowMovesThroughExpectedPhasesAndKeepsCaptureSanitized() async throws {
        let client = MockCoreClient()
        client.connection = .init(state: .connected, port: 9222, cdpReachable: true)
        client.capture = AccountCapture(
            captureID: "capture-1",
            userID: "u2",
            nickname: "新账号",
            email: "new@example.com",
            role: "pro",
            capturedAt: nil
        )
        client.savedAccount = makeAccount(id: "u2", nickname: "新账号")
        let model = AppModel(coreClient: client)
        var phases: [AddAccountPhase] = []
        client.onEstablishConnection = { phases.append(model.addAccountPhase) }
        client.onCaptureCurrentAccount = { phases.append(model.addAccountPhase) }
        client.onSaveCapture = { phases.append(model.addAccountPhase) }

        await model.beginAddAccount()
        phases.append(model.addAccountPhase)
        XCTAssertEqual(model.pendingAccountCapture?.userID, "u2")

        let encodedCapture = try JSONEncoder().encode(model.pendingAccountCapture)
        let encodedText = String(decoding: encodedCapture, as: UTF8.self)
        XCTAssertFalse(encodedText.localizedCaseInsensitiveContains("token"))

        await model.savePendingAccount(nickname: "新账号", email: "new@example.com")
        phases.append(model.addAccountPhase)

        XCTAssertEqual(phases, [.establishingConnection, .capturing, .reviewing, .saving, .completed])
        XCTAssertEqual(client.savedCaptureID, "capture-1")
        XCTAssertEqual(model.accounts.map(\.id), ["u2"])
    }

    func testAddAccountShowsSafeCaptureFailureMessage() async {
        let client = MockCoreClient()
        client.captureError = CoreError.currentAccountUnavailable(
            message: "未在 Typeless 页面中观察到登录授权请求",
            details: .init(recoverable: true, suggestedAction: "accounts.captureCurrent", context: .object([:]))
        )
        let model = AppModel(coreClient: client)

        await model.beginAddAccount()

        XCTAssertEqual(model.addAccountPhase, .failed)
        XCTAssertEqual(model.lastErrorMessage, "无法抓取当前账号：未在 Typeless 页面中观察到登录授权请求")
    }

    func testDeleteAccountIsPreparedBeforeExecution() async {
        let client = MockCoreClient()
        client.confirmation = makeConfirmation(summary: .object([
            "title": .string("删除账号"),
            "message": .string("同时删除本地快照")
        ]))
        client.accounts = [makeAccount(id: "u1", nickname: "待删除")]
        let model = AppModel(coreClient: client)

        await model.prepareDeleteAccount(accountID: "u1", deleteSnapshot: true)

        XCTAssertEqual(client.preparedMethods, ["accounts.delete"])
        XCTAssertEqual(client.deleteAccountCallCount, 0)
        XCTAssertEqual(model.pendingAccountOperation?.kind, .delete)

        await model.confirmPendingAccountOperation()

        XCTAssertEqual(client.deleteAccountCallCount, 1)
        XCTAssertEqual(client.deletedAccountID, "u1")
        XCTAssertEqual(client.usedConfirmationToken, "confirm-1")
        XCTAssertTrue(model.accounts.isEmpty)
    }

    func testSwitchAccountIsPreparedBeforeExecution() async {
        let client = MockCoreClient()
        client.confirmation = makeConfirmation(summary: .object([
            "title": .string("切换账号"),
            "message": .string("Typeless 将重新启动")
        ]))
        client.accounts = [makeAccount(id: "u1", nickname: "目标账号")]
        let model = AppModel(coreClient: client)

        await model.prepareSwitchAccount(accountID: "u1")

        XCTAssertEqual(client.preparedMethods, ["snapshots.switch"])
        XCTAssertEqual(client.switchSnapshotCallCount, 0)
        XCTAssertEqual(model.pendingAccountOperation?.kind, .switchSnapshot)

        await model.confirmPendingAccountOperation()

        XCTAssertEqual(client.switchSnapshotCallCount, 1)
        XCTAssertEqual(client.switchedAccountID, "u1")
        XCTAssertEqual(client.usedConfirmationToken, "confirm-1")
    }

    func testAccountDictionarySearchMatchesTermsCaseInsensitively() async {
        let client = MockCoreClient()
        client.accountDictionaryValue = .init(words: [
            .init(term: "SwiftUI", auto: false),
            .init(term: "Node.js", auto: true),
            .init(term: "苹果原生", auto: false),
        ])
        let model = AppModel(coreClient: client)

        await model.refreshAccountDictionary(accountID: "u1")
        model.dictionarySearchText = "swift"

        XCTAssertEqual(model.filteredAccountDictionaryWords.map(\.term), ["SwiftUI"])
    }

    func testDictionaryBulkInputTrimsDropsEmptyLinesAndDeduplicates() {
        let model = AppModel(coreClient: MockCoreClient())

        let terms = model.normalizedDictionaryTerms(from: "  SwiftUI  \n\nNode.js\nSwiftUI\n node.js \n苹果原生")

        XCTAssertEqual(terms, ["SwiftUI", "Node.js", "苹果原生"])
    }

    func testDeletingDictionaryWordWaitsForServerThenReloadsRemoteDictionary() async {
        let client = MockCoreClient()
        client.accountDictionaryValue = .init(words: [
            .init(term: "保留", auto: false),
            .init(term: "删除我", auto: false),
        ])
        let model = AppModel(coreClient: client)
        await model.refreshAccountDictionary(accountID: "u1")
        client.onDeleteWord = {
            XCTAssertEqual(model.accountDictionary?.words.map(\.term), ["保留", "删除我"])
            client.accountDictionaryValue = .init(words: [.init(term: "保留", auto: false)])
        }

        await model.deleteDictionaryWord("删除我", accountID: "u1")

        XCTAssertEqual(client.deletedDictionaryTerms, ["删除我"])
        XCTAssertEqual(client.accountDictionaryCallCount, 2)
        XCTAssertEqual(model.accountDictionary?.words.map(\.term), ["保留"])
    }

    func testMasterReplacementShowsDiffAndRequiresConfirmationBeforeWriting() async {
        let client = MockCoreClient()
        client.masterDictionaryValue = .init(words: ["保留", "移除"])
        client.confirmation = makeConfirmation(summary: .object(["title": .string("替换主词库")]))
        let model = AppModel(coreClient: client)
        await model.refreshMasterDictionary()

        await model.prepareMasterReplacement(from: "保留\n新增\n新增")

        XCTAssertEqual(model.pendingMasterReplacement?.diff.added, ["新增"])
        XCTAssertEqual(model.pendingMasterReplacement?.diff.removed, ["移除"])
        XCTAssertEqual(model.pendingMasterReplacement?.diff.unchanged, ["保留"])
        XCTAssertEqual(client.preparedMethods, ["master.replace"])
        XCTAssertEqual(client.replaceMasterCallCount, 0)

        client.masterDictionaryValue = .init(words: ["保留", "新增"])
        await model.confirmMasterReplacement()

        XCTAssertEqual(client.replaceMasterCallCount, 1)
        XCTAssertEqual(client.replacedMasterTerms, ["保留", "新增"])
        XCTAssertEqual(client.usedConfirmationToken, "confirm-1")
        XCTAssertEqual(model.masterDictionary.words, ["保留", "新增"])
    }

    func testMasterReplacementHandlesExistingTermsThatDifferOnlyByCase() async {
        let client = MockCoreClient()
        client.masterDictionaryValue = .init(words: ["Swift", "swift", "移除"])
        client.confirmation = makeConfirmation(summary: .object(["title": .string("替换主词库")]))
        let model = AppModel(coreClient: client)
        await model.refreshMasterDictionary()

        await model.prepareMasterReplacement(from: "SWIFT\n新增")

        XCTAssertEqual(model.pendingMasterReplacement?.diff.added, ["新增"])
        XCTAssertEqual(model.pendingMasterReplacement?.diff.removed, ["移除"])
        XCTAssertEqual(model.pendingMasterReplacement?.diff.unchanged, ["SWIFT"])
        XCTAssertEqual(client.preparedMethods, ["master.replace"])
    }

    func testSingleAccountSyncAppearsInGlobalTaskProgress() async {
        let client = MockCoreClient()
        client.accountSyncTask = .init(
            id: "sync-u1", type: "sync-account", state: .running, cancellable: true,
            progress: .init(phase: "syncing", completed: 0, total: 1, message: "正在同步"),
            result: nil, error: nil
        )
        let model = AppModel(coreClient: client)

        await model.syncAccountDictionary(accountID: "u1")

        XCTAssertEqual(client.syncedAccountIDs, ["u1"])
        XCTAssertEqual(model.activeTasks.map(\.id), ["sync-u1"])
        XCTAssertEqual(model.dictionaryTask(for: "u1")?.progress?.message, "正在同步")
    }

    func testCancellingSyncAllRequestsBoundaryCancellationWithoutOptimisticRemoval() async {
        let client = MockCoreClient()
        let task = CoreTask(
            id: "sync-all", type: "sync-all", state: .running, cancellable: true,
            progress: .init(phase: "syncing", completed: 1, total: 3, message: "正在同步 1/3"),
            result: nil, error: nil
        )
        client.overview = makeOverview(activeTasks: [task])
        let model = AppModel(coreClient: client)
        await model.refreshOverview()

        await model.cancelTask(id: "sync-all")

        XCTAssertEqual(client.cancelledTaskIDs, ["sync-all"])
        XCTAssertEqual(model.activeTasks.map(\.id), ["sync-all"])
        XCTAssertEqual(model.taskCancellationNotice, "将在当前账号同步结束后取消")
    }

    func testBackupRestoreMovesThroughInspectionReviewConfirmationAndCompletion() async {
        let client = MockCoreClient()
        client.confirmation = makeConfirmation(summary: .object(["title": .string("恢复备份")]))
        let model = AppModel(coreClient: client)
        var phases: [BackupRestorePhase] = []
        client.onInspectBackup = { phases.append(model.backupRestorePhase) }
        client.onPrepareOperation = { method in
            if method == "backup.restore" { phases.append(model.backupRestorePhase) }
        }
        client.onRestoreBackup = { phases.append(model.backupRestorePhase) }

        model.beginBackupSelection()
        phases.append(model.backupRestorePhase)
        await model.inspectBackup(at: "/tmp/runtime-backup.json")
        phases.append(model.backupRestorePhase)
        await model.prepareBackupRestore()
        await model.confirmBackupRestore()
        phases.append(model.backupRestorePhase)

        XCTAssertEqual(phases, [.selecting, .inspecting, .reviewing, .preparingConfirmation, .restoring, .completed])
        XCTAssertEqual(client.inspectedBackupPaths, ["/tmp/runtime-backup.json"])
        XCTAssertEqual(client.preparedMethods, ["backup.restore"])
        XCTAssertEqual(client.restoredInspectionIDs, ["inspection-1"])
        XCTAssertEqual(client.usedConfirmationToken, "confirm-1")
        XCTAssertEqual(model.activeTasks.map(\.id), ["restore-1"])
    }

    func testCancellingBackupConfirmationReturnsToReviewedInspection() async {
        let client = MockCoreClient()
        let model = AppModel(coreClient: client)
        model.beginBackupSelection()
        await model.inspectBackup(at: "/tmp/runtime-backup.json")
        await model.prepareBackupRestore()

        model.cancelBackupRestoreConfirmation()

        XCTAssertEqual(model.backupRestorePhase, .reviewing)
        XCTAssertEqual(model.pendingBackupInspection?.inspectionID, "inspection-1")
        XCTAssertNil(model.pendingBackupRestore)
    }

    func testBackupChangedDuringRestoreReturnsToReviewAndRequiresReinspection() async {
        let client = MockCoreClient()
        client.confirmation = makeConfirmation(summary: .object(["title": .string("恢复备份")]))
        client.restoreError = CoreError.backupChanged(
            message: "备份文件在检查后发生变化",
            details: .init(recoverable: true, suggestedAction: "backup.inspect", context: .object([:]))
        )
        let model = AppModel(coreClient: client)
        model.beginBackupSelection()
        await model.inspectBackup(at: "/tmp/runtime-backup.json")
        await model.prepareBackupRestore()

        await model.confirmBackupRestore()

        XCTAssertEqual(model.backupRestorePhase, .reviewing)
        XCTAssertTrue(model.requiresBackupReinspection)
        XCTAssertNil(model.pendingBackupInspection)
        XCTAssertEqual(client.restoredInspectionIDs, ["inspection-1"])

        await model.prepareBackupRestore()
        XCTAssertEqual(client.preparedMethods, ["backup.restore"])
    }

    func testDeviceResetAndPatchCannotExecuteBeforeConfirmation() async {
        let client = MockCoreClient()
        client.confirmation = makeConfirmation(summary: .object(["title": .string("高风险操作")]))
        let model = AppModel(coreClient: client)

        await model.confirmDeviceReset()
        await model.confirmPatchApplication()
        XCTAssertEqual(client.resetDeviceCallCount, 0)
        XCTAssertTrue(client.patchApplyActions.isEmpty)

        await model.prepareDeviceReset()
        XCTAssertEqual(client.preparedMethods, ["device.reset"])
        XCTAssertEqual(client.resetDeviceCallCount, 0)
        await model.confirmDeviceReset()

        await model.preparePatchApplication(action: "apply")
        XCTAssertEqual(client.preparedMethods, ["device.reset", "patch.apply"])
        XCTAssertTrue(client.patchApplyActions.isEmpty)
        await model.confirmPatchApplication()

        XCTAssertEqual(client.resetDeviceCallCount, 1)
        XCTAssertEqual(client.patchApplyActions, ["apply"])
        XCTAssertEqual(model.activeTasks.map(\.id), ["reset-1", "patch-1"])
    }

    func testBackupActionsRefreshStatusAndKeepExportPath() async {
        let client = MockCoreClient()
        client.backupStatusValue = makeOverview().backup
        client.exportedPath = .init(path: "/tmp/typeless-export.json")
        let model = AppModel(coreClient: client)

        await model.refreshBackupStatus()
        await model.createBackup()
        await model.exportBackup(to: "/chosen/export.json")

        XCTAssertEqual(model.backupStatus.status, .backedUp)
        XCTAssertEqual(client.createBackupCallCount, 1)
        XCTAssertEqual(client.exportedBackupPaths, ["/chosen/export.json"])
        XCTAssertEqual(model.exportedBackupPath, "/tmp/typeless-export.json")
    }

    func testDiagnosticsAndAdvancedStatusAreLoadedFromSanitizedCoreDTOs() async {
        let client = MockCoreClient()
        let overview = makeOverview()
        client.diagnosticReportValue = DiagnosticReport(
            typeless: .init(appPath: "/Applications/Typeless.app", appFound: true, binPath: "/bin", binFound: true, asarPath: "/app.asar", asarFound: true, infoPlist: "/Info.plist", infoPlistFound: true, userDataDirectory: "/data", userDataFound: true),
            cdp: .init(port: 9222, reachable: false, state: .disconnected),
            data: .init(directory: "/toolkit", codeDirectory: "/code", writable: true, migration: .object(["status": .string("none")]), accountsFile: "/toolkit/accounts.json", accountCount: 2, profilesDirectory: "/profiles", runtimeBackupsDirectory: "/backups", backup: overview.backup),
            connection: overview.connection,
            version: overview.version,
            backup: overview.backup,
            patch: overview.patch
        )
        client.deviceStatusValue = .init(connection: overview.connection, backup: overview.backup)
        client.patchStatusValue = overview.patch
        client.versionStatusValue = overview.version
        let model = AppModel(coreClient: client)

        await model.runDiagnostics()
        await model.refreshAdvancedTools()
        await model.acknowledgeCurrentVersion()

        XCTAssertEqual(model.diagnosticReport?.data.accountCount, 2)
        XCTAssertEqual(model.deviceStatus?.connection.state, .connected)
        XCTAssertEqual(model.advancedPatchStatus?.patched, true)
        XCTAssertEqual(model.advancedVersionStatus?.current, "1.2.3")
        XCTAssertEqual(client.diagnosticsCallCount, 1)
        XCTAssertEqual(client.acknowledgeVersionCallCount, 1)
    }

    func testPreferencesPersistMenuBarWindowRefreshAndNotificationChoices() {
        let defaults = isolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)

        preferences.showsMenuBarExtra = false
        preferences.quitAfterLastWindowClosed = false
        preferences.refreshOnActivation = false
        preferences.notificationsEnabled = true

        let restored = AppPreferences(defaults: defaults)
        XCTAssertFalse(restored.showsMenuBarExtra)
        XCTAssertFalse(restored.quitAfterLastWindowClosed)
        XCTAssertFalse(restored.refreshOnActivation)
        XCTAssertTrue(restored.notificationsEnabled)
        XCTAssertFalse(AppDelegate(preferences: restored).applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    func testMenuBarExtraDefaultsOffAndPersistsExplicitChoices() {
        let defaults = isolatedDefaults()

        let fresh = AppPreferences(defaults: defaults)
        XCTAssertFalse(fresh.showsMenuBarExtra)

        fresh.showsMenuBarExtra = true
        XCTAssertTrue(AppPreferences(defaults: defaults).showsMenuBarExtra)

        fresh.showsMenuBarExtra = false
        XCTAssertFalse(AppPreferences(defaults: defaults).showsMenuBarExtra)
    }

    func testForegroundRefreshHonorsPreference() async {
        let defaults = isolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)
        preferences.refreshOnActivation = false
        let client = MockCoreClient()
        let model = AppModel(coreClient: client, preferences: preferences)

        await model.handleAppBecameActive()
        XCTAssertEqual(client.getOverviewCallCount, 0)

        preferences.refreshOnActivation = true
        await model.handleAppBecameActive()
        XCTAssertEqual(client.getOverviewCallCount, 1)
    }

    func testRecentActivityKeepsLatestOneHundredAndCanBeCleared() {
        let store = RecentActivityStore(defaults: isolatedDefaults())

        for index in 0..<105 {
            store.record(title: "活动 \(index)", detail: nil, kind: .information)
        }

        XCTAssertEqual(store.activities.count, 100)
        XCTAssertEqual(store.activities.first?.title, "活动 104")
        XCTAssertEqual(store.activities.last?.title, "活动 5")

        store.clear()
        XCTAssertTrue(store.activities.isEmpty)
    }

    func testCompletedTaskRecordsActivityAndNotificationWhenEnabled() async {
        let preferences = AppPreferences(defaults: isolatedDefaults())
        preferences.notificationsEnabled = true
        let store = RecentActivityStore(defaults: isolatedDefaults())
        let notifications = MockNotificationCenter()
        let client = MockCoreClient()
        client.syncTask = .init(
            id: "sync-complete",
            type: "dictionaries.syncAll",
            state: .succeeded,
            cancellable: false,
            progress: nil,
            result: nil,
            error: nil
        )
        let model = AppModel(
            coreClient: client,
            preferences: preferences,
            activityStore: store,
            notificationCenter: notifications
        )

        await model.syncAllDictionaries()

        XCTAssertEqual(model.recentActivities.first?.title, "同步全部词库完成")
        XCTAssertEqual(notifications.delivered.map(\.title), ["同步全部词库完成"])
    }

    func testDebugLoggingIsSessionOnlyAndActivityLimitIsApplied() {
        let defaults = isolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)
        preferences.diagnosticLogLevel = .debug
        preferences.recentActivityLimit = 25

        let restarted = AppPreferences(defaults: defaults)
        XCTAssertEqual(restarted.diagnosticLogLevel, .info)
        XCTAssertEqual(restarted.recentActivityLimit, 25)

        let store = RecentActivityStore(defaults: isolatedDefaults())
        store.updateLimit(25)
        for index in 0..<30 {
            store.record(title: "活动 \(index)", detail: nil, kind: .information)
        }
        XCTAssertEqual(store.activities.count, 25)
    }

    func testLoadRotationUpdatesRotationSettingsAndStatus() async {
        let client = MockCoreClient()
        let settings = RotationSettings(
            enabled: true,
            mode: .auto,
            wordThreshold: 3000,
            warningWords: 200,
            intervalMinutes: 10
        )
        let status = RotationStatus(
            phase: .waiting,
            message: "等待检查用量",
            lastCheckAt: nil,
            nextCheckAt: nil,
            currentUserId: "u1",
            usedWords: 1500,
            lastResult: nil,
            issue: nil,
            candidateIssues: [],
            notificationError: nil
        )
        client.rotationValue = RotationViewPayload(settings: settings, status: status)
        let model = AppModel(coreClient: client)

        await model.loadRotation()

        XCTAssertEqual(client.rotationCallCount, 1)
        XCTAssertEqual(model.rotationSettings.enabled, true)
        XCTAssertEqual(model.rotationSettings.mode, .auto)
        XCTAssertEqual(model.rotationSettings.wordThreshold, 3000)
        XCTAssertEqual(model.rotationStatus.phase, .waiting)
        XCTAssertEqual(model.rotationStatus.usedWords, 1500)
    }

    func testUpdateRotationSettingsCallsCoreClientAndRecordsActivity() async {
        let client = MockCoreClient()
        let store = RecentActivityStore(defaults: isolatedDefaults())
        let model = AppModel(coreClient: client, activityStore: store)
        let targetSettings = RotationSettings(
            enabled: true,
            mode: .notify,
            wordThreshold: 2000,
            warningWords: 100,
            intervalMinutes: 15
        )

        await model.updateRotationSettings(targetSettings)

        XCTAssertEqual(client.configureRotationCallCount, 1)
        XCTAssertEqual(model.rotationSettings.enabled, true)
        XCTAssertEqual(model.rotationSettings.wordThreshold, 2000)
        XCTAssertEqual(model.recentActivities.first?.title, "保存轮动设置")
        XCTAssertTrue(model.recentActivities.first?.detail?.contains("2000") ?? false)
    }

    func testTriggerRotationCheckNowUpdatesStatusAndRecordsActivity() async {
        let client = MockCoreClient()
        let store = RecentActivityStore(defaults: isolatedDefaults())
        let model = AppModel(coreClient: client, activityStore: store)
        let checkedStatus = RotationStatus(
            phase: .prompting,
            message: "当前账号本周词数已达 2000 词，建议切换",
            lastCheckAt: Date(),
            nextCheckAt: nil,
            currentUserId: "u1",
            usedWords: 2050,
            lastResult: "达到阈值",
            issue: nil,
            candidateIssues: [],
            notificationError: nil
        )
        client.rotationValue = RotationViewPayload(settings: .default, status: checkedStatus)

        await model.triggerRotationCheckNow()

        XCTAssertEqual(client.checkRotationNowCallCount, 1)
        XCTAssertEqual(model.rotationStatus.phase, .prompting)
        XCTAssertEqual(model.rotationStatus.usedWords, 2050)
        XCTAssertEqual(model.recentActivities.first?.title, "轮动检查")
        XCTAssertEqual(model.recentActivities.first?.detail, "当前账号本周词数已达 2000 词，建议切换")
    }

    func testRefreshOverviewSyncsRotationStatus() async {
        let client = MockCoreClient()
        var overview = makeOverview()
        let rotationStatus = RotationStatus(
            phase: .waiting,
            message: "轮动正常运行",
            lastCheckAt: Date(),
            nextCheckAt: nil,
            currentUserId: "u1",
            usedWords: 800,
            lastResult: nil,
            issue: nil,
            candidateIssues: [],
            notificationError: nil
        )
        overview.rotation = rotationStatus
        client.overview = overview
        let model = AppModel(coreClient: client)

        await model.refreshOverview()

        XCTAssertEqual(model.rotationStatus.phase, .waiting)
        XCTAssertEqual(model.rotationStatus.usedWords, 800)
        XCTAssertEqual(model.rotationStatus.message, "轮动正常运行")
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "TypelessSwitchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeConfirmation(summary: JSONValue) -> Confirmation {
        Confirmation(token: "confirm-1", expiresAt: Date(timeIntervalSince1970: 4_000_000_000), summary: summary)
    }

    private func makeAccount(id: String, nickname: String) -> Account {
        let data = Data(#"{"user_id":"\#(id)","nickname":"\#(nickname)","has_snapshot":true}"#.utf8)
        return try! JSONDecoder().decode(Account.self, from: data)
    }

    private func makeOverview(activeTasks: [CoreTask]? = nil) -> SystemOverview {
        SystemOverview(
            connection: .init(state: .connected, port: 9222, cdpReachable: true),
            accounts: [makeAccount()],
            version: .init(current: "1.2.3", lastSeen: "1.2.3", drifted: false, recordedAt: nil),
            backup: .init(
                status: .backedUp,
                backedUp: true,
                hasData: true,
                sources: [],
                latestDataModifiedAt: nil,
                latestBackup: nil,
                backupDirectory: "/tmp/backups",
                backupPath: "/tmp/backups/latest"
            ),
            patch: .init(exists: true, patched: true, detectedFile: nil, filePath: nil, replacementsSource: nil, hasBackup: true, error: nil),
            activeTasks: activeTasks ?? [
                .init(id: "task-1", type: "dictionaries.syncAll", state: .running, cancellable: true, progress: nil, result: nil, error: nil)
            ]
        )
    }

    private func makeAccount() -> Account {
        let data = Data(#"{"user_id":"u1","nickname":"测试账号","has_snapshot":true}"#.utf8)
        return try! JSONDecoder().decode(Account.self, from: data)
    }
}

private actor RuntimeRecordingTransport: RPCTransportProtocol {
    private var methods: [String] = []
    private var closed = false

    func call(method: String, params: JSONValue) async throws -> JSONValue {
        methods.append(method)
        return .object(["accounts": .array([])])
    }

    func close() async {
        closed = true
    }

    func calledMethods() -> [String] { methods }
    func wasClosed() -> Bool { closed }
}
