import SwiftUI
import UIKit

/// 大きさの上限つきの控え（古い物から捨てる）。家具の小さな絵の控えに使う。
///
/// 2026-10-21 判断: 点検で「上限の無い辞書に 2,194 点 × 影絵まで控え、最大で約 495MB」と出た。`NSCache` の
/// `totalCostLimit` は捨てる順が決まっておらず（Apple の実装）、上限で古い絵が捨てられることを試験で確かめられない。
/// 同じ考え（費用の上限で捨てる）を、使った順が分かる小さな控えで持つ。メモリの警告と部屋を閉じたときは全部捨てる
struct CamperThumbCache<Value> {
    let costLimit: Int
    private var entries: [String: (value: Value, cost: Int)] = [:]
    /// 使った順（後ろほど新しい）
    private var order: [String] = []
    private(set) var totalCost = 0

    init(costLimit: Int) { self.costLimit = costLimit }

    var count: Int { entries.count }

    mutating func value(_ key: String) -> Value? {
        guard let hit = entries[key] else { return nil }
        touch(key)
        return hit.value
    }

    mutating func insert(_ value: Value, key: String, cost: Int) {
        if let old = entries[key] {
            totalCost -= old.cost
            order.removeAll { $0 == key }
        }
        entries[key] = (value, cost)
        order.append(key)
        totalCost += cost
        while totalCost > costLimit, order.count > 1, let oldest = order.first {
            order.removeFirst()
            if let gone = entries.removeValue(forKey: oldest) { totalCost -= gone.cost }
        }
    }

    mutating func removeAll() {
        entries = [:]
        order = []
        totalCost = 0
    }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

/// 家具の小さな絵（下の棚と図鑑の枠）。網から端末の中で描き（`CamperRoomRaster`）、画面の処理の外で作って覚える。
/// まだ持っていない家具は影絵（黒に細い灰の縁）。形をまだ作っていない家具（近日）は絵が無い。
///
/// 2026-10-21（点検）: 控えは 30MB まで（`CamperThumbCache`）。同じ絵を二重に描かない（描いている途中の絵は待つ）。
/// 枠ごとに自分の絵だけを持つ（1 枚届くたびに全部の枠を描き直さない）
@MainActor
final class CamperRoomThumbs {
    static let shared = CamperRoomThumbs()
    /// 1 枚 168×168 の RGBA ≈ 113KB。30MB で 270 枚ほど
    static let costLimit = 30 * 1024 * 1024
    static let side = 168

    private var cache: CamperThumbCache<UIImage>
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let render: @Sendable (String, Bool) -> CamperBitmap?
    /// 試験用: 描いた回数
    private(set) var renderCount = 0
    private var memoryObserver: NSObjectProtocol?

    init(costLimit: Int = CamperRoomThumbs.costLimit, render: @escaping @Sendable (String, Bool) -> CamperBitmap? = CamperRoomThumbs.draw) {
        cache = CamperThumbCache(costLimit: costLimit)
        self.render = render
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeAll() }
        }
    }

    static func key(_ id: String, silhouette: Bool) -> String { silhouette ? "\(id).s" : id }

    /// 控えにあれば、すぐ返す
    func cached(_ id: String, silhouette: Bool) -> UIImage? { cache.value(Self.key(id, silhouette: silhouette)) }

    /// 絵を返す（控えに無ければ描く。同じ絵を描いている途中なら、それを待つ）
    func image(_ id: String, silhouette: Bool) async -> UIImage? {
        let key = Self.key(id, silhouette: silhouette)
        if let hit = cache.value(key) { return hit }
        if let running = inFlight[key] { return await running.value }
        guard CamperRoomCatalog.furniture(id)?.built == true else { return nil }
        renderCount += 1
        let render = self.render
        let task = Task { () -> UIImage? in
            let bitmap = await Task.detached(priority: .utility) { render(id, silhouette) }.value
            guard let bitmap, let cg = CamperScenePalette.cgImage(bitmap) else { return nil }
            return UIImage(cgImage: cg)
        }
        inFlight[key] = task
        let made = await task.value
        inFlight[key] = nil
        if let made { cache.insert(made, key: key, cost: Self.side * Self.side * 4) }
        return made
    }

    /// 全部捨てる（メモリの警告・部屋を閉じたとき）。絵のもとの網の控え（組み合わせの家具）も一緒に
    func removeAll() {
        cache.removeAll()
        CamperRoomVariety.removeAllMeshes()
    }

    var cachedCount: Int { cache.count }

    nonisolated static func draw(_ id: String, _ silhouette: Bool) -> CamperBitmap? {
        guard let mesh = CamperRoomFurnitureModels.mesh(id) else { return nil }
        var o = CamperRoomRaster.Options()
        o.width = side
        o.height = side
        o.silhouette = silhouette
        let wall = CamperRoomCatalog.furniture(id)?.placement == .wall
        o.pitch = wall ? 8 : 26
        o.yaw = wall ? 18 : 34
        return CamperRoomRaster.render(mesh, o).premultiplied()
    }
}

/// 家具の絵の枠（絵が無ければ分類の印）。枠ごとに自分の絵だけを持ち、描き始めは `.task(id:)`
struct CamperRoomThumb: View {
    let furniture: CamperRoomFurniture
    let silhouette: Bool
    @State private var image: UIImage?

    private var key: String { CamperRoomThumbs.key(furniture.id, silhouette: silhouette) }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: furniture.category.symbol)
                    .jpSystemFont(24)
                    .foregroundStyle(silhouette ? WebTheme.faint : WebTheme.text)
            }
        }
        .accessibilityHidden(true)
        .task(id: key) {
            let thumbs = CamperRoomThumbs.shared
            if let hit = thumbs.cached(furniture.id, silhouette: silhouette) {
                image = hit
                return
            }
            image = nil
            image = await thumbs.image(furniture.id, silhouette: silhouette)
        }
    }
}
