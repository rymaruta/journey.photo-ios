import SwiftUI

/// 写真の上に置く「ガラス」（デザインシステム・ストーリーの板）。
///
/// **黒55%＋ぼかし＋白の髪線。** 板はどの画面でもこの3つを組にしている
/// （`background: rgba(0,0,0,0.55); backdrop-filter: blur(18px);
/// border: 1px solid rgba(255,255,255,0.10)`）。以前は `Color.black.opacity(0.55)`
/// を直に書く所と `.ultraThinMaterial` を使う所が混ざっていた。
///
/// 写真の上の文字は白だけ（`WebTheme` の規則）。真鍮は写真の上では沈む。
extension View {

    /// - Parameters:
    ///   - shape: 形（丸・カプセル・角丸）
    ///   - border: 縁の白の濃さ。返信欄は 0.35、入力中は 0.6（板の値）
    func jpGlass<S: Shape>(in shape: S, border: Double = 0.10) -> some View {
        self
            .background(Color.black.opacity(0.55), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay { shape.stroke(Color.white.opacity(border), lineWidth: 1) }
    }

    /// 写真の上の大きい文字の影（板の `text-shadow: 0 2px 14px rgba(0,0,0,0.6)`）
    func jpPhotoTextShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.6), radius: 7, x: 0, y: 2)
    }
}
