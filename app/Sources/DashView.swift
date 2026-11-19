import Foundation

/// Tampilan dash yang bisa diganti (klik 2x stang untuk pindah).
enum DashView: Int, CaseIterable {
    case map = 0
    case speedo = 1
    case music = 2

    var name: String {
        switch self {
        case .map: return "Peta + Data"
        case .speedo: return "Speedometer"
        case .music: return "Musik"
        }
    }
}