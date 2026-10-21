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

    /// その段で外に足す箱。車の部屋とトレーラーの部屋は含まない。
    /// 殻の絵は伸ばさない。住む所の箱だけを大きくし、床のマスも同じだけ増やす。
    static func boxes(_ stage: CamperStage) -> [CamperRoomKind: Box] {
        let bw = bodyHalfWidth(stage)
        let rt = roofTop(stage)
        let rear = bodyRear(stage)
        // バンは殻が短いので、張り出しは一回り小さくする
        let sideLen = stage == .van ? 160.0 : 180.0
        let sideDepth = stage == .van ? 90.0 : 110.0
        let sideNear = -(bw + 6)
        let sideFar = sideNear - sideDepth
        let porchNear = bw + 16
        let porchDepth = stage == .van ? 60.0 : 100.0
        // キャンピングカーの軒先はオーニングの布（x 32 まで）より前から。バンにオーニングは無い
        let porchX0 = stage == .van ? 16.0 : 40.0
        var out: [CamperRoomKind: Box] = [
            // 後ろの張り出し（扉の反対側。キャンピングカー 18×11、バン 16×9）
            .sideRear: Box(x0: 10 - sideLen, x1: 10, z0: sideNear, z1: sideFar, floorTop: groundFloorY, height: groundHeight),
            // 前の張り出し（同じ側。前後は 16 空ける）
            .sideFront: Box(x0: 26, x1: 26 + sideLen, z0: sideNear, z1: sideFar, floorTop: groundFloorY, height: groundHeight),
            // 軒先（扉の側。キャンプの敷物とは左右がずれる。キャンピングカー 14×10、バン 14×6）
            .porch: Box(x0: porchX0, x1: porchX0 + 140, z0: porchNear, z1: porchNear + porchDepth, floorTop: groundFloorY, height: groundHeight),
        ]
        if stage != .trailer {
            // 荷物室 12×7（自転車の台のさらに後ろ。トレーラーの胴とは出さない）
            let lockFront = rear - 40
            out[.locker] = Box(x0: lockFront - 120, x1: lockFront, z0: -35, z1: 35, floorTop: groundFloorY, height: groundHeight)
        }
        if stage == .van {
            // 積み荷より高いロフト 12×7 と、アンテナより前の運転席の上 9×7
            out[.loft] = Box(x0: -110, x1: 10, z0: -35, z1: 35, floorTop: rt + 28, height: upperHeight)
            out[.bunk] = Box(x0: 48, x1: 138, z0: -35, z1: 35, floorTop: rt + 8, height: upperHeight)
        } else {
            // 太陽電池の上のロフト 12×7。運転席の上 12×7 は荷台の先（x 70）から、アンテナの外
            out[.loft] = Box(x0: -160, x1: -40, z0: -35, z1: 35, floorTop: rt + 8, height: upperHeight)
            out[.bunk] = Box(x0: 70, x1: 190, z0: -35, z1: 35, floorTop: rt + 8, height: upperHeight)
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

