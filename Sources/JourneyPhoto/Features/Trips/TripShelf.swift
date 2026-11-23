import SwiftUI

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
    /// 空のときの次の一手も出さない（2026-10-16 判断）
    var isMine = true
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
        trips.map(TripBookshelf.book) + deviceBooks.map { TripBookshelf.book($0, name: deviceNames[$0.id]) }
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

/// 年ごとの段の本棚。押した一冊は `open` の画面で開く
struct TripBookshelfView<Opened: View>: View {

    let books: [TripBookshelf.Book]
    @ViewBuilder let open: (TripBookshelf.Book) -> Opened

    @Namespace private var bookSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 棚の幅（折り返しの計算）。測るまでは 390pt の iPhone の幅で見積もる
    @State private var width: CGFloat = 390
    /// 長押しの「開く」から開く一冊
    @State private var peekOpened: TripBookshelf.Book?
    /// 一冊を開いて棚を離れたか（戻ったときに触覚を1回）
    @State private var leftForBook = false
    @State private var returned = 0

    var body: some View {
        let shelves = TripBookshelf.shelves(books)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shelves) { shelf in
                yearHeader(shelf)
                let inner = max(0, Double(width) - Double(JPSpace.gutter) * 2)
                let rows = TripBookshelf.rows(widths: shelf.books.map { TripBookshelf.spineWidth(photos: $0.photoCount) },
                                              available: inner)
                VStack(alignment: .leading, spacing: TripBookshelf.rowGap) {
                    ForEach(rows, id: \.first) { row in
                        shelfRow(row.map { shelf.books[$0] })
                    }
                }
                .padding(.bottom, JPSpace.s)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 > 0 { width = $0 } }
        .navigationDestination(item: $peekOpened) { book in
            opened(book)
        }
        .onDisappear { if peekOpened != nil { leftForBook = true } }
        .onAppear {
            guard leftForBook else { return }
            leftForBook = false
            returned += 1
        }
        // 棚へ戻った瞬間（.light）。開くときの触覚は背を押した瞬間（`SpineButtonStyle`）
        .sensoryFeedback(.impact(weight: .light), trigger: returned)
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
            HStack(alignment: .bottom, spacing: TripBookshelf.spineGap) {
                ForEach(row) { book in
                    spine(book)
                }
            }
            .frame(maxWidth: .infinity, minHeight: TripBookshelf.rowHeight, alignment: .bottomLeading)
            .padding(.horizontal, JPSpace.gutter)
            VStack(spacing: 0) {
                Rectangle().fill(Self.plank).frame(height: 4)
                Rectangle().fill(Color.black.opacity(0.9)).frame(height: 2)
            }
            .accessibilityHidden(true)
        }
    }

    private func spine(_ book: TripBookshelf.Book) -> some View {
        NavigationLink {
            opened(book)
        } label: {
            BookSpine(book: book)
        }
        .buttonStyle(SpineButtonStyle(reduceMotion: reduceMotion))
        .simultaneousGesture(TapGesture().onEnded { leftForBook = true })
        .bookZoomSource(id: book.id, in: bookSpace)
        // 長押しは本の形で表紙だけ見る（中は開かない）。「開く」で開く
        .contextMenu {
            Button {
                peekOpened = book
            } label: {
                Label(L("開く", "Open"), systemImage: "book")
            }
        } preview: {
            BookCoverFace(book: book)
                .frame(width: BookCoverFace.size.width, height: BookCoverFace.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TripBookshelf.spokenLabel(book))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(book.isDevice ? "trips.deviceBook" : "trips.book")
    }

    private func opened(_ book: TripBookshelf.Book) -> some View {
        open(book)
            .modifier(TripBookOpening(book: book, namespace: bookSpace, animated: !reduceMotion))
    }

    /// 棚板の色（濃い灰）
    private static var plank: Color { Color(red: 0x2B / 255, green: 0x29 / 255, blue: 0x27 / 255) }
}

/// 背表紙（案の頁「背表紙」）。上 30pt に表紙の写真、地は写真の色を暗くした布、縦書きの明朝で旅の名前、下に月
struct BookSpine: View {

    let book: TripBookshelf.Book

