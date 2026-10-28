import UIKit

/// 画面写真の試験でストーリー作成に入れる見本の写真と曲（`PreviewSession.opensStorySongSample`・Debug のみ）。
///
/// 曲の札の6つの形（2026-10-28）を撮るため。**アプリに入っている画像だけを使う**（写真のライブラリにも
/// 通信にも頼らない。ジャケットも同梱の構図の見本で代える）。鍵の無いときは何もしない
enum PreviewStorySample {

    /// 写真（構図の見本の1枚・`PreviewUploadSample` と同じ）
    static let photoAsset = PreviewUploadSample.assetName
    /// ジャケットの代わり（構図の見本の1枚）
    static let artworkAsset = "composition-ai-goldenSpiral"
    /// ジャケットの見分けに使う印（通信はしない・`ProfileSongLine.artworkURL` に通る形だけ）
    static let artworkMarker = "https://preview.journey-photo.invalid/artwork.jpg"

    /// 見本の曲。曲名は長め（札の「…」と見る画面の流れる行を撮る）
    static let song = Photo.Song(title: "夜明けの港で聴くバラード", artist: "Journey Photo Band",
                                 artwork: artworkMarker,
                                 previewUrl: "https://audio-ssl.itunes.apple.com/preview.m4a", trackUrl: nil)

    static func photoData() -> Data? {
        guard PreviewSession.opensStorySongSample else { return nil }
        return UIImage(named: photoAsset)?.jpegData(compressionQuality: 0.9)
    }

    /// 見本の曲のジャケット（見本の曲のときだけ）
    static func artwork(for song: Photo.Song?) -> UIImage? {
        guard PreviewSession.opensStorySongSample, song?.artwork == artworkMarker else { return nil }
        return UIImage(named: artworkAsset)
    }
}
