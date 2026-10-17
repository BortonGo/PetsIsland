import Foundation
import StoreKit
import Combine

enum AuthorTip: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large
    var id: String { "org.bortongo.PetIsland.tip.\(rawValue)" }
    static var productIDs: Set<String> { Set(allCases.map(\.id)) }
}

struct SupportProduct: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let price: String
}

struct SupportTransaction: Sendable {
    let id: UInt64
    let productID: String
    let verified: Bool
    let revoked: Bool
}

enum SupportPurchaseResult: Sendable {
    case completed(SupportTransaction), pending, cancelled
}

enum SupportPurchaseError: Error { case unavailable, verification }

@MainActor
protocol SupportCommerce: AnyObject {
    var canMakePayments: Bool { get }
    func products() async throws -> [SupportProduct]
    func purchase(_ id: String) async throws -> SupportPurchaseResult
    func updates() -> AsyncStream<SupportTransaction>
    func unfinished() async -> [SupportTransaction]
    func finish(_ id: UInt64) async
}

/// Tips never touch the island save, coins, pet state or entitlements.
@MainActor
final class AuthorSupportStore: ObservableObject {
    static let shared = AuthorSupportStore(commerce: StoreKitSupportCommerce())

    enum Notice: Equatable { case thanks, pending, failed, verification, restricted }
    @Published private(set) var products: [SupportProduct] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    @Published private(set) var purchasingID: String?
    @Published private(set) var pendingIDs: Set<String> = []
    @Published private(set) var notice: Notice?
    var canMakePayments: Bool { commerce.canMakePayments }
    private let commerce: any SupportCommerce
    private var listener: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var handled: Set<UInt64> = []

    init(commerce: any SupportCommerce) { self.commerce = commerce }
    deinit { listener?.cancel(); recovery?.cancel() }

    func startObserving() {
        guard listener == nil else { return }
        let events = commerce.updates()
        listener = Task { [weak self] in
            for await transaction in events {
                guard !Task.isCancelled else { break }
                await self?.accept(transaction)
            }
        }
        let commerce = commerce
        recovery = Task { [weak self] in
            for transaction in await commerce.unfinished() {
                guard !Task.isCancelled else { break }
                await self?.accept(transaction)
            }
        }
    }

    func load() async {
        guard !isLoading, purchasingID == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await commerce.products()
            // The server may return only products available in this storefront.
            products = AuthorTip.allCases.compactMap { kind in fetched.first { $0.id == kind.id } }
            loadFailed = false
        } catch {
            products = []
            loadFailed = true
        }
    }

    func purchase(_ product: SupportProduct) async {
        guard purchasingID == nil, !isLoading, !pendingIDs.contains(product.id),
              products.contains(product), AuthorTip.productIDs.contains(product.id) else { return }
        guard commerce.canMakePayments else { notice = .restricted; return }
        purchasingID = product.id
        notice = nil
        defer { purchasingID = nil }
        do {
            switch try await commerce.purchase(product.id) {
            case .completed(let transaction): await accept(transaction)
            case .pending:
                if notice != .thanks {
                    pendingIDs.insert(product.id)
                    notice = .pending
                }
            case .cancelled: break
            }
        } catch is CancellationError {
            // Dismissing Apple's payment sheet is not a failed payment.
        } catch SupportPurchaseError.verification {
            notice = .verification
        } catch {
            if notice != .thanks { notice = .failed }
        }
    }

    func accept(_ transaction: SupportTransaction) async {
        guard AuthorTip.productIDs.contains(transaction.productID) else { return }
        guard transaction.verified else { notice = .verification; return }
        guard handled.insert(transaction.id).inserted else { return }
        pendingIDs.remove(transaction.productID)
        if !transaction.revoked { notice = .thanks }
        // There is no consumable game benefit to grant. Acknowledge verified tips
        // even when delivered after a relaunch or while the support screen is closed.
        await commerce.finish(transaction.id)
    }
}

@MainActor
final class StoreKitSupportCommerce: SupportCommerce {
    private var catalog: [String: Product] = [:]
    private var transactions: [UInt64: Transaction] = [:]
    private var finished: Set<UInt64> = []
    var canMakePayments: Bool { AppStore.canMakePayments }

    func products() async throws -> [SupportProduct] {
        let items = try await Product.products(for: AuthorTip.productIDs)
            .filter { $0.type == .consumable }
        catalog = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return items.map { SupportProduct(id: $0.id, title: $0.displayName, price: $0.displayPrice) }
    }

    func purchase(_ id: String) async throws -> SupportPurchaseResult {
        guard let product = catalog[id] else { throw SupportPurchaseError.unavailable }
        switch try await product.purchase() {
        case .success(let result): return .completed(record(result))
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: throw SupportPurchaseError.unavailable
        }
    }

    func updates() -> AsyncStream<SupportTransaction> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled, let self else { break }
                    continuation.yield(self.record(result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func unfinished() async -> [SupportTransaction] {
        var results: [SupportTransaction] = []
        for await result in Transaction.unfinished { results.append(record(result)) }
        return results
    }

    func finish(_ id: UInt64) async {
        guard let transaction = transactions.removeValue(forKey: id) else { return }
        finished.insert(id)
        await transaction.finish()
    }

    private func record(_ result: VerificationResult<Transaction>) -> SupportTransaction {
        switch result {
        case .verified(let transaction):
            if AuthorTip.productIDs.contains(transaction.productID), !finished.contains(transaction.id) {
                transactions[transaction.id] = transaction
            }
            return SupportTransaction(id: transaction.id, productID: transaction.productID,
                                      verified: true, revoked: transaction.revocationDate != nil)
        case .unverified(let transaction, _):
            return SupportTransaction(id: transaction.id, productID: transaction.productID,
                                      verified: false, revoked: transaction.revocationDate != nil)
        }
    }
}
