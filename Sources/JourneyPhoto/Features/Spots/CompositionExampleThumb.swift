import SwiftUI
import UIKit

/// 構図の行の右に出す作例写真（2026-10-17 owner「撮ろうとしている時に、この構図をどんな時に使うか分かるように」）。
///
/// 構図のシート（撮る画面）と構図一覧（設定）の行で同じ形を使う（画面ごとに見た目を割らない）。
/// 作例は `composition-ai-<rawValue>`（37種類・`docs/COMPOSITION_AI_EXAMPLES.md`）。原寸（864×1152）を
/// 一覧に37枚そのまま描くと重いので、行の大きさに縮めた絵を1度だけ作って使い回す。作例の無い構図は何も出さない。
struct CompositionExampleThumb: View {

    let kind: CompositionKind

    /// 行の写真の大きさ（縦3:4・作例と同じ比）
    static let size = CGSize(width: 48, height: 64)

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = CompositionExampleThumbs.image(for: kind, size: Self.size, scale: displayScale) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Self.size.width, height: Self.size.height)
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs))
                .overlay(RoundedRectangle(cornerRadius: JPRadius.xs)
                    .strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                // 行の読み上げは名前と難しさで足りる（写真は見た目の手がかり）
                .accessibilityHidden(true)
        }
    }
}

/// 縮めた作例写真の控え（構図の種類ごとに1枚）
enum CompositionExampleThumbs {

    @MainActor private static var cache: [String: UIImage] = [:]

    /// 作例写真の入れ物の名前（詳細画面 `CompositionExplanationView` と同じ）
    static func assetName(for kind: CompositionKind) -> String {
        "composition-ai-\(kind.rawValue)"
    }

    @MainActor static func image(for kind: CompositionKind, size: CGSize, scale: CGFloat) -> UIImage? {
        let name = assetName(for: kind)
        if let hit = cache[name] { return hit }
        guard let full = UIImage(named: name) else { return nil }
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let thumb = full.preparingThumbnail(of: pixels) ?? full
        cache[name] = thumb
        return thumb
    }
}
