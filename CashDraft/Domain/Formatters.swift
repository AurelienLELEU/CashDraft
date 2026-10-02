import Foundation

enum Formatters {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = "EUR"; formatter.locale = Locale(identifier: "fr_FR"); return formatter
    }()
    static let date: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.locale = Locale(identifier: "fr_FR"); return formatter
    }()
    static func money(_ value: Double, currencyCode: String = "EUR") -> String {
        let formatter = currency.copy() as! NumberFormatter
        formatter.currencyCode = currencyCode
        return formatter.string(from: NSNumber(value: value)) ?? "0,00 €"
    }
}
