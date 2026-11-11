import SwiftUI
import UIKit

/// トランクの絵を「画素を持つ 1 枚の絵」にする道具（2026-11-11 判断・owner「旅のトランク重すぎる」）。
///
/// **なぜ要るか（run 997 の数）**:
/// - `ImageRenderer` の `uiImage` は、その場では塗られていない「後で塗る絵」を返す。SceneKit が中身を読んだときに
///   主スレッドで塗られ、回す画面を開く間に主スレッドが止まっていた（積み: `MedalCoinCoordinator.apply` の中の
///   `RB::ImageProvider::wait_phase`・開く間の停止 2.7〜5.2 秒）
/// - 特別なトランクの一覧は、6 つの生の絵の `drawingGroup` を送る 1 コマごとに描き直し、主スレッドが GPU を待っていた
///   （積み: `RBLayer displayWithBounds` の `waitUntilScheduled`・1 コマ平均 48ms）。1 度描いた絵にすると 17.7ms
///
/// ここでは、後で塗る絵を**主スレッドの外で**同じ画素の形（色空間・1 画素の並び）の絵に塗り写す。色は変えない
enum TrunkStill {

    /// 後で塗る絵を、画素を持つ絵に塗り写す（**主スレッドの外で呼ぶ**）。塗れなければ元の絵をそのまま返す
    static func bitmap(_ image: UIImage?) -> UIImage? {
        #if os(iOS)
        guard let image, let cg = image.cgImage else { return image }
        let rect = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        // 元と同じ色空間・同じ並びで塗る（色の変換をしない）。その並びで作れないときだけ sRGB の 8 ビットにする
        let space = cg.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: cg.bitsPerComponent,
                                bytesPerRow: 0, space: space, bitmapInfo: cg.bitmapInfo.rawValue)
            ?? CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context else { return image }
        context.draw(cg, in: rect)
        guard let made = context.makeImage() else { return image }
        return UIImage(cgImage: made, scale: image.scale, orientation: image.imageOrientation)
        #else
        return image
        #endif
    }

    /// いくつかの絵を、主スレッドの外でまとめて塗り写す
    static func settle(_ images: [UIImage?]) async -> [UIImage?] {
        let boxed = StillBox(images)
        let done = await Task.detached(priority: .userInitiated) { () -> StillBox in
            StillBox(TrunkPerfMeter.measure("StillBitmap") { boxed.images.map { bitmap($0) } })
        }.value
        return done.images
    }

    /// 測る起動のときだけ: 絵の中で色が付いている範囲が、360×300 の枠からどれだけはみ出しているか（枠の単位）。
    /// 余白（`TrunkStillLayout`）が足りているかを数で見る（2026-11-11）
    static func reach(_ image: UIImage, k: Double, scale: CGFloat) -> String {
        #if os(iOS)
        guard let cg = image.cgImage else { return "-" }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return "-" }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where data[(y * w + x) * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return "empty" }
        let unit = Double(scale) * k
        // 枠の外へ出た量（正ならはみ出し）と、余白の端までの残り
        let left = TrunkStillLayout.padSide - Double(minX) / unit
        let right = Double(maxX + 1) / unit - TrunkStillLayout.padSide - TrunkLooks.canvasWidth
        let top = TrunkStillLayout.padTop - Double(minY) / unit
        let bottom = Double(maxY + 1) / unit - TrunkStillLayout.padTop - TrunkLooks.canvasHeight
        return String(format: "left=%.1f right=%.1f top=%.1f bottom=%.1f touches_edge=%d", left, right, top, bottom,
                      (minX == 0 || minY == 0 || maxX == w - 1 || maxY == h - 1) ? 1 : 0)
        #else
        return "-"
        #endif
    }

    /// 絵にする（`ImageRenderer`・主スレッド）。`scale` は画面の倍率
    @MainActor
    static func render<V: View>(_ view: V, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.uiImage
    }
}

/// 型の一覧の画素の絵の余白（View の外に置く: 試験から isolation なしで読む）
enum TrunkStillLayout {
    /// 枠の外へ出る分の余白（360×300 の枠の単位）。胴の影（下へ 30＋ぼかし 25）・左右の影・吊るすタグ。
    /// 18 の倍数（幅 140 の札で 1〜3 倍のどれでも画素が整数になる・`TrunkPerfFixTests`）
    static let padTop = 18.0
    static let padSide = 54.0
    static let padBottom = 90.0
}

/// 糸をまたいで絵を渡す入れ物（`UIImage` は作った後は読むだけ）
private struct StillBox: @unchecked Sendable {
    let images: [UIImage?]
    init(_ images: [UIImage?]) { self.images = images }
}

