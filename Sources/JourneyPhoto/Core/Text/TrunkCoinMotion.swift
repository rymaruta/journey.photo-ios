import Foundation

// 羅針盤の硬貨とカプセルの機械の動き（札 #716・2026-11-23 owner 採用の案の頁の「詳しく」の時間と曲線）。
// 動きは「経った秒 → 位置・向き・透明度」の純粋な関数にして、画面は `TimelineView` で読むだけにする
// （SwiftUI を読まない層なので Linux でテストできる。動かすのは位置、向き、透明度、大きさだけで、影とぼかしは動かさない）。

/// CSS の `cubic-bezier(x1, y1, x2, y2)` と同じ曲線（案の頁の曲線をそのまま写す）
struct TrunkBezier: Equatable {
    let x1: Double, y1: Double, x2: Double, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    static let linear = TrunkBezier(0, 0, 1, 1)
    static let ease = TrunkBezier(0.25, 0.1, 0.25, 1)
    static let easeOut = TrunkBezier(0, 0, 0.58, 1)
    static let easeIn = TrunkBezier(0.42, 0, 1, 1)
    static let easeInOut = TrunkBezier(0.42, 0, 0.58, 1)

    private static func coord(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }

    /// 進み x（0〜1）での値。行き過ぎる曲線（y が 1 を越える）もそのまま返す
    func value(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // x(t) = x を二分法で解く（単調なので 30 回で十分）
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<30 {
            t = (lo + hi) / 2
            if Self.coord(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return Self.coord(t, y1, y2)
    }
}

/// キーフレーム（CSS の `@keyframes` と同じく、区間ごとに曲線をかける）
struct TrunkKeyframes: Equatable {
    struct Key: Equatable {
        /// 0〜1 の位置
        let at: Double
        let value: Double
        /// この位置から次の位置までの曲線
        var curve: TrunkBezier = .ease
    }

    let keys: [Key]

    init(_ keys: [Key]) { self.keys = keys.sorted { $0.at < $1.at } }

    /// 同じ曲線を区間ごとにかける
    init(_ pairs: [(Double, Double)], curve: TrunkBezier) {
        self.init(pairs.map { Key(at: $0.0, value: $0.1, curve: curve) })
    }

    /// 進み p（0〜1）での値
    func value(_ p: Double) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if p <= first.at { return first.value }
        if p >= last.at { return last.value }
        for i in 0..<(keys.count - 1) where p <= keys[i + 1].at {
            let a = keys[i], b = keys[i + 1]
            let span = b.at - a.at
            guard span > 0 else { return b.value }
            return a.value + (b.value - a.value) * a.curve.value((p - a.at) / span)
        }
        return last.value
    }
}

/// 動きの時間と曲線（案の頁の値）
enum TrunkMotion {

    // MARK: 羅針盤の針（手に取ったとき・もらったとき）

    /// 針が揺れて北で止まる（1.15 秒・-38、22、-12、6、-2、0 度・cubic-bezier(.2,.7,.3,1)）
    static let needleSeconds = 1.15
    static let needle = TrunkKeyframes([(0, -38), (0.2, 22), (0.4, -12), (0.6, 6), (0.8, -2), (1, 0)],
                                       curve: TrunkBezier(0.2, 0.7, 0.3, 1))

    static func needleAngle(elapsed: Double) -> Double {
        needle.value(elapsed / needleSeconds)
    }

    /// 縁の光（24 本の弧を 0.04 秒ずつ遅らせて点ける・1本 0.95 秒。18% で 0.9、70% で 0）
    static let rimLightSeconds = 0.95
    static let rimLightDelay = 0.04
    static let rimLight = TrunkKeyframes([(0, 0), (0.18, 0.9), (0.7, 0), (1, 0)], curve: .easeOut)

    static func rimLightOpacity(arc i: Int, elapsed: Double) -> Double {
        let t = elapsed - Double(i) * rimLightDelay
        guard t > 0 else { return 0 }
        return rimLight.value(t / rimLightSeconds)
    }

