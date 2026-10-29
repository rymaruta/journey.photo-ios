import Foundation

/// ストーリーを作る画面で、付けた曲をその場で流す決まり（Issue #403・owner「インスタみたいにこの時点で流れるように」）。
///
/// 鳴らすのは共有の `MusicPreviewPlayer`（見る画面 `StoryViewerView` と同じ再生器・同じ「自分が鳴らした回か」の見分け）。
/// ここは画面を持たない判断だけ（単体テスト用）。
///
/// 2026-10-29 判断:
/// - **流し始めから表示秒数ぶんを繰り返す**（見る人に流れる部分と同じ。`MusicPreviewPlayer.play(… length:)`）
/// - 曲を付けた・替えた・流し始めや表示秒数を直した → その位置から流し直す。外した → 止める
/// - シート・カメラ・写真選びで覆われた間と、アプリが前面にいない間は一時停止。
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
}
