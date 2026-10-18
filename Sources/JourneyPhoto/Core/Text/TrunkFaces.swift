import Foundation

// 回したときの面（板「旅のトランク」の TrunkFaces・Trunk.dc.html の `face`・2026-10-18 owner 承認）。
//
// 正面と同じ素材・縫い目・古び方で、左右の側面・上の面・底・背面を描く**数だけ**を持つ（SwiftUI を読まない層）。
// 色は正面と同じ `TrunkLooks.look(model, stage:)`、古び方も同じ段（`TrunkAging.stage`）。
// 画面（`Features/Trunk/TrunkFaceView.swift`）はここの値を読んで描き、SceneKit の箱の各面に貼る。
//
// 寸法（板の注記）: 胴 360×268・側面 86×268・上下 360×86・ふたの合わせ目は正面から 26。
// 向きは展開図のまま——上の面は正面の辺が下、底は正面の辺が上、側面は正面の辺が内側。
// ふたは前開き（2026-10-18 決定）: 蝶番は**底の前寄り**、持ち手は上の面に残す。

/// 回したときに見える面（正面は `TrunkBoxView`）
enum TrunkFaceSide: String, CaseIterable {
    case left, right, top, bottom, back
}

enum TrunkFaces {

    /// 厚み（横 360 の 0.24・板の D）
    static let depth: Double = 86
    /// ふたの合わせ目（正面から・板の LID）
    static let lidSeam: Double = 26
    /// 背面の型押し「JOURNEY PHOTO」の上の位置
    static let markY: Double = 216
    /// 面の角の丸み（板の `border-radius: 10px`）
    static let faceCorner: Double = 10

    /// 面の大きさ（幅・高さ）
    static func size(_ side: TrunkFaceSide) -> (w: Double, h: Double) {
        switch side {
        case .left, .right: return (depth, TrunkLooks.bodyHeight)
        case .top, .bottom: return (TrunkLooks.bodyWidth, depth)
        case .back: return (TrunkLooks.bodyWidth, TrunkLooks.bodyHeight)
        }
    }

    /// 面の名前（読み上げ）
    static func name(_ side: TrunkFaceSide) -> String {
        switch side {
        case .left: return L("左の側面", "left side")
        case .right: return L("右の側面", "right side")
        case .top: return L("上の面", "top")
        case .bottom: return L("底", "bottom")
        case .back: return L("背面", "back")
        }
    }

    static func accessibilityLabel(model: TrunkModel, side: TrunkFaceSide) -> String {
        L("\(TrunkText.info(model).name)の\(name(side))", "\(TrunkText.info(model).name), \(name(side))")
    }

    // MARK: 向きのボタン（板 TrunkSpin）

    /// 決まった向き（名前・読み上げ・横の回りと縦の傾き〔ラジアン・SceneKit の向き〕）。
    /// 板の CSS（`rotateX(rx) rotateY(ry)`）の度を、縦は符号を返して写す（SceneKit は上が +y）
    struct View: Equatable {
        let id: String
        let name: String
        let label: String
        let yaw: Double
        let pitch: Double
    }

    static var views: [View] {
        func rad(_ deg: Double) -> Double { deg * .pi / 180 }
        return [
            View(id: "front", name: L("正面", "Front"), label: L("正面を見る", "Show the front"), yaw: rad(0), pitch: rad(8)),
            View(id: "side", name: L("側面", "Side"), label: L("側面を見る", "Show the side"), yaw: rad(-90), pitch: rad(10)),
            View(id: "topBack", name: L("上と背面", "Top & back"), label: L("上と背面を見る", "Show the top and back"),
                 yaw: rad(-160), pitch: rad(48)),
            View(id: "bottom", name: L("底", "Bottom"), label: L("底を見る（蝶番と足）", "Show the bottom (hinges and feet)"),
                 yaw: rad(-20), pitch: rad(-70)),
        ]
    }

    // MARK: ふたの合わせ目と蝶番

    /// ふたの合わせ目（縦の線なら x・横の線なら y）。**背面には無い**（ふたは正面だけ）
    static func seam(_ side: TrunkFaceSide) -> (position: Double, horizontal: Bool)? {
        let s = size(side)
        switch side {
        case .left: return (s.w - lidSeam, false)
        case .right: return (lidSeam, false)
        case .top: return (s.h - lidSeam, true)
        case .bottom: return (lidSeam, true)
        case .back: return nil
        }
    }

    /// 合わせ目が金属の縁か（アルミ・飛行艇は帯と同じ金属の 6pt、ほかは暗い 3pt の線）
    static func seamIsMetal(_ model: TrunkModel) -> Bool { model == .aluminum || model == .clipper }