    /// 針と縁の光が終わるまで（24 本目の弧が消えるまで）
    static var pickUpSeconds: Double { max(needleSeconds, 23 * rimLightDelay + rimLightSeconds) }

    /// 大きい絵の傾く光沢（7 秒で左右に・rotateY ±24°、rotateX 6 → -4）
    static let tiltSeconds = 7.0

    // MARK: 硬貨をもらう（届いた画面の札・案「投稿して硬貨をもらう瞬間」）

    /// ラベルが貼りついてから硬貨が落ち始めるまで
    static let coinAfterLabel = 0.25
    /// 硬貨が札に落ちる長さ
    static let coinFallSeconds = 0.62
    /// 落ちる硬貨の描く大きさ（札の 14pt へ 0.35 倍で縮む）
    static let coinFallSize = 40.0
    static let coinFallY = TrunkKeyframes([(0, -170), (0.78, 4), (1, 0)], curve: TrunkBezier(0.35, 0, 0.3, 1))
    static let coinFallScale = TrunkKeyframes([(0, 1), (0.78, 0.38), (1, 0.35)], curve: TrunkBezier(0.35, 0, 0.3, 1))
    static let coinFallOpacity = TrunkKeyframes([(0, 0), (0.12, 1), (1, 1)], curve: .linear)
    /// 回りながら落ちる（横の縮みで表と裏を見せる）
    static let coinFlip = TrunkKeyframes([(0, 1), (0.2, 0.1), (0.4, 1), (0.6, 0.1), (0.8, 1), (1, 1)], curve: .linear)
    /// 札が少しふくらむ（0.28 秒・45% で 1.07 倍）
    static let chipBumpSeconds = 0.28
    static let chipBump = TrunkKeyframes([(0, 1), (0.45, 1.07), (1, 1)], curve: .ease)

    // MARK: カプセルの機械

    /// ハンドルの目盛りを跳ぶ（カチッ）長さ
    static let detentSnapSeconds = 0.06
    /// ボタンで回すときの1歩の曲線（少し行き過ぎる・0.055 秒）
    static let autoStepSnapSeconds = 0.055
    static let autoStepCurve = TrunkBezier(0.2, 0.9, 0.3, 1.35)
    /// 途中で離したときに 0° へ戻る（0.45 秒・cubic-bezier(.3,1.35,.5,1)）
    static let springBackSeconds = 0.45
    static let springBackCurve = TrunkBezier(0.3, 1.35, 0.5, 1)
    /// 0枚・圏外でハンドルを触ったときの小さな揺れ（0.36 秒・-9°、7°）
    static let wiggleSeconds = 0.36
    static let wiggle = TrunkKeyframes([(0, 0), (0.25, -9), (0.6, 7), (1, 0)], curve: .ease)

    /// 1周したところの溜め（0.06 秒待って、0.12 秒で 8° 行き過ぎ、0.16 秒で戻る）
    static let windUpPause = 0.06
    static let windUpOvershoot = 8.0
    static let windUpOutSeconds = 0.12
    static let windUpBackSeconds = 0.16
    static let windUpBackCurve = TrunkBezier(0.3, 1.4, 0.5, 1)

    /// カプセルが落ちる（0.62 秒。55% で底に着き、76% で 11pt 弾み、100% で止まる）
    static let dropSeconds = 0.62
    static let dropFrom = -64.0
    static let drop = TrunkKeyframes([
        .init(at: 0, value: -64, curve: TrunkBezier(0.55, 0, 1, 0.6)),
        .init(at: 0.55, value: 0, curve: TrunkBezier(0, 0.45, 0.4, 1)),
        .init(at: 0.76, value: -11, curve: TrunkBezier(0.6, 0, 1, 0.6)),
        .init(at: 1, value: 0, curve: .linear),
    ])
    /// 底に着いた瞬間（重い触覚・光の輪）
    static var landsAt: Double { dropSeconds * 0.55 }

