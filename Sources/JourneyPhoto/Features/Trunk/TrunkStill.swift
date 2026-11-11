import SwiftUI
import UIKit

/// トランクの絵を「画素を持つ 1 枚の絵」にする道具（2026-11-11 判断・owner「旅のトランク重すぎる」）。
///
/// **なぜ要るか（run 997 の数）**:
/// - `ImageRenderer` の `uiImage` は、その場では塗られていない「後で塗る絵」を返す。SceneKit が中身を読んだときに
///   主スレッドで塗られ、回す画面を開く間に主スレッドが止まっていた（積み: `MedalCoinCoordinator.apply` の中の
///   `RB::ImageProvider::wait_phase`・開く間の停止 2.7〜5.2 秒）
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
}

/// 糸をまたいで絵を渡す入れ物（`UIImage` は作った後は読むだけ）
private struct StillBox: @unchecked Sendable {
    let images: [UIImage?]
    init(_ images: [UIImage?]) { self.images = images }
}
