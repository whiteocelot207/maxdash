import Foundation
import Combine

/// Satu item perawatan (oli, gearbox, ban, dst). Interval diisi pengguna; sisa km dihitung dari ODO CCU.
struct MaintenanceItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var intervalKm: Double
    var lastServiceOdo: Double
    /// Jika true, nilai saat ini dibaca dari CCU (ODO); jika false, pakai ODO manual.
    var useCCUValue: Bool

    /// Sisa km sampai jatuh tempo.
    func remainingKm(currentOdo: Double) -> Double {
        return (lastServiceOdo + intervalKm) - currentOdo
    }

    static let defaults: [MaintenanceItem] = [
        MaintenanceItem(name: "Oli mesin", intervalKm: 5000, lastServiceOdo: 23501, useCCUValue: true),
        MaintenanceItem(name: "Oli gearbox", intervalKm: 10000, lastServiceOdo: 19421, useCCUValue: true),
        MaintenanceItem(name: "Filter udara", intervalKm: 20000, lastServiceOdo: 10281, useCCUValue: false),
        MaintenanceItem(name: "Ban depan", intervalKm: 12000, lastServiceOdo: 19681, useCCUValue: false),
        MaintenanceItem(name: "Ban belakang", intervalKm: 8000, lastServiceOdo: 21981, useCCUValue: false),
        MaintenanceItem(name: "Aki", intervalKm: 12000, lastServiceOdo: 22181, useCCUValue: false),
        MaintenanceItem(name: "Belt CVT", intervalKm: 15000, lastServiceOdo: 18181, useCCUValue: false),
    ]
}

/// Penyimpanan item perawatan (UserDefaults) + ODO saat ini (dari CCU; mock sampai Link B).
final class MaintenanceStore: ObservableObject {
    @Published var items: [MaintenanceItem]
    @Published var currentOdo: Double = 28181

    private let key = "maintenanceItems"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([MaintenanceItem].self, from: data) {
            items = decoded
        } else {
            items = MaintenanceItem.defaults
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(_ item: MaintenanceItem) {
        items.append(item)
        save()
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }
}