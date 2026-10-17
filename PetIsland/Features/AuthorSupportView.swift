import SwiftUI

struct AuthorSupportView: View {
    @ObservedObject var store: AuthorSupportStore = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingRetryProduct: SupportProduct?
    @State private var showsPendingRetry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 48)).foregroundStyle(PetDesign.accent)
                        .accessibilityHidden(true)
                    Text(String(localized: "A little kindness for Pet Island", table: "ReleaseSupport"))
                        .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text(String(localized: "If the island makes your day warmer, you can leave a one-time tip to help its author keep improving it. Thank you for being here.", table: "ReleaseSupport"))
                        .foregroundStyle(PetDesign.secondary)
                    Text(String(localized: "Completely optional. No subscription, coins or extra features — every pet stays available without a tip.", table: "ReleaseSupport"))
                        .font(.footnote).foregroundStyle(PetDesign.secondary)
                    if let notice = store.notice { noticeView(notice) }
                    if store.isLoading {
                        ProgressView(String(localized: "Loading prices…", table: "ReleaseSupport"))
                    } else if !store.canMakePayments {
                        Text(String(localized: "Purchases are restricted on this iPhone. You can keep enjoying the island as usual.", table: "ReleaseSupport"))
                            .accessibilityIdentifier("support.restricted")
                    } else if store.products.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(localized: "Tips are unavailable right now. You can try again later — the island works as usual.", table: "ReleaseSupport"))
                            Button(String(localized: "Reload prices", table: "ReleaseSupport")) { Task { await store.load() } }
                                .buttonStyle(PetQuietButtonStyle()).accessibilityIdentifier("support.reload")
                        }
                    } else {
                        ForEach(store.products) { product in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { Task { await store.purchase(product) } } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(product.title).font(.headline)
                                            Text(product.price).font(.subheadline)
                                        }
                                        Spacer(minLength: 4)
                                        if store.purchasingID == product.id { ProgressView() }
                                        else if store.pendingIDs.contains(product.id) { Image(systemName: "clock") }
                                        else { Image(systemName: "heart") }
                                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).petSurface()
                                }
                                .buttonStyle(.plain)
                                .disabled(store.purchasingID != nil || store.pendingIDs.contains(product.id))
                                .accessibilityIdentifier("support.buy.\(product.id)")
                                if store.pendingIDs.contains(product.id) {
                                    Button(String(localized: "Retry declined request", table: "ReleaseSupport")) {
                                        pendingRetryProduct = product
                                        showsPendingRetry = true
                                    }
                                    .buttonStyle(PetQuietButtonStyle())
                                    .disabled(store.purchasingID != nil)
                                    .accessibilityIdentifier("support.retry.\(product.id)")
                                }
                            }
                        }
                    }
                    Text(String(localized: "Apple confirms the price and processes the payment. Completed tips do not need restoring on another device.", table: "ReleaseSupport"))
                        .font(.caption).foregroundStyle(PetDesign.secondary)
                }.padding(24)
            }
            .petPage()
            .navigationTitle(String(localized: "Support the author", table: "ReleaseSupport"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task { store.startObserving(); await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
        .alert(pendingRetryProduct?.title ?? "", isPresented: $showsPendingRetry,
               presenting: pendingRetryProduct) { product in
            Button(String(localized: "Retry declined request", table: "ReleaseSupport")) {
                Task { await store.purchase(product, retryPending: true) }
            }
            .accessibilityIdentifier("support.retry.confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("support.retry.cancel")
        } message: { _ in
            Text(String(localized: "Only try again if your previous request was declined. If it is still waiting for approval, cancel and wait so you do not send another request.", table: "ReleaseSupport"))
        }
    }

    private func noticeView(_ notice: AuthorSupportStore.Notice) -> some View {
        let message: String
        switch notice {
        case .thanks: message = String(localized: "Thank you for supporting the island! Your kindness means a lot.", table: "ReleaseSupport")
        case .pending: message = String(localized: "Waiting for Apple's approval. We’ll confirm your tip when it is approved; you don’t need to pay again.", table: "ReleaseSupport")
        case .verification: message = String(localized: "We couldn’t verify this payment yet. Please check your App Store purchase history before trying again.", table: "ReleaseSupport")
        case .failed: message = String(localized: "The payment couldn’t be completed. Check your connection and App Store purchase history before trying again.", table: "ReleaseSupport")
        case .restricted: message = String(localized: "Purchases are restricted on this iPhone. You can keep enjoying the island as usual.", table: "ReleaseSupport")
        }
        return Text(message).font(.callout).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .petSurface().accessibilityIdentifier("support.notice.\(String(describing: notice))")
    }
}

#if DEBUG && targetEnvironment(simulator)
struct AuthorSupportPreviewHost: View {
    @StateObject private var store = AuthorSupportStore(commerce: PreviewSupportCommerce())
    @State private var presented = true
    var body: some View {
        Text("Support preview closed").accessibilityIdentifier("support.preview.closed")
            .sheet(isPresented: $presented) { AuthorSupportView(store: store) }
    }
}

@MainActor
private final class PreviewSupportCommerce: SupportCommerce {
    private let args = ProcessInfo.processInfo.arguments
    var canMakePayments: Bool { !args.contains("-support-restricted") }
    func products() async throws -> [SupportProduct] {
        guard !args.contains("-support-empty") else { return [] }
        return [SupportProduct(id: AuthorTip.small.id, title: "A little thank-you", price: "$0.99")]
    }
    func purchase(_ id: String) async throws -> SupportPurchaseResult {
        if args.contains("-support-pending") { return .pending }
        if args.contains("-support-failure") { throw SupportPurchaseError.unavailable }
        return .completed(.init(id: 1, productID: id, verified: true, revoked: false))
    }
    func updates() -> AsyncStream<SupportTransaction> { AsyncStream { $0.finish() } }
    func unfinished() async -> [SupportTransaction] { [] }
    func finish(_ id: UInt64) async {}
}
#endif