/// 1 つの画面（型の一覧・特別なトランクの一覧）の、画素の絵の置き場（2026-11-11 判断）。
///
/// - 画面を開いたら、見えている札から順に 1 枚ずつ作る（主スレッドで組むのは 1 枚ずつ・間に 1 コマ返す。塗るのは主スレッドの外）。
///   run 1003: 札が出るたびに作り直すと、送る間に 1 枚 34〜61ms の組み立てで止まった（100ms 超 45 回）ので、画面の間は持っておく
/// - 画面から戻ると、この置き場ごと手放す（`@StateObject`）。メモリが足りないと知らされたら空にする
@MainActor
final class TrunkStillCache: ObservableObject {
    /// 作った絵（1 画面に多くて 6 枚なので並びで持つ）
    @Published private(set) var images: [(key: TrunkStillKey, image: UIImage)] = []
    private var pending: [(key: TrunkStillKey, figure: TrunkFigure, scale: CGFloat)] = []
    private var running = false
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.images = [] }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func image(_ key: TrunkStillKey) -> UIImage? { images.first(where: { $0.key == key })?.image }

    /// 作る順に並べる（もうある・並んでいるものは足さない）
    func want(_ key: TrunkStillKey, _ figure: TrunkFigure, scale: CGFloat) {
        guard image(key) == nil, !pending.contains(where: { $0.key == key }) else { return }
        pending.append((key, figure, scale))
        guard !running else { return }
        running = true
        Task { await drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let job = pending.removeFirst()
            let k = job.figure.width / TrunkLooks.canvasWidth
            let raw = TrunkPerfMeter.measure("StillRender") {
                TrunkStill.render(job.figure
                                    .padding(.top, TrunkStillLayout.padTop * k)
                                    .padding(.horizontal, TrunkStillLayout.padSide * k)
                                    .padding(.bottom, TrunkStillLayout.padBottom * k),
                                  scale: job.scale)
            }
            let made = await TrunkStill.settle([raw])[0]
            if let made, image(job.key) == nil { images.append((job.key, made)) }
            TrunkPerfMeter.shared.hit("StillReady")
            if TrunkPerfMeter.shared.enabled, let made {
                TrunkPerfMeter.shared.note("StillReach", TrunkStill.reach(made, k: k, scale: job.scale))
            }
            // 1 コマ返してから次へ（送り・押すのを止めない）
            try? await Task.sleep(for: .milliseconds(16))
        }
        running = false
    }
}

/// 型の一覧・特別なトランクの一覧のトランク（2026-11-11 判断）。**生の `TrunkFigure` と同じ絵**を、画面の倍率で 1 度だけ
/// 画素の絵にして置く。描き上がるまでは生の絵を出す（空白を見せない）。影と吊るすタグが枠の外へ出る分は余白を付けて描く。
///
/// メモリの手当て: 画面の倍率で描く・画面から外れたら（`onDisappear`：送って見えなくなった・ほかの画面へ進んだ・戻った）
/// 絵を手放す。特別なトランクの一覧は `LazyVStack` で、画面の外の札は作らない
struct TrunkFigureStill: View {
    @ObservedObject var cache: TrunkStillCache
    let model: TrunkModel
    let posts: Int
    var stuck: [TrunkLabel] = []
    var ownerName: String?
    /// 置く幅（`maxWidth` があれば、置き場の幅に合わせて縮める・`TrunkFigureFit` と同じ）
    var width: Double = TrunkLooks.canvasWidth
    var maxWidth: Double?
    var tagsFrom: [TrunkLabel]?
    var tagPicks: [TrunkTagPick] = []
    /// 同じ画面に並ぶほかの型（見えている札の後に、続けて作っておく）
    var siblings: [TrunkModel] = []

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let maxWidth {
            GeometryReader { geo in
                still(width: min(maxWidth, Double(geo.size.width)))
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .aspectRatio(TrunkLooks.canvasWidth / TrunkLooks.canvasHeight, contentMode: .fit)
            .frame(maxWidth: maxWidth)
        } else {
            still(width: width)
        }
    }

    private func figure(_ model: TrunkModel, width: Double) -> TrunkFigure {
        TrunkFigure(model: model, posts: posts, stuck: stuck, ownerName: ownerName, width: width, tagsFrom: tagsFrom, tagPicks: tagPicks)
    }

    private func key(_ model: TrunkModel, width: Double) -> TrunkStillKey {
        TrunkStillKey(model: model, posts: posts, stuck: stuck, ownerName: ownerName, width: width, tagsFrom: tagsFrom,
                      tagPicks: tagPicks, scale: Double(max(1, displayScale)))
    }

    @ViewBuilder
    private func still(width: Double) -> some View {
        let live = figure(model, width: width)
        let mine = key(model, width: width)
        let k = width / TrunkLooks.canvasWidth
        Group {
            // 測定専用（`-JPPreviewTrunkDiag live`・Debug のみ）: 前の作り（生の絵）のまま。絵の見比べの「前」に使う
            if let image = cache.image(mine), !PreviewSession.trunkDiag.contains("live") {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: (TrunkLooks.canvasWidth + 2 * TrunkStillLayout.padSide) * k,
                           height: (TrunkLooks.canvasHeight + TrunkStillLayout.padTop + TrunkStillLayout.padBottom) * k)
                    .offset(x: -TrunkStillLayout.padSide * k, y: -TrunkStillLayout.padTop * k)
                    .frame(width: width, height: TrunkLooks.canvasHeight * k, alignment: .topLeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isImage)
                    .modifier(TrunkLiveCount(name: "Still"))
            } else {
                // 描き上がるまでは生の絵（空白を見せない）
                live
            }
        }
        .task(id: mine) {
            guard !PreviewSession.trunkDiag.contains("live") else { return }
            let scale = CGFloat(mine.scale)
            cache.want(mine, live, scale: scale)
            for other in siblings where other != model {
                cache.want(key(other, width: width), figure(other, width: width), scale: scale)
            }
        }
    }
}

/// 絵を作り直す合図（絵に効くものだけ）
struct TrunkStillKey: Equatable {
    let model: TrunkModel
    let posts: Int
    let stuck: [TrunkLabel]
    let ownerName: String?
    let width: Double
    let tagsFrom: [TrunkLabel]?
    let tagPicks: [TrunkTagPick]
    /// 画面の倍率
    let scale: Double
}
