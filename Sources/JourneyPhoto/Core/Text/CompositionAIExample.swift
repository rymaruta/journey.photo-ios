import Foundation

/// 構図の作例写真（AI で作ったもの・2026-10-13〜）の名前と表記。画面を持たない決まりなので Linux の試験で見張る。
///
/// - 絵は `Assets.xcassets/composition-ai-<rawValue>.imageset`。無い構図は今まで通り線の図だけ
///   （画面は `UIImage(named:)` が nil かどうかで分ける・`CompositionThumbnail`・`CompositionExplanationView`）
/// - **作例には必ず「AI で作った」と分かる表記を付ける。** 実写の SNS なので、本物の写真と誤解させない
/// - 作り方と入れ方は `Tools/composition-examples/README.md`（指示文・生成・入れる道具）
enum CompositionAIExample {

    /// 絵の入れ物の名前
    static func assetName(_ kind: CompositionKind) -> String { "composition-ai-\(kind.rawValue)" }

    /// 作例の下に出す表記（解説の画面）
    static var label: String { L("AI で作ったイメージ", "AI-generated example") }

    /// 構図のシートの札の上に置く小さな印（写真の上なので白）
    static let badge = "AI"

    /// 構図のシートの見出しの下の一言（12pt）
    static var sheetNote: String {
        L("作例の写真は AI で作ったイメージです。実際の撮影ではありません。",
          "Example photos are AI-generated, not real shots.")
    }

    /// 札の読み上げ（名前・難しさに続けて読む）
    static func accessibilitySuffix(hasExample: Bool) -> String {
        hasExample ? L("、\(label)", ", \(label)") : ""
    }
}
