import Foundation

/// ストーリーの写真の合わせ方（拡大・位置・回し）。owner の「ストーリーの自由度が
/// 低い」（2026-09-29）——写真は画面いっぱいに敷くだけで、寄せる・ずらす・傾けることが
/// できなかった。
///
/// **送る画像の大きさは変えない。** 元の写真と同じ画素の枠の中へ、合わせたとおりに
/// 描き直して焼く（`TextOverlayRenderer.burn`）。文字と札の位置は**その枠に対する割合**の
/// ままなので、写真を動かしても札は画面の同じ所に残る（Instagram と同じ）。
/// 枠の中で写真が届かない所は黒（作る画面の地も黒）。
///
/// - `scale`: 枠いっぱい（1）に対する倍率
/// - `offsetX` / `offsetY`: 写真の中心のずれ。**枠の幅・高さに対する割合**
/// - `rotation`: 回し（ラジアン・中心の周り）
///
/// 編集画面（`StoryCanvas`）と焼き込みは**同じ順で重ねる**: 枠の中心へ移し → ずらし →
/// 回し → 倍率。SwiftUI の `.scaleEffect` → `.rotationEffect` → `.offset` と同じ重なり
struct PhotoFraming: Equatable, Codable {

    var scale: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0
    var rotation: Double = 0

    static let identity = PhotoFraming()

    /// 倍率の幅。**下は枠の半分まで（引いて黒い縁を付けられる）、上は5倍まで**
    /// （それ以上は 1920px の写真が粗くなる）
    static let minScale = 0.5
    static let maxScale = 5.0
    /// ずらしの幅（枠の大きさに対する割合）。**写真の中心が枠の外へ出ない所まで**
    /// ——出ると掴み直せない（写真のどこも枠の中に無くなる）
    static let maxOffset = 0.5

    var isIdentity: Bool { self == .identity }

    func scaled(by factor: Double) -> PhotoFraming {
        guard factor.isFinite, factor > 0 else { return self }
        var next = self
        next.scale = min(max(scale * factor, Self.minScale), Self.maxScale)
        return next
    }

    func rotated(by radians: Double) -> PhotoFraming {
        guard radians.isFinite else { return self }
        var next = self
        next.rotation = rotation + radians
        return next
    }

    /// 指で動かした量（画面の点）を、枠（`frame`・画面の点）に対する割合で足す
    func moved(by translation: CGSize, in frame: CGSize) -> PhotoFraming {
        guard frame.width > 0, frame.height > 0,
              translation.width.isFinite, translation.height.isFinite else { return self }
        var next = self
        next.offsetX = Self.clampOffset(offsetX + Double(translation.width / frame.width))
        next.offsetY = Self.clampOffset(offsetY + Double(translation.height / frame.height))
        return next
    }

    static func clampOffset(_ value: Double) -> Double {
        min(max(value, -maxOffset), maxOffset)
    }

    /// 読んだ値を幅に収める（下書きの読み戻し。壊れた値で写真を消さない）
    var sanitized: PhotoFraming {
        PhotoFraming(scale: scale.isFinite ? min(max(scale, Self.minScale), Self.maxScale) : 1,
                     offsetX: offsetX.isFinite ? Self.clampOffset(offsetX) : 0,
                     offsetY: offsetY.isFinite ? Self.clampOffset(offsetY) : 0,
                     rotation: rotation.isFinite ? rotation : 0)
    }

    /// 焼き込みで写真を描く所。`size` の枠の中で、**中心**（ずらしたあと）と、
    /// 中心の周りに回す前の**描く大きさ**
    func placement(in size: CGSize) -> (center: CGPoint, drawSize: CGSize) {
        (CGPoint(x: size.width / 2 + size.width * offsetX, y: size.height / 2 + size.height * offsetY),
         CGSize(width: size.width * scale, height: size.height * scale))
    }

    init(scale: Double = 1, offsetX: Double = 0, offsetY: Double = 0, rotation: Double = 0) {
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.rotation = rotation
    }

    private enum CodingKeys: String, CodingKey { case scale, offsetX, offsetY, rotation }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = PhotoFraming(scale: (try? c.decodeIfPresent(Double.self, forKey: .scale)) ?? 1,
                            offsetX: (try? c.decodeIfPresent(Double.self, forKey: .offsetX)) ?? 0,
                            offsetY: (try? c.decodeIfPresent(Double.self, forKey: .offsetY)) ?? 0,
                            rotation: (try? c.decodeIfPresent(Double.self, forKey: .rotation)) ?? 0)
            .sanitized
    }
}
