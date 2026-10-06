import Foundation
import StoreKit

@MainActor
final class LicenseManager: ObservableObject {
    static let lifetimeID = "com.cashdraft.pro.lifetime"
    static let creditsID = "com.cashdraft.credits.20"
    static let studioMonthlyID = "com.cashdraft.studio.monthly"
    static let studioYearlyID = "com.cashdraft.studio.yearly"
    @Published private(set) var products: [Product] = []
    @Published var isPurchasing = false
    @Published var message: String?
    private var updates: Task<Void, Never>?

    deinit { updates?.cancel() }

    func startListening(store: AppStore) {
        guard updates == nil else { return }
        updates = Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                store.applyPurchase(productID: transaction.productID, transactionID: String(transaction.id), expirationDate: transaction.expirationDate)
                await transaction.finish()
            }
        }
    }

    func loadProducts() async {
        do { products = try await Product.products(for: [Self.lifetimeID, Self.creditsID, Self.studioMonthlyID, Self.studioYearlyID]) } catch { message = "Les achats ne sont pas disponibles actuellement." }
    }
    func purchase(_ product: Product, store: AppStore) async {
        isPurchasing = true; defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { message = "Achat non vérifié."; return }
                store.applyPurchase(productID: transaction.productID, transactionID: String(transaction.id), expirationDate: transaction.expirationDate)
                await transaction.finish()
            case .pending: message = "Votre achat est en attente de validation."
            case .userCancelled: break
            @unknown default: break
            }
        } catch { message = "L’achat n’a pas abouti : \(error.localizedDescription)" }
    }
    func restore(store: AppStore) async {
        do {
            try await StoreKit.AppStore.sync()
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result { store.applyPurchase(productID: transaction.productID, transactionID: String(transaction.id), expirationDate: transaction.expirationDate) }
            }
            message = (store.license.isProUnlocked || store.isStudioActive) ? "Vos achats ont été restaurés." : "Aucun achat restaurable n’a été trouvé."
        } catch { message = "Impossible de restaurer les achats actuellement." }
    }
}
