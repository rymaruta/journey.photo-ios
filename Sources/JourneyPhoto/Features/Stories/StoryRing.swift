import SwiftUI

/// **ストーリーの輪1つ**（v2 の板 StoryRings・Components 03「まだ見ていない輪／見終わった輪」・2026-10-14）。
///
/// 外径 64・線 2・線と写真の間の黒いすき間 3・写真 54。本数は輪の切れ目で見せる（1本は切れ目なし）。
///
/// - **まだ見ていない**: 真鍮の金属の光（brass-lo → brass-hi → 真鍮 → brass-lo が円周を回る・
///   `WebTheme.accentMetal`）。CLAUDE.md の owner の好み「未見の輪は真鍮」と同じ
/// - **見た**: 白 22%
///
/// ホームの輪の並び（`StoriesRow`）の自分・人の輪がこの1つを使う（以前は行の中に
/// 外径 62・写真 52・一色の真鍮で書いていた）
struct StoryRing<Content: View>: View {

    /// 本数（切れ目の数）。1以下は切れ目なし
    let count: Int
    let unseen: Bool
    /// 外径。ホームの輪は 64（板）。**プロフィールの顔・写真の作者の顔は、その顔の大きさのまま**
    /// 輪を描き、写真を内側へ縮める（2026-10-22・顔の周りの並びを動かさない）
    let diameter: CGFloat
    let content: Content

    init(count: Int, unseen: Bool, diameter: CGFloat = StoryRingMetrics.size,
         @ViewBuilder content: () -> Content) {
        self.count = count
        self.unseen = unseen
        self.diameter = diameter
        self.content = content()
    }

    var body: some View {
        ZStack {
            // 🔴 **輪の下に黒の丸を敷く**（2026-10-22 の確かめ）。カバー写真の上に重なる顔（人のページ・
            // マイページ）では、線と写真の間のすき間・本数の切れ目から写真が透け、真鍮が写真に接していた
            // （真鍮は黒地の上だけ・CLAUDE.md）。ホームの列は黒地なので見た目は変わらない
            Circle()
                .fill(Self.gapFill)
            ForEach(Array(StoryPlayback.ringSegments(count: count, gap: StoryRingMetrics.segmentGapFraction(diameter: diameter))
                .enumerated()), id: \.offset) { _, seg in
                Circle()
                    .trim(from: seg.start, to: seg.end)
                    // 🔴 **端は丸めない**（`.butt`）。丸めると端が線の太さの半分ずつ切れ目へはみ出し、
                    // 板の約 4pt の切れ目が 2pt ほどに潰れていた（2026-10-16 判断）
                    .stroke(Self.style(unseen: unseen),
                            style: StrokeStyle(lineWidth: StoryRingMetrics.stroke, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .padding(StoryRingMetrics.stroke / 2)
            }
            content
                .frame(width: StoryRingMetrics.photo(diameter: diameter),
                       height: StoryRingMetrics.photo(diameter: diameter))
                .clipShape(Circle())
        }
        .frame(width: diameter, height: diameter)
    }

    /// 輪の下に敷く黒（線と写真の間のすき間・切れ目の地）
    @MainActor static var gapFill: Color { WebTheme.background }

    /// 輪の塗り。**未見は金属の光、見たものは白 22%**
    @MainActor static func style(unseen: Bool) -> AnyShapeStyle {
        if unseen {
            // 板の `conic-gradient(from 210deg, lo, hi, 真鍮, lo)`（上から時計回りに 210°）。
            // 輪は -90° 回して描く（描く前の 0° ＝右が、画面では上に来る）ので、角度はそのまま 210°
            let metal = WebTheme.accentMetal
            return AnyShapeStyle(AngularGradient(colors: [metal[2], metal[0], metal[1], metal[2]],
                                                 center: .center,
                                                 startAngle: .degrees(StoryRingMetrics.metalStartDegrees),
                                                 endAngle: .degrees(StoryRingMetrics.metalStartDegrees + 360)))
        }
        return AnyShapeStyle(Color.white.opacity(StoryRingMetrics.seenOpacity))
    }
}

/// 輪の寸法（数だけ・Linux のテストで見張る）
enum StoryRingMetrics {
    /// 外径（板 64）
    static let size: CGFloat = 64
    /// 輪の線（`JPStroke.emphasis`）
    static let stroke: CGFloat = JPStroke.emphasis
    /// 線と写真の間の黒いすき間（`JPStroke.ringGap`）
    static let gap: CGFloat = JPStroke.ringGap
    /// 写真の直径（64 − 2×(線 2 ＋ すき間 3) = 54）
    static let photo: CGFloat = size - 2 * (stroke + gap)
    /// 見た輪の白の濃さ（板の `rgba(255,255,255,.22)`）
    static let seenOpacity = 0.22
    /// 金属の光の始まり（板の `from 210deg`）
    static let metalStartDegrees = 210.0
    /// 輪と輪の間（板の gap 14）
    static let spacing: CGFloat = 14
    /// 輪の下の名前と輪の間（板の gap 6）
    static let nameSpacing: CGFloat = 6
    /// 自分の輪の右下の「＋」の白い丸（板 22・黒 3 の縁）
    static let plusSize: CGFloat = 22
    /// 輪が無いときの行の顔（44）に付ける「＋」（板 18）
    static let smallPlusSize: CGFloat = 18
    /// 輪が無いときの行の幅（いちばん狭い iPhone の幅 320 − 左右の端 16×2）
    static let emptyRowWidth: CGFloat = 288
    /// 送っている間の輪の地（板の `rgba(255,255,255,.16)`）
    static let uploadTrackOpacity = 0.16
    /// 送っている間の写真の濃さ（板の `opacity: .6`）
    static let uploadPhotoOpacity = 0.6
    /// 本数の切れ目（板の `stroke-dasharray` の 4）
    static let segmentGap: CGFloat = 4
    /// 線の中心の円周（板の r=31 → 2π×31 ≈ 194.8）。切れ目の割合はこれで割る（`StoryPlayback.ringSegments`）
    static let strokeCircumference: Double = 2 * Double.pi * Double(size - stroke) / 2

    /// 外径 `diameter` の輪の中の写真の直径（線とすき間を両側から引く）。64 なら `photo`（54）
    static func photo(diameter: CGFloat) -> CGFloat {
        max(0, diameter - 2 * (stroke + gap))
    }

    /// 本数の切れ目（4pt）を円周の割合に。**外径ごとに測り直す**（小さい輪で切れ目が太らない）
    static func segmentGapFraction(diameter: CGFloat) -> Double {
        let circumference = Double.pi * Double(max(diameter - stroke, 1))
        return Double(segmentGap) / circumference
    }
}
