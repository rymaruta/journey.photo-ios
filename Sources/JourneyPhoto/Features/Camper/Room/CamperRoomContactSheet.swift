import SwiftUI
import UIKit
#if canImport(SceneKit)
import SceneKit
import Metal
#elseif canImport(SceneKitShim)
import SceneKitShim
#endif

// 家具の接写の一覧（2026-10-21・**見本の起動 `-JPPreviewCamperRoomContact`・`Frames`・`Legs` だけ**。Debug のみ）。
//
// 板と別種の家具（`CamperRoomCatalog.board`）を、図鑑の寄りと同じ小部屋・同じ素材と光で 1 つずつ本物の SceneKit に描き、
// 4 点ずつの頁に並べる。ソフトラスタ（`CamperRoomRaster`）では素材の映り・光・接地の影が見えないので、
// 全家具の出来を Mac の画面写真（`testCapturesCamperRoomContactSheet`）で一度に見るためのもの。
//
// 2026-10-21 判断: 画面の SCNView を 8 つ並べず、画面の外の `SCNRenderer` 1 つで順に描いて絵にする（部屋の殻は 1 回だけ組み、
// 家具だけ入れ替える）。頁を開くたびにその頁の 4 点だけ描く。
// 2026-10-21（run 596）: 8 点だと画面写真（長辺 700px）で 1 点が 150px ほどになり素材が読めない。4 点にし、並びの所だけを撮る。

/// 1 頁の数（2 列 × 2 段）。頁の種類は `CamperRoomContactKind`（板の家具・額・脚。2026-10-22 に 1 つの enum にまとめた）
enum CamperRoomContactPages {
    static let perPage = 4

    /// 1 枚の絵（家具と、額なら入れる写真の向き、脚の接写なら向き）
    struct Entry: Identifiable {
        var furniture: CamperRoomFurniture
        /// 額に入れる写真（nil は家具だけ）。"wide"・"tall"
        var photo: String?
        /// 脚の接写の向き（`CamperRoomLegs.views` の番号。nil は図鑑の寄りの向き）
        var view: Int? = nil
        var id: String { furniture.id + (photo.map { "." + $0 } ?? "") + (view.map { "#\($0)" } ?? "") }
    }

    /// 脚の接写に並べる家具（`CamperRoomLegs.sheet`・1 頁に 1 つを 4 方向）
    static let legItems: [CamperRoomFurniture] = CamperRoomLegs.sheet

    static func entries(_ kind: CamperRoomContactKind) -> [Entry] {
        switch kind {
        case .board: return entries(frames: false)
        case .frames: return entries(frames: true)
        case .legs: return legItems.flatMap { f in CamperRoomLegs.views.indices.map { Entry(furniture: f, photo: nil, view: $0) } }
        }
    }

    static func count(_ kind: CamperRoomContactKind) -> Int { max(1, (entries(kind).count + perPage - 1) / perPage) }

    static func page(_ index: Int, _ kind: CamperRoomContactKind) -> [Entry] {
        let all = entries(kind)
        let lo = min(all.count, max(0, index) * perPage)
        return Array(all[lo..<min(all.count, lo + perPage)])
    }

    /// 画面写真の試験が待つ合図（脚の接写は昼だけなので `legs-ready`）
    static func marker(mood: CamperMood, page: Int, _ kind: CamperRoomContactKind) -> String {
        kind == .legs ? "legs-ready \(page + 1)/\(count(kind))" : "contact-ready \(mood.rawValue) \(page + 1)/\(count(kind))"
    }

    /// 写真を入れられる額（印画の材質を持つ家具・2026-10-22）
    /// 2026-10-28: 全家具の網を作って材質を見るので、手分けして作る（1 つずつでは Mac の試験の 1 分の枠を超えた・run 751）
    static let photoFrames: [CamperRoomFurniture] = {
        let built = CamperRoomCatalog.all.filter(\.built)
        let hasPhoto = CamperRoomFurnitureModels.concurrentMap(built) { f in
            CamperRoomFurnitureModels.mesh(f.id)?.materials.contains { if case .room(.photo) = $0 { return true } else { return false } } ?? false
        }
        return zip(built, hasPhoto).filter(\.1).map(\.0)
    }()

