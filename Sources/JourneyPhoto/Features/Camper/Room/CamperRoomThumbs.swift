import SwiftUI
import UIKit

/// 家具の小さな絵（下の棚と図鑑の枠）。網から端末の中で描き（`CamperRoomRaster`）、画面の処理の外で作って覚える。
/// まだ持っていない家具は影絵（黒に細い灰の縁）。形をまだ作っていない家具（近日）は絵が無い
@MainActor
final class CamperRoomThumbs: ObservableObject {
    static let shared = CamperRoomThumbs()

    @Published private(set) var images: [String: UIImage] = [:]
    private var inFlight = Set<String>()

    static func key(_ id: String, silhouette: Bool) -> String { silhouette ? "\(id).s" : id }

    func image(_ id: String, silhouette: Bool) -> UIImage? {
        let key = Self.key(id, silhouette: silhouette)
        if let hit = images[key] { return hit }
        guard !inFlight.contains(key), CamperRoomCatalog.furniture(id)?.built == true else { return nil }
        inFlight.insert(key)
        Task {
            let bitmap = await Task.detached(priority: .utility) { () -> CamperBitmap? in
                guard let mesh = CamperRoomFurnitureModels.mesh(id) else { return nil }
                var o = CamperRoomRaster.Options()
                o.width = 168
                o.height = 168
                o.silhouette = silhouette
                let wall = CamperRoomCatalog.furniture(id)?.placement == .wall
                o.pitch = wall ? 8 : 26
                o.yaw = wall ? 18 : 34
                return CamperRoomRaster.render(mesh, o).premultiplied()
            }.value
            inFlight.remove(key)
            if let bitmap, let cg = CamperScenePalette.cgImage(bitmap) { images[key] = UIImage(cgImage: cg) }
        }
        return nil
    }
}

/// 家具の絵の枠（絵が無ければ分類の印）
struct CamperRoomThumb: View {
    let furniture: CamperRoomFurniture
    let silhouette: Bool
    @ObservedObject var thumbs = CamperRoomThumbs.shared

    var body: some View {
        Group {
            if let image = thumbs.image(furniture.id, silhouette: silhouette) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: furniture.category.symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(silhouette ? WebTheme.faint : WebTheme.text)
            }
        }
        .accessibilityHidden(true)
    }
}
