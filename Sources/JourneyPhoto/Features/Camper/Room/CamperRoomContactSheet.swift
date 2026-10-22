import SwiftUI
import UIKit
#if canImport(SceneKit)
import SceneKit
import Metal
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif

// 家具の接写の一覧（2026-10-21・**見本の起動 `-JPPreviewCamperRoomContact` だけ**。Debug のみ）。
//
// 板と別種の家具（`CamperRoomCatalog.board`）を、図鑑の寄りと同じ小部屋・同じ素材と光で 1 つずつ本物の SceneKit に描き、
// 4 点ずつの頁に並べる。ソフトラスタ（`CamperRoomRaster`）では素材の映り・光・接地の影が見えないので、
// 全家具の出来を Mac の画面写真（`testCapturesCamperRoomContactSheet`）で一度に見るためのもの。
//
// 2026-10-21 判断: 画面の SCNView を 8 つ並べず、画面の外の `SCNRenderer` 1 つで順に描いて絵にする（部屋の殻は 1 回だけ組み、
// 家具だけ入れ替える）。頁を開くたびにその頁の 4 点だけ描く。
// 2026-10-21（run 596）: 8 点だと画面写真（長辺 700px）で 1 点が 150px ほどになり素材が読めない。4 点にし、並びの所だけを撮る。

/// 脚の接写の一覧（2026-10-22・`-JPPreviewCamperRoomLegs`）: 脚のある家具 1 つを 1 頁に、4 方向（`CamperRoomLegs.views`）で並べる
enum CamperRoomLegPages {
    static let items: [CamperRoomFurniture] = CamperRoomLegs.sheet
    static var count: Int { max(1, items.count) }

    /// 画面写真の試験が待つ合図
    static func marker(page: Int) -> String { "legs-ready \(page + 1)/\(count)" }
}

/// 1 頁の数（2 列 × 2 段）
enum CamperRoomContactPages {
    static let perPage = 4
    static var items: [CamperRoomFurniture] { CamperRoomCatalog.board }
    static var count: Int { max(1, (items.count + perPage - 1) / perPage) }

    static func page(_ index: Int) -> [CamperRoomFurniture] {
        let all = items
        let lo = min(all.count, max(0, index) * perPage)
        return Array(all[lo..<min(all.count, lo + perPage)])
    }

    /// 画面写真の試験が待つ合図
    static func marker(mood: CamperMood, page: Int) -> String {
        "contact-ready \(mood.rawValue) \(page + 1)/\(count)"
    }
}

#if canImport(SceneKit) || canImport(SceneKitShim)

/// 画面の外で家具を 1 つずつ描く（図鑑の寄りと同じ小部屋・カメラ・光）
@MainActor
final class CamperRoomContactRenderer {
    private let scene = CamperRoomScene()
    private let renderer: SCNRenderer
    private var installed = false
    private let paint: UInt32

    init(paint: UInt32) {
        self.paint = paint
        scene.studio = true
        #if canImport(SceneKit)
        renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        #else
        renderer = SCNRenderer(device: nil, options: nil)
        #endif
        renderer.scene = scene.scene
        renderer.pointOfView = scene.cameraNode
    }

    func render(_ f: CamperRoomFurniture, mood: CamperMood, size: CGSize, view: (yaw: Double, pitch: Double)? = nil) -> UIImage {
        let studio = CamperRoomStudio.make(f)
        if !installed {
            scene.installNow(layout: studio.layout, doc: studio.doc, paint: paint)
            installed = true
        } else {
            scene.replaceItemsNow(studio.doc)
        }
        scene.setMood(mood)
        // 図鑑の寄りより一段寄る（小さな枠いっぱいに家具を見せる）
        var camera = CamperRoomStudio.camera(f)
        camera.zoom = 1.35
        // 脚の接写は向きを替えて 4 方向から（2026-10-22）
        if let view {
            camera.yaw = view.yaw
            camera.pitch = view.pitch
        }
        scene.setCamera(camera, animated: false)
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }
}

#endif

/// 接写の一覧の画面（頁送り・昼と夜）
struct CamperRoomContactSheet: View {
    let paint: UInt32
    /// 脚の接写の一覧（1 頁に 1 つの家具を 4 方向で）
    var legs = false
    let onClose: () -> Void

