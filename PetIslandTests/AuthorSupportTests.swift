import XCTest
import Combine
import StoreKit
import StoreKitTest
@testable import PetIsland

@MainActor
final class AuthorSupportTests: XCTestCase {
    func testCatalogRejectsUnknownProductsAndUsesStorePrices() async {
        let client = SupportCommerceStub()
        client.catalog = [client.product(.large), .init(id: "unknown", title: "Unknown", price: "$0"), client.product(.small)]
        let store = AuthorSupportStore(commerce: client)
        await store.load()
        XCTAssertEqual(store.products.map(\.id), [AuthorTip.small.id, AuthorTip.large.id])
        XCTAssertEqual(store.products.first?.price, "1,99 €")
    }

    func testEmptyAndFailedCatalogCanRecover() async {
        let client = SupportCommerceStub()
        let model = AuthorSupportStore(commerce: client)
        client.shouldFail = true
        await model.load()
        XCTAssertTrue(model.loadFailed)
        XCTAssertTrue(model.products.isEmpty)
        client.shouldFail = false
        await model.load()
        XCTAssertFalse(model.loadFailed)
        XCTAssertEqual(model.products.count, 3)
        client.catalog = []
        await model.load()
        XCTAssertTrue(model.products.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    func testCancellationAndFailureDoNotAcknowledgeAPayment() async {
        let client = SupportCommerceStub(), before = PetHabitatStore.load()
        let model = AuthorSupportStore(commerce: client)
        await model.load()
        client.result = .cancelled
        await model.purchase(client.product(.small))
        XCTAssertNil(model.notice)
        XCTAssertNil(model.purchasingID)
        client.shouldFail = true
        await model.purchase(client.product(.small))
        XCTAssertEqual(model.notice, .failed)
        XCTAssertTrue(client.finished.isEmpty)
        XCTAssertEqual(PetHabitatStore.load(), before)
    }

    func testPendingPurchaseCannotBeSubmittedAgainUntilApproved() async {
        let client = SupportCommerceStub()
        let store = AuthorSupportStore(commerce: client)
        await store.load()
        client.result = .pending
        await store.purchase(client.product(.small))
        await store.purchase(client.product(.small))
        XCTAssertEqual(client.purchaseCount, 1)
        XCTAssertEqual(store.notice, .pending)
        await store.accept(client.receipt())
        XCTAssertEqual(store.notice, .thanks)
        XCTAssertTrue(store.pendingIDs.isEmpty)
        XCTAssertEqual(client.finished, [1])
    }

    func testPendingPurchaseCanBeExplicitlyRetriedAfterDecline() async {
        let client = SupportCommerceStub()
        let store = AuthorSupportStore(commerce: client)
        await store.load()
        client.result = .pending
        await store.purchase(client.product(.small))
        // A declined Ask to Buy request sends no transaction update.
        client.result = .completed(client.receipt())
        await store.purchase(client.product(.small), retryPending: true)
        XCTAssertEqual(client.purchaseCount, 2)
        XCTAssertEqual(store.notice, .thanks)
        XCTAssertTrue(store.pendingIDs.isEmpty)
        XCTAssertEqual(client.finished, [1])
    }

    func testApprovalWhileRetryConfirmationIsOpenPreventsAnotherPayment() async {
        let client = SupportCommerceStub()
        let store = AuthorSupportStore(commerce: client)
        await store.load()
        client.result = .pending
        await store.purchase(client.product(.small))
        await store.accept(client.receipt())
        await store.purchase(client.product(.small), retryPending: true)
        XCTAssertEqual(client.purchaseCount, 1)
        XCTAssertEqual(store.notice, .thanks)
    }

    func testActivePurchaseRejectsDuplicateRequestsIncludingExplicitRetry() async {
        let client = SupportCommerceStub()
        let store = AuthorSupportStore(commerce: client)
        await store.load()
        client.result = .pending
        await store.purchase(client.product(.small))
        client.pausesPurchases = true
        let purchase = Task { await store.purchase(client.product(.small), retryPending: true) }
        await client.waitForPausedPurchase()
        await store.purchase(client.product(.small))
        await store.purchase(client.product(.small), retryPending: true)
        XCTAssertEqual(client.purchaseCount, 2)
        XCTAssertEqual(store.purchasingID, AuthorTip.small.id)
        client.resumePurchase(with: .success(.pending))
        await purchase.value
        XCTAssertNil(store.purchasingID)
    }

    func testUnrelatedApprovalDoesNotHidePendingOrFailedPurchase() async {
        let outcomes: [(Result<SupportPurchaseResult, Error>, AuthorSupportStore.Notice)] = [
            (.success(.pending), .pending),
            (.failure(SupportPurchaseError.unavailable), .failed)
        ]
        for (outcome, expectedNotice) in outcomes {
            let client = SupportCommerceStub()
            let store = AuthorSupportStore(commerce: client)
            await store.load()
            client.pausesPurchases = true
            let purchase = Task { await store.purchase(client.product(.small)) }
            await client.waitForPausedPurchase()
            await store.accept(.init(id: 2, productID: AuthorTip.medium.id, verified: true, revoked: false))
            client.resumePurchase(with: outcome)
            await purchase.value
            XCTAssertEqual(store.notice, expectedNotice)
            XCTAssertEqual(store.pendingIDs.contains(AuthorTip.small.id), expectedNotice == .pending)
            XCTAssertEqual(client.finished, [2])
            XCTAssertNil(store.purchasingID)
        }
    }

    func testMatchingApprovalPreservesSuccessWhenPurchaseReturnsLate() async {
        let outcomes: [Result<SupportPurchaseResult, Error>] = [
            .success(.pending),
            .failure(SupportPurchaseError.unavailable),
            .failure(SupportPurchaseError.verification)
        ]
        for outcome in outcomes {
            let client = SupportCommerceStub()
            let store = AuthorSupportStore(commerce: client)
            await store.load()
            client.pausesPurchases = true
            let purchase = Task { await store.purchase(client.product(.small)) }
            await client.waitForPausedPurchase()
            await store.accept(client.receipt())
            client.resumePurchase(with: outcome)
            await purchase.value
            XCTAssertEqual(store.notice, .thanks)
            XCTAssertTrue(store.pendingIDs.isEmpty)
            XCTAssertEqual(client.finished, [1])
            XCTAssertNil(store.purchasingID)
            client.pausesPurchases = false
            client.shouldFail = true
            await store.purchase(client.product(.small))
            XCTAssertEqual(store.notice, .failed, "Confirmation must not carry into a later purchase")
        }
    }

    func testEveryPurchaseOutcomeWaitsForMatchingTransactionToFinish() async {
        let receipt = SupportTransaction(id: 1, productID: AuthorTip.small.id, verified: true, revoked: false)
        let outcomes: [Result<SupportPurchaseResult, Error>] = [
            .success(.completed(receipt)), .success(.pending), .success(.cancelled),
            .failure(SupportPurchaseError.unavailable), .failure(SupportPurchaseError.verification),
            .failure(CancellationError())
        ]
        for outcome in outcomes {
            let client = SupportCommerceStub()
            let store = AuthorSupportStore(commerce: client)
            await store.load()
            client.pausesPurchases = true
            client.pausesFinishing = true
            let purchaseReturned = XCTestExpectation(description: "Purchase returned after finishing")
            let purchase = Task {
                await store.purchase(client.product(.small))
                purchaseReturned.fulfill()
            }
            await client.waitForPausedPurchase()
            let update = Task { await store.accept(receipt) }
            await client.waitForPausedFinish()
            client.resumePurchase(with: outcome)
            let earlyReturn = await XCTWaiter.fulfillment(of: [purchaseReturned], timeout: 0.05)
            XCTAssertEqual(earlyReturn, .timedOut)
            XCTAssertEqual(store.purchasingID, AuthorTip.small.id)
            XCTAssertEqual(client.finished, [1])
            client.resumeFinish()
            await update.value
            await purchase.value
            XCTAssertNil(store.purchasingID)
            XCTAssertEqual(store.notice, .thanks)
            XCTAssertEqual(client.finished, [1])
        }
    }

    func testPurchaseWaitsForStandaloneRecoveryBeforeCallingCommerce() async {
        let outcomes: [(Result<SupportPurchaseResult, Error>, AuthorSupportStore.Notice)] = [
            (.success(.pending), .pending),
            (.failure(SupportPurchaseError.unavailable), .failed)
        ]
        for (outcome, expectedNotice) in outcomes {
            let client = SupportCommerceStub()
            let store = AuthorSupportStore(commerce: client)
            await store.load()
            client.pausesFinishing = true
            let recovery = Task { await store.accept(client.receipt()) }
            await client.waitForPausedFinish()
            XCTAssertNil(store.purchasingID)
            let busy = XCTestExpectation(description: "Purchase acquired busy guard")
            let observation = store.$purchasingID.sink { id in
                if id == AuthorTip.small.id { busy.fulfill() }
            }
            client.pausesPurchases = true
            let purchase = Task { await store.purchase(client.product(.small)) }
            let started = await XCTWaiter.fulfillment(of: [busy], timeout: 1)
            XCTAssertEqual(started, .completed)
            observation.cancel()
            XCTAssertEqual(store.purchasingID, AuthorTip.small.id)
            XCTAssertEqual(client.purchaseCount, 0)
            await store.purchase(client.product(.small))
            XCTAssertEqual(client.purchaseCount, 0)
            client.resumeFinish()
            await recovery.value
            await client.waitForPausedPurchase()
            XCTAssertEqual(client.purchaseCount, 1)
            client.resumePurchase(with: outcome)
            await purchase.value
            XCTAssertEqual(store.notice, expectedNotice)
            XCTAssertEqual(store.pendingIDs.contains(AuthorTip.small.id), expectedNotice == .pending)
            XCTAssertNil(store.purchasingID)
        }
    }

    func testUnverifiedUnknownAndRevokedTransactionsCannotGrantThanks() async {
        let client = SupportCommerceStub(), store = AuthorSupportStore(commerce: SupportCommerceStub())
        await store.accept(.init(id: 2, productID: "future.product", verified: true, revoked: false))
        XCTAssertNil(store.notice)
        let model = AuthorSupportStore(commerce: client)
        await model.accept(.init(id: 3, productID: AuthorTip.small.id, verified: false, revoked: false))
        XCTAssertEqual(model.notice, .verification)
        XCTAssertTrue(client.finished.isEmpty)
        await model.accept(.init(id: 4, productID: AuthorTip.small.id, verified: true, revoked: true))
        XCTAssertNotEqual(model.notice, .thanks)
        XCTAssertEqual(client.finished, [4])
    }

    func testVerifiedRedeliveryFinishesAgainWithoutRepeatingThanks() async {
        let client = SupportCommerceStub(), before = PetHabitatStore.load()
        let store = AuthorSupportStore(commerce: client)
        await store.load()
        await store.purchase(client.product(.small))
        XCTAssertEqual(client.finished, [1])
        XCTAssertEqual(store.notice, .thanks)
        client.shouldFail = true
        await store.purchase(client.product(.medium))
        XCTAssertEqual(store.notice, .failed)
        // StoreKit may redeliver a transaction after its previous finish returned.
        await store.accept(client.receipt())
        XCTAssertEqual(client.finished, [1, 1])
        XCTAssertEqual(store.notice, .failed)
        XCTAssertEqual(PetHabitatStore.load(), before)
    }

    func testRestrictedAndUnavailableProductCannotStartPayment() async {
        let client = SupportCommerceStub()
        let store = AuthorSupportStore(commerce: client)
        await store.load()
        client.canMakePayments = false
        await store.purchase(client.product(.small))
        XCTAssertEqual(store.notice, .restricted)
        client.canMakePayments = true
        await store.purchase(.init(id: "unknown", title: "Unknown", price: "$1"))
        XCTAssertEqual(client.purchaseCount, 0)
    }

    func testObserverRecoversUnfinishedTipAndContinuesAfterScreenClosed() async {
        let client = SupportCommerceStub()
        client.unfinishedTransactions = [client.receipt()]
        let store = AuthorSupportStore(commerce: client)
        store.startObserving()
        store.startObserving()
        for _ in 0..<100 where client.finished.count < 1 { await Task.yield() }
        client.continuation?.yield(.init(id: 2, productID: AuthorTip.medium.id, verified: true, revoked: false))
        for _ in 0..<100 where client.finished.count < 2 { await Task.yield() }
        XCTAssertEqual(client.finished, [1, 2])
        XCTAssertEqual(client.observerCount, 1)
    }

    func testRealStoreKitConsumableCanBePurchasedTwiceAndFinished() async throws {
        let session = try localStoreKitSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let commerce = StoreKitSupportCommerce()
        let products = try await commerce.products()
        XCTAssertEqual(Set(products.map(\.id)), AuthorTip.productIDs)
        let store = AuthorSupportStore(commerce: commerce)
        store.startObserving()
        await store.load()
        XCTAssertEqual(Set(store.products.map(\.id)), AuthorTip.productIDs)
        // Exercise the app's actual purchase and finish path. A consumable's
        // first transaction must finish before StoreKit permits another one.
        var purchaseCount = 0
        for product in store.products {
            for _ in 0..<2 {
                await store.purchase(product)
                purchaseCount += 1
                XCTAssertEqual(store.notice, .thanks)
                XCTAssertNil(store.purchasingID)
                XCTAssertEqual(session.allTransactions().count, purchaseCount)
                // StoreKit's transaction cache may briefly lag behind finish().
                let deadline = ContinuousClock.now.advanced(by: .seconds(3))
                var unfinished = await commerce.unfinished()
                while !unfinished.isEmpty, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(20))
                    unfinished = await commerce.unfinished()
                }
                XCTAssertTrue(unfinished.isEmpty, "Unfinished tip: \(product.id), receipts: \(unfinished)")
            }
        }
        XCTAssertEqual(purchaseCount, AuthorTip.allCases.count * 2)
    }

