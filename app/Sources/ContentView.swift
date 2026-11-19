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
    @StateObject private var maintenance = MaintenanceStore()
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
        .environmentObject(maintenance)
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
            ShareLink.resolveRedirect(urlStr) { resolved in
                guard let resolved = resolved else { return }
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
                    HStack { statusDot(on: navigator.dashConnected); Text(navigator.dashConnected ? "Dash terhubung" : "Dash terputus") }
                    HStack { statusDot(on: navigator.gpsActive); Text(navigator.gpsActive ? "GPS aktif" : "GPS mati") }
                    Text(navigator.status).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Preview Dash") {
                    if let img = navigator.previewImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(480.0 / 234.0, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("Belum ada frame").foregroundStyle(.secondary)
                    }
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
                    Button("Simulasi rute (uji dash)") {
                        navigator.startSimulation()
                    }
                    .tint(accent)
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
                    Button("Buka di Google Maps") {
                        openInGoogleMaps()
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(accent)
                    Button("Paste dari Google Maps") {
                        navigator.navigateFromPasteboard()
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

    private func openInGoogleMaps() {
        let q = query.trimmingCharacters(in: .whitespaces)
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "comgooglemaps://?q=\(encoded)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Motor
private enum MotorSubTab: String, CaseIterable, Identifiable {
    case ringkasan = "Ringkasan"
    case perawatan = "Perawatan"
    case riwayat = "Riwayat"
    var id: String { rawValue }
}

private struct MotorView: View {
    @State private var subTab: MotorSubTab = .ringkasan
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Sub", selection: $subTab) {
                    ForEach(MotorSubTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
                switch subTab {
                case .ringkasan: RingkasanMotorView()
                case .perawatan: PerawatanMotorView()
                case .riwayat: RiwayatMotorView()
                }
            }
            .navigationTitle("Motor")
        }
    }
}

private struct FuelCalc {
    var tankLiters: Double = 13.2
    var levelLiters: Double = 8.2
    var consumption: Double = 22
    var levelPercent: Double { tankLiters > 0 ? levelLiters / tankLiters * 100 : 0 }
    var rangeKm: Double { levelLiters * consumption }
}

private struct RingkasanMotorView: View {
    @EnvironmentObject private var navigator: RideNavigator
    @EnvironmentObject private var store: MaintenanceStore
    @State private var fuel = FuelCalc()
    @State private var addLiters = ""
    @State private var manualLiters = ""

    var body: some View {
        List {
            Section("Identitas Motor") {
                LabeledContent("Motor", value: "Yamaha XMAX 2024")
                LabeledContent("ODO", value: "\(Int(store.currentOdo)) km")
                LabeledContent("Konsumsi (CCU)", value: String(format: "%.1f km/L", fuel.consumption))
            }
            Section("Kalkulator Bensin") {
                HStack {
                    Text("Bensin sekarang")
                    Spacer()
                    Text(String(format: "%.1f L", fuel.levelLiters)).bold()
                }
                ProgressView(value: fuel.levelPercent, total: 100)
                    .tint(accent)
                HStack {
                    Text("Kapasitas tangki")
                    Spacer()
                    Text(String(format: "%.1f L", fuel.tankLiters))
                }
                LabeledContent("Sisa bensin", value: String(format: "%.1f L", fuel.levelLiters))
                LabeledContent("Sisa jarak tempuh", value: "± \(Int(fuel.rangeKm)) km")
                Button("Isi Full Tank") { fuel.levelLiters = fuel.tankLiters }
                    .tint(accent)
                HStack {
                    TextField("Tambah bensin (L)", text: $addLiters)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Tambah") {
                        if let v = Double(addLiters) { fuel.levelLiters = min(fuel.tankLiters, fuel.levelLiters + v); addLiters = "" }
                    }
                    .tint(accent)
                }
                HStack {
                    TextField("Level manual (L)", text: $manualLiters)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Set") {
                        if let v = Double(manualLiters) { fuel.levelLiters = max(0, min(fuel.tankLiters, v)); manualLiters = "" }
                    }
                    .tint(accent)
                }
            }
        }
        .onChange(of: fuel.levelPercent) { _, v in navigator.fuelLevelPercent = v }
    }
}

private struct PerawatanMotorView: View {
    @EnvironmentObject private var store: MaintenanceStore
    var body: some View {
        List {
            ForEach(store.items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        Text("\(Int(item.remainingKm(currentOdo: store.currentOdo))) km lagi")
                            .font(.subheadline)
                            .foregroundStyle(color(for: item))
                    }
                    Spacer()
                    if item.useCCUValue {
                        Text("CCU").font(.caption).foregroundStyle(.blue)
                    }
                }
            }
            .onDelete { store.remove(at: $0) }
            Section {
                Text("Sisa km = (ODO terakhir + interval) − ODO sekarang. Atur item di Setting → Perawatan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func color(for item: MaintenanceItem) -> Color {
        let r = item.remainingKm(currentOdo: store.currentOdo)
        return r <= 0 ? .red : (r <= 500 ? .orange : .green)
    }
}

private struct RiwayatMotorView: View {
    var body: some View {
        List {
            Section("Riwayat Perjalanan") {
                Text("Belum ada data trip.")
                    .foregroundStyle(.secondary)
            }
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
    @AppStorage("gpsEnabled") private var gpsEnabled = true
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
                Section("Perangkat") {
                    Toggle("Aktifkan GPS", isOn: $gpsEnabled)
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
                Section("Perawatan") {
                    NavigationLink("Kelola item perawatan") {
                        MaintenanceSettingsView()
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
        .onChange(of: gpsEnabled) { _, v in navigator.setGPS(v) }
        .onAppear { updateSlots() }
    }

    private func updateSlots() {
        navigator.selectedSlots = [slot1, slot2, slot3, slot4].compactMap { DataSlot(rawValue: $0) }
    }
}

// MARK: - Pengaturan Perawatan (dinamis: tambah/hapus/edit item)
private struct MaintenanceSettingsView: View {
    @EnvironmentObject private var store: MaintenanceStore
    @State private var newName = ""
    @State private var newInterval = 5000.0

    var body: some View {
        List {
            ForEach($store.items) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Nama item", text: $item.name)
                    HStack {
                        Text("Interval (km)")
                        Spacer()
                        TextField("Interval", value: $item.intervalKm, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Nilai dari CCU (ODO)", isOn: $item.useCCUValue)
                }
            }
            .onDelete { store.remove(at: $0) }
            Section("Tambah item") {
                TextField("Nama item baru", text: $newName)
                HStack {
                    Text("Interval (km)")
                    Spacer()
                    TextField("Interval", value: $newInterval, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Button("Tambah") {
                    guard !newName.isEmpty else { return }
                    store.add(MaintenanceItem(name: newName, intervalKm: newInterval, lastServiceOdo: store.currentOdo, useCCUValue: false))
                    newName = ""
                    newInterval = 5000
                }
                .tint(accent)
            }
        }
        .navigationTitle("Perawatan")
        .onDisappear { store.save() }
    }
}