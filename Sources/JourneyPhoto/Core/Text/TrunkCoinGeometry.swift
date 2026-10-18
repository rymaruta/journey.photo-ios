import Foundation

/// 硬貨の形の数値（`TrunkCoinMark` が描く・2026-10-18）。
///
/// 前は真鍮の放射の塗りの丸だけで、大きく描くと**金色の玉（球）**に見えた（はじめての硬貨の案内・画面写真 96c）。
/// 平たい円盤として描く: 縁（リム）の段 → 一段下がった面 → 浮き彫りの内輪 → 「COIN」の刻印、
/// 真鍮の光は左上から斜め（縁の照り返しは右下）。傾けると縦に潰れて楕円になり、下に厚みの帯が見える。
///
/// 色は旅のトランクの板（Gacha.dc.html の硬貨・COIN の口・ハンドル）の真鍮の段:
/// #FFF1C4（照り）・#F2DFAE・#C9A66B・#8A6B39・#7E6438・#6E5630（陰）、刻印の字 #3A2A12
struct TrunkCoinGeometry: Equatable {
    /// 正面から見た直径（pt）
    let size: Double
    /// 手前へ倒した角度（度）。0 は正面（真円）
    let tilt: Double

    init(size: Double, tilt: Double = 0) {
        self.size = max(1, size)
        self.tilt = min(80, max(0, tilt))
    }

    /// 縁（リム）の幅。直径の 11%（小さくても 1.5pt）
    var rimWidth: Double { max(1.5, size * 0.11) }
    /// 浮き彫りの内輪の位置（外から）。縁の内側にもう一段
    var ringInset: Double { rimWidth + max(1, size * 0.07) }
    /// 内輪の太さ
    var ringWidth: Double { max(0.75, size * 0.025) }
    /// 外の縁の暗い線（板の `inset 0 0 0 2px rgba(60,40,15,0.35)` を大きさに合わせる）
    var outlineWidth: Double { max(1, size * 0.02) }
    /// 刻印の字の下限（CLAUDE.md の例外: 硬貨の COIN の刻印は 7pt まで）
    static let minLetterSize: Double = 7
    /// 刻印を描く最小の直径（直径の 17% が 7pt に届く大きさ）
    static let minLetteredSize: Double = 41
    /// 刻印「COIN」の字の大きさ（読み上げから外した飾り）。直径の 17%・7pt を下回らない
    var letterSize: Double { max(Self.minLetterSize, size * 0.17) }
    /// 刻印を描くか。**字が 7pt に届かない大きさ（直径 41pt 未満・数の行の 26pt の印など）では字だけ描かない**
    /// （縁・面・内輪の形は同じ）
    var showsLetters: Bool { size >= Self.minLetteredSize }
    /// 縦の潰れ（cos）。正面は 1、倒すほど楕円になる
    var squash: Double { cos(tilt * .pi / 180) }
    /// 倒したときに下に見える厚みの帯（直径の 8% × sin）
    var edgeDepth: Double { size * 0.08 * sin(tilt * .pi / 180) }
    /// 描いたときの枠の高さ
    var drawnHeight: Double { size * squash + edgeDepth }
    /// 落とす影（大きい硬貨だけ・小さな印は行の字と並ぶので薄く）
    var shadowRadius: Double { size > 20 ? max(1.5, size * 0.06) : 0 }
    var shadowY: Double { size > 20 ? max(2, size * 0.05) : 0 }
}
