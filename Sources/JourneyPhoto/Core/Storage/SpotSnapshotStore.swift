import Foundation

/// 最後に取れた撮影スポットの索引を端末に残す（`PhotoSnapshotStore` と同じ形）。
///
/// **圏外で地図のピンが黙って消えないため。** 取れたら必ず上書き、
/// 取れなかったときだけ前回のぶんを出す。
///
/// **同梱の索引は持たない。** `Package.swift` が `Resources` を除外しているし、
/// 台帳は Web 側で動くので、焼き込んだ写しはすぐ古くなる。
struct SpotSnapshotStore {

    private let url: URL
    /// 中身と同じ回の版の印（`ETag`・`Last-Modified`）。条件付きの取得に使う（`ConditionalGet`）
    let validators: ValidatorStore

    init(fileName: String = "spots-snapshot.json") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.url = caches.appendingPathComponent(fileName)
        self.validators = ValidatorStore(snapshotURL: url)
    }

    /// 中身と、その応答の版の印を書く。**印の無い応答なら印は残さない**
    /// （前の回の印を残すと、304 で違う中身を出す）
    func save(_ data: Data, validator: HTTPValidator? = nil) {
        validators.saveSnapshot(data, to: url, validator: validator)
    }

    /// 控えを消す。**索引が下げられた（404）とき**——古い控えを出し続けない
    func clear() {
        validators.clear()
        try? FileManager.default.removeItem(at: url)
    }

    func load() -> [OfficialSpot]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 控えの側も1行の型違いで全部消さない（`LenientOfficialSpotList` の理由）
        return try? JSONDecoder.api.decode(LenientOfficialSpotList.self, from: data).spots
    }
}
