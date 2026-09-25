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

    init(fileName: String = "spots-snapshot.json") {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.url = caches.appendingPathComponent(fileName)
    }

    func save(_ data: Data) {
        // 失敗しても何も言わない（控えが取れないだけで、本筋は動いている）
        try? data.write(to: url, options: .atomic)
    }

    /// 控えを消す。**索引が下げられた（404）とき**——古い控えを出し続けない
    func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    func load() -> [OfficialSpot]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 控えの側も1行の型違いで全部消さない（`LenientOfficialSpotList` の理由）
        return try? JSONDecoder.api.decode(LenientOfficialSpotList.self, from: data).spots
    }
}
