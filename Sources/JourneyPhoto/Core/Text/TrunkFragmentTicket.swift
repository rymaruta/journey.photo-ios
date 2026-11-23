import Foundation

/// かけらの絵「切符の切れ端」（札 #713・2026-11-23 owner「カケラはおすすめにしよう」）。
///
/// 5つの切れ端で1枚の切符（100×44 の箱）になり、あと何個で交換できるかが絵で分かる。前の真鍮のひし形は硬貨と同じ色で
/// 何の物か分からず、真鍮なのでガラスの知らせの上に置けなかった。切符は紙の色（#E9DFC8・ラベルと同じ）なので、
/// 黒地の上にもガラスの上にも同じ形で置ける。色は3色: 紙 #E9DFC8、印刷 #5A1D1B（ラベルの深い赤茶）、細い線だけ真鍮。
/// 座標は案の頁（かけらの案）と同じ。描くのは `TrunkFragmentTicketView`・`TrunkFragmentPieceView`
enum TrunkFragmentTicket {
    static let width: Double = 100
    static let height: Double = 44
    /// 裂く線の x（4本で5つに分ける）
    static let cuts: [Double] = [20, 40, 60, 80]
    /// 裂く線のぎざぎざ（5.5 ごとに左右へ 2.2）
    static let zigStep: Double = 5.5
    static let zigWidth: Double = 2.2

    /// 切れ端の数（`TrunkPartsBoxText.fragmentsPerExchange` と同じ 5）
    static var pieces: Int { TrunkPartsBoxText.fragmentsPerExchange }

    /// x の所で上から下へ裂く線の点
    static func cutLine(_ x: Double) -> [(x: Double, y: Double)] {
        var points: [(x: Double, y: Double)] = []
        var i = 0
        var y = 0.0
        while y <= height + 1e-9 {
            points.append((x + (i % 2 == 1 ? zigWidth : -zigWidth), min(y, height)))
            i += 1
            y += zigStep
        }
        return points
    }

    /// i 番目（左から 0〜4）の切れ端の輪郭（左の線を上から下へ、右の線を下から上へ）
    static func piece(_ i: Int) -> [(x: Double, y: Double)] {
        let i = max(0, min(pieces - 1, i))
        let left: [(x: Double, y: Double)] = i == 0 ? [(0, 0), (0, height)] : cutLine(cuts[i - 1])
        let right: [(x: Double, y: Double)] = i == pieces - 1 ? [(width, 0), (width, height)] : cutLine(cuts[i])
        return left + right.reversed()
    }

    /// i 番目の切れ端の左右の端（1片だけ描くときの箱）
    static func pieceBounds(_ i: Int) -> (minX: Double, maxX: Double) {
        let xs = piece(i).map(\.x)
        return (xs.min() ?? 0, xs.max() ?? width)
    }

    /// 埋まっている切れ端の数（0〜5）
    static func filled(_ fragments: Int) -> Int { TrunkPartsBoxText.filledFragments(fragments) }

    // MARK: 色（案の頁の3色）

    static let paper = TrunkRGBA(0xE9DFC8)
    static let ink = TrunkRGBA(0x5A1D1B)
    /// 紙の明暗（上から下へ）
    static let paperLight = TrunkRGBA(r: 255, g: 248, b: 230, a: 0.55)
    static let paperShade = TrunkRGBA(r: 184, g: 154, b: 106, a: 0.28)
}

/// かけらの数の言葉（札 #713）
enum TrunkFragmentText {
    /// 数の字（「3 / 5」）
    static func count(_ fragments: Int) -> String {
        "\(TrunkFragmentTicket.filled(fragments)) / \(TrunkPartsBoxText.fragmentsPerExchange)"
    }

    /// 5つたまったときの真鍮の一言
    static var ready: String { L("交換できます", "Ready to exchange") }

    /// トランクの「部品箱」のカードに出す言葉（5つなら「交換できます」、ほかは数）
    static func tileCaption(_ fragments: Int) -> String {
        TrunkPartsBoxText.canExchange(fragments: fragments) ? ready : count(fragments)
    }

    /// 投稿のお礼で届いたかけらの札（「かけら +1」）
    static func chip(_ n: Int) -> String { L("かけら +\(n)", "+\(n) fragment") }
}
