import Foundation

// 部屋の外の箱（2026-10-19）。
//
// 床のマスは、その部屋の外の箱を 10 で割った数（1 マス ≈ 25 cm）。車の部屋とトレーラーの部屋は、
// すでに描いてある殻が外の箱なので、ここでは足さない。地面の箱の高さは室内の天井 88。
// ロフトと運転席の上は屋根の上に載る。床のマスも天井の高さも、その箱と同じ（高さ 46）。
//
// 置き場所は、車輪・オーニング・キャンプの敷物・屋根の積み荷・自転車の台と重ならない所。
// 荷物室はトレーラーの胴と前後が重なるので、トレーラーつきでは出さない。

enum CamperVolumes {

    /// 室内の床の上面（殻の床と同じ）
    static let groundFloorY = 34.0
    /// 地面の部屋の高さ（室内の天井）
    static let groundHeight = 88.0
    /// 屋根の上の部屋の高さ
    static let upperHeight = 46.0
    static let cell = 10.0
    /// トレーラーの床（すでにある殻の内側。長さ 110・幅 70）
    static let trailerLength = 110.0
    static let trailerWidth = 70.0

    struct Box: Equatable, Sendable {
        var x0: Double
        var x1: Double
        var z0: Double
        var z1: Double
        var floorTop: Double
        var height: Double

        var length: Double { abs(x1 - x0) }
        var width: Double { abs(z1 - z0) }
    }

    static func bodyRear(_ stage: CamperStage) -> Double { stage == .van ? -100 : -122 }
    static func bodyFront(_ stage: CamperStage) -> Double { stage == .van ? 119 : 120 }
    static func bodyHalfWidth(_ stage: CamperStage) -> Double { stage == .van ? 48 : 50 }
    static func roofTop(_ stage: CamperStage) -> Double { stage == .van ? 126 : 134 }

    /// 殻の前後（トレーラーつきはトレーラーの後ろまで）
    static func shellX(_ stage: CamperStage) -> ClosedRange<Double> {
        let back = stage == .trailer ? -264.0 : bodyRear(stage)
        return back...bodyFront(stage)
    }

    /// その段で外に足す箱。車の部屋とトレーラーの部屋は含まない
    static func boxes(_ stage: CamperStage) -> [CamperRoomKind: Box] {
        let bw = bodyHalfWidth(stage)
        let rt = roofTop(stage)
        let rear = bodyRear(stage)
        let sideNear = -(bw + 6)
        let sideFar = sideNear - 60
        let porchNear = bw + 16
        var out: [CamperRoomKind: Box] = [
            // 後ろの張り出し 120×60（扉の反対側）
            .sideRear: Box(x0: -116, x1: 4, z0: sideNear, z1: sideFar, floorTop: groundFloorY, height: groundHeight),
            // 前の張り出し 120×60（同じ側・前後は重ねない）
            .sideFront: Box(x0: 16, x1: 136, z0: sideNear, z1: sideFar, floorTop: groundFloorY, height: groundHeight),
            // 軒先 120×30（扉の側。オーニングの前で、キャンプの敷物とは左右がずれる）
            .porch: Box(x0: 40, x1: 160, z0: porchNear, z1: porchNear + 30, floorTop: groundFloorY, height: groundHeight),
        ]
        if stage != .trailer {
            // 荷物室 100×70（後ろの自転車の台のさらに後ろ）
            let lockFront = rear - 40
            out[.locker] = Box(x0: lockFront - 100, x1: lockFront, z0: -35, z1: 35, floorTop: groundFloorY, height: groundHeight)
        }
        if stage == .van {
            // 積み荷の上をまたぐロフトと、運転席の上
            out[.loft] = Box(x0: -96, x1: -16, z0: -35, z1: 35, floorTop: rt + 28, height: upperHeight)
            out[.bunk] = Box(x0: 42, x1: 122, z0: -35, z1: 35, floorTop: rt + 8, height: upperHeight)
        } else {
            // 太陽電池の上のロフトと、荷台より前の運転席の上（積み荷の上に脚で載せる）
            out[.loft] = Box(x0: -118, x1: -38, z0: -35, z1: 35, floorTop: rt + 8, height: upperHeight)
            out[.bunk] = Box(x0: 50, x1: 130, z0: -35, z1: 35, floorTop: rt + 34, height: upperHeight)
        }
        return out
    }

    /// 影と寄りの計算に使う外形（殻・トレーラー・足した箱）
    static func bounds(_ stage: CamperStage) -> (x: ClosedRange<Double>, halfWidth: Double) {
        let shell = shellX(stage)
        var x0 = shell.lowerBound
        var x1 = shell.upperBound
        var half = bodyHalfWidth(stage)
        for box in boxes(stage).values {
            x0 = min(x0, box.x0, box.x1)
            x1 = max(x1, box.x0, box.x1)
            half = max(half, abs(box.z0), abs(box.z1))
        }
        return (x0...x1, half)
    }
}

extension CamperBuilder {

    /// 足した部屋の殻（床・屋根・壁 4・窓）。車の部屋とトレーラーは、すでに描いた殻を使う
    mutating func wings() {
        let rt = roofTop
        for (kind, box) in CamperVolumes.boxes(stage) {
            let x0 = min(box.x0, box.x1), x1 = max(box.x0, box.x1)
            let z0 = min(box.z0, box.z1), z1 = max(box.z0, box.z1)
            let len = x1 - x0, wid = z1 - z0
            let cx = (x0 + x1) / 2, cz = (z0 + z1) / 2
            let name = "wing.\(kind.rawValue)"
            rbox("\(name).floor", CV3(cx, box.floorTop - 2, cz), CV3(len, 4, wid), 1.2, .wood)
            rbox("\(name).roof", CV3(cx, box.floorTop + box.height + 2, cz), CV3(len, 4, wid), 1.2, .roof)
            let hy = box.floorTop + box.height / 2
            rbox("\(name).wall.rear", CV3(x0, hy, cz), CV3(3, box.height, wid), 0.8, .alu)
            rbox("\(name).wall.front", CV3(x1, hy, cz), CV3(3, box.height, wid), 0.8, .alu)
            rbox("\(name).wall.near", CV3(cx, hy, z1), CV3(len, box.height, 3), 0.8, .alu)
            rbox("\(name).wall.far", CV3(cx, hy, z0), CV3(len, box.height, 3), 0.8, .alu)
            let outerZ = abs(z0) >= abs(z1) ? z0 : z1
            rbox("\(name).window", CV3(cx, box.floorTop + box.height * 0.55, outerZ), CV3(28, 18, 1.2), 0.6, .glass)
            if box.floorTop - rt > 12 {
                for (px, pz) in [(x0 + 6, z0 + 6), (x0 + 6, z1 - 6), (x1 - 6, z0 + 6), (x1 - 6, z1 - 6)] {
                    rod("\(name).post", CV3(px, rt, pz), CV3(px, box.floorTop - 4, pz), 1.3, .alu, segments: 8)
                }
            }
        }
    }
}
