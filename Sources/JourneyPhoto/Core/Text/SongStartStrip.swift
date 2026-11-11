import Foundation

/// 曲の流し始めの帯（2026-11-12 判断・設計の案「ストーリーのデザイン 残り」03）。
///
/// 数字と横棒では「どこが好きな所か」が見えないので、**30 秒の試聴の帯の上に、表示の秒数ぶんの枠**を置き、
/// 枠を動かすとその位置から鳴らす。画面（`SongStartSheet`）から出してある——Linux の `swift test` で確かめるため。
///
/// **帯の棒は本物の音の形ではない。** 試聴の音を端末で読んで形を出せるかは試していない（設計の案の「確かめていないこと」）。
/// 案どおり「出せなければ等間隔の拍の棒」にした——1 秒に 2 本、毎秒の棒を高く、5 秒ごとをさらに高くして、
/// 時間の目盛りとして読めるようにする（音の形に見せかけない）
enum SongStartStrip {

    /// 帯の長さ（秒）。試聴の長さ（`Photo.Song.previewSeconds`）
    static let totalSeconds = Photo.Song.previewSeconds

    /// 1 秒あたりの棒の数
    static let barsPerSecond = 2

    /// 棒の数（30 秒 × 2）
    static var barCount: Int { totalSeconds * barsPerSecond }

    /// 帯の高さ・棒の高さ（pt）
    static let stripHeight: Double = 56
    static let tallBar: Double = 32
    static let secondBar: Double = 20
    static let halfBar: Double = 12

    /// `index` 本目の棒の高さ。5 秒ごと > 毎秒 > 半秒
    static func barHeight(_ index: Int) -> Double {
        guard index % barsPerSecond == 0 else { return halfBar }
        let second = index / barsPerSecond
        return second % 5 == 0 ? tallBar : secondBar
    }

    /// `index` 本目の棒が指す時刻（秒）
    static func barTime(_ index: Int) -> Double {
        Double(index) / Double(barsPerSecond)
    }

    /// 棒の塗り。枠の外は灰、枠の中は「鳴った所まで白・まだの所は白 55%」
    enum BarTone: Equatable { case outside, played, upcoming }

    static func tone(index: Int, start: Int, window: Int, played: Double) -> BarTone {
        let time = barTime(index)
        let from = Double(start)
        guard time >= from - 0.001, time < from + Double(max(1, window)) - 0.001 else { return .outside }
        return time <= from + max(0, played) ? .played : .upcoming
    }

    /// 枠の左端と幅（帯の幅に対する割合 0〜1）
    static func windowFraction(start: Int, window: Int) -> (left: Double, width: Double) {
        let total = Double(totalSeconds)
        let width = min(1, Double(max(1, window)) / total)
        let left = min(max(0, Double(start) / total), 1 - width)
        return (left, width)
    }

    /// 指を置いた所から、枠のどこを掴んだか（秒）。**枠の中を押したらその位置のまま**掴み、
    /// 外を押したら枠の真ん中を指の下へ寄せる
    static func grabOffset(touchSeconds: Double, start: Int, window: Int) -> Double {
        let from = Double(start)
        let width = Double(max(1, window))
        if touchSeconds >= from, touchSeconds <= from + width { return touchSeconds - from }
        return width / 2
    }

    /// 指の位置（秒）と掴んだ所から、流し始め（整数の秒）。**表示秒数ぶんが試聴に収まる所まで**
    /// （`Photo.Song.maxStart`）。保存はサーバーと同じ整数の秒なので、ここで丸める
    static func start(touchSeconds: Double, grab: Double, window: Int) -> Int {
        guard touchSeconds.isFinite, grab.isFinite else { return 0 }
        let raw = Int((touchSeconds - grab).rounded())
        return min(max(0, raw), Photo.Song.maxStart(window: window))
    }

    /// 帯の横位置（0...width）→ 秒
    static func seconds(atX x: Double, width: Double) -> Double {
        guard width > 0, x.isFinite else { return 0 }
        return min(max(x / width, 0), 1) * Double(totalSeconds)
    }

    /// 帯の下の目盛り（0:00・0:10・0:20・0:30）
    static let tickLabels = ["0:00", "0:10", "0:20", "0:30"]

    /// 「0:12」（流し始めの大きな数字）
    static func clock(_ seconds: Int) -> String {
        let sec = max(0, seconds)
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }

    /// 数字の横の「から 5秒」
    static func lengthNote(window: Int) -> String {
        L("から \(window)秒", "· \(window)s")
    }

    /// 試聴の状態（読み込み中・鳴っている・流せない・止まっている）
    enum Playback: Equatable { case idle, loading, playing, failed }

    /// 試聴の状態を決める。**この画面が鳴らした回（`mine`）だけを見る**。
    /// - 鳴らしたのに、自分で止めていない（`stoppedByMe` でない）のに鳴っていない → 流せない
    ///   （試聴の再生器は失敗すると自分で止まる・`MusicPreviewPlayer` の `FailedToPlayToEnd`。繰り返し鳴らすので鳴り終わりでは止まらない）
    /// - 項目の読み込みに失敗（`itemFailed`）→ 流せない
    /// - 鳴っているが、まだ音が出ていない（`waiting`）→ 読み込み中
    static func playback(mine: Bool, playing: Bool, stoppedByMe: Bool, itemFailed: Bool, waiting: Bool) -> Playback {
        guard mine else { return .idle }
        if itemFailed { return .failed }
        if !playing { return stoppedByMe ? .idle : .failed }
        return waiting ? .loading : .playing
    }
}
