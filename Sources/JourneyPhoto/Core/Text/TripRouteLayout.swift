import Foundation

/// 旅の本のルート図（`TripBookView.routeDrawing`）の置き方。
///
/// 点は左から右へ等間隔、高さは交互（偶数番は低く札は下・奇数番は高く札は上）。
/// 札は2行（1行目 `DAY n`・2行目 地名）。
///
/// - **札は図の外へはみ出さない。** 端の札は図の縁で止め、点からずらす
/// - **同じ側の札どうしは重ねない。** 同じ側の隣（2つ隣の点）との中間までを札の幅にする。
///   反対側の札とは上下で分かれるので重ならない
/// - **高さは札の高さから決める。** 札の高さは呼ぶ側が字の大きさの設定に合わせて渡す
///   （`@ScaledMetric`）。大きな字でも札が点・線に重ならない
enum TripRouteLayout {

    struct Label: Equatable {
        let centerX: CGFloat
        let centerY: CGFloat
        let width: CGFloat
        /// 高い点の札（点の上に出す）
        let above: Bool
    }

    struct Layout: Equatable {
        let points: [CGPoint]
        let labels: [Label]
        let height: CGFloat
    }

    /// 端の点の内側への寄せ（板の波打つ線の見た目）
    static let inset: CGFloat = 44
    /// 図の縁から札までの余白
    static let margin: CGFloat = 8
    /// 同じ側の札どうしの間
    static let labelGap: CGFloat = 8
    /// 札の幅の上限（長い地名で図を横切らない）
    static let maxLabelWidth: CGFloat = 160
    /// 点の直径・高い点と低い点の差・札と点の間
    static let dot: CGFloat = 14
    static let amplitude: CGFloat = 28
    static let dotGap: CGFloat = 6

    /// 図の高さ（上の札・点の帯・下の札と余白）
    static func height(labelHeight: CGFloat) -> CGFloat {
        margin + labelHeight + dotGap + dot + amplitude + dotGap + labelHeight + margin
    }

    static func layout(count: Int, width: CGFloat, labelHeight: CGFloat) -> Layout {
        let upperY = margin + labelHeight + dotGap + dot / 2
        let lowerY = upperY + amplitude
        let total = height(labelHeight: labelHeight)
        guard count > 0 else { return Layout(points: [], labels: [], height: total) }

        // 2026-10-18: 三項の中に CGFloat の四則を連ねた式が型検査に約4秒かかった（Linux の模型で計測）。
        // 段に分けて型を書く（値は前と同じ: inset + span × index ÷ (count − 1)、1つなら真ん中）
        let span: CGFloat = max(0, width - inset * 2)
        let gaps: CGFloat = CGFloat(max(1, count - 1))
        let xs: [CGFloat] = (0..<count).map { (index: Int) -> CGFloat in
            guard count > 1 else { return width / 2 }
            let along: CGFloat = span * CGFloat(index)
            return inset + along / gaps
        }
        let points = xs.indices.map { index in
            CGPoint(x: xs[index], y: index.isMultiple(of: 2) ? lowerY : upperY)
        }
        let labels: [Label] = xs.indices.map { index in
            let x = xs[index]
            let left = index >= 2 ? (xs[index - 2] + x) / 2 + labelGap / 2 : margin
            let right = index + 2 < count ? (x + xs[index + 2]) / 2 - labelGap / 2 : width - margin
            let labelWidth = max(0, min(maxLabelWidth, right - left))
            let centerX = min(max(x, left + labelWidth / 2), right - labelWidth / 2)
            let above = !index.isMultiple(of: 2)
            let centerY = above
                ? upperY - dot / 2 - dotGap - labelHeight / 2
                : lowerY + dot / 2 + dotGap + labelHeight / 2
            return Label(centerX: centerX, centerY: centerY, width: labelWidth, above: above)
        }
        return Layout(points: points, labels: labels, height: total)
    }
}
