import Foundation

/// 見る画面の名前の下の「♪ 曲名 · 歌手」の行を**横に流す**計算（2026-10-28・モックの `.mq`）。
///
/// 行の幅（`maxWidth`）に収まる曲名は流さない。収まらない曲名だけ、頭で少し止まってから左へ流し、
/// 1周したら頭に戻る（同じ字を間を空けて2つ並べ、継ぎ目なく回す）。
/// **「動きを減らす」がオンなら流さない**（「…」で切って止める）。
enum SongMarquee {

    /// 行の幅（pt）。名前の下に収まる幅（右の「…」と ✕ に掛からない）
    static let maxWidth: Double = 190
    /// 流す速さ（pt/秒）
    static let speed: Double = 28
    /// 頭で止まる秒数（読み始められるように）
    static let pause: Double = 1.6
    /// 2つ並べた字の間（pt）
    static let gap: Double = 36

    /// 流すか
    static func scrolls(textWidth: Double, boxWidth: Double = maxWidth, reduceMotion: Bool) -> Bool {
        !reduceMotion && textWidth > boxWidth + 0.5
    }

    /// 1周の秒数（止まる分を含む）
    static func cycle(textWidth: Double) -> Double {
        pause + (textWidth + gap) / speed
    }

    /// `time` 秒の時点で左へずらす量（pt・0 以上 `textWidth + gap` 以下）
    static func offset(time: Double, textWidth: Double) -> Double {
        guard textWidth > 0, time.isFinite else { return 0 }
        let period = cycle(textWidth: textWidth)
        var t = time.truncatingRemainder(dividingBy: period)
        if t < 0 { t += period }
        guard t > pause else { return 0 }
        return min((t - pause) * speed, textWidth + gap)
    }
}
