import SwiftUI

/// 写真の上に置く「ガラス」（デザインシステム・ストーリーの板）。
///
/// **黒55%＋ぼかし＋白の髪線。** 板はどの画面でもこの3つを組にしている
/// （`background: rgba(0,0,0,0.55); backdrop-filter: blur(18px);
/// border: 1px solid rgba(255,255,255,0.10)`）。以前は `Color.black.opacity(0.55)`
/// を直に書く所と `.ultraThinMaterial` を使う所が混ざっていた。
///
/// 写真の上の文字は白だけ（`WebTheme` の規則）。真鍮は写真の上では沈む。
///
/// **2026-11-25 判断（人間工学の案 6）**: iPhone の「透明度を下げる」をオンにしている人には、
/// 透けない #161617（`WebTheme.sheet`・板のシートと入力欄の地）にする。屋外の日差しで、明るい写真や地図が
/// 札の下から透けて字が読みにくい人の設定。新しい設定は足さない（オフの人は今のまま）。決まりは `JPGlassLook`
extension View {

    /// - Parameters:
    ///   - shape: 形（丸・カプセル・角丸）
    ///   - border: 縁の白の濃さ。返信欄は 0.35、入力中は 0.6（板の値）
    func jpGlass<S: Shape>(in shape: S, border: Double = 0.10) -> some View {
        modifier(JPGlassFace(shape: shape, border: border))
    }

    /// 写真の上の大きい文字の影（板の `text-shadow: 0 2px 14px rgba(0,0,0,0.6)`）
    func jpPhotoTextShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.6), radius: 7, x: 0, y: 2)
    }
}

/// ガラスの地の決まり（画面を持たない・単体テスト用）
enum JPGlassLook: Equatable {
    /// 黒 55%＋ぼかし（板のガラス）
    case seeThrough
    /// 透けない #161617（「透明度を下げる」の人）
    case opaque

    static func look(reduceTransparency: Bool) -> JPGlassLook {
        reduceTransparency ? .opaque : .seeThrough
    }

    /// 透けるときの黒の濃さ（板の 55%）
    static let tint: Double = 0.55
}

/// ガラスの地。「透明度を下げる」を読むために修飾子にしてある（`View` の拡張だけでは環境の値を読めない）
private struct JPGlassFace<S: Shape>: ViewModifier {
    let shape: S
    let border: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        switch JPGlassLook.look(reduceTransparency: reduceTransparency) {
        case .seeThrough:
            content
                .background(Color.black.opacity(JPGlassLook.tint), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.stroke(Color.white.opacity(border), lineWidth: 1) }
        case .opaque:
            content
                .background(WebTheme.sheet, in: shape)
                .overlay { shape.stroke(Color.white.opacity(border), lineWidth: 1) }
        }
    }
}
