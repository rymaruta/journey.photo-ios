import Foundation
import Combine

/// 通知の説明（`PushPrimerView`）を出す頃合いを `RootView` に伝える（決まりは `PushPrimer`・2026-10-11）。
///
/// **回数で伝える**（`requests`）。真偽値にすると、2回目に立てても「変わっていない」と
/// 見なされて届かない（`ReviewPromptStore` と同じ理由）。出したかどうかは端末にだけ置く。
///
/// 絵を撮るための入り方（`PreviewSession`・UI テスト）では投稿で数えない——巡回の途中で
/// 説明が出て、ほかの画面の絵を覆わないように。説明そのものの絵は `PreviewSession.opensPushPrimer`
/// で起動のときに1回だけ出す
@MainActor
final class PushPrimerStore: ObservableObject {

    static let shared = PushPrimerStore()

    /// 出してよいか確かめる頃合いになった回数（`RootView` がこれを見て、ほかの画面が閉じてから確かめる）
    @Published private(set) var requests = 0

    static let offeredKey = "pushPrimer.offered"

    private let defaults: UserDefaults
    private let isPreview: () -> Bool

    init(defaults: UserDefaults = .standard,
         isPreview: @escaping () -> Bool = { PreviewSession.userId != nil }) {
        self.defaults = defaults
        self.isPreview = isPreview
    }

    /// この端末で前に出したか
    var alreadyOffered: Bool { defaults.bool(forKey: Self.offeredKey) }

    /// 投稿が全部上がった（`UploadViewModel`）。**まだ出していない端末でだけ**合図する
    /// （許可の状態は、出す直前に `RootView` が読み直して `PushPrimer.shouldOffer` で決める）
    func notePosted() {
        guard !isPreview(), !alreadyOffered else { return }
        requests += 1
    }

    /// これから出す。**出してよいときだけ** true を返し、出したことを覚える
    /// （「あとで」でも二度と出さない。押しつけない）
    @discardableResult
    func consume(signedIn: Bool, permission: PushPermission) -> Bool {
        guard PushPrimer.shouldOffer(signedIn: signedIn, permission: permission,
                                     alreadyOffered: alreadyOffered) else { return false }
        defaults.set(true, forKey: Self.offeredKey)
        return true
    }
}
