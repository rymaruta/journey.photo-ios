import Foundation
// `ObservableObject` は Combine のもの（`MusicPreviewPlayer` と同じく明示する）
import Combine

/// ストーリーを作る画面で、付けた曲をその場で流す決まり（Issue #403・owner「インスタみたいにこの時点で流れるように」）。
///
/// 鳴らすのは共有の `MusicPreviewPlayer`（見る画面 `StoryViewerView` と同じ再生器・同じ「自分が鳴らした回か」の見分け）。
/// ここは画面を持たない判断だけ（単体テスト用）。
///
/// 2026-10-29 判断:
/// - **流し始めから表示秒数ぶんを繰り返す**（見る人に流れる部分と同じ。`MusicPreviewPlayer.play(… length:)`）
/// - 曲を付けた・替えた・流し始めや表示秒数を直した → その位置から流し直す。外した → 止める
/// - シート・カメラ・写真選びで覆われた間・写真を全部外して写真選びの段に戻った間・アプリが前面にいない間は
///   一時停止（写真が入る・覆いが外れる・前面に戻ると続きから）。
///   **カメラ（全面の覆い）を開いても止めない**——開くと作る画面の onDisappear が走るが、そこで止めると
///   場を返して他のアプリの音楽が一瞬戻り、戻ると頭から流れ直していた（2026-10-29 の見直し）。覆いとして一時停止し、
///   閉じたら続きから。カメラを開いたまま作る画面ごと閉じられたときは、`Owner` が消えるときに止める。
///   覆いが外れたら、**まだ自分の回なら続きから**（一時停止を解くだけ）。覆いの間に曲選び・流し始めのシートが
///   試し聴きで鳴らして回が替わっていたら、流し始めから流し直す
/// - 文字を打つ・投票の欄・撮影地の入力は覆いに数えない（写真の上の作業。インスタも打つ間は流れたまま）。
///   曲の札の動きを止める `songStickersCovered` より狭い（シート・全面の覆いだけ）
/// - 音の場はこの再生器の決まりのまま `.playback`（見る画面のストーリーの曲と同じ。マナーモードでも鳴る）。
///   見る画面の「音を消す」の好み（`StoryAudioPreference`）は使わない——作る画面には音を戻す口が無く、
///   消したままだと付けた曲を確かめられない
/// - 全体の再生器（`MiniPlayerBar`）には出さない（見る画面と同じく `song: nil` で鳴らす）
/// - 試聴の URL が無い・配信元が試聴のホストでない曲は黙って鳴らさない（`StoryPlayback.isAllowedPreview`）
enum StoryComposerSong {

    /// 鳴らす中身（どの曲を・どこから・何秒ぶん）。変わったら流し直す
    struct Cue: Equatable {
        let url: URL
        let start: Double
        let length: Double
    }

    /// 付けた曲から鳴らす中身を作る。鳴らせない曲なら nil
    static func cue(song: Photo.Song?, durationSec: Int) -> Cue? {
        guard let song, let url = song.previewURL, StoryPlayback.isAllowedPreview(url) else { return nil }
        let window = durationSec
        let start = song.fitting(window: window).startSec ?? 0
        return Cue(url: url, start: Double(start), length: Double(window))
    }

    enum Action: Equatable {
        case none
        /// 頭（流し始め）から鳴らす
        case play(Cue)
        case pause
        case resume
        /// 自分の鳴らした曲を止める
        case stop
    }

    /// - Parameters:
    ///   - cue: いま付いている曲（鳴らせなければ nil）
    ///   - played: この画面が最後に鳴らした中身
    ///   - owns: いま鳴っているのがこの画面の鳴らした回か（`MusicPreviewPlayer.session`）
    ///   - paused: 再生器が一時停止中か
    ///   - held: 覆われている・前面にいない（鳴らさない）
    static func action(cue: Cue?, played: Cue?, owns: Bool, paused: Bool, held: Bool) -> Action {
        guard let cue else { return owns ? .stop : .none }
        if held { return owns && !paused ? .pause : .none }
        if !owns || played != cue { return .play(cue) }
        return paused ? .resume : .none
    }

    /// この画面が鳴らした回を持つ係（作る画面の `@StateObject`）。**画面が消えたら（どの道で閉じても）自分の回を止める**
    /// ——カメラを開いている間は onDisappear で止めないので、そのまま外から閉じられても鳴り残らないように
    final class Owner: ObservableObject {
        /// この画面が鳴らした回（`MusicPreviewPlayer.session`）と中身
        private(set) var session: Int?
        private(set) var played: Cue?
        private let player: MusicPreviewPlayer

        init(player: MusicPreviewPlayer = .shared) { self.player = player }

        deinit { stop() }

        /// いま鳴っているのがこの画面の鳴らした回か（見る画面の `ownsSong` と同じ見分け）
        var owns: Bool {
            session != nil && session == player.session && player.playingURL != nil
        }

        /// 開いたとき: **ほかで鳴っている曲（マイページの BGM の試聴など）は止める**（見る画面と同じ・
        /// Web の `stopGlobalMusic`）。全体の再生器はこのシートに覆われて止める口が無く、付けた曲と重なる。
        /// 自分の回（カメラから戻った）は止めない
        func stopOthers() {
            if !owns, player.playingURL != nil { player.stop() }
        }

        /// 流し始めから表示秒数ぶんを繰り返す。`song` は渡さない——全体の再生器（`MiniPlayerBar`）に出さない
        func play(_ cue: Cue) {
            session = player.play(cue.url, song: nil, loops: true, from: cue.start, length: cue.length)
            played = cue
        }

        /// **自分が鳴らした曲だけ止める**（見る画面の `stopSong` と同じ）
        func stop() {
            defer {
                session = nil
                played = nil
            }
            guard owns else { return }
            player.stop()
        }
    }
}
