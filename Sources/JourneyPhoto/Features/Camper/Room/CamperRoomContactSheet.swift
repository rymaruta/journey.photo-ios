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

    func render(_ f: CamperRoomFurniture, mood: CamperMood, size: CGSize) -> UIImage {
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
        scene.setCamera(camera, animated: false)
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }
}

#endif

/// 接写の一覧の画面（頁送り・昼と夜）
struct CamperRoomContactSheet: View {
    let paint: UInt32
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
                    Text(L("閉じる", "Close")).font(.system(size: 15, weight: .semibold)).foregroundStyle(WebTheme.accent)
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("camper.room.contact.close")
                Spacer()
                // 読み上げの値に描き終えた合図（画面写真の試験が待つ。部屋の場面の `camper-room-ready` と同じ仕組み）
                Text("\(mood == .night ? L("夜", "Night") : L("昼", "Day")) \(page + 1) / \(CamperRoomContactPages.count)")
                    .font(JPFont.number(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.text)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("接写の一覧", "Close-up sheet"))
                    .accessibilityValue(marker)
                    .accessibilityIdentifier("camper.room.contact")
                Spacer()
                pager("chevron.left", id: "camper.room.contact.prev", enabled: page > 0) { go(page - 1) }
                pager("chevron.right", id: "camper.room.contact.next", enabled: page + 1 < CamperRoomContactPages.count) { go(page + 1) }
                pager(mood == .night ? "sun.max" : "moon", id: "camper.room.contact.mood", enabled: true) {
                    mood = mood == .night ? .day : .night
                    images = [:]
                    draw()
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(CamperRoomContactPages.page(page), id: \.id) { f in
                    VStack(spacing: 2) {
                        Group {
                            if let image = images[f.id] {
                                Image(uiImage: image).resizable().scaledToFit()
                            } else {
                                Color.white.opacity(0.04)
                            }
                        }
                        .frame(height: Self.cell.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("\(f.name) · \(f.id)")
                            .font(.system(size: 12))
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

    private func pager(_ symbol: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? WebTheme.foreground : WebTheme.faint)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }

    private func go(_ next: Int) {
        page = max(0, min(CamperRoomContactPages.count - 1, next))
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
            for f in CamperRoomContactPages.page(want) {
                guard want == page, m == mood else { return }
                images[f.id] = r.render(f, mood: m, size: CGSize(width: Self.cell.width * 3, height: Self.cell.height * 3))
                await Task.yield()
            }
            if want == page, m == mood { marker = CamperRoomContactPages.marker(mood: m, page: want) }
        }
        #endif
    }
}
