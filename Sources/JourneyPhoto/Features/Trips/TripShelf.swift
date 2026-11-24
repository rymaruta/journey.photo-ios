import SwiftUI
import UIKit

/// 旅の記録の棚（札 #714・2026-11-23 owner 決定）。マイページの「旅の記録」のタブと、人のページの「すべての旅」の中身。
///
/// **年ごとの段に背表紙を並べる本棚**（数と決まりは `TripBookshelf`）。投稿した旅と端末の旅を同じ棚に並べ、
/// 端末の旅は背に iPhone の印、自分だけの旅は鍵の印を付ける。背表紙を押すと本を開く動きで一冊が開く（`TripBookOpening`）。
///
/// **説明の文は旅が無いときの1行だけ**（2026-11-23 owner 判断: 前の「旅があっても出す」の決まりを改めた。
/// 画面を説明文で埋めず、形と言葉の短さで分からせる）
struct TripShelfList: View {

    let trips: [TripBook.Trip]
    /// 写真に個別ページが在るか（`TripBookView.isPublic`）
    var isPublic: (Photo) -> Bool = { _ in false }
    /// 自分の棚か。人の棚（人のプロフィールの「すべての旅」）は偽——開いた一冊で「この一冊を送る」を出さず、
    /// 空のときの次の一手も出さない（2026-10-16 判断）。
    /// **既定の値を置かない**（2026-11-23 判断・`TripBookView.isMine` と同じ理由。呼び手が自分の棚か人の棚かを必ず言う）
    var isMine: Bool
    /// 端末の旅（マイページだけ・`DeviceTrips.books(isMine:)`）と、その地名
    var deviceBooks: [LibraryTrip] = []
    var deviceNames: [String: String] = [:]

    /// 0冊のときの次の一手の題（下の「投稿」の行と同じ語・2026-10-16）
    nonisolated static var startTripTitle: String { L("旅の写真からまとめて", "From a trip in your photos") }

    nonisolated static var explanation: String { explanation(isMine: true) }

    /// 旅が無いときの1行（2026-11-23 owner「日本語として自然なのにして」・札 #714 のコメント）。
    /// アプリは近い日に撮った写真を1つの旅にまとめるので「同じ場所」ではなく「同じ旅」。人の棚は本人の操作を言わない
    nonisolated static func explanation(isMine: Bool) -> String {
        guard isMine else {
            return L("同じ旅で撮った写真が2枚載ると、旅の記録が一冊できます",
                     "Two photos from the same trip make one travel book")
        }
        return L("同じ旅で撮った写真を2枚載せると、旅の記録が一冊できます",
                 "Post two photos from the same trip to make a travel book")
    }

    private var books: [TripBookshelf.Book] {
        trips.map(TripBookshelf.book)
            + deviceBooks.filter(TripBookshelf.showsOnShelf).map { TripBookshelf.book($0, name: deviceNames[$0.id]) }
    }

    var body: some View {
        let books = self.books
        if books.isEmpty {
            // 空の状態（v2 Components 06: 明朝 20 の見出し → 1行 → 次の一手）。マイページは印なし（2026-11-12）。
            // 次の一手は自分の棚だけ（下の「投稿」と同じ道 `TabRouter.openPost`）
            EmptyState(icon: nil, title: L("まだ旅はありません", "No trips yet"), message: Self.explanation(isMine: isMine),
                       actionTitle: isMine ? Self.startTripTitle : nil,
                       actionIdentifier: "trips.emptyStart",
                       action: isMine ? { TabRouter.shared.openPost(.trip) } : nil)
                .padding(.horizontal, JPSpace.gutter)
        } else {
            TripBookshelfView(books: books) { book in
                switch book.source {
                case .posted(let trip):
                    TripBookView(trip: trip, isPublic: isPublic, isMine: isMine)
                case .device(let trip):
                    DeviceTripBookView(trip: trip, name: book.name)
                }
            }
        }
    }
}

/// 年ごとの段の本棚。押した一冊は本を開く動き（`BookStageModel`）のあと `open` の画面で開く
struct TripBookshelfView<Opened: View>: View {

