import XCTest
@testable import Maxdash

final class FuelTests: XCTestCase {
    func testFuelMath() {
        var fuel = FuelCalculator(tankLiters: 13.2, levelPercent: 62, consumption: 22, pricePerLiter: 10_000)
        // 13.2 L * 62% = 8.184 L
        XCTAssertEqual(fuel.litersRemaining, 8.184, accuracy: 0.001)
        // 8.184 L * 22 km/L = 180.048 km
        XCTAssertEqual(fuel.rangeKm, 180.048, accuracy: 0.01)
        // isi penuh = (13.2 - 8.184) = 5.016 L → Rp 50.160
        XCTAssertEqual(fuel.costToFull, 50_160, accuracy: 1)

        fuel.levelPercent = 0
        XCTAssertEqual(fuel.litersRemaining, 0, accuracy: 0.0001)
        XCTAssertEqual(fuel.rangeKm, 0, accuracy: 0.0001)
    }

    func testClamp() {
        var fuel = FuelCalculator()
        fuel.levelPercent = 150 // di luar 0...100; di aplikasi dibatasi slider, tapi fungsi tetap aman
        XCTAssertEqual(fuel.litersRemaining, fuel.tankLiters * 1.5, accuracy: 0.0001)
        fuel.levelPercent = -10
        XCTAssertEqual(fuel.litersRemaining, -1.32, accuracy: 0.0001)
    }
}