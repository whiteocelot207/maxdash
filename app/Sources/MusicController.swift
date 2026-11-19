import Foundation
import MediaPlayer

/// Info musik yang sedang diputar (dari Apple Music / pemutar sistem).
struct NowPlaying {
    var title: String = "Tidak ada musik"
    var artist: String = ""
    var isPlaying: Bool = false
}

/// Kontrol pemutar musik sistem (Apple Music) untuk ditampilkan di dash.
/// `MPMusicPlayerController.applicationMusicPlayer` mengontrol pemutar musik sistem.
final class MusicController {
    private let player = MPMusicPlayerController.applicationMusicPlayer

    var nowPlaying: NowPlaying {
        guard let item = player.nowPlayingItem else { return NowPlaying() }
        return NowPlaying(
            title: item.title ?? "Tanpa judul",
            artist: item.artist ?? "",
            isPlaying: player.playbackState == .playing)
    }

    func toggle() {
        if player.playbackState == .playing { player.pause() } else { player.play() }
    }

    func next() { player.skipToNextItem() }
    func previous() { player.skipToPreviousItem() }
}