    let books: [TripBookshelf.Book]
    @ViewBuilder let open: (TripBookshelf.Book) -> Opened

    @Namespace private var bookSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 棚の幅（折り返しの計算）。測るまでは 390pt の iPhone の幅で見積もる
    @State private var width: CGFloat = 390
    /// 開いている一冊（一冊の頁）
    @State private var presented: TripBookshelf.Book?
    /// 引き出す・めくる段取り。**棚はこれを見張らない**（動くたびに棚を作り直さない）
    @StateObject private var stage = BookStageModel()
    @State private var returned = 0

    private static var space: String { "trips.bookshelf" }

    var body: some View {
        let shelves = TripBookshelf.shelves(books)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shelves) { shelf in
                yearHeader(shelf)
                // 押せる幅は背の幅＋間（間の半分ずつを両側に・`spineSlot`）。段の幅もその分で数える
                let inner = max(0, Double(width) - Double(JPSpace.gutter) * 2)
                let rows = TripBookshelf.rows(widths: shelf.books.map { TripBookshelf.spineWidth(photos: $0.photoCount)
                                                                        + TripBookshelf.spineGap },
                                              available: inner + TripBookshelf.spineGap, gap: 0)
                VStack(alignment: .leading, spacing: TripBookshelf.rowGap) {
                    ForEach(rows, id: \.first) { row in
                        shelfRow(row.map { shelf.books[$0] })
                    }
                }
                .padding(.bottom, JPSpace.s)
            }
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            if $0 > 0 { width = $0; stage.shelfWidth = $0 }
        }
        // 引き出す先を決める: 縦の送りの見えている所の中の棚の位置と、見えている高さ
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { stage.shelfInScroll = $0 }
        .background {
            Color.clear
                .containerRelativeFrame(.vertical) { length, _ in length }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stage.visibleHeight = $0 }
                .accessibilityHidden(true)
        }
        // 開いている一冊（本の層）。棚の上に重ね、動いている間は棚への押しを止める
        .overlay(alignment: .topLeading) {
            BookStageLayer(model: stage, namespace: bookSpace)
        }
        .navigationDestination(item: $presented) { book in
            open(book)
                .modifier(TripBookOpening(book: book, namespace: bookSpace, animated: !reduceMotion))
        }
        // 一冊の頁が閉じた（「戻る」・下へ引いた）: 表紙を戻して棚へ帰す。帰り着いた瞬間に触覚（.light）
        .onChange(of: presented) { old, new in
            guard old != nil, new == nil else { return }
            stage.close { returned += 1 }
        }
        .onDisappear { if presented == nil { stage.reset() } }
        .sensoryFeedback(.impact(weight: .light), trigger: returned)
    }

    /// 背表紙を押した（長押しの「開く」も同じ）。動きを減らす設定ではすぐ開く
    private func openBook(_ book: TripBookshelf.Book) {
        guard presented == nil, !stage.isBusy, stage.stage == nil else { return }
        if reduceMotion {
            presented = book
        } else {
            stage.open(book) { presented = book }
        }
    }

    private func yearHeader(_ shelf: TripBookshelf.Shelf) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
            Text(verbatim: "\(shelf.year)")
                .font(JPFont.number(13, weight: .semibold))
                .foregroundStyle(WebTheme.text2)
            Text(L("\(shelf.books.count)冊", shelf.books.count == 1 ? "1 trip" : "\(shelf.books.count) trips"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
        }
        .padding(.horizontal, JPSpace.gutter)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// 1段。背表紙は下でそろえ、下に棚板（濃い灰の帯と影だけ）
    private func shelfRow(_ row: [TripBookshelf.Book]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(row) { book in
                    spine(book)
                }
            }
            .frame(maxWidth: .infinity, minHeight: TripBookshelf.rowHeight, alignment: .bottomLeading)
            // 背の当たりが間の半分ずつ外へ出る分、段の左を詰める（背の見た目の位置は前と同じ）
            .padding(.horizontal, JPSpace.gutter - CGFloat(TripBookshelf.spineGap / 2))
            VStack(spacing: 0) {
                Rectangle().fill(Self.plank).frame(height: 4)
                Rectangle().fill(Color.black.opacity(0.9)).frame(height: 2)
            }
            .accessibilityHidden(true)
        }
    }

    private func spine(_ book: TripBookshelf.Book) -> some View {
        Button {
            openBook(book)
        } label: {
            BookSpineSlot(book: book, model: stage)
        }
        .buttonStyle(SpineButtonStyle(reduceMotion: reduceMotion))
        // 本を引き出す元の枠（棚の座標・知らせない）と、表紙を先に読んでおく
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(Self.space)).insetBy(dx: CGFloat(TripBookshelf.spineGap / 2), dy: 0)
        } action: { stage.spineFrames[book.id] = $0 }
        .task(id: book.id) { await BookCoverCache.prefetch(book) }
        // 長押しは本の形で表紙だけ見る（中は開かない）。「開く」で開く
        .contextMenu {
            Button {
                openBook(book)
            } label: {
                Label(L("開く", "Open"), systemImage: "book")
            }
        } preview: {
            BookCoverFace(book: book, image: BookCoverCache.image(for: book))
                .frame(width: BookCoverFace.size.width, height: BookCoverFace.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TripBookshelf.spokenLabel(book))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openBook(book) }
        .accessibilityIdentifier(book.isDevice ? "trips.deviceBook" : "trips.book")
    }

    /// 棚板の色（濃い灰）
    private static var plank: Color { Color(red: 0x2B / 255, green: 0x29 / 255, blue: 0x27 / 255) }
}

/// 背表紙の枠。**押せる所は背の幅＋間**（間の半分ずつを両側に・隣の背との真ん中で区切る）。
/// 引き出している一冊の背は隠す（棚に隙間が空く）。見張るのはここだけ（棚ぜんぶを作り直さない）
struct BookSpineSlot: View {
    let book: TripBookshelf.Book
    @ObservedObject var model: BookStageModel

    var body: some View {
        BookSpine(book: book)
            .opacity(model.stage?.book.id == book.id ? 0 : 1)
            .padding(.horizontal, CGFloat(TripBookshelf.spineGap / 2))
            .contentShape(Rectangle())
    }
}

/// 背表紙（案の頁「背表紙」）。上 30pt に表紙の写真、地は写真の色を暗くした布、縦書きの明朝で旅でいちばん多い県（取れなければ旅の名前・`Book.spineText`）、下に月
struct BookSpine: View {

    let book: TripBookshelf.Book

    var body: some View {
        let width = TripBookshelf.spineWidth(photos: book.photoCount)
        let height = TripBookshelf.spineHeight(days: book.days)
        let marks = (book.isDevice ? 1 : 0) + (book.isPrivate ? 1 : 0)
        VStack(spacing: 0) {
            BookCoverImage(book: book, side: CGFloat(TripBookshelf.spineMaxWidth))
                .frame(width: width, height: TripBookshelf.windowHeight)
                .clipped()
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.black.opacity(0.55)).frame(height: 1)
                }
            if book.isDevice { mark("iphone") }
            if book.isPrivate { mark("lock.fill") }
            // 1字ずつ同じ高さの箱に入れる（字の行の高さで並びが割れない・`TripBookshelf.titleBox`）
            VStack(spacing: 0) {
                ForEach(Array(TripBookshelf.spineTitle(book.spineText,
                                                       maxCharacters: TripBookshelf.spineTitleCapacity(height: height, marks: marks))
                    .enumerated()), id: \.offset) { _, char in
                    let glyph = TripBookshelf.spineGlyph(char)
                    Text(verbatim: glyph.text)
                        .font(.custom(JPFont.displayName, fixedSize: TripBookshelf.titleSize))
                        .foregroundStyle(Color.white)
                        .rotationEffect(.degrees(glyph.rotated ? 90 : 0))
                        .frame(width: width, height: TripBookshelf.titleBox)
                }
            }
            .padding(.top, TripBookshelf.titleTop)
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(verbatim: "\(book.month)")
                    .font(.system(size: TripBookshelf.monthSize, weight: .semibold).monospacedDigit())
                Text(L("月", ""))
                    .font(.system(size: TripBookshelf.monthSize))
            }
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.bottom, 6)
        }
        .frame(width: width, height: height)
        .background { BookCloth(color: book.cloth) }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 1,
                                          bottomTrailingRadius: 1, topTrailingRadius: 2))
    }

    private func mark(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(height: 12)
            .padding(.top, 5)
            .accessibilityHidden(true)
    }
}

/// 布の地（写真の色を暗くした色に、丸みの影を1枚のグラデーションで重ねる）
struct BookCloth: View {
    let color: UInt32

    var body: some View {
        ZStack {
            Color(red: Double((color >> 16) & 0xFF) / 255, green: Double((color >> 8) & 0xFF) / 255,
                  blue: Double(color & 0xFF) / 255)
            LinearGradient(stops: [.init(color: Color.black.opacity(0.38), location: 0),
                                   .init(color: Color.white.opacity(0.07), location: 0.45),
                                   .init(color: Color.black.opacity(0.28), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// 背の窓の小さな表紙。**縮めた画像だけを読む**（投稿した旅は 256px の `pinImageURL`、端末の旅は辺の 3 倍の画素）
struct BookCoverImage: View {
    let book: TripBookshelf.Book
    let side: CGFloat

    var body: some View {
        switch book.source {
        case .posted(let trip):
            if let cover = trip.cover {
                RemoteImage(url: cover.pinImageURL, alignment: cover.gridAlignment)
            } else {
                BookCloth(color: book.cloth)
            }
        case .device(let trip):
            if let cover = trip.cover {
                LibraryThumbView(id: cover.id, side: side)
            } else {
                BookCloth(color: book.cloth)
            }
        }
    }
}

/// 本の表紙（約 196×266pt）。長押しで見る形と、開くときにめくれる表紙。
/// **絵は読み終えたものを受け取って描くだけ**（`BookCoverCache`）。無ければ布の色だけ（読み込みの輪は出さない）
struct BookCoverFace: View {
    nonisolated static let size = CGSize(width: 196, height: 266)

    let book: TripBookshelf.Book
    let image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .clipped()
            } else {
                BookCloth(color: book.cloth)
            }
            LinearGradient(stops: [.init(color: Color.black.opacity(TripStyle.coverCardShade), location: 0),
                                   .init(color: Color.black.opacity(0), location: 0.6)],
                           startPoint: .bottom, endPoint: .top)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(JPFont.display(22, relativeTo: .title2))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(2)
                Text(L("\(book.year)年\(book.month)月", "\(book.month)/\(book.year)"))
                    .font(JPFont.mono(13, relativeTo: .footnote))
                    .foregroundStyle(WebTheme.muted)
            }
            .padding(JPSpace.m)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // 背の側（左）に布の帯。本の形に見せる
        .overlay(alignment: .leading) {
            BookCloth(color: book.cloth).frame(width: 10)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2,
                                          bottomTrailingRadius: 6, topTrailingRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TripBookshelf.spokenLabel(book))
    }
}

/// 背表紙を押したとき: 指が触れた瞬間に明るくなり、少しだけ持ち上がる。押した瞬間に軽い触覚（.light）。
/// 動きを減らす設定では明るくなるだけ
private struct SpineButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.12 : 0)
            .offset(y: configuration.isPressed && !reduceMotion ? -4 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// 「投稿日でまとめています」の線の札（板 Trips・TripBook: 撮影日の無い写真だけの旅）。
/// 黒地の上は text-2 の字に白 14% の線、写真の上は白の字に黒 45% の地・白 30% の線
struct UploadDateChip: View {
    var onPhoto = false

    var body: some View {
        Text(L("投稿日でまとめています", "Grouped by upload date"))
            .font(JPFont.caption)
            .foregroundStyle(onPhoto ? WebTheme.foreground : WebTheme.text2)
            .padding(.horizontal, JPSpace.xs)
            .padding(.vertical, 1)
            .background(onPhoto ? Color.black.opacity(0.45) : Color.clear, in: RoundedRectangle(cornerRadius: JPRadius.s))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.s)
                .strokeBorder(onPhoto ? Color.white.opacity(0.3) : WebTheme.line, lineWidth: JPStroke.hairline))
    }
}
