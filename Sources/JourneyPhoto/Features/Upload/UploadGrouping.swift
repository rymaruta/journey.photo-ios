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

    /// 「旅の写真からまとめて」で上げた束の印の頭（2026-10-02 判断）。
    ///
    /// 旅の記録の一冊にするのは**この流れで上げた束だけ**（`TripBook.groupTrips`）。ふだんの
    /// 「1つの投稿にまとめる」まで一冊にすると、日付で束ねた一冊が割れ、開いた印も外れた。
    /// サーバーに印の欄は足さず、`groupId` の頭で見分ける（サーバーの `sanitizeGroupId` は
    /// 英数字とハイフン・64字まで——「trip-」＋UUID の 41字は通る）。1.0.51 以前に上げた
    /// 旅の束は頭が無いので一冊にならないが、まだ公開前の機能なので受け入れる
    static let tripPrefix = "trip-"

    /// 新しい束の印。旅の写真の流れから来た投稿だけ `tripPrefix` を付ける
    static func newGroupId(fromTrip: Bool, uuid: String = UUID().uuidString) -> String {
        fromTrip ? tripPrefix + uuid : uuid
    }

    /// 旅の写真の流れから開いた投稿画面の、束についての一言（「それぞれ別の投稿」の切り替えの代わり）。
    /// **旅の流れでは、いつも1つの投稿にまとめる**（束でないと旅の記録に入らない）。
    /// 写真を外して1枚になっても送信は止めない——旅の記録には2枚からと伝えるだけ
    static func tripNote(fromTrip: Bool, count: Int) -> String? {
        guard fromTrip, count > 0 else { return nil }
        return count >= TripBook.minPhotos
            ? L("1つの投稿にまとめて、旅の記録の一冊にします", "Posted as one and kept as a trip")
            : L("旅の記録には2枚から入ります。1枚のままでも投稿できます",
                "Trips need 2 or more photos. You can still post this one.")
    }

    /// 旅の写真の流れで上げた束か
    static func isTripGroup(_ groupId: String?) -> Bool {
        groupId?.trimmingCharacters(in: .whitespaces).hasPrefix(tripPrefix) ?? false
    }
}
