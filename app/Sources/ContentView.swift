import SwiftUI
import UIKit

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
    @Environment(\.scenePhase) private var scenePhase

    @State private var pendingShare: ShareResult?
    @State private var shareName = ""
    @State private var lastPaste = ""
    @State private var showShareConfirm = false

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
        .onAppear {
            navigator.start()
            checkPasteboard()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { checkPasteboard() }
        }
        .alert("Mulai navigasi ke \(shareName)?", isPresented: $showShareConfirm) {
            Button("Mulai navigasi") {
                if let pending = pendingShare { navigator.navigate(to: pending) }
                UIPasteboard.general.string = ""
            }
            Button("Batal", role: .cancel) {}
        }
    }

    /// Baca pasteboard (diisi share extension). Jika berisi tautan maps, minta konfirmasi.
    private func checkPasteboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty, text != lastPaste else { return }
        lastPaste = text
        let result = ShareLink.parse(text)
        if case .redirect(let urlStr) = result {
            ShareLink.resolveRedirect(urlStr) { [weak self] resolved in
                guard let self = self, let resolved = resolved else { return }
                self.presentShare(ShareLink.parse(resolved))
            }
        } else {
            presentShare(result)
        }
    }

    private func presentShare(_ result: ShareResult) {
        switch result {
        case .coords, .query, .directions:
            pendingShare = result
            shareName = Self.displayName(result)
            showShareConfirm = true
        default:
            break
        }
    }

    static func displayName(_ r: ShareResult) -> String {
        switch r {
        case .coords(_, _, let name): return name ?? "titik tujuan"
        case .query(let q): return q
        case .directions(let dest, _): return dest.name ?? dest.q ?? "tujuan"
        default: return "tujuan"
        }
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
                    LabeledContent("Sisa bensin", value: String(format: "%.1f L", FuelCalculator().litersRemaining))
                    LabeledContent("Sisa jarak", value: "± \(Int(FuelCalculator().rangeKm)) km")
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
    @EnvironmentObject private var navigator: RideNavigator
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("Cari tujuan atau alamat", text: $query)
                            .onSubmit { navigator.navigate(toText: query) }
                            .submitLabel(.search)
                    }
                    Button("Cari & mulai navigasi") {
                        navigator.navigate(toText: query)
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(accent)
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
                Section {
                    Text(navigator.status).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Navigasi")
        }
    }
}

// MARK: - Motor
private struct MotorView: View {
    @State private var fuel = FuelCalculator()
    @EnvironmentObject private var navigator: RideNavigator

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
        .onChange(of: fuel.levelPercent) { _, v in navigator.fuelLevelPercent = v }
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
    @AppStorage("slot1") private var slot1 = DataSlot.defaults[0].rawValue
    @AppStorage("slot2") private var slot2 = DataSlot.defaults[1].rawValue
    @AppStorage("slot3") private var slot3 = DataSlot.defaults[2].rawValue
    @AppStorage("slot4") private var slot4 = DataSlot.defaults[3].rawValue
    @AppStorage("speedLimit") private var speedLimit = 60
    @EnvironmentObject private var navigator: RideNavigator
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
                    Stepper("Batas kecepatan default: \(speedLimit)", value: $speedLimit, in: 30...120)
                }
                Section("Kotak Data") {
                    Picker("Kartu 1", selection: $slot1) {
                        ForEach(DataSlot.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Picker("Kartu 2", selection: $slot2) {
                        ForEach(DataSlot.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Picker("Kartu 3", selection: $slot3) {
                        ForEach(DataSlot.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Picker("Kartu 4", selection: $slot4) {
                        ForEach(DataSlot.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
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
        .onChange(of: defaultDash) { _, v in
            switch v {
            case "speedo": navigator.currentView = .speedo
            case "musik": navigator.currentView = .music
            default: navigator.currentView = .map
            }
        }
        .onChange(of: slot1) { _, _ in updateSlots() }
        .onChange(of: slot2) { _, _ in updateSlots() }
        .onChange(of: slot3) { _, _ in updateSlots() }
        .onChange(of: slot4) { _, _ in updateSlots() }
        .onChange(of: speedLimit) { _, v in navigator.defaultSpeedLimit = Float(v) }
        .onAppear { updateSlots() }
    }

    private func updateSlots() {
        navigator.selectedSlots = [slot1, slot2, slot3, slot4].compactMap { DataSlot(rawValue: $0) }
    }
}