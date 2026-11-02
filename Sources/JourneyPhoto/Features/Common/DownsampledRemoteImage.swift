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
    /// 絵が出るときの動き（`RemoteImage` の `AsyncImage` と同じ 0.15 秒の淡い出を、格子で揃えるため）。
    /// 既定は動き無し（今までの呼び出しは変わらない）。控えから出す絵には付けない（戻ったときに瞬かない）
    var appearAnimation: Animation? = nil

    /// 縮めて展開した絵の控え（2026-10-28 判断・マイページの送りの重さ）。`@State` の絵は格子のマスが
    /// 画面の外へ出ると捨てられ、戻るたびに取り直し・展開し直していた。URL ごとに1枚、いちばん大きく
    /// 読めた絵を持つ（展開後の大きさで上限 `DecodedImageMemory.defaultCostLimit`・足りなければ古いものから捨てる）
    static let memory = DecodedImageMemory<UIImage>()

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
            // 控えに在れば、取りに行く前から出す（格子へ戻ったときに読み込み中の輪から出直さない）
            if let image = image ?? url.flatMap({ Self.memory.entry(for: $0)?.image }) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            } else if DownsampledImagePhase.of(hasImage: false, failed: failed, hasURL: url != nil) == .failed {
                // URL の無い写真も写真の記号（読み込み中の輪を回し続けない・前の `RemoteImage` と同じ）
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
        // URL の無い写真は読みに行かず、出せないと決める（輪を回し続けない・2026-10-28 確かめ役の指摘）
        guard let url else {
            if !failed {
                failed = true
                onSettled?(false)
            }
            return
        }
        guard let pixels = neededPixels else { return }
        // 同じ大きさ以上で読めていれば読み直さない（幅が少し縮んだだけの回）
        if image != nil, loadedPixels >= pixels { return }
        // 控えに足りる大きさで在れば、取りに行かず展開もしない
        if let cached = Self.memory.entry(for: url, atLeast: pixels) {
            image = cached.image
            loadedPixels = cached.pixels
            failed = false
            onSettled?(true)
            return
        }
        do {
            // 同じURLを複数セルが同時に表示しても、通信は一度だけ。
            let data = try await GridImageInFlight.shared.data(for: url)
            // 同じURL・画素数を複数セルが同時に要求しても、展開は一度だけ。
            let decoded = await GridImageDecodeInFlight.shared.image(data: data, for: url, pixels: pixels)
            guard !Task.isCancelled else { return }
            guard let decoded else { throw URLError(.cannotDecodeContentData) }
            Self.memory.store(decoded.image, pixels: pixels, for: url, cost: decoded.cost)
            withAnimation(appearAnimation) { image = decoded.image }
            loadedPixels = pixels
            failed = false
            onSettled?(true)
        } catch {
            // 取り消し（スクロールで外れた・別の写真に替わった）は失敗にしない
            guard !Task.isCancelled else { return }
            // 期限の切れた署名つき URL なら、一覧を取り直す合図を出す（読み直しても 403 のまま。
            // 2026-10-18・札 #294。署名の無い URL・期限内の失敗では何もしない）
            SignedImageExpiry.report(url)
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

/// 絵の段のどれを出すか（画面を持たない計算・2026-10-28）。**URL が無ければ写真の記号**
/// ——読みに行く先が無いのに読み込み中の輪を回し続けない（前の `RemoteImage` は記号を出していた）
enum DownsampledImagePhase: Equatable {
    case image
    case failed
    case loading

    static func of(hasImage: Bool, failed: Bool, hasURL: Bool) -> DownsampledImagePhase {
        if hasImage { return .image }
        if failed || !hasURL { return .failed }
        return .loading
    }
}

/// 縮めて展開した絵の控え（画面を持たない計算・2026-10-28 判断）。
///
/// URL ごとに**いちばん大きく読めた1枚**を持つ。小さな枠で読んだ絵を、大きな枠の求めに返さない
/// （`entry(for:atLeast:)`）。中身は `NSCache`——展開後の大きさ（縦 × 横 × 4 バイト）で上限を見て、
/// メモリが足りなくなれば OS が捨てる。`URLCache` とは別の控えなので、**ログアウト（`AuthStore.settleSignedOut`）と
/// 設定の「控えを空にする」で一緒に空にする**（`removeAll`）
final class DecodedImageMemory<Image> {

    /// 既定の上限（展開後の大きさ）。格子のマス（約 1024px 四方・4MB）で 20 枚ほど。
    /// **実機のメモリで確かめていない**（見積もりだけ・2026-10-28）
    static var defaultCostLimit: Int { 80 * 1024 * 1024 }

    private final class Entry {
        let image: Image
        let pixels: Int
        init(image: Image, pixels: Int) {
            self.image = image
            self.pixels = pixels
        }
    }

    private let cache = NSCache<NSString, Entry>()

    init(costLimit: Int = DecodedImageMemory.defaultCostLimit) {
        cache.totalCostLimit = costLimit
    }

    /// その URL の控え。`atLeast` を渡せば、その画素数（長い辺）以上で読めたものだけ
    func entry(for url: URL, atLeast pixels: Int = 0) -> (image: Image, pixels: Int)? {
        guard let entry = cache.object(forKey: url.absoluteString as NSString), entry.pixels >= pixels else { return nil }
        return (entry.image, entry.pixels)
    }

    /// 控える。**今の控えより小さければ置き換えない**
    func store(_ image: Image, pixels: Int, for url: URL, cost: Int) {
        let key = url.absoluteString as NSString
        if let current = cache.object(forKey: key), current.pixels >= pixels { return }
        cache.setObject(Entry(image: image, pixels: pixels), forKey: key, cost: max(0, cost))
    }

    func removeAll() { cache.removeAllObjects() }
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


/// 一覧・旅の本の縮小画像に限定した通信中リクエストの共有。
/// URLCacheは完了済み応答のキャッシュであり、通信中の同時要求を統合する保証はない。
/// 完了後は必ず破棄し、永続的な画像データキャッシュを増やさない。
/// セル単位のキャンセルで他セルの通信を止めない（結果の反映は各セル側でキャンセル判定）。
private actor GridImageInFlight {
    static let shared = GridImageInFlight()

    private struct Entry {
        let id: UUID
        let task: Task<Data, Error>
    }
    private var requests: [URL: Entry] = [:]

    func data(for url: URL) async throws -> Data {
        if let running = requests[url] {
            return try await running.task.value
        }
        let id = UUID()
        let task = Task.detached(priority: .userInitiated) {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }
        requests[url] = Entry(id: id, task: task)
        // 失敗時にも必ず除去し、次回の自動リトライを妨げない。
        defer {
            if requests[url]?.id == id { requests[url] = nil }
        }
        return try await task.value
    }
}


/// 通信の共有とは別に、同じ画像の縮小デコード中タスクを共有する。
/// 完了後はタスクを保持しない。完成した画像の保持・破棄は既存の NSCache が担当。
/// セルのキャンセルが別セルの画像展開を止めないよう detached task を使う。
private actor GridImageDecodeInFlight {
    static let shared = GridImageDecodeInFlight()

    // UIImage はデコード後に変更しない。actor 境界を越える値を明示的に包む。
    struct Decoded: @unchecked Sendable {
        let image: UIImage
        let cost: Int
    }

    private struct Key: Hashable {
        let url: URL
        let pixels: Int
    }

    private var tasks: [Key: Task<Decoded?, Never>] = [:]

    func image(data: Data, for url: URL, pixels: Int) async -> Decoded? {
        let key = Key(url: url, pixels: pixels)
        if let existing = tasks[key] { return await existing.value }

        let task = Task.detached(priority: .userInitiated) { () -> Decoded? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = ImagePreparer.downsampledImage(source: source, maxPixelSize: pixels) else {
                return nil
            }
            return Decoded(image: UIImage(cgImage: cgImage), cost: cgImage.width * cgImage.height * 4)
        }
        tasks[key] = task
        let result = await task.value
        tasks[key] = nil
        return result
    }
}