    func testRealStoreKitDeclinedRequestCanRetryAndApprove() async throws {
        let session = try localStoreKitSession()
        session.askToBuyEnabled = true
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let commerce = StoreKitSupportCommerce()
        let store = AuthorSupportStore(commerce: commerce)
        store.startObserving()
        await store.load()
        let product = try XCTUnwrap(store.products.first)
        await store.purchase(product)
        XCTAssertEqual(store.notice, .pending)
        let declined = try XCTUnwrap(session.allTransactions().first(where: \.pendingAskToBuyConfirmation))
        try session.declineAskToBuyTransaction(identifier: declined.identifier)
        await store.purchase(product, retryPending: true)
        XCTAssertEqual(store.notice, .pending)
        let approved = try XCTUnwrap(session.allTransactions().first { $0.pendingAskToBuyConfirmation && $0.identifier != declined.identifier })
        try session.approveAskToBuyTransaction(identifier: approved.identifier)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while store.notice != .thanks, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(store.notice, .thanks)
        XCTAssertTrue(store.pendingIDs.isEmpty)
        session.askToBuyEnabled = false
        await store.purchase(product)
        XCTAssertEqual(store.notice, .thanks)
        let unfinished = await commerce.unfinished()
        XCTAssertTrue(unfinished.isEmpty)
    }