    static func entries(frames: Bool) -> [Entry] {
        frames ? photoFrames.flatMap { [Entry(furniture: $0, photo: "wide"), Entry(furniture: $0, photo: "tall")] }
            : CamperRoomCatalog.board.map { Entry(furniture: $0, photo: nil) }
    }

    static func count(frames: Bool) -> Int { max(1, (entries(frames: frames).count + perPage - 1) / perPage) }

    static func page(_ index: Int, frames: Bool) -> [Entry] {
        let all = entries(frames: frames)
        let lo = min(all.count, max(0, index) * perPage)
        return Array(all[lo..<min(all.count, lo + perPage)])
    }

    /// 画面写真の試験が待つ合図
    static func marker(mood: CamperMood, page: Int, frames: Bool) -> String {
        "contact-ready \(mood.rawValue) \(page + 1)/\(count(frames: frames))"
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

    /// 写真の外を読んだ量の最大（額の頁の試験用・`CamperRoomScene.photoUVOverflow`）
    var photoUVOverflow: Double { scene.photoUVOverflow }

    func render(_ f: CamperRoomFurniture, mood: CamperMood, size: CGSize, photoId: String? = nil, images: [String: UIImage] = [:],
                view: Int? = nil) -> UIImage {
        var studio = CamperRoomStudio.make(f)
        if let photoId {
            // 額に写真を入れる（飾った時と同じ印画の材質の差し替え）
            studio.doc.items = studio.doc.items.map { var it = $0; it.p = photoId; return it }
            studio.doc.ceil = studio.doc.ceil.map { var it = $0; it.p = photoId; return it }
        }
        scene.setPhotoImages(images)
        if !installed {
            scene.installNow(layout: studio.layout, doc: studio.doc, paint: paint)
            installed = true
        } else {
            // 同じ額で写真だけ替える時は、場面の側が印画の材質だけ差し替える（`syncItems` → `applyPhotos`）
            scene.replaceItemsNow(studio.doc)
        }
        scene.setMood(mood)
        // 図鑑の寄りより一段寄る（小さな枠いっぱいに家具を見せる）
        var camera = CamperRoomStudio.camera(f)
        camera.zoom = 1.35
        // 脚の接写は向きを替えて 4 方向から（2026-10-22）。「下から」は狙いを床の近くへ下げ、脚の付け根と足先を覗く
        // （Mac run 673: 狙いが家具の真ん中のままだと正面と同じ絵・run 677: 3° では床の板の縁しか写らない）
        if let view {
            let v = CamperRoomLegs.views[view]
            camera.yaw = v.yaw
            camera.pitch = v.scenePitch
            if v.low { camera.target = CV3(camera.target.x, 4, camera.target.z) }
        }
        scene.setCamera(camera, animated: false)
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }
}

#endif

/// 接写の一覧の画面（頁送り・昼と夜）
struct CamperRoomContactSheet: View {
    let paint: UInt32
    /// 頁の種類（板の家具・額・脚）
    var kind: CamperRoomContactKind = .board
    /// 額の頁（写真を入れられる全部の額に、横長・縦長の写真を入れる）
    private var frames: Bool { kind == .frames }
    /// 額に入れる写真の候補（自分の投稿。本物の URL から、飾る時と同じ読み込みで読む）
    var photos: [Photo] = []
    let onClose: () -> Void

