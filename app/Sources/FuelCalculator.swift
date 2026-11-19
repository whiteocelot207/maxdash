import Foundation

/// Kalkulator bensin: sisa bensin (liter) dan perkiraan sisa jarak tempuh (km).
/// Semua angka bisa diatur pengguna di tab Motor.
struct FuelCalculator {
    var tankLiters: Double = 13.2      // kapasitas tangki XMAX (liter)
    var levelPercent: Double = 62      // persentase bensin sekarang
    var consumption: Double = 22       // konsumsi rata-rata (km per liter)
    var pricePerLiter: Double = 10_000 // harga BBM per liter (Rp)

    /// Sisa bensin dalam liter.
    var litersRemaining: Double { tankLiters * levelPercent / 100 }
    /// Perkiraan sisa jarak tempuh (km).
    var rangeKm: Double { litersRemaining * consumption }
    /// Liter yang dibutuhkan untuk penuh.
    var litersToFull: Double { max(0, tankLiters - litersRemaining) }
    /// Perkiraan biaya mengisi sampai penuh (Rp).
    var costToFull: Double { litersToFull * pricePerLiter }

    /// Persentase pemakaian per 100 km (L/100 km), untuk ditampilkan.
    var litersPer100km: Double { consumption > 0 ? 100 / consumption : 0 }
}