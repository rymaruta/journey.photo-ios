import SwiftUI
import UIKit
import ImageIO
// Linux では URLSession が別モジュールに居る（iOS では何も起きない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 写真を**表示する幅に縮めて**出す（2026-10-03 の品質点検）。
///
/// `RemoteImage`（中身は `AsyncImage`）は元の画像（長い辺 1920px）を**縮めずに展開する**——
/// 1枚あたり約 11MB。旅の一冊はページを `LazyVStack` に並べ、通り過ぎたページの絵も
/// 抱えたままになりやすいので、長い旅を最後までめくると数百 MB 規模になりうる
/// （**実機では測っていない**。見積もりは 1920×1440×4 バイト）。
///
/// ここでは画像の中身を取ってから、ImageIO で**表示に要る画素数まで縮めて**展開する
/// （縮め方は投稿と同じ `ImagePreparer.downsampledImage`——向きを画素に焼く・HDR を SDR に直す）。
/// 取りに行くのは `URLSession.shared`＝`URLCache.shared` で、`AsyncImage` と同じ控えを使う
/// （ログアウトで空にする控えもこれ・`AuthStore.responseCache`）。
///
/// 見た目は `RemoteImage` と同じ（地の色・読み込み中の輪・失敗の記号・自動で1回だけ読み直す）。
/// 押して読み直す記号は出さない——旅の一冊ではページ全体が `NavigationLink` なので、
/// ボタンを置くと押下を奪う（`RemoteImage.allowsManualRetry` の注記と同じ理由）
struct DownsampledRemoteImage: View {

    let url: URL?
    var contentMode: ContentMode = .fit
    /// 写真の縦横比（幅 ÷ 高さ）。分かれば渡す——縦長の写真も幅いっぱいに描くので、
    /// 長い辺の画素数を縦横比から決める（`DownsampledImageSize.pixels`）
    var aspectRatio: CGFloat? = nil
    /// 敷き方が `.fill` のとき、枠のどこを残すか（`RemoteImage.alignment` と同じ）
    var alignment: Alignment = .center
    /// 縦横比が分からない写真を `.fill` で敷くとき、**この比（長い辺 ÷ 短い辺）までの形**と
    /// 見込んで読む。nil なら上限で読む（`DownsampledImageSize.pixels(filling:)`）。
    /// 小さな枠（一覧の表紙）で、縦横比を持たない写真を上限の大きさで読まないため
    var assumedRatioLimit: CGFloat? = nil
    /// 読み込みが片付いたときに呼ぶ（出た＝true・出せないと分かった＝false。`RemoteImage.onSettled` と同じ）。
    /// 既定は何もしない
    var onSettled: ((Bool) -> Void)? = nil

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    /// いま出している絵を読んだときの画素数（長い辺）。これ以上で読めていれば読み直さない
    @State private var loadedPixels = 0
    @State private var failed = false
    /// 敷く枠の大きさ（読む画素数を決めるため）。0 の間は読まない
    @State private var size: CGSize = .zero
    /// 自動で読み直した回数（上限は `RemoteImageRetry.automaticLimit`）
    @State private var automaticRetries = 0

    var body: some View {
        ZStack {
            WebTheme.surface
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            } else if failed {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
            }
        }
        .clipped()
        // 枠を測る（読む画素数を決めるため）。0 の間は読まない
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { size = g.size }
                    .onChange(of: g.size) { _, newSize in size = newSize }
            }
        }
        .task(id: LoadKey(url: url, pixels: neededPixels, attempt: automaticRetries)) {
            await load()
        }
        // 別の写真に替わったら数え直す（前の写真の失敗で、次の写真の読み直しを使い切らない）
        .onChange(of: url) { _, _ in
            image = nil
            loadedPixels = 0
            failed = false
            automaticRetries = 0
        }
    }

    /// いまの枠で要る長い辺の画素数（敷き方で決め方が違う）
    private var neededPixels: Int? {
        switch contentMode {
        case .fill:
            return DownsampledImageSize.pixels(filling: size, scale: displayScale, aspectRatio: aspectRatio,
                                               assumedRatioLimit: assumedRatioLimit)
        default:
            return DownsampledImageSize.pixels(width: size.width, scale: displayScale, aspectRatio: aspectRatio)
        }
    }

    private struct LoadKey: Equatable {
        let url: URL?
        let pixels: Int?
        let attempt: Int
    }

    private func load() async {
        guard let url, let pixels = neededPixels else { return }
        // 同じ大きさ以上で読めていれば読み直さない（幅が少し縮んだだけの回）
        if image != nil, loadedPixels >= pixels { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImage = ImagePreparer.downsampledImage(source: source, maxPixelSize: pixels) else { return nil }
                return UIImage(cgImage: cgImage)
            }.value
            guard !Task.isCancelled else { return }
            guard let decoded else { throw URLError(.cannotDecodeContentData) }
            image = decoded
            loadedPixels = pixels
            failed = false
            onSettled?(true)
        } catch {
            // 取り消し（スクロールで外れた・別の写真に替わった）は失敗にしない
            guard !Task.isCancelled else { return }
            if case .retryAutomatically(let seconds) = RemoteImageRetry.step(automaticDone: automaticRetries,
                                                                               manualDone: 0) {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                automaticRetries += 1
            } else if image == nil {
                failed = true
                onSettled?(false)
            }
        }
    }
}

