import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = LicenseManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "sparkles").font(.system(size: 46)).foregroundStyle(.mint)
                    Text("Facturez à votre rythme").font(.title.bold())
                    Text("Les 5 premiers documents donnent accès à toutes les fonctions. Ensuite, vos données et vos brouillons restent toujours accessibles.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    if store.isStudioActive { Label("CashDraft Studio est actif", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green).padding() }
                    productCard(for: LicenseManager.studioMonthlyID, title: "CashDraft Studio", price: "9,99 € / mois", subtitle: "Documents illimités, synchronisation iCloud, Mac, personnalisation et outils avancés", prominent: true)
                    productCard(for: LicenseManager.studioYearlyID, title: "CashDraft Studio annuel", price: "69,99 € / an", subtitle: "Toutes les fonctions Studio, au meilleur prix", prominent: false)
                    if !store.license.isProUnlocked { productCard(for: LicenseManager.lifetimeID, title: "Pro Lifetime", price: "14,99 €", subtitle: "Documents de base illimités, à vie, sans abonnement", prominent: false) }
                    productCard(for: LicenseManager.creditsID, title: "20 documents", price: "4,99 €", subtitle: "Documents de base pour les besoins ponctuels", prominent: false)
                    Button("Restaurer mes achats") { Task { await manager.restore(store: store) } }.padding(.top, 4)
                    Text("Les crédits sont utilisés uniquement lors de la première émission d’un document. Les brouillons, données et sauvegardes restent accessibles gratuitement.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                }.padding()
            }
            .navigationTitle("Passer à Pro")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task { manager.startListening(store: store); await manager.loadProducts() }
            .overlay { if manager.isPurchasing { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .alert("Achats", isPresented: Binding(get: { manager.message != nil }, set: { if !$0 { manager.message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(manager.message ?? "") }
        }
    }

    @ViewBuilder private func productCard(for id: String, title: String, price: String, subtitle: String, prominent: Bool) -> some View {
        let product = manager.products.first { $0.id == id }
        Button {
            if let product { Task { await manager.purchase(product, store: store) } }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(title).font(.headline); Spacer(); Text(product?.displayPrice ?? price).font(.title3.bold()) }
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                if prominent { Label("Le choix le plus simple", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.mint) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding().background(prominent ? Color.mint.opacity(0.13) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(prominent ? Color.mint : .clear, lineWidth: 1) }
        }.buttonStyle(.plain).disabled(product == nil)
    }
}