    static func dropOffset(elapsed: Double) -> Double { drop.value(elapsed / dropSeconds) }

    /// 取り出し口のふた（上へ跳ね上がって 0.3 秒で戻る）
    static let flapSeconds = 0.3
    static let flapOpen = -0.15

    /// 取り出し口の光の輪（0.55 秒・0.4 倍 → 1.7 倍、0.9 → 0）
    static let outletRingSeconds = 0.55
    static func outletRing(elapsed: Double) -> (scale: Double, opacity: Double) {
        let p = TrunkBezier.easeOut.value(min(1, max(0, elapsed / outletRingSeconds)))
        return (0.4 + 1.3 * p, elapsed >= outletRingSeconds ? 0 : 0.9 * (1 - p))
    }

    /// 硬貨を入れる（重ねた硬貨のいちばん上が、顔を見せたまま入れ口の上へ 0.26 秒、入れ口へ 0.16 秒で沈んで消える）
    static let insertLiftSeconds = 0.26
    static let insertLiftCurve = TrunkBezier(0.3, 0.7, 0.3, 1)
    static let insertSinkSeconds = 0.16
    static let insertSinkCurve = TrunkBezier(0.5, 0, 0.9, 0.5)
    static let insertSinkScale = 0.8

    /// 中のカプセルの層が目盛りでずれる（0.07 秒でずれ、0.32 秒で弾んで戻る）
    static let jostleOutSeconds = 0.07
    static let jostleBackSeconds = 0.32
    static let jostleBackCurve = TrunkBezier(0.3, 1.5, 0.5, 1)

    /// 目盛りを越えた回の、層ごとのずれ（乱数の代わりに回と層から決める・強さ k）
    static func jostle(layer: Int, beat: Int, k: Double) -> (dx: Double, dy: Double, rotation: Double) {
        func unit(_ salt: Int) -> Double {
            // 0〜1 の決まった値（同じ回と層なら同じ）
            var h = UInt64(truncatingIfNeeded: beat &* 2_654_435_761 &+ layer &* 40_503 &+ salt &* 97)
            h ^= h >> 13; h = h &* 0x5bd1e995; h ^= h >> 15
            return Double(h % 10_000) / 10_000
        }
        let dx = (unit(1) * 2 - 1) * 3.2 * k
        let dy = -(1.2 + unit(2) * 3) * k
        let r = (unit(3) * 2 - 1) * 4 * k + Double(layer - 1) * 1.5 * k
        return (dx, dy, r)
    }

    /// 回している間の小さな震え（0.32 秒で一回り）
    static let jigSeconds = 0.32
    static let jigX = TrunkKeyframes([(0, 0), (0.25, -1.6), (0.5, 1), (0.75, 1.6), (1, 0)], curve: .linear)
    static let jigY = TrunkKeyframes([(0, 0), (0.25, 1), (0.5, -1.4), (0.75, 0.8), (1, 0)], curve: .linear)

    static func jig(elapsed: Double) -> (dx: Double, dy: Double) {
        let p = elapsed.truncatingRemainder(dividingBy: jigSeconds) / jigSeconds
        return (jigX.value(p), jigY.value(p))
    }

    /// 待っているときガラスを走る光（6 秒ごと・55% まで休み、65% で見え、100% で 420pt 右へ）
    static let sweepSeconds = 6.0
    static func sweep(elapsed: Double) -> (x: Double, opacity: Double) {
        let p = elapsed.truncatingRemainder(dividingBy: sweepSeconds) / sweepSeconds
        let e = TrunkBezier.easeInOut.value(p)
        guard p > 0.55 else { return (0, 0) }
        let move = (e - TrunkBezier.easeInOut.value(0.55)) / (1 - TrunkBezier.easeInOut.value(0.55))
        let opacity = p < 0.65 ? (p - 0.55) / 0.1 : 1 - (p - 0.65) / 0.35
        return (420 * move, max(0, min(1, opacity)))
    }