/// 縮めて読む画素数（画面を持たない計算）。
enum DownsampledImageSize {
    /// 刻み。**幅が少し変わるたびに読み直さない**ように、この単位で切り上げる
    static let step = 256
    /// 下限（小さな枠でも、ぼやけない程度）
    static let minimum = 256
    /// 上限。元の画像（長い辺 1920px）より大きく読む意味は無い
    static let maximum = 2048

    /// **長い辺**の画素数（ImageIO の `ThumbnailMaxPixelSize` が長い辺で縮めるから）。
    /// 表示する幅 × 画面の倍率から長い辺を出し、`step` で切り上げ、`minimum`〜`maximum` に収める。
    /// **幅がまだ分からない（0 以下）なら nil**——測れるまで読まない
    ///
    /// 🔴 **縦長の写真も幅いっぱいに描く**（旅の一冊のページ）。長い辺＝高さなので、幅の画素だけを
    /// 長い辺に渡すと幅が足りずにぼやける（幅 1,170px が要るのに 960px で読む）。縦横比
    /// （幅 ÷ 高さ）が分かれば、長い辺 = 幅の画素 ÷ 縦横比。分からなければ幅をそのまま長い辺にする
    static func pixels(width: CGFloat, scale: CGFloat, aspectRatio: CGFloat? = nil) -> Int? {
        guard width > 0, scale > 0 else { return nil }
        var longSide = width * scale
        if let aspectRatio, aspectRatio > 0, aspectRatio < 1 { longSide /= aspectRatio }
        let needed = Int(longSide.rounded(.up))
        let stepped = ((needed + step - 1) / step) * step
        return min(maximum, max(minimum, stepped))
    }

    /// 枠いっぱいに**敷き詰める**（`.fill`）ときの長い辺の画素数（撮影地の代表写真の並び）。
    ///
    /// 敷き詰めると、写真は枠の幅と高さの**両方を覆う**まで広がる。枠より横長の写真は
    /// 高さに合わせて広がり、幅は枠からはみ出す——幅の画素だけで読むとぼやける。
    /// 縦横比（幅 ÷ 高さ）が分かれば、広がった後の写真の長い辺を出す。
    /// **縦横比が分からなければ上限で読む**（どの形でもぼやけない。縮める得は無くなる）。
    /// ただし `assumedRatioLimit`（長い辺 ÷ 短い辺）を渡されたら、**その比までの横長・縦長の
    /// どちらでも足りる**大きさで読む（一覧の小さな表紙・台帳の写真は縦横比を持たない）。
    /// 枠の幅か高さがまだ分からない（0 以下）なら nil
    static func pixels(filling box: CGSize, scale: CGFloat, aspectRatio: CGFloat? = nil,
                       assumedRatioLimit: CGFloat? = nil) -> Int? {
        guard box.width > 0, box.height > 0, scale > 0 else { return nil }
        guard let ratio = aspectRatio, ratio > 0 else {
            guard let limit = assumedRatioLimit, limit >= 1 else { return maximum }
            // いちばん横長（limit:1）といちばん縦長（1:limit）の、要る方の大きい方
            let wide = pixels(filling: box, scale: scale, aspectRatio: limit) ?? maximum
            let tall = pixels(filling: box, scale: scale, aspectRatio: 1 / limit) ?? maximum
            return max(wide, tall)
        }
        // 写真が枠を覆うまで広げたときの大きさ（pt）
        let boxRatio = box.width / box.height
        let shown = ratio >= boxRatio
            ? CGSize(width: box.height * ratio, height: box.height)
            : CGSize(width: box.width, height: box.width / ratio)
        let needed = Int((max(shown.width, shown.height) * scale).rounded(.up))
        let stepped = ((needed + step - 1) / step) * step
        return min(maximum, max(minimum, stepped))
    }
}
