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

    /// 出すかどうかを `RootView` が決めている途中か（合図から `finishDeciding` まで）。
    ///
    /// 2026-10-11 判断: **評価のお願い（`ReviewPromptStore`）と1つの判断にまとめる。**
    /// 同じ投稿のあとに両方の合図が来る。別々に待つと、説明の側が許可を読み直している間に
    /// 評価の側が先に「何も出ていない」と見て、2つが続けて（重なって）出た。
    /// 評価の側はこれが下りるまで待ち、説明を出した回は見送る（`letsReviewAsk`）。
    /// `@Published` にしない——画面を描き直す必要は無い
    private(set) var isDeciding = false

    /// 投稿が全部上がった（`UploadViewModel`）。**まだ出していない端末でだけ**合図する
    /// （許可の状態は、出す直前に `RootView` が読み直して `PushPrimer.shouldOffer` で決める）。
    /// 評価の合図（`noteHappyMoment`）より**先に**呼ばれるので、ここで「決めている途中」を立てる
    func notePosted() {
        guard !isPreview(), !alreadyOffered else { return }
        isDeciding = true
        requests += 1
    }

    /// 出すかどうか決め終えた（出した・出さなかった・待ちきれなかった、のどれでも呼ぶ）
    func finishDeciding() {
        isDeciding = false
    }

    /// 評価のお願いを頼んでよいか。`offeredAtStart` は評価の側が待ち始めたときの `alreadyOffered`。
    /// 説明を決めている途中、または待っている間に説明を出した（覚えが立った）回は頼まない
    /// ——評価は次のうれしい瞬間に回す（数えた分は消さない）
    func letsReviewAsk(offeredAtStart: Bool) -> Bool {
        guard !isDeciding else { return false }
        return offeredAtStart || !alreadyOffered
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
