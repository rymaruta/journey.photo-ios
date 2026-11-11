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

/// 型の一覧・特別なトランクの一覧のトランク（2026-11-11 判断）。**生の `TrunkFigure` と同じ絵**を、画面の倍率で 1 度だけ
/// 画素の絵にして置く。描き上がるまでは生の絵を出す（空白を見せない）。影と吊るすタグが枠の外へ出る分は余白を付けて描く。
///
/// メモリの手当て: 画面の倍率で描く・画面から外れたら（`onDisappear`：送って見えなくなった・ほかの画面へ進んだ・戻った）
/// 絵を手放す。特別なトランクの一覧は `LazyVStack` で、画面の外の札は作らない
struct TrunkFigureStill: View {
    let model: TrunkModel
    let posts: Int
    var stuck: [TrunkLabel] = []
    var ownerName: String?
    /// 置く幅（`maxWidth` があれば、置き場の幅に合わせて縮める・`TrunkFigureFit` と同じ）
    var width: Double = TrunkLooks.canvasWidth
    var maxWidth: Double?
    var tagsFrom: [TrunkLabel]?
    var tagPicks: [TrunkTagPick] = []


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

    private func still(width: Double) -> some View {
        TrunkFigureStillBody(figure: TrunkFigure(model: model, posts: posts, stuck: stuck, ownerName: ownerName, width: width,
                                                 tagsFrom: tagsFrom, tagPicks: tagPicks),
                             key: TrunkStillKey(model: model, posts: posts, stuck: stuck, ownerName: ownerName, width: width,
                                                tagsFrom: tagsFrom, tagPicks: tagPicks))
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
}

private struct TrunkFigureStillBody: View {
    let figure: TrunkFigure
    let key: TrunkStillKey

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var madeFor: TrunkStillKey?

    var body: some View {
        let k = figure.width / TrunkLooks.canvasWidth
        Group {
            // 測定専用（`-JPPreviewTrunkDiag live`・Debug のみ）: 前の作り（生の絵）のまま。絵の見比べの「前」に使う
            if let image, madeFor == key, !PreviewSession.trunkDiag.contains("live") {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: (TrunkLooks.canvasWidth + 2 * TrunkStillLayout.padSide) * k,
                           height: (TrunkLooks.canvasHeight + TrunkStillLayout.padTop + TrunkStillLayout.padBottom) * k)
                    .offset(x: -TrunkStillLayout.padSide * k, y: -TrunkStillLayout.padTop * k)
                    .frame(width: figure.width, height: TrunkLooks.canvasHeight * k, alignment: .topLeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isImage)
            } else {
                figure
            }
        }
        .task(id: key) {
            guard !PreviewSession.trunkDiag.contains("live"), image == nil || madeFor != key else { return }
            let scale = max(1, displayScale)
            let raw = TrunkPerfMeter.measure("StillRender") {
                TrunkStill.render(figure
                                    .padding(.top, TrunkStillLayout.padTop * k)
                                    .padding(.horizontal, TrunkStillLayout.padSide * k)
                                    .padding(.bottom, TrunkStillLayout.padBottom * k),
                                  scale: scale)
            }
            let made = await TrunkStill.settle([raw])[0]
            guard !Task.isCancelled else { return }
            image = made
            madeFor = key
            TrunkPerfMeter.shared.hit("StillReady")
        }
        // 画面から外れたら手放す（送って見えなくなった・進んだ・戻った）。次に出たときに描き直す
        .onDisappear {
            image = nil
            madeFor = nil
        }
        .modifier(TrunkLiveCount(name: "Still"))
    }
}
