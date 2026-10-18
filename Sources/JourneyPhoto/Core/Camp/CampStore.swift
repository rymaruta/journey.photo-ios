import Combine
import Foundation

/// 切り絵 1 つ（撮った写真を 3 枚に切ったもの）。紙の表の絵は `CampStore` の入れ物に画像で置く
struct CampCutoutRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    /// 元の写真の記録（`CampShot.id`）
    let shotId: String
    var layers: CampCutLayers
    /// 立てた場所（0 手前の芝・1 小道のそば・2 テントの横）。まだ立てていなければ nil（「あとで置く」）
    var spot: Int?
    /// 題（「霧の針葉樹林」・写った物から）
    var title: String
    /// 撮った所の名前（市区町村）
    var place: String?
    let takenAt: Date
    let createdAt: Date
}

/// 写真から取った空の色（その時刻の空になる・板 Main「空の色は、その時刻に撮った写真から」）
struct CampSkySample: Codable, Equatable, Sendable {
    /// 上・中・下の 3 色
    var colors: [UInt32]
    let takenAt: Date
}

/// キャンプ場の中身（端末の中だけ・サーバーには送らない）。
///
/// - 置き場所はアプリの書類の入れ物の `Camp/`（`camp.json` と、切り絵の紙の絵 `<id>-<層>.png`・元の写真の切り抜き `<id>.jpg`）
/// - **人が写った写真は使わない**（切り絵にしない・数えない）
/// - サーバー・データベースは使わない（2026-10-18: 要サーバーの部品は「近日」）
@MainActor
final class CampStore: ObservableObject {

    struct Snapshot: Codable, Equatable {
        var name: String?
        var shots: [CampShot] = []
        var cutouts: [CampCutoutRecord] = []
        /// 時刻ごとの空の色
        var skies: [String: CampSkySample] = [:]
        /// 図鑑で見た部品（「新着」の数を出す）
        var seen: [String] = []
    }

    static let shared = CampStore()

    @Published private(set) var snapshot = Snapshot()
    /// 中身が変わった回数（場面を組み直す合図）
    @Published private(set) var revision = 0

    let directory: URL
    private let persists: Bool