    static func seamThickness(_ model: TrunkModel) -> Double { seamIsMetal(model) ? 6 : 3 }

    /// 蝶番（**底の前寄り**だけ・前開きの軸）。合わせ目をまたいで 28×16 を2つ
    static func hinges(_ side: TrunkFaceSide) -> [TrunkRect] {
        guard side == .bottom, let seam = seam(side) else { return [] }
        return [64.0, 268].map { TrunkRect(x: $0, y: seam.position - 8, w: 28, h: 16) }
    }

    // MARK: 持ち手（上の面）

    /// 上の面の持ち手（真上から見た帯）。太さは正面の持ち手の太さ＋4（板の `hT`）
    static func handle(_ side: TrunkFaceSide, thickness: Double = 10) -> TrunkRect? {
        guard side == .top else { return nil }
        let t = thickness + 4
        return TrunkRect(x: 128, y: 30 - t / 2, w: 104, h: t)
    }

    /// 持ち手の付け根の真ん中（胴の左から）。**正面の絵（120・220 に幅 20）・上の面・立体の金具で同じ**
    /// （板の上の面は 116・224 だったが、正面の付け根と ±4 ずれ、回すと金具が持ち手の脚から外れて見えた・2026-10-18）
    static let handleClipCenters: [Double] = [130, 230]

    /// 持ち手の付け根の金具（錠前と同じ金属・20×20）
    static func handleClips(_ side: TrunkFaceSide) -> [TrunkRect] {
        guard side == .top else { return [] }
        return handleClipCenters.map { TrunkRect(x: $0 - 10, y: 20, w: 20, h: 20) }
    }

    /// 持ち手に縫い目があるか（アルミ・漆は無し。正面と同じ）
    static func handleStitched(_ model: TrunkModel) -> Bool { model != .aluminum && model != .urushi }

    // MARK: 吊るす物（立体・#305）

    /// 立体の正面に吊るす物（ラベルの手荷物タグ・部品のタグ・チャーム・鍵）を描くとき、2D の絵（360×300）の y から
    /// 引く量。2D ではタグの紐の上の端が y 2（胴の上の縁より上）なので、正面の絵では紐の上の端を胴の上の縁（0）に
    /// そろえ、札・チャーム・鍵が胴の上の縁から下がって見えるようにする（2D のまま胴の座標にすると上の 30 が切れる）
    static let frontHangLift: Double = TrunkLooks.tagStringTop

    /// 吊るす紐1本（上の面: 持ち手から正面の辺へ・正面: 上の縁から吊るす点へ）
    struct HangCord: Equatable {
        let fromX: Double
        let fromY: Double
        let toX: Double
        let toY: Double
        let width: Double
        let color: TrunkRGBA
    }

    /// 上の面の紐の付け根（持ち手の付け根の金具の間・持ち手の帯の真ん中の高さ）。外にあるものは近い付け根から
    static func cordRoot(_ x: Double) -> (x: Double, y: Double) {
        let lo = handleClipCenters[0], hi = handleClipCenters[handleClipCenters.count - 1]
        return (min(hi, max(lo, x)), 30)
    }

    /// 上の面に渡す紐（吊るす物ごとに1本・持ち手から正面の辺〔y = 厚み〕の吊るす点の真上へ）。
    /// 立体では正面の絵（`TrunkBoxView` の `hangsOnFront`）が吊るした物を描き、ここで持ち手からつなぐ
    static func topCords(tags: [TrunkLooks.Tag], fittings: TrunkFittings) -> [HangCord] {
        var out: [HangCord] = []
        for t in tags {
            let x = t.x + TrunkLooks.tagStringInset + TrunkLooks.tagStringWidth / 2
            let root = cordRoot(x)
            out.append(HangCord(fromX: root.x, fromY: root.y, toX: x, toY: depth,
                                width: TrunkLooks.tagStringWidth, color: TrunkLooks.tagStringColor))
        }
        for p in fittings.placements where !p.onBody {
            guard let cord = TrunkFittings.cord(p) else { continue }
            let root = cordRoot(p.hangX)
            out.append(HangCord(fromX: root.x, fromY: root.y, toX: p.hangX, toY: depth, width: cord.width, color: cord.color))
        }
        return out
    }

