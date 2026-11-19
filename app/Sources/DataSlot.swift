import Foundation

/// Jenis data yang bisa ditampilkan di tiap kartu kecil pada panel data dash.
enum DataSlot: String, CaseIterable, Identifiable {
    case phoneBattery = "Baterai HP"
    case phoneVolume = "Volume HP"
    case fuelLiters = "Sisa bensin"
    case fuelRange = "Sisa jarak"
    case coolantTemp = "Suhu mesin"
    case voltage = "Tegangan"
    case odo = "ODO"
    case speed = "Kecepatan"

    var id: String { rawValue }

    /// Slot default (4 kartu kecil).
    static let defaults: [DataSlot] = [.phoneBattery, .fuelLiters, .coolantTemp, .voltage]
}

/// Satu nilai siap tampil (label + teks nilai).
struct DataSlotReadout {
    let label: String
    let value: String
}

/// Membaca nilai tiap slot dari sumber data yang tersedia.
/// Data CCU (suhu/tegangan) masih mock sampai Link B diimplementasi.
enum DataSlotReader {
    static func read(_ slot: DataSlot,
                     fuel: FuelCalculator,
                     speedKmh: Int,
                     battery: Double,
                     volume: Double,
                     coolant: Double?,
                     voltage: Double?,
                     odo: Double?) -> DataSlotReadout {
        switch slot {
        case .phoneBattery:
            return DataSlotReadout(label: slot.rawValue, value: "\(Int(battery.rounded()))%")
        case .phoneVolume:
            return DataSlotReadout(label: slot.rawValue, value: "\(Int(volume.rounded()))%")
        case .fuelLiters:
            return DataSlotReadout(label: slot.rawValue, value: String(format: "%.1f L", fuel.litersRemaining))
        case .fuelRange:
            return DataSlotReadout(label: slot.rawValue, value: "\(Int(fuel.rangeKm.rounded())) km")
        case .coolantTemp:
            return DataSlotReadout(label: slot.rawValue, value: coolant.map { "\(Int($0.rounded()))°C" } ?? "--")
        case .voltage:
            return DataSlotReadout(label: slot.rawValue, value: voltage.map { String(format: "%.1f V", $0) } ?? "--")
        case .odo:
            return DataSlotReadout(label: slot.rawValue, value: odo.map { "\(Int($0.rounded())) km" } ?? "--")
        case .speed:
            return DataSlotReadout(label: slot.rawValue, value: "\(speedKmh) km/j")
        }
    }
}