    @StateObject private var photoImages = CamperRoomPhotoImages()
    /// 額に入れる写真（横長・縦長の 1 枚ずつ。読めたものから決める）
    @State private var picks: [String: String] = [:]

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
                Text("\(mood == .night ? L("夜", "Night") : L("昼", "Day")) \(page + 1) / \(CamperRoomContactPages.count(kind))")
                    .font(JPFont.number(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.text)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("接写の一覧", "Close-up sheet"))
                    .accessibilityValue(marker)
                    .accessibilityIdentifier("camper.room.contact")
                Spacer()
                pager("chevron.left", id: "camper.room.contact.prev", enabled: page > 0) { go(page - 1) }
                pager("chevron.right", id: "camper.room.contact.next", enabled: page + 1 < CamperRoomContactPages.count(kind)) { go(page + 1) }
                pager(mood == .night ? "sun.max" : "moon", id: "camper.room.contact.mood", enabled: true) {
                    mood = mood == .night ? .day : .night
                    images = [:]
                    draw()
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(CamperRoomContactPages.page(page, kind)) { e in
                    let f = e.furniture
                    VStack(spacing: 2) {
                        Group {
                            if let image = images[e.id] {
                                Image(uiImage: image).resizable().scaledToFit()
                            } else {
                                Color.white.opacity(0.04)
                            }
                        }
                        .frame(height: Self.cell.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("\(e.view.map { CamperRoomLegs.views[$0].name + " · " } ?? "")\(f.name) · \(f.id)\(e.photo.map { $0 == "wide" ? L("・横長の写真", " · wide photo") : L("・縦長の写真", " · tall photo") } ?? "")")
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
        .onAppear {
            if frames {
                photoImages.load(Array(photos.prefix(24).map(\.id)), from: photos)
                // 読めない写真ばかりでも、待ち続けない（20 秒で読めた分から選ぶ）
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { pickPhotos(final: true) }
            } else {
                draw()
            }
        }
        .onChange(of: photoImages.images.count) { _, _ in pickPhotos(final: false) }
        // 写真の一覧は部屋より後に届く（開いた時に空なら、届いてから読む）
        .onChange(of: photos.count) { _, _ in
            if frames { photoImages.load(Array(photos.prefix(24).map(\.id)), from: photos) }
        }
    }

    /// 横長（幅/高さ 1.2 以上）と縦長（0.85 以下）の写真を 1 枚ずつ選んで、描き始める
    private func pickPhotos(final: Bool) {
        guard frames, picks.isEmpty else { return }
        let loaded = photos.compactMap { p in photoImages.images[p.id].map { (p.id, $0.size.width / max(1, $0.size.height)) } }
        let wide = loaded.first { $0.1 >= 1.2 }?.0, tall = loaded.first { $0.1 <= 0.85 }?.0
        guard (wide != nil && tall != nil) || (final && !loaded.isEmpty) else { return }
        picks = ["wide": wide ?? loaded.max { $0.1 < $1.1 }!.0, "tall": tall ?? loaded.min { $0.1 < $1.1 }!.0]
        draw()
    }

    private func pager(_ symbol: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).jpSystemFont(16, weight: .semibold)
                .foregroundStyle(enabled ? WebTheme.foreground : WebTheme.faint)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                // 44pt の枠全体を押せるように（2026-10-23 PR #371 の検証: 読み上げの枠が矢印の形 8×14pt だけで、
                // 込んだ Mac で 16 → 17 頁の押しが届かなかった見立て）
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }

    private func go(_ next: Int) {
        page = max(0, min(CamperRoomContactPages.count(kind) - 1, next))
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
        let shots = photoImages.images, chosen = picks
        Task { @MainActor in
            var overflow = 0.0
            for e in CamperRoomContactPages.page(want, kind) {
                guard want == page, m == mood else { return }
                let photoId = e.photo.flatMap { chosen[$0] }
                images[e.id] = r.render(e.furniture, mood: m, size: CGSize(width: Self.cell.width * 3, height: Self.cell.height * 3),
                                       photoId: photoId, images: shots, view: e.view)
                overflow = max(overflow, r.photoUVOverflow)
                await Task.yield()
            }
            guard want == page, m == mood else { return }
            var done = CamperRoomContactPages.marker(mood: m, page: want, kind)
            if frames {
                // 額の頁: 入れた写真（id と縦横比）と、印画が写真の外を読んだ量（0 でなければ筋に崩れる）
                let aspect = { (id: String?) in id.flatMap { shots[$0] }.map { String(format: "%.2f", $0.size.width / max(1, $0.size.height)) } ?? "-" }
                done += " wide=\(aspect(chosen["wide"])) tall=\(aspect(chosen["tall"])) uvOut=\(CamperRoomScene.overflowText(overflow))"
            }
            marker = done
        }
        #endif
    }
}
