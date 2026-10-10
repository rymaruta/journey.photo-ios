import Foundation
import UIKit
import CoreImage
import ImageIO

/// 名前の横のバッジの絵を**画面の画素ちょうどに縮めて**持つ（案 C・2026-10-09）。
///
/// owner の決定: 名前の横には**大きいメダルの絵（棚・手に取って回す画面と同じ絵）をそのまま縮めて**出す
/// （「C が好き。だってそのままがいいじゃん」）。文字の帯を省いた小さい絵（`-s`）は使わない。
///
/// 780px の絵を 22pt 前後（3倍の画面で 67〜92px）へ一気に縮めると、描くたびの補間では
/// 細い線がざらつく。だから比べた案 C と同じく **Lanczos で縮め、軽く輪郭を立てた**
/// （半径 0.8px・強さ 0.6）絵を1度だけ作り、画素の数ごとに覚えておく。
/// 1枚は 92px 四方で約 34KB——大きい絵を何枚も小さく描き直すより軽い。
///
/// **SwiftUI を読まない**（`MedalTextures` と同じ。Linux の模型で `UIColor` などの名前が割れる）
enum NameBadgeRaster {

    /// 輪郭の立て方（比べた案 C の作り方 `UnsharpMask(radius=0.8, percent=60)` と同じ）
    static let sharpenRadius: Double = 0.8
    static let sharpenIntensity: Double = 0.6
    /// 作る絵の上限（大きい文字の設定でも 256px あれば足りる。元の絵より大きくはしない）。
    /// 名前の横の画面の「持っているバッジ」56pt × 3倍 = 168px も収まる（2026-10-09 確かめた）
    static let maxPixels = 256
    /// 覚えておく枚数。名前の横（画面に数枚）に加え、名前の横の画面の2つの格子（16枚前後）・棚・
    /// お知らせのメダルも同じ絵を使う（2026-10-09）ので 48 → 64。168px で1枚 約 110KB、満杯で 7MB ほど
    static let cacheLimit = 64

    /// 縮めた先の一辺（px）。点の大きさ × 画面の倍率を丸める。値が壊れていれば nil
    static func pixelSide(points: Double, scale: Double) -> Int? {
        guard points.isFinite, scale.isFinite, points > 0, scale > 0 else { return nil }
        let pixels = (points * scale).rounded()
        guard pixels >= 1 else { return nil }
        return Int(min(pixels, Double(maxPixels)))
    }

    /// 覚えておく鍵（絵の名前と画素の数）
    static func cacheKey(image: String, pixels: Int) -> String { "\(image)@\(pixels)" }

    /// 覚えている絵（無ければ nil・画面の処理で引いてよい）
    static func cached(image: String, pixels: Int) -> UIImage? {
        cache.object(forKey: cacheKey(image: image, pixels: pixels) as NSString)?.image
    }

    /// 縮めた絵を画面の処理の外で作る。**同じ鍵（絵の名前と画素の数）を同時に頼まれたら1回だけ作る**
    /// （名前の横の画面の格子・お知らせで同じ絵のマスが並ぶ。2026-10-09 確かめ役の指摘）
    ///
    /// 🔴 **作るのは専用の1本の列（`renderQueue`）で、1枚ずつ。** Swift の並行処理の共有の糸（協調スレッドの
    /// 一団）の上では作らない（2026-10-10 Mac run 385: 格子・お知らせへ広げたら、名前の横の画面で 10 枚以上を
    /// `Task.detached` の中で同時に作り、重い同期の仕事が共有の糸を全部ふさいだ。縮めた絵は1枚も出ず、
    /// `GET /user/badges` の続きも走らず「決める」が押せないまま、画面写真の試験は UI の問い合わせが
    /// 時間切れになった）。待つ側は継続（continuation）で待つだけで、糸を握らない
    static func shared(named name: String, pixels: Int) async -> UIImage? {
        if let hit = cached(image: name, pixels: pixels) { return hit }
        let box = await inflight.value(for: cacheKey(image: name, pixels: pixels)) {
            await onRenderQueue { image(named: name, pixels: pixels).map(Box.init) }
        }
        return box?.image
    }