    @State private var page = 0
    @State private var mood: CamperMood = .day
    @State private var images: [String: UIImage] = [:]
    @State private var marker = ""
    #if canImport(SceneKit) || canImport(SceneKitShim)
    @State private var renderer: CamperRoomContactRenderer?
    #endif

    private static let cell = CGSize(width: 184, height: 184)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Button(action: onClose) {
                    Text(L("閉じる", "Close")).jpSystemFont(15, weight: .semibold).foregroundStyle(WebTheme.accent)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("camper.room.contact.close")
                Spacer()
                // 読み上げの値に描き終えた合図（画面写真の試験が待つ。部屋の場面の `camper-room-ready` と同じ仕組み）
                Text("\(mood == .night ? L("夜", "Night") : L("昼", "Day")) \(page + 1) / \(pageCount)")
                    .font(JPFont.number(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.text)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("接写の一覧", "Close-up sheet"))
                    .accessibilityValue(marker)
                    .accessibilityIdentifier("camper.room.contact")
                Spacer()
                pager("chevron.left", id: "camper.room.contact.prev", enabled: page > 0) { go(page - 1) }
                pager("chevron.right", id: "camper.room.contact.next", enabled: page + 1 < pageCount) { go(page + 1) }
                pager(mood == .night ? "sun.max" : "moon", id: "camper.room.contact.mood", enabled: true) {
                    mood = mood == .night ? .day : .night
                    images = [:]
                    draw()
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(cells, id: \.key) { cell in
                    let f = cell.furniture
                    VStack(spacing: 2) {
                        Group {
                            if let image = images[cell.key] {
                                Image(uiImage: image).resizable().scaledToFit()
                            } else {
                                Color.white.opacity(0.04)
                            }
                        }
                        .frame(height: Self.cell.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(cell.view.map { "\(CamperRoomLegs.views[$0].name) · \(f.name) · \(f.id)" } ?? "\(f.name) · \(f.id)")
                            .jpSystemFont(12)
                            .foregroundStyle(WebTheme.text)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("camper.room.contact.grid")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .background { Color.black.ignoresSafeArea() }
        .onAppear(perform: draw)
    }

    private var pageCount: Int { legs ? CamperRoomLegPages.count : CamperRoomContactPages.count }

    /// その頁の枠（脚の接写は 1 つの家具の 4 方向）
    private var cells: [Cell] {
        if legs {
            guard CamperRoomLegPages.items.indices.contains(page) else { return [] }
            let f = CamperRoomLegPages.items[page]
            return CamperRoomLegs.views.indices.map { Cell(key: "\(f.id)#\($0)", furniture: f, view: $0) }
        }
        return CamperRoomContactPages.page(page).map { Cell(key: $0.id, furniture: $0, view: nil) }
    }

    private struct Cell {
        var key: String
        var furniture: CamperRoomFurniture
        /// 脚の接写の向き（`CamperRoomLegs.views` の番号）
        var view: Int?
    }

    private func pager(_ symbol: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).jpSystemFont(16, weight: .semibold)
                .foregroundStyle(enabled ? WebTheme.foreground : WebTheme.faint)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }

    private func go(_ next: Int) {
        page = max(0, min(pageCount - 1, next))
        images = [:]
        draw()
    }

    /// その頁の 4 点を描く（1 点ずつ間を空けて、画面が固まらないように）
    private func draw() {
        marker = ""
        #if canImport(SceneKit) || canImport(SceneKitShim)
        let r = renderer ?? CamperRoomContactRenderer(paint: paint)
        renderer = r
        let want = page, m = mood
        Task { @MainActor in
            for cell in cells {
                guard want == page, m == mood else { return }
                let view = cell.view.map { (yaw: CamperRoomLegs.views[$0].yaw, pitch: CamperRoomLegs.views[$0].scenePitch) }
                images[cell.key] = r.render(cell.furniture, mood: m, size: CGSize(width: Self.cell.width * 3, height: Self.cell.height * 3), view: view)
                await Task.yield()
            }
            if want == page, m == mood {
                marker = legs ? CamperRoomLegPages.marker(page: want) : CamperRoomContactPages.marker(mood: m, page: want)
            }
        }
        #endif
    }
}