    /// 正面の上の縁から、吊るした部品の吊るす点までの紐（ラベルのタグは自分の紐が縁から始まるので要らない）。
    /// 座標は正面の絵（胴 360×268）
    static func frontCords(fittings: TrunkFittings) -> [HangCord] {
        fittings.placements.filter { !$0.onBody }.compactMap { p in
            guard let cord = TrunkFittings.cord(p) else { return nil }
            let y = p.hangY - frontHangLift
            guard y > 0 else { return nil }
            // 部品の紐・輪の上の端の少し下まで（つなぎ目を見せない）
            return HangCord(fromX: p.hangX, fromY: 0, toX: p.hangX, toY: y + 2, width: cord.width, color: cord.color)
        }
    }

    // MARK: 桟・帯・ベルト

    /// 面に描く桟・帯（横なら y・縦なら x）
    struct Band: Equatable {
        let horizontal: Bool
        let position: Double
        let size: Double
        /// 真鍮の帯（桟の色ではなく）
        let brass: Bool
    }

    /// 桟・帯の回り込み（板の `fBars`）。
    /// - 側面: 横の桟はそのまま、縦の桟は1本だけ真ん中に
    /// - 上・底: 縦の桟はそのまま通り、横の桟は上（y < 40）か下（y > 200）の縁にあるものだけ両端に
    /// - 背面: 正面と同じ
    static func bands(_ side: TrunkFaceSide, look: TrunkLook) -> [Band] {
        let yBars = look.bars.filter { $0.y != nil }
        let xBars = look.bars.filter { $0.x != nil }
        switch side {
        case .left, .right:
            var out = yBars.map { Band(horizontal: true, position: $0.y ?? 0, size: $0.size, brass: $0.brass) }
            if let first = xBars.first {
                out.append(Band(horizontal: false, position: (depth - first.size) / 2, size: first.size, brass: first.brass))
            }
            return out
        case .top, .bottom:
            var out = xBars.map { Band(horizontal: false, position: $0.x ?? 0, size: $0.size, brass: $0.brass) }
            for bar in yBars where side == .top ? (bar.y ?? 0) < 40 : (bar.y ?? 0) > 200 {
                out.append(Band(horizontal: true, position: 0, size: bar.size, brass: bar.brass))
                out.append(Band(horizontal: true, position: depth - bar.size, size: bar.size, brass: bar.brass))
            }
            return out
        case .back:
            return look.bars.map { bar in
                if let x = bar.x { return Band(horizontal: false, position: x, size: bar.size, brass: bar.brass) }
                return Band(horizontal: true, position: bar.y ?? 0, size: bar.size, brass: bar.brass)
            }
        }
    }

    /// ベルト・組紐・麻縄が通る面（上・底・背面。尾錠は正面だけ）
    static func showsStraps(_ side: TrunkFaceSide) -> Bool { side == .top || side == .bottom || side == .back }

    /// 胴を横切る帯が一周して見える面（左右・背面）
    static func showsRail(_ side: TrunkFaceSide) -> Bool { side == .left || side == .right || side == .back }

    // MARK: 鋲

    struct Rivet: Equatable {
        let x: Double
        let y: Double
        let r: Double
        /// 桟の上の真鍮の鋲（列の鋲ではなく）
        let slat: Bool
    }

    /// 鋲（板の `fRivets`）。列の鋲は面の幅に並べ直し、桟の鋲は桟に沿って
    static func rivets(_ side: TrunkFaceSide, look: TrunkLook) -> [Rivet] {
        var out: [Rivet] = []
        let xBars = look.bars.filter { $0.x != nil }
        func row(from: Double, to: Double, step: Double, y: Double) {
            var x = from
            while x <= to {
                out.append(Rivet(x: x, y: y, r: 2, slat: false))
                x += step
            }
        }
        switch side {
        case .left, .right:
            if look.slatRivets, !xBars.isEmpty {
                for y in [30.0, 100, 170, 240] { out.append(Rivet(x: depth / 2, y: y, r: 2.6, slat: true)) }
            }
            for r in look.rivetRows { row(from: 12, to: depth - 12, step: r.step, y: r.y) }
        case .top, .bottom:
            for r in look.rivetRows where side == .top ? r.y < 40 : r.y > 200 {
                for y in [8.0, depth - 8] { row(from: 22, to: TrunkLooks.bodyWidth - 22, step: r.step, y: y) }
            }
            if look.slatRivets {
                for bar in xBars {
                    for y in [22.0, 64] { out.append(Rivet(x: (bar.x ?? 0) + bar.size / 2, y: y, r: 2.6, slat: true)) }
                }
            }
        case .back:
            for r in look.rivetRows { row(from: 22, to: TrunkLooks.bodyWidth - 22, step: r.step, y: r.y) }
            if look.slatRivets {
                for bar in xBars {
                    for y in [30.0, 100, 170, 240] { out.append(Rivet(x: (bar.x ?? 0) + bar.size / 2, y: y, r: 2.6, slat: true)) }
                }
            }
        }
        return out
    }