    /// 縮める仕事の専用の列（直列）。共有の糸をふさがず、同時に何枚も作らない
    private static let renderQueue = DispatchQueue(label: "photo.journey.badge-raster", qos: .userInitiated)
    private static let renderQueueKey = DispatchSpecificKey<Bool>()
    private static let markRenderQueue: Void = { renderQueue.setSpecific(key: renderQueueKey, value: true) }()

    /// いま専用の列の上か（テスト用）
    static var isOnRenderQueue: Bool { DispatchQueue.getSpecific(key: renderQueueKey) == true }

    /// 重い同期の仕事を専用の列で走らせ、終わるまで（糸を握らずに）待つ
    static func onRenderQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        _ = markRenderQueue
        return await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            renderQueue.async { continuation.resume(returning: work()) }
        }
    }

    /// 作っている途中の仕事（鍵ごと）
    private static let inflight = InflightTasks<Box?>()

    /// 縮めた絵。覚えていればそれを、無ければ作って覚える。**重いので画面の処理の外で呼ぶ**
    static func image(named name: String, pixels: Int) -> UIImage? {
        if let hit = cached(image: name, pixels: pixels) { return hit }
        guard let made = render(named: name, pixels: pixels) else { return nil }
        cache.setObject(Box(made), forKey: cacheKey(image: name, pixels: pixels) as NSString)
        return made
    }

    // MARK: - 作る

    final class Box: @unchecked Sendable {
        let image: UIImage
        init(_ image: UIImage) { self.image = image }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = cacheLimit
        return cache
    }()

    /// 作業の色空間は sRGB（比べた案 C と同じく、ガンマのかかった値のまま縮める・立てる）。
    /// `CIContext` は使い回す（作るたびに準備が捨てられる・`PhotoRenderer` と同じ判断）
    private static let context: CIContext = {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return CIContext() }
        return CIContext(options: [.workingColorSpace: srgb])
    }()

    private static func render(named name: String, pixels: Int) -> UIImage? {
        guard pixels >= 1, let source = UIImage(named: name)?.cgImage, source.width > 0 else { return nil }
        let target = min(pixels, source.width)
        let factor = Double(target) / Double(source.width)
        var output = CIImage(cgImage: source)
        if factor < 1 {
            guard let lanczos = CIFilter(name: "CILanczosScaleTransform") else { return nil }
            lanczos.setValue(output, forKey: kCIInputImageKey)
            lanczos.setValue(factor, forKey: "inputScale")
            lanczos.setValue(1.0, forKey: "inputAspectRatio")
            guard let scaled = lanczos.outputImage else { return nil }
            output = scaled
        }
        let rect = CGRect(x: 0, y: 0, width: target, height: target)
        if let sharpen = CIFilter(name: "CIUnsharpMask") {
            // 縁で透明を拾って枠が欠けないよう、縁の画素を外へ伸ばしてから立てる
            sharpen.setValue(output.clampedToExtent(), forKey: kCIInputImageKey)
            sharpen.setValue(sharpenRadius, forKey: "inputRadius")
            sharpen.setValue(sharpenIntensity, forKey: "inputIntensity")
            if let sharpened = sharpen.outputImage { output = sharpened.cropped(to: rect) }
        }
        guard let made = context.createCGImage(output, from: rect, format: .RGBA8,
                                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return UIImage(cgImage: made)
    }
}

/// 同じ鍵の仕事を1つにまとめる。作っている途中に同じ鍵が頼まれたら、その仕事の答えを待って分ける。
/// 終わったら忘れる（できた絵は `NameBadgeRaster` の覚えに残る）
actor InflightTasks<Value: Sendable> {
    private var running: [String: Task<Value, Never>] = [:]

    /// `make` は待つだけの仕事にする（重い同期の仕事は `NameBadgeRaster.onRenderQueue` で専用の列へ）
    func value(for key: String, make: @escaping @Sendable () async -> Value) async -> Value {
        if let task = running[key] { return await task.value }
        let task = Task { await make() }
        running[key] = task
        let value = await task.value
        running[key] = nil
        return value
    }

    /// 作っている途中の数（テスト用）
    var runningCount: Int { running.count }
}