    func testRealStoreKitRecoversAnUnfinishedTip() async throws {
        let session = try localStoreKitSession()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        _ = try await session.buyProduct(identifier: AuthorTip.medium.id)
        let commerce = StoreKitSupportCommerce()
        let store = AuthorSupportStore(commerce: commerce)
        store.startObserving()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var unfinished = await commerce.unfinished()
        while (store.notice != .thanks || !unfinished.isEmpty), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            unfinished = await commerce.unfinished()
        }
        XCTAssertEqual(store.notice, .thanks)
        XCTAssertTrue(unfinished.isEmpty)
        XCTAssertEqual(session.allTransactions().count, 1)
    }

    private func localStoreKitSession() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PetIslandTips", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    func testSupportEmailIsARealMailtoLink() throws {
        let url = try XCTUnwrap(PetSupportContact.emailURL)
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertEqual(url.path, "bortone52@yandex.ru")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "subject")
    }
}

@MainActor
private final class SupportCommerceStub: SupportCommerce {
    var canMakePayments = true
    var shouldFail = false
    var catalog: [SupportProduct]?
    var result: SupportPurchaseResult?
    var purchaseCount = 0
    var observerCount = 0
    var finished: [UInt64] = []
    var unfinishedTransactions: [SupportTransaction] = []
    var continuation: AsyncStream<SupportTransaction>.Continuation?
    var pausesPurchases = false
    var pausesFinishing = false
    private var purchaseContinuation: CheckedContinuation<SupportPurchaseResult, Error>?
    private var purchaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    func product(_ kind: AuthorTip) -> SupportProduct { .init(id: kind.id, title: "A thank-you", price: "1,99 €") }
    func receipt() -> SupportTransaction { .init(id: 1, productID: AuthorTip.small.id, verified: true, revoked: false) }
    func products() async throws -> [SupportProduct] {
        if shouldFail { throw SupportPurchaseError.unavailable }
        return catalog ?? AuthorTip.allCases.map(product)
    }
    func purchase(_ id: String) async throws -> SupportPurchaseResult {
        purchaseCount += 1
        if pausesPurchases {
            return try await withCheckedThrowingContinuation {
                purchaseContinuation = $0
                purchaseWaiters.forEach { $0.resume() }
                purchaseWaiters.removeAll()
            }
        }
        if shouldFail { throw SupportPurchaseError.unavailable }
        return result ?? .completed(receipt())
    }
    func waitForPausedPurchase() async {
        if purchaseContinuation != nil { return }
        await withCheckedContinuation { purchaseWaiters.append($0) }
    }
    func resumePurchase(with result: Result<SupportPurchaseResult, Error>) {
        let continuation = purchaseContinuation
        purchaseContinuation = nil
        continuation?.resume(with: result)
    }
    func updates() -> AsyncStream<SupportTransaction> {
        observerCount += 1
        return AsyncStream { continuation = $0 }
    }
    func unfinished() async -> [SupportTransaction] { unfinishedTransactions }
    func finish(_ id: UInt64) async {
        finished.append(id)
        if pausesFinishing {
            await withCheckedContinuation {
                finishContinuation = $0
                finishWaiters.forEach { $0.resume() }
                finishWaiters.removeAll()
            }
        }
    }
    func waitForPausedFinish() async {
        if finishContinuation != nil { return }
        await withCheckedContinuation { finishWaiters.append($0) }
    }
    func resumeFinish() {
        let continuation = finishContinuation
        finishContinuation = nil
        continuation?.resume()
    }
}