    /// 入れ口の背の光（2.4 秒で呼吸・0.45 ↔ 1）
    static let pulseSeconds = 2.4

    // MARK: 開けた画面

    /// 全画面が下から出たあと、カプセルが割れ始めるまで
    static let openDelay = 0.4
    /// 半分2つが離れる・部品が 0.6 倍から出る
    static let splitSeconds = 0.46
    static let partFrom = 0.6
    /// 段階で出る文（眉 0.3・見出し 0.4・線 0.45・一行 0.5・札 0.55・ボタン 0.65 秒遅れて 0.5 秒で）
    static let stageDelays: [Double] = [0.3, 0.4, 0.45, 0.5, 0.55, 0.65]
    static let stageSeconds = 0.5
    static let stageRise = 12.0
    /// 衝撃の輪（0.7 秒・0.3 倍 → 3.4 倍、0.9 → 0）
    static let shockSeconds = 0.7
    static func shock(elapsed: Double) -> (scale: Double, opacity: Double) {
        let p = TrunkBezier.easeOut.value(min(1, max(0, elapsed / shockSeconds)))
        return (0.3 + 3.1 * p, elapsed >= shockSeconds || elapsed < 0 ? 0 : 0.9 * (1 - p))
    }
    /// きらめき（2.6 秒で一回り・遅れは1つずつ）
    static let twinkleSeconds = 2.6
    static func twinkle(elapsed: Double, delay: Double) -> (scale: Double, opacity: Double, rotation: Double) {
        let t = elapsed - delay
        guard t > 0 else { return (0.3, 0, 0) }
        let p = t.truncatingRemainder(dividingBy: twinkleSeconds) / twinkleSeconds
        // 0 → 50% → 100% を ease-in-out で行って戻る
        let half = p < 0.5 ? TrunkBezier.easeInOut.value(p * 2) : TrunkBezier.easeInOut.value((1 - p) * 2)
        return (0.3 + 0.7 * half, half, 45 * half)
    }
    /// 部品の揺れ（3.6 秒で 6pt 上下）
    static let bobSeconds = 3.6
    static let bobHeight = 6.0
    static func bob(elapsed: Double) -> Double {
        let p = elapsed.truncatingRemainder(dividingBy: bobSeconds) / bobSeconds
        let half = p < 0.5 ? TrunkBezier.easeInOut.value(p * 2) : TrunkBezier.easeInOut.value((1 - p) * 2)
        return -bobHeight * half
    }
    /// 光の放射（20 秒で一回り）
    static let raysSeconds = 20.0
    /// 持っている部品: 部品が影になり始めるまで（割れてから）と、切れ端が札の切符へ入る長さ
    static let fragmentAfterOpen = 0.65
    static let fragmentTilt = -14.0
    static let fragmentLiftSeconds = 0.28
    static let fragmentFlySeconds = 0.46
}

extension TrunkCrank {
    /// ハンドルの引っかかり（札 #716・案「回すときの手ざわり」）。指の角度 `raw`（0〜360）から、見せる角度を決める:
    /// 目盛り（30°）の間は指の 45% しか進まず（重さ）、目盛りの間の 72% を越えると次の目盛りへ跳ぶ（カチッ）。360 で1周
    static func detent(raw: Double) -> Double {
        if raw >= goal { return goal }
        guard raw > 0 else { return 0 }
        let k = floor(raw / tickStep)
        let t = raw / tickStep - k
        return tickStep * k + (t < detentJump ? tickStep * detentDrag * (t / detentJump) : tickStep)
    }

    /// 目盛りの間で指に付いて進む割合
    static let detentDrag = 0.45
    /// 次の目盛りへ跳ぶ位置（目盛りの間の割合）
    static let detentJump = 0.72

    /// 点いている目盛りの数（0〜12・見せる角度から）
    var litTicks: Int { min(12, Int(floor(angle / Self.tickStep + 1e-6))) }
}