    var body: some View {
        let width = TripBookshelf.spineWidth(photos: book.photoCount)
        let height = TripBookshelf.spineHeight(days: book.days)
        let marks = (book.isDevice ? 1 : 0) + (book.isPrivate ? 1 : 0)
        VStack(spacing: 0) {
            BookCoverImage(book: book, side: 36)
                .frame(width: width, height: TripBookshelf.windowHeight)
                .clipped()
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.black.opacity(0.55)).frame(height: 1)
                }
            if book.isDevice { mark("iphone") }
            if book.isPrivate { mark("lock.fill") }
            VStack(spacing: 1) {
                ForEach(Array(TripBookshelf.spineTitle(book.title,
                                                       maxCharacters: TripBookshelf.spineTitleCapacity(height: height, marks: marks))
                    .enumerated()), id: \.offset) { _, char in
                    Text(verbatim: char)
                        .font(.custom(JPFont.displayName, fixedSize: TripBookshelf.titleSize))
                        .foregroundStyle(Color.white)
                        .frame(width: width)
                }
            }
            .padding(.top, 6)
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
        // 押せる幅は 44pt（細い背は当たりを左右に広げる）
        .padding(.horizontal, max(0, (TripBookshelf.tapWidth - width) / 2))
        .contentShape(Rectangle())
        .padding(.horizontal, -max(0, (TripBookshelf.tapWidth - width) / 2))
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
private struct BookCloth: View {
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

/// 表紙の写真。**縮めた画像だけを読む**（投稿した旅は 256px の `pinImageURL`、端末の旅は辺の 3 倍の画素）
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

/// 本の表紙（約 196×266pt）。長押しで見る形と、開くときにめくれる表紙
struct BookCoverFace: View {
    nonisolated static let size = CGSize(width: 196, height: 266)

    let book: TripBookshelf.Book

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BookCoverImage(book: book, side: Self.size.width)
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

/// 本を開く動き（案の頁の「本を開く（実機）」・2026-11-23 owner 決定）。
///
/// - 背表紙から画面いっぱいへ広げるのは iOS 18 の拡大の移り変わり（`navigationTransition(.zoom)`）。下へ引いて閉じるのもこれ
/// - その上で表紙が左の辺を軸に -165° めくれる（0.12 秒から 0.26 秒）。0.54 秒で1回だけ 1.2% はずみ、触覚（.soft）
/// - **動かすのは位置・向き・透明度だけ。** 表紙は縮めた画像を1枚の絵にまとめて回し（`drawingGroup`）、
///   動いている間は写真を描き直さない。めくれ終えたら表紙を外す
/// - 動きを減らす設定ではすぐ開く（表紙も拡大も無し）。表紙は押せない（動いている間に押しても下の頁に届かない）
/// - 一度開いたら、詳しい頁から戻ったときにもう一度めくらない
struct TripBookOpening: ViewModifier {
    let book: TripBookshelf.Book
    let namespace: Namespace.ID
    let animated: Bool

    @State private var started = false
    @State private var flipped = false
    @State private var coverShown = true
    @State private var bounce = false
    @State private var bounced = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(bounce ? TripBookMotion.bounceScale : 1)
            .overlay {
                if animated && coverShown {
                    BookCoverFace(book: book)
                        .drawingGroup()
                        .rotation3DEffect(.degrees(flipped ? TripBookMotion.coverFlipAngle : 0), axis: (x: 0, y: 1, z: 0),
                                          anchor: .leading, perspective: TripBookMotion.perspective)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .ignoresSafeArea()
                }
            }
            .bookZoomTransition(id: book.id, in: namespace, enabled: animated)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: bounced)
            .task {
                guard animated, !started else { return }
                started = true
                try? await Task.sleep(nanoseconds: UInt64(TripBookMotion.coverFlipDelay * 1_000_000_000))
                withAnimation(.easeInOut(duration: TripBookMotion.coverFlipDuration)) { flipped = true }
                let flipEnd = TripBookMotion.coverFlipDelay + TripBookMotion.coverFlipDuration
                try? await Task.sleep(nanoseconds: UInt64(TripBookMotion.coverFlipDuration * 1_000_000_000))
                coverShown = false
                try? await Task.sleep(nanoseconds: UInt64(max(0, TripBookMotion.bounceAt - flipEnd) * 1_000_000_000))
                bounced += 1
                withAnimation(.easeOut(duration: 0.06)) { bounce = true }
                try? await Task.sleep(nanoseconds: 60_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { bounce = false }
            }
    }
}

extension View {
    /// 背表紙を拡大の移り変わりの元にする（iOS 18 から。17 は今までどおり横から積む）
    @ViewBuilder
    func bookZoomSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// 開いた一冊を背表紙から広げる（iOS 18 から・動きを減らす設定では使わない）
    @ViewBuilder
    func bookZoomTransition(id: String, in namespace: Namespace.ID, enabled: Bool) -> some View {
        if #available(iOS 18.0, *), enabled {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
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
