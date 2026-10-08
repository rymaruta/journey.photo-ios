import SwiftUI

/// 撮影スポットの小さな写真（〜100pt の丸・行の頭）。**縮小版を先に読み、読めなければ一度だけ
/// 元の画像に切り替える**（2026-10-08 のレビュー）。
///
/// Web が索引を先に出して縮小版のファイルが CDN に届く前の間・縮小版の1枚だけ 404 の回に、
/// 小さな丸が空のまま残らないため。元の画像は読める。
///
/// 縮小版の無い行は元の画像だけを読む（二度読みしない）。見た目は中の `RemoteImage` /
/// `DownsampledRemoteImage` のまま（地の色・読み込み中の輪・失敗の記号）。切り替えの決め方は
/// 画面を持たない `SpotThumbFallback`（試験はこちらで見る）
struct SpotThumbImage: View {

    private let source: SpotThumbFallback
    /// 縮めて読むとき（`DownsampledRemoteImage`・`.fill`）の見込みの縦横比。nil なら `RemoteImage`
    private let assumedRatioLimit: CGFloat?
    @State private var state: SpotThumbFallback

    /// `url` を先に読み、読めなければ `fallbackURL`（無ければ切り替えない）
    init(url: URL, fallbackURL: URL?, assumedRatioLimit: CGFloat? = nil) {
        let source = SpotThumbFallback(primary: url, fallback: fallbackURL)
        self.source = source
        self.assumedRatioLimit = assumedRatioLimit
        _state = State(initialValue: source)
    }

    /// スポットの写真から（縮小版 → 元の画像）
    init(image: SpotImage, assumedRatioLimit: CGFloat? = nil) {
        self.init(url: image.smallURL, fallbackURL: image.smallFallbackURL, assumedRatioLimit: assumedRatioLimit)
    }

    var body: some View {
        Group {
            if let assumedRatioLimit {
                DownsampledRemoteImage(url: state.current, contentMode: .fill,
                                       assumedRatioLimit: assumedRatioLimit, onSettled: settled)
            } else {
                RemoteImage(url: state.current, onSettled: settled)
            }
        }
        // 同じ枠に別のスポットが来たら（一覧の使い回し）最初から
        .onChange(of: source) { _, next in state = next }
    }

    private func settled(_ ok: Bool) {
        guard !ok else { return }
        var next = state
        if next.failed() { state = next }
    }
}

/// 小さな写真の読み先の決め方（画面を持たない）。**切り替えは一度だけ**——元の画像も
/// 読めなければそのまま失敗の記号を出す（行き来しない）
struct SpotThumbFallback: Equatable {
    let primary: URL
    /// 先が読めなかったときの読み先。先と同じなら nil（同じものを二度読まない）
    let fallback: URL?
    private(set) var switched = false

    init(primary: URL, fallback: URL?) {
        self.primary = primary
        self.fallback = fallback == primary ? nil : fallback
    }

    init(_ image: SpotImage) {
        self.init(primary: image.smallURL, fallback: image.smallFallbackURL)
    }

    /// いま読む先
    var current: URL { switched ? (fallback ?? primary) : primary }

    /// 読めなかった。**切り替えたら true**（2度目以降・切り替え先の無いときは false）
    mutating func failed() -> Bool {
        guard !switched, fallback != nil else { return false }
        switched = true
        return true
    }
}
