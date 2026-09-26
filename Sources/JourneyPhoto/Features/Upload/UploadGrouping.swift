import Foundation

/// 写真を「1つの投稿にまとめる」ときの束の印の決め方。
///
/// **画面の外に出しておく。** `UploadViewModel` は MainActor に縛られていて、
/// 試験（isolation を持たない XCTestCase）から直接呼べない（`Tools/verify.sh` が止める）。
enum UploadGrouping {
    /// 送るときの束の印。
    ///
    /// **まとめるのは2枚以上のときだけ。** 1枚に印を付けても意味が無く、
    /// 「1/1」の送りが出るだけになる。
    /// 🔴 **押し直しでは同じ印を使い続ける。** 5枚のうち2枚が失敗して押し直すと、
    /// 送るたびに作り直していたので 3枚と2枚の2つの束に割れ、残りが1枚なら
    /// 印の無い単独の投稿になっていた。印を捨てるのは `reset()` と、選び直しで
    /// 前の写真が1枚も残らなかったときだけ（「追加」では捨てない）
    static func groupIdForSubmit(current: String?, grouping: Bool, count: Int,
                                 make: () -> String) -> String? {
        guard grouping else { return nil }
        if let current { return current }
        return count > 1 ? make() : nil
    }
}
