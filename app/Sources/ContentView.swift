import SwiftUI

// MARK: - Warna
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

private let accent = Color(hex: 0x2FE0C8)

// MARK: - Akar
struct ContentView: View {
    @StateObject private var navigator = RideNavigator()

    var body: some View {
        TabView {
            BerandaView()
                .tabItem { Label("Beranda", systemImage: "house") }
            NavigasiView()
                .tabItem { Label("Navigasi", systemImage: "map") }
            MotorView()
                .tabItem { Label("Motor", systemImage: "wrench.and.screwdriver") }
            PengaturanView()
                .tabItem { Label("Setting", systemImage: "gearshape") }
        }
        .tint(accent)
        .environmentObject(navigator)
        .onAppear { navigator.start() }
    }
}

// MARK: - Beranda
private struct BerandaView: View {
    @EnvironmentObject private var navigator: RideNavigator

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    HStack { statusDot(); Text(navigator.status) }
                    HStack { statusDot(); Text("Yamaha XMAX 2024") }
                    HStack { statusDot(on: false); Text("GPS") }
                }
                Section("Bensin") {
                    let fuel = FuelCalculator()
                    LabeledContent("Sisa bensin", value: String(format: "%.1f L", fuel.litersRemaining))
                    LabeledContent("Sisa jarak", value: "± \(Int(fuel.rangeKm)) km")
                }
                Section("Perawatan terdekat") {
                    LabeledContent("Oli mesin", value: "dalam 320 km")
                        .foregroundStyle(.orange)
                }
                Section {
                    Text("Temukan tempat di Google Maps, ketuk Bagikan, lalu pilih maxdash.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("maxdash")
        }
    }

    private func statusDot(on: Bool = true) -> some View {
        Circle().fill(on ? Color.green : Color.gray).frame(width: 8, height: 8)
    }
}

// MARK: - Navigasi
private struct NavigasiView: View {
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("Cari tujuan atau alamat", text: $query)
                    }
                    Button {
                        // Tempat berbagi dari Google Maps (share extension) akan muncul di sini.
                    } label: {
                        Label("Bagikan dari Google Maps", systemImage: "square.and.arrow.up")
                    }
                    .tint(accent)
                }
                Section("Sering ke") {
                    Label("Rumah", systemImage: "house")
                    Label("Kantor", systemImage: "building.2")
                }
            }
            .navigationTitle("Navigasi")
        }
    }
}

// MARK: - Motor
private struct MotorView: View {
    @State private var fuel = FuelCalculator()

    var body: some View {
        NavigationStack {
            List {
                Section("Kalkulator bensin") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Bensin sekarang"); Spacer(); Text("\(Int(fuel.levelPercent))%") }
                        Slider(value: $fuel.levelPercent, in: 0...100)
                            .tint(accent)
                        HStack { Text("Konsumsi"); Spacer(); Text("\(Int(fuel.consumption)) km/L") }
                        Slider(value: $fuel.consumption, in: 5...60)
                            .tint(accent)
                    }
                    LabeledContent("Sisa bensin", value: String(format: "%.1f L", fuel.litersRemaining))
                    LabeledContent("Sisa jarak tempuh", value: "± \(Int(fuel.rangeKm)) km")
                    LabeledContent("Isi penuh", value: "Rp \(Int(fuel.costToFull))")
                }
                Section("Perawatan") {
                    maintenanceRow("Oli mesin", "320 km lagi", warn: true)
                    maintenanceRow("Oli gearbox", "1.240 km lagi", warn: false)
                    maintenanceRow("Filter udara", "2.100 km lagi", warn: false)
                    maintenanceRow("Ban depan", "3.500 km lagi", warn: false)
                    maintenanceRow("Ban belakang", "1.800 km lagi", warn: false)
                    maintenanceRow("Aki", "6 bulan lagi", warn: false)
                    maintenanceRow("Belt CVT", "5.000 km lagi", warn: false)
                }
                Section {
                    Text("Angka perawatan hanya perkiraan. Ikuti buku manual resmi Yamaha XMAX.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Motor")
        }
    }

    private func maintenanceRow(_ name: String, _ detail: String, warn: Bool) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(detail).foregroundStyle(warn ? .orange : .green)
        }
    }
}

// MARK: - Pengaturan
private struct PengaturanView: View {
    @AppStorage("accent") private var accentName = "teal"
    @AppStorage("unit") private var unit = "km/jam"
    @AppStorage("defaultDash") private var defaultDash = "peta"
    var body: some View {
        NavigationStack {
            List {
                Section("Tampilan") {
                    Picker("Warna aksen", selection: $accentName) {
                        Text("Teal").tag("teal")
                        Text("Biru").tag("biru")
                        Text("Merah").tag("merah")
                    }
                    Picker("Tampilan dash awal", selection: $defaultDash) {
                        Text("Peta + Data").tag("peta")
                        Text("Speedometer").tag("speedo")
                        Text("Musik").tag("musik")
                    }
                    Picker("Unit kecepatan", selection: $unit) {
                        Text("km/jam").tag("km/jam")
                        Text("mph").tag("mph")
                    }
                }
                Section("Navigasi") {
                    LabeledContent("Sumber rute", value: "Apple Maps")
                    LabeledContent("Gaya peta", value: "Vektor CPU")
                }
                Section("Motor") {
                    Stepper("Batas kecepatan default: \(Int(60))", value: .constant(60), in: 30...120)
                }
                Section("Tentang") {
                    LabeledContent("Versi", value: "0.1.0")
                    LabeledContent("Dash terdeteksi", value: "XMAX · 480×234")
                }
                Section {
                    Text("maxdash adalah proyek independen, tidak berafiliasi dengan Yamaha, Garmin, atau Apple.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Setting")
        }
    }
}