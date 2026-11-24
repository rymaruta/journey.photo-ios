import SwiftUI
import UIKit

/// 本の表紙の絵の控え（札 #714・2026-11-23 確かめ役の指摘）。
///
/// **開く動きの間に絵を読まない。** 背表紙が画面に出たときに、本の大きさ（長い辺 `pixels`）に縮めた表紙を読んでおき、
/// 押した瞬間に控えに在る絵だけを本に渡す（`Image(uiImage:)` で描くだけ）。まだ無ければ布の色だけ（読み込みの輪は出さない）。
/// 投稿した旅は格子と同じ控え（`DownsampledRemoteImage.memory`）、端末の旅は最近の数冊だけをここに持つ
@MainActor
enum BookCoverCache {
    /// 表紙の長い辺の画素（`TripBookMotion.coverPixels`）
    static var pixels: Int { TripBookMotion.coverPixels }
    /// 端末の旅の表紙を持つ冊数（古いものから捨てる）
    static let deviceLimit = 24

    private static var device: [String: UIImage] = [:]
    private static var deviceOrder: [String] = []

    /// 控えに在る表紙（取りに行かない）
    static func image(for book: TripBookshelf.Book) -> UIImage? {
        switch book.source {
        case .posted(let trip):
            return image(posted: trip)
        case .device(let trip):
            return trip.cover.flatMap { device[$0.id] }
        }
    }

    /// 投稿した旅の表紙（一冊の頁が広がっている間に描く・`TripBookCoverPhoto`）
    static func image(posted trip: TripBook.Trip) -> UIImage? {
        trip.cover?.gridImageURL.flatMap { DownsampledRemoteImage.cached($0, pixels: pixels) }
    }

    /// 表紙を読んでおく（背表紙が画面に出たとき）
    static func prefetch(_ book: TripBookshelf.Book) async {
        guard image(for: book) == nil else { return }
        switch book.source {
        case .posted(let trip):
            guard let url = trip.cover?.gridImageURL else { return }
            _ = await DownsampledRemoteImage.preload(url, pixels: pixels)
        case .device(let trip):
            guard let id = trip.cover?.id,
                  let image = await LibraryThumbnails.shared.image(for: id, pixels: CGFloat(pixels)) else { return }
            device[id] = image
            deviceOrder.removeAll { $0 == id }
            deviceOrder.append(id)
            while deviceOrder.count > deviceLimit { device[deviceOrder.removeFirst()] = nil }
        }
    }
}

/// 棚の上で開いている一冊（引き出す → 手前に回す → 表紙がめくれる）
struct BookStageState: Equatable {
    let book: TripBookshelf.Book
    /// 押した瞬間に控えに在った表紙（無ければ布の色）
    let image: UIImage?
    /// 背表紙の枠（棚の座標）と、引き出した本の真ん中（棚の座標）
    let from: CGRect
    let center: CGPoint
    var pulled = false
    var coverOpen = false

    static func == (a: BookStageState, b: BookStageState) -> Bool {
        a.book.id == b.book.id && a.pulled == b.pulled && a.coverOpen == b.coverOpen && a.from == b.from && a.center == b.center
    }
}

/// 引き出している一冊の印（2026-11-24 判断・owner「本を開く・閉じる動きが重い」）。
///
/// **背表紙が見張るのはこれだけ。** 前は背表紙の枠がみな `BookStageModel` を見張り、開く（出す・引き出す・めくる）・
/// 閉じる（めくり戻す・棚へ・消す）のたびに棚のすべての背表紙の `body` を作り直していた（1回の開閉で6〜7回 × 冊数）。
/// これは一冊を出すときと棚に戻し終えたときの2回だけ変わる
@MainActor
final class BookSpineHider: ObservableObject {
    @Published private(set) var hiddenId: String?

    func hide(_ id: String?) {
        if hiddenId != id { hiddenId = id }
    }
}

/// 本を開く・閉じる段取り（案の頁の「本を開く（実機）」・2026-11-23 owner 決定）。
///
/// **棚は見張らない**（棚の `@State` に置くと、動くたびに棚ぜんぶの `body` を作り直す）。見張るのは本の層（`BookStageLayer`）と
/// 背表紙の枠（`BookSpineSlot`・引き出した一冊の背を隠す）だけ
@MainActor
final class BookStageModel: ObservableObject {

    @Published private(set) var stage: BookStageState?
    /// 背表紙が見張る印（`BookSpineHider`）。`stage` の動きでは背表紙を作り直さない
    let hider = BookSpineHider()

    /// 背表紙の枠（棚の座標）。動くたびに知らせない（測るだけ）
    var spineFrames: [String: CGRect] = [:]
    /// 棚の、縦の送りの見えている所の中の位置と、見えている高さ（引き出す先を決める）
    var shelfInScroll: CGRect = .zero
    var visibleHeight: CGFloat = 0
    var shelfWidth: CGFloat = 390

    private var task: Task<Void, Never>?

    /// 動いている間（開く・閉じる）。この間は背表紙を押しても何もしない
    var isBusy: Bool { task != nil }

    /// 引き出した本の真ん中（棚の座標）。見えている所の中央より少し上（`TripBookMotion.stageCenterRatio`）
    func stageCenter() -> CGPoint {
        let visible = visibleHeight > 0 ? Double(visibleHeight) : 760
        let y = TripBookMotion.stageCenterY(visibleHeight: visible, shelfTopInScroll: Double(shelfInScroll.minY))
        return CGPoint(x: shelfWidth / 2, y: CGFloat(y))
    }

    /// 背表紙を押した。引き出して手前に回し、表紙をめくり、`push` で一冊の頁へ移る
    func open(_ book: TripBookshelf.Book, push: @escaping () -> Void) {
        guard task == nil, stage == nil else { return }
        let from = spineFrames[book.id] ?? CGRect(x: shelfWidth / 2 - 15, y: 0, width: 30, height: 130)
        stage = BookStageState(book: book, image: BookCoverCache.image(for: book), from: from, center: stageCenter())
        hider.hide(book.id)
        task = Task { [weak self] in
            // 背表紙の位置で1度描いてから動かす
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self else { return }
            withAnimation(.spring(response: TripBookMotion.pullResponse, dampingFraction: TripBookMotion.pullDamping)) {
                self.stage?.pulled = true
            }
            try? await Task.sleep(nanoseconds: Self.ns(TripBookMotion.coverFlipDelay))
            withAnimation(.timingCurve(0.42, 0, 0.58, 1, duration: TripBookMotion.coverFlipDuration)) {
                self.stage?.coverOpen = true
            }
            try? await Task.sleep(nanoseconds: Self.ns(TripBookMotion.pageGrowAt - TripBookMotion.coverFlipDelay))
            push()
            // 頁が広がり切るまでは押しを受けない（`TripBookOpening` も頁の側で止める）
            try? await Task.sleep(nanoseconds: Self.ns(TripBookMotion.openTotal - TripBookMotion.pageGrowAt))
            self.task = nil
        }
    }

    /// 一冊の頁が閉じた（「戻る」・下へ引いた）。表紙を戻し、棚へ帰す。帰り着いたら `arrived`
    func close(arrived: @escaping () -> Void) {
        task?.cancel()
        guard stage != nil else { task = nil; hider.hide(nil); arrived(); return }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.ns(TripBookMotion.coverCloseDelay))
            guard let self else { return }
            withAnimation(.timingCurve(0.42, 0, 0.58, 1, duration: TripBookMotion.coverCloseDuration)) {
                self.stage?.coverOpen = false
            }
            try? await Task.sleep(nanoseconds: Self.ns(TripBookMotion.shelveAt - TripBookMotion.coverCloseDelay))
            withAnimation(.timingCurve(0.42, 0, 0.58, 1, duration: TripBookMotion.shelveDuration)) {
                self.stage?.pulled = false
            }
            try? await Task.sleep(nanoseconds: Self.ns(TripBookMotion.shelveDuration))
            self.stage = nil
            self.hider.hide(nil)
            self.task = nil
            arrived()
        }
    }

    /// 棚を離れた（タブを替えた等）。本を出したままにしない
    func reset() {
        task?.cancel()
        task = nil
        stage = nil
        hider.hide(nil)
    }

    private static func ns(_ seconds: Double) -> UInt64 { UInt64(max(0, seconds) * 1_000_000_000) }
}

/// 棚の上の本の層。開いている一冊だけを描く。動いている間は棚への押しを止める（下の背表紙に届かない）
struct BookStageLayer: View {
    @ObservedObject var model: BookStageModel
    let namespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let stage = model.stage {
                // 動いている間は棚を押せない
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}
                OpeningBook(book: stage.book, image: stage.image, coverOpen: stage.coverOpen)
                    .frame(width: BookCoverFace.size.width, height: BookCoverFace.size.height)
                    // 一冊の頁はここから広がり、閉じるとここへ縮む（iOS 18・`TripBookOpening`）
                    .bookZoomSource(id: stage.book.id, in: namespace)
                    .modifier(BookStagePose(stage: stage))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// 引き出す動き。**動かすのは位置・大きさ・向き・透明度だけ**（本は 196×266 の1枚の絵のまま）。
/// 背表紙の位置では、背の高さに縮めて横を向いている（手前に回すと表紙が見える）
struct BookStagePose: ViewModifier {
    let stage: BookStageState

    func body(content: Content) -> some View {
        let size = BookCoverFace.size
        let pulled = stage.pulled
        let center = pulled ? stage.center : CGPoint(x: stage.from.midX, y: stage.from.midY)
        let scale = pulled ? 1 : max(0.1, stage.from.height / size.height)
        content
            // 影は先に描いた層の透明度で出す（ぼかしを動かさない）
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black)
                    .offset(x: 6, y: 12)
                    .opacity(pulled ? 0.45 : 0)
            }
            .rotation3DEffect(.degrees(pulled ? 0 : TripBookMotion.shelvedTurn), axis: (x: 0, y: 1, z: 0),
                              anchor: .center, perspective: TripBookMotion.perspective)
            .scaleEffect(scale)
            .offset(x: center.x - size.width / 2, y: center.y - size.height / 2)
    }
}

/// 開いていく本（中の頁の上に表紙。表紙は左の辺を軸にめくれる）。どちらも1枚の絵にまとめる（`drawingGroup`）
struct OpeningBook: View {
    let book: TripBookshelf.Book
    let image: UIImage?
    let coverOpen: Bool

    var body: some View {
        ZStack {
            BookInnerPage(book: book, image: image)
                .drawingGroup()
            FlippingCover(angle: coverOpen ? TripBookMotion.coverFlipAngle : 0, book: book, image: image)
        }
    }
}

/// めくれる表紙。90° を越えたら表紙の裏（見返し）を見せる（裏返った写真を見せない）。
///
/// **毎フレーム作り直すのは表と裏の透明度（`CoverSide`）だけ**（2026-11-24 判断・owner「本を開く・閉じる動きが重い」）。
/// 前はこの部品そのものが角度で動いていて（`Animatable`）、めくる 0.26 秒・戻す 0.20 秒の毎フレームに表紙（明朝の題・
/// グラデーション・布）を組み直し、`drawingGroup` の1枚の絵を描き直していた。回すのは `rotation3DEffect` に任せる
/// （描いた絵を回すだけ）。見た目・角度・時間は前と同じ
struct FlippingCover: View {
    let angle: Double
    let book: TripBookshelf.Book
    let image: UIImage?

    var body: some View {
        ZStack {
            BookCoverFace(book: book, image: image)
                .drawingGroup()
                .modifier(CoverSide(angle: angle, isBack: false))
            // 見返し（布の色の紙）。裏から見るので左右を返す
            BookCloth(color: book.cloth)
                .overlay(Color.black.opacity(0.25))
                .scaleEffect(x: -1, y: 1)
                .modifier(CoverSide(angle: angle, isBack: true))
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2,
                                          bottomTrailingRadius: 6, topTrailingRadius: 6))
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0),
                          anchor: .leading, perspective: TripBookMotion.perspective)
    }
}

/// めくれている表紙の表と裏の見え方。角度に合わせて動くのはここだけ（中身の絵は作り直さない）
struct CoverSide: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(TripBookMotion.showsCoverBack(angle: angle) == isBack ? 1 : 0)
    }
}

/// 表紙の下の最初の頁（一冊の頁の頭と同じ: 上に表紙の写真、下に題）。紙の小口は1枚のグラデーション
struct BookInnerPage: View {
    let book: TripBookshelf.Book
    let image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    BookCloth(color: book.cloth)
                }
            }
            .frame(width: BookCoverFace.size.width, height: BookCoverFace.size.height * 0.58)
            .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(JPFont.display(18, relativeTo: .headline))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(2)
                Text(L("\(book.year)年\(book.month)月", "\(book.month)/\(book.year)"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
            .padding(12)
            Spacer(minLength: 0)
        }
        .frame(width: BookCoverFace.size.width, height: BookCoverFace.size.height, alignment: .topLeading)
        .background(WebTheme.background)
        .overlay(alignment: .trailing) {
            LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.18)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 4)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2,
                                          bottomTrailingRadius: 6, topTrailingRadius: 6))
    }
}

/// 一冊の頁の表紙の写真（2026-11-24 判断・owner「本を開く・閉じる動きが重い」）。
///
/// **頁が広がっている間は、棚で読んでおいた表紙（`BookCoverCache`・512px・展開済み）を描くだけ。** 前は頁が出た瞬間に
/// 画面いっぱいの大きな写真（`detailImageURL`）を読み始め、広がる 0.23 秒の途中で展開して描いていた。
/// 大きな写真は開き切ってから読み、出たら上に重ねる（読めなければ控えの表紙のまま）。控えに無ければ今までどおりすぐ読む
struct TripBookCoverPhoto: View {
    let cover: Photo
    let quick: UIImage?

    @State private var loadsDetail = false
    @State private var detailShown = false

    var body: some View {
        if let quick {
            ZStack {
                Image(uiImage: quick)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cover.gridAlignment)
                if loadsDetail {
                    RemoteImage(url: cover.detailImageURL, alignment: cover.gridAlignment, onSettled: { ok in
                        withAnimation(.easeOut(duration: 0.15)) { detailShown = ok }
                    })
                    .opacity(detailShown ? 1 : 0)
                }
            }
            .task {
                guard !loadsDetail else { return }
                try? await Task.sleep(nanoseconds: UInt64(TripBookMotion.openTotal * 1_000_000_000))
                loadsDetail = true
            }
        } else {
            RemoteImage(url: cover.detailImageURL, alignment: cover.gridAlignment)
        }
    }
}

/// 一冊の頁の側の開く動き（札 #714）。
///
/// - 棚の本から画面いっぱいへ広げるのは iOS 18 の拡大の移り変わり（`navigationTransition(.zoom)`）。下へ引いて閉じるのもこれ
/// - 開き切って1回だけ 1.2% はずみ、触覚（.soft）
/// - **広がっている間は押しを受けない**（下の頁の写真・ボタンに届かない）。開き切ったら受ける
/// - 動きを減らす設定ではすぐ開く（拡大もはずみも無し）
/// - 一度開いたら、詳しい頁から戻ったときにもう一度はずまない
struct TripBookOpening: ViewModifier {
    let book: TripBookshelf.Book
    let namespace: Namespace.ID
    let animated: Bool

    @State private var started = false
    @State private var settling = true
    @State private var bounce = false
    @State private var bounced = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(bounce ? TripBookMotion.bounceScale : 1)
            .overlay {
                if animated && settling {
                    // 広がっている間の押しをここで止める
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .accessibilityHidden(true)
                        .ignoresSafeArea()
                }
            }
            .bookZoomTransition(id: book.id, in: namespace, enabled: animated)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: bounced)
            .task {
                guard animated, !started else { settling = false; return }
                started = true
                let wait = TripBookMotion.bounceAt - TripBookMotion.pageGrowAt
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                bounced += 1
                withAnimation(.easeOut(duration: 0.06)) { bounce = true }
                try? await Task.sleep(nanoseconds: 60_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { bounce = false }
                settling = false
            }
    }
}

extension View {
    /// 本を拡大の移り変わりの元にする（iOS 18 から。17 は今までどおり横から積む）
    @ViewBuilder
    func bookZoomSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// 開いた一冊を棚の本から広げる（iOS 18 から・動きを減らす設定では使わない）
    @ViewBuilder
    func bookZoomTransition(id: String, in namespace: Namespace.ID, enabled: Bool) -> some View {
        if #available(iOS 18.0, *), enabled {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
