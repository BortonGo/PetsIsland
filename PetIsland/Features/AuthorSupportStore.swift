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
    private var finishing: [UInt64: (productID: String, token: UUID, task: Task<Void, Never>)] = [:]
    private var activePurchaseConfirmed = false

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

    func purchase(_ product: SupportProduct, retryPending: Bool = false) async {
        // Ask to Buy declines have no transaction callback. Only an explicit
        // retry may resubmit a pending tip; an approval closes that retry path.
        guard !retryPending || pendingIDs.contains(product.id) else { return }
        guard purchasingID == nil, !isLoading,
              retryPending || !pendingIDs.contains(product.id),
              products.contains(product), AuthorTip.productIDs.contains(product.id) else { return }
        guard commerce.canMakePayments else { notice = .restricted; return }
        purchasingID = product.id
        activePurchaseConfirmed = false
        defer { purchasingID = nil; activePurchaseConfirmed = false }
        // A recovered or externally approved tip may still be finishing when
        // the user starts another purchase of the same consumable.
        await waitForFinishingTransactions(for: product.id)
        guard !retryPending || pendingIDs.contains(product.id) else { return }
        activePurchaseConfirmed = false
        notice = pendingIDs.contains(product.id) ? .pending : nil
        do {
            switch try await commerce.purchase(product.id) {
            case .completed(let transaction): await accept(transaction)
            case .pending:
                if activePurchaseConfirmed {
                    notice = .thanks
                } else {
                    pendingIDs.insert(product.id)
                    notice = .pending
                }
            case .cancelled: break
            }
        } catch is CancellationError {
            // Dismissing Apple's payment sheet is not a failed payment.
        } catch SupportPurchaseError.verification {
            notice = activePurchaseConfirmed ? .thanks : .verification
        } catch {
            notice = activePurchaseConfirmed ? .thanks : .failed
        }
        // Updates can approve a tip while purchase() still returns pending,
        // cancellation or an error. Keep the purchase guard until those matching
        // transactions finish, including any received during this wait.
        await waitForFinishingTransactions(for: product.id)
    }

    private func waitForFinishingTransactions(for productID: String) async {
        var awaited: Set<UUID> = []
        while let finish = finishing.values.first(where: {
            $0.productID == productID && !awaited.contains($0.token)
        }) {
            awaited.insert(finish.token)
            await finish.task.value
        }
    }

    func accept(_ transaction: SupportTransaction) async {
        guard AuthorTip.productIDs.contains(transaction.productID) else { return }
        guard transaction.verified else { notice = .verification; return }
        if let finish = finishing[transaction.id] {
            await finish.task.value
            return
        }
        if handled.insert(transaction.id).inserted {
            pendingIDs.remove(transaction.productID)
            if !transaction.revoked {
                // Approval may arrive before purchase() returns its pending result.
                // Another tip's approval must not suppress this purchase's outcome.
                if transaction.productID == purchasingID { activePurchaseConfirmed = true }
                notice = .thanks
            }
        }
        // There is no consumable game benefit to grant. Acknowledge verified tips
        // even when delivered after a relaunch or while the support screen is closed.
        // A later redelivery must finish again even if its thanks was already shown.
        let commerce = commerce
        let token = UUID()
        let task = Task { await commerce.finish(transaction.id) }
        finishing[transaction.id] = (transaction.productID, token, task)
        await task.value
        if finishing[transaction.id]?.token == token { finishing[transaction.id] = nil }
    }
}

@MainActor
final class StoreKitSupportCommerce: SupportCommerce {
    private var catalog: [String: Product] = [:]
    private var transactions: [UInt64: Transaction] = [:]
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
        await transaction.finish()
        // StoreKit can return from finish while its transaction cache still
        // reports this consumable as unfinished. Acknowledge that verified
        // redelivery once; never start another purchase or poll in the background.
        for await result in Transaction.unfinished {
            if case .verified(let remaining) = result, remaining.id == id {
                await remaining.finish()
            }
        }
    }

    private func record(_ result: VerificationResult<Transaction>) -> SupportTransaction {
        switch result {
        case .verified(let transaction):
            if AuthorTip.productIDs.contains(transaction.productID) {
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
