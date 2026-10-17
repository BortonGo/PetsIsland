import XCTest
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

    func testVerifiedTipIsFinishedOnceAcrossDuplicateDeliveries() async {
        let client = SupportCommerceStub(), before = PetHabitatStore.load()
        let store = AuthorSupportStore(commerce: client)
        await store.load()
        await store.purchase(client.product(.small))
        await store.accept(client.receipt())
        XCTAssertEqual(client.finished, [1])
        XCTAssertEqual(store.notice, .thanks)
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
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PetIslandTips", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let commerce = StoreKitSupportCommerce()
        let products = try await commerce.products()
        XCTAssertEqual(Set(products.map(\.id)), AuthorTip.productIDs)
        let store = AuthorSupportStore(commerce: commerce)
        await store.load()
        let product = try XCTUnwrap(store.products.first)
        // Use the StoreKit Test server to create purchases, never a real
        // account or a payment dialog in an unattended hosted unit test.
        _ = try await session.buyProduct(identifier: product.id)
        _ = try await session.buyProduct(identifier: product.id)
        for transaction in await commerce.unfinished() { await store.accept(transaction) }
        XCTAssertEqual(store.notice, .thanks)
        XCTAssertEqual(session.allTransactions().count, 2)
        let unfinished = await commerce.unfinished()
        XCTAssertTrue(unfinished.isEmpty)
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
    func product(_ kind: AuthorTip) -> SupportProduct { .init(id: kind.id, title: "A thank-you", price: "1,99 €") }
    func receipt() -> SupportTransaction { .init(id: 1, productID: AuthorTip.small.id, verified: true, revoked: false) }
    func products() async throws -> [SupportProduct] {
        if shouldFail { throw SupportPurchaseError.unavailable }
        return catalog ?? AuthorTip.allCases.map(product)
    }
    func purchase(_ id: String) async throws -> SupportPurchaseResult {
        purchaseCount += 1
        if shouldFail { throw SupportPurchaseError.unavailable }
        return result ?? .completed(receipt())
    }
    func updates() -> AsyncStream<SupportTransaction> {
        observerCount += 1
        return AsyncStream { continuation = $0 }
    }
    func unfinished() async -> [SupportTransaction] { unfinishedTransactions }
    func finish(_ id: UInt64) async { finished.append(id) }
}
