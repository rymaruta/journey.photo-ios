import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 端末の AI（Apple Foundation Models・`SystemLanguageModel`）が使えるかの判定。**AI の機能はみなここを通す。**
///
/// 2026-11-15 判断（札 #622・#621）: 投稿の候補（#622）と旅行プランの AI（#621）で同じ判定を使う。写しを作らない。
/// #621 の枝（`claude/621-ai-trip`）はまだ push されていなかったので、#622 が先にこの共通の小さな部品として置いた。
///
/// 使えるのは次のすべてが揃ったとき（公式の文書 `SystemLanguageModel.availability`・`supportsLocale(_:)`）:
/// - iOS 26 以上（`FoundationModels` は iOS 26.0 から）
/// - Apple Intelligence の機種で、Apple Intelligence がオン、モデルの準備が済んでいる（`.available`）
/// - モデルが日本語を扱える（`supportsLocale(ja_JP)`）。アプリの画面の言語が英語のときは使わない
///   （候補の言葉と画面の言葉が割れる。英語の画面はいま無いが、`L` の英語の枝のため）
///
/// 使えない理由（`reason`）は画面に出さない。**使えない機種・OS では、AI の機能は何も見せない**（#622 の決まり）。
/// 理由は試験とログ（`OnDeviceAIProbeTests` の `measured [onDeviceAI] …`）で見る
enum OnDeviceAI {

    enum Status: Equatable {
        case available
        /// 使えない。値は理由（`deviceNotEligible`・`appleIntelligenceNotEnabled`・`modelNotReady`・`osTooOld`・
        /// `noFramework`・`localeNotSupported`・`englishScreen`・`forcedOff`）。**画面には出さない**
        case unavailable(String)

        var isAvailable: Bool { self == .available }
    }

    /// 試験だけの切り替え（`-JPOnDeviceAI off|sample`・Debug のみ。Release では効かない）
    ///
    /// - `off`: 使えない機種と同じに見せる（候補が出ないことを確かめる）
    /// - `sample`: 使えると見せ、AI を呼ばずに決まった候補を返す（画面写真の試験。Mac のシミュレーターは
    ///   端末の AI を持たないことがあるため・`PostSuggest.sample`）
    enum Mode: String {
        case off
        case sample
    }

    static let modeKey = "JPOnDeviceAI"

    static var mode: Mode? {
        #if DEBUG
        UserDefaults.standard.string(forKey: modeKey).flatMap(Mode.init(rawValue:))
        #else
        nil
        #endif
    }

    /// 今使えるか。**呼ぶたびに見る**（モデルの準備は後から済む・設定で Apple Intelligence を切れる）
    static var status: Status {
        switch mode {
        case .off?: return .unavailable("forcedOff")
        case .sample?: return .available
        case nil: break
        }
        guard Locale.preferredAppLanguage != "en" else { return .unavailable("englishScreen") }
        return systemStatus
    }

    static var isAvailable: Bool { status.isAvailable }

    /// 試験の切り替えを見ない、端末そのものの答え（`OnDeviceAIProbeTests` が理由を書き出す）
    static var systemStatus: Status {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .unavailable(let reason) = model.availability {
                return .unavailable(String(describing: reason))
            }
            guard model.isAvailable else { return .unavailable("unknown") }
            guard model.supportsLocale(Locale(identifier: "ja_JP")) else { return .unavailable("localeNotSupported") }
            return .available
        }
        return .unavailable("osTooOld")
        #else
        return .unavailable("noFramework")
        #endif
    }
}