    // MARK: 角金具

    /// 角金具の大きさ（3つの面にまたがる。側面・上・底は厚みの 46% までに縮める）
    static func cornerSize(_ side: TrunkFaceSide, look: TrunkLook) -> Double {
        side == .back ? look.corners.size : min(look.corners.size, (depth * 0.46).rounded())
    }

    // MARK: 底の足

    enum FootKind: Equatable {
        /// 真鍮（漆は金箔）の丸い足 16
        case metal(TrunkMetal)
        /// ゴムの足 18（アルミ・飛行艇）
        case rubber
        /// 革の当て 24×16（柳行李）
        case leatherPad
        /// 滑り材の鋲（船旅・船長）
        case stud
    }

    struct Foot: Equatable {
        let x: Double
        let y: Double
        let kind: FootKind
    }

    /// 底の足と滑り材（底だけ・型で違う）
    static func feet(_ side: TrunkFaceSide, model: TrunkModel) -> (feet: [Foot], runners: [TrunkRect]) {
        guard side == .bottom else { return ([], []) }
        let w = TrunkLooks.bodyWidth
        let points: [(Double, Double)] = [(46, 22), (w - 46, 22), (46, depth - 22), (w - 46, depth - 22)]
        switch model {
        case .steamer, .captain:
            let runners = [16.0, depth - 26].map { TrunkRect(x: 30, y: $0, w: w - 60, h: 10) }
            let studs = [21.0, depth - 21].flatMap { y in [60.0, 180, 300].map { Foot(x: $0, y: y, kind: .stud) } }
            return (studs, runners)
        case .aluminum, .clipper:
            return (points.map { Foot(x: $0.0, y: $0.1, kind: .rubber) }, [])
        case .kori:
            return (points.map { Foot(x: $0.0, y: $0.1, kind: .leatherPad) }, [])
        case .urushi:
            return (points.map { Foot(x: $0.0, y: $0.1, kind: .metal(.gilt)) }, [])
        case .leather, .canvas, .sleeper, .starchart:
            return (points.map { Foot(x: $0.0, y: $0.1, kind: .metal(.brass)) }, [])
        }
    }

    // MARK: 絵

    enum SideArt: Equatable {
        /// 漆の金の波の帯（下に並ぶ・升の幅）
        case waves(tile: Double)
        /// 星図の金の星が散る
        case stars
    }

    /// 側面・上・底の絵（背面は `backArt`）
    static func sideArt(_ model: TrunkModel, side: TrunkFaceSide) -> SideArt? {
        guard side != .back else { return nil }
        switch model {
        case .urushi: return .waves(tile: side == .left || side == .right ? 43 : 60)
        case .starchart: return .stars
        default: return nil
        }
    }

    /// 背面の絵（漆の金蒔絵の波と丸紋の続き・星図の星座の続き）
    static func backArt(_ model: TrunkModel) -> TrunkArt? {
        switch model {
        case .urushi: return .makie
        case .starchart: return .stars
        default: return nil
        }
    }

    /// 縁が擦れて明るくなる素材（革・布・木）
    static func softEdges(_ model: TrunkModel) -> Bool {
        [.leather, .sleeper, .starchart, .canvas, .steamer].contains(model)
    }

    /// 縁の擦れの強さ（内側の光の幅とぼかし・濃さ）。古び方 0 なら無し（板 Trunk の `edgeWear`）。
    /// 正面（胴 360×268）は `inset (2+5st)px`・`(18+26st)px`、回したときの面は `(2+4st)px`・`(14+18st)px`
    static func edgeWear(_ model: TrunkModel, stage st: Double, front: Bool = false) -> (width: Double, blur: Double, alpha: Double)? {
        guard softEdges(model), st > 0 else { return nil }
        return front ? (2 + 5 * st, 18 + 26 * st, 0.16 * st) : (2 + 4 * st, 14 + 18 * st, 0.16 * st)
    }

    /// 縁の革の太さ（正面より 2 細く・5 より細くしない）。縁の無い型は 0
    static func bindingWidth(_ look: TrunkLook) -> Double {
        look.binding.width > 0 ? max(5, look.binding.width - 2) : 0
    }

    /// 縫い目の内側への寄り（正面の縫い目より 1 外）
    static func stitchInset(_ look: TrunkLook) -> Double {
        max(2, (look.binding.width > 0 ? look.binding.width : 6) - 5)
    }
}