    init(directory: URL? = nil, persists: Bool = true) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Camp", isDirectory: true)
        self.directory = base
        self.persists = persists
        if persists { load() }
    }

    private var fileURL: URL { directory.appendingPathComponent("camp.json") }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        snapshot = decoded
        revision += 1
    }

    private func save() {
        revision += 1
        guard persists else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - 読む

    var shots: [CampShot] { snapshot.shots }
    var cutouts: [CampCutoutRecord] { snapshot.cutouts }

    /// 立てた切り絵（置き場所ごとに新しい 1 つ）
    var placed: [CampCutoutRecord] {
        var bySpot: [Int: CampCutoutRecord] = [:]
        for c in snapshot.cutouts {
            guard let spot = c.spot else { continue }
            if let old = bySpot[spot], old.createdAt > c.createdAt { continue }
            bySpot[spot] = c
        }
        return bySpot.keys.sorted().compactMap { bySpot[$0] }
    }

    /// 育ち（立てた切り絵の数で）
    var stage: CampStage { CampStage.stage(cutouts: snapshot.cutouts.filter { $0.spot != nil }.count) }
    var placedCount: Int { snapshot.cutouts.filter { $0.spot != nil }.count }

    var owned: Set<String> { CampCollection.owned(shots: snapshot.shots) }

    /// 図鑑でまだ見ていない、新しく持った部品（最初からの部品は数えない）
    var unseen: Set<String> {
        let starters = Set(CampCatalog.starters.map(\.id))
        return owned.subtracting(snapshot.seen).subtracting(starters)
    }

    func sky(for time: CampTime) -> CampSkySample? { snapshot.skies[time.rawValue] }

    /// キャンプ場の名前（無ければ持ち主の名前から）
    func displayName(owner: String?) -> String {
        if let name = snapshot.name, !name.isEmpty { return name }
        return L("はじまりの野営地", "First Camp")
    }

    func imageURL(cutout id: String, layer: Int) -> URL { directory.appendingPathComponent("\(id)-\(layer).png") }
    func photoURL(cutout id: String) -> URL { directory.appendingPathComponent("\(id).jpg") }

    // MARK: - 書く

    /// 撮った 1 枚を足す（切り絵にしたなら、紙の絵と元の切り抜きも置く）
    func add(shot: CampShot, cutout: CampCutoutRecord?, layerImages: [Data], photo: Data?, sky: CampSkySample?) {
        snapshot.shots.append(shot)
        if let cutout {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (i, data) in layerImages.enumerated() { try? data.write(to: imageURL(cutout: cutout.id, layer: i), options: .atomic) }
            if let photo { try? photo.write(to: photoURL(cutout: cutout.id), options: .atomic) }
            snapshot.cutouts.append(cutout)
        }
        if let sky {
            let time = CampTime(slot: CampClock.slot(of: sky.takenAt))
            snapshot.skies[time.rawValue] = sky
        }
        save()
    }

    /// 切り絵を立てる（`nil` で「あとで置く」）
    func place(_ id: String, spot: Int?) {
        guard let i = snapshot.cutouts.firstIndex(where: { $0.id == id }) else { return }
        snapshot.cutouts[i].spot = spot.map { max(0, min(2, $0)) }
        save()
    }

    /// 切り抜きを直した（同じ写真の 3 枚を差し替える）
    func replace(_ id: String, layers: CampCutLayers, layerImages: [Data]) {
        guard let i = snapshot.cutouts.firstIndex(where: { $0.id == id }) else { return }
        snapshot.cutouts[i].layers = layers
        for (k, data) in layerImages.enumerated() { try? data.write(to: imageURL(cutout: id, layer: k), options: .atomic) }
        save()
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.name = trimmed.isEmpty ? nil : String(trimmed.prefix(20))
        save()
    }

    /// 図鑑を開いた（新しく持った部品を見たことにする）
    func markSeen() {
        let now = owned
        guard !now.isSubset(of: Set(snapshot.seen)) else { return }
        snapshot.seen = Array(Set(snapshot.seen).union(now)).sorted()
        save()
    }

    /// 見本の中身に差し替える（画面写真の試験・Debug のみ。`CampPreview`）
    func replaceForPreview(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        revision += 1
    }
}

/// 画面写真のための見本（Debug の起動の鍵だけ）。`-JPPreviewCamp YES`（切り絵 2 つを立てたテント場）、
/// `-JPPreviewCampViews YES`（ホームに 12 の向きを順に見せるボタン）
enum CampPreview {
    static let sampleKey = "JPPreviewCamp"
    static let viewsKey = "JPPreviewCampViews"

    static var usesSample: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: sampleKey) || UserDefaults.standard.bool(forKey: viewsKey)
        #else
        return false
        #endif
    }

    static var showsViews: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: viewsKey)
        #else
        return false
        #endif
    }

    /// 見本の記録（写真 12 枚・森 6・夜 3・山 2。テント場で、切り絵 2 つを立てている）
    static func sampleShots(now: Date = Date()) -> [CampShot] {
        let day = 86_400.0
        let subjects: [[CampSubject]] = [[.forest], [.forest, .mountain], [.forest], [.river], [.forest], [.mountain],
                                         [.forest], [.lake], [], [.forest], [.campfire], [.snow]]
        return subjects.enumerated().map { i, s in
            CampShot(id: "sample-\(i)", takenAt: now.addingTimeInterval(-Double(i) * day * 9 - Double(i % 3) * 3600 * 7),
                     latitude: 35.36 + Double(i % 4) * 0.2, longitude: 138.72 + Double(i % 3) * 0.3,
                     altitude: i % 5 == 0 ? 1200 : 600, prefecture: ["山梨県", "長野県", "静岡県"][i % 3],
                     locality: ["富士河口湖町", "白馬村", "富士宮市", "北杜市"][i % 4], subjects: s)
        }
    }
}
