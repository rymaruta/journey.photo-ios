import SwiftUI

/// ホームの上段の札（元は板 01・55「開く場面ごとに1枚」。いまは横にめくる並び）。
///
/// どれを出すかは `HomeTopCard.cards` が決める。**当たる札と「今日のテーマ」を
/// 横にめくる並び**にする（2026-09-28・owner「両方欲しい」）。縦に積まないのは、
/// 写真の一覧が札の数だけ下がるため（写真が主役）。次の札の端を少し見せて、
/// めくれることを分からせる。自分に当たる札が無い日は今日のテーマが先頭で、その右に
/// 「この季節の撮影スポット」（索引が取れて当たる行がある日だけ）。
///
/// 旅行プランはログイン中だけ読む。**取れなかった回は空のまま**
/// （札が出ないだけで、ホームは壊さない）。
///
/// 読み直すのは、人が替わったとき・`reloadToken` が変わったとき（引き下げ更新・
/// 前面に戻った・メニューのシートを閉じた）・札から旅行プランを開いて戻ったときだけ。
/// **ホームに戻るたびには取りに行かない**（Lambda の同時実行はアカウント全体で10）
struct HomeTopCardView: View {

    /// 今日のテーマの札の背景に使う写真（`DailyThemeCard` に渡す）
    let themePhotos: [Photo]
    /// 自分の写真（一冊・1年前の判定と、今日のテーマの参加の判定に使う）
    let myPhotos: [Photo]
    /// 変わったら旅行プランを読み直す（`GalleryView` が渡す）
    var reloadToken: Int = 0

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment

    @State private var plans: [TripPlan] = []
    /// `plans` が誰のものか。**人が替わったら、取れるまで前の人のプランを出さない**
    @State private var plansOwner: String?
    /// 最後に取れた条件（人と `reloadToken`）。同じなら取り直さない
    @State private var loadedKey: String?
    /// 札から旅行プランを開いた。戻ってきたら読み直す（そこで変えたかもしれない）
    @State private var reloadPlansOnReturn = false
    /// 札から開いた旅行プランから戻った回数。**読み込みの入口を `.task` 1つにまとめる**
    /// ——`onAppear` で別の `Task` を立てると、戻った瞬間の `.task` と2本同時に取りに行った
    @State private var returnReloads = 0
    @State private var openedBooks: Set<String> = []
    /// 撮影スポットの索引（「この季節の撮影スポット」の札）。**取れなかった回は空のまま**
    /// ——札が出ないだけ。索引は静的な JSON（Lambda を通らない）で、サービスが
    /// 60秒の控えと端末の控えを持つ。**一度取れたら画面が生きている間は取り直さない**
    @State private var spots: [OfficialSpot] = []

    private let opened = OpenedTripBooks()

    var body: some View {
        content
            .task(id: "\(auth.userId ?? "-")#\(reloadToken)#\(returnReloads)") { await load() }
            .task { await loadSpots() }
            // ホームに戻ってきたら、開いた一冊の印を読み直す（札を下げる）。
            // 札から旅行プランを開いていたら、プランも読み直す（`.task` の鍵を変えて）
            //
            // 🔴 **開いた印を読み直すのはここと人が替わったときだけ。** 読み込み（`load`）で
            // 読み直すと、一冊を読んでいる最中に前面へ戻った合図で札が差し替わり、
            // 押した元のリンクが消えて一冊の画面が閉じることがある
            .onAppear {
                openedBooks = opened.ids(for: auth.userId)
                if reloadPlansOnReturn {
                    reloadPlansOnReturn = false
                    returnReloads &+= 1
                }
            }
            .onChange(of: auth.userId) { _, userId in
                openedBooks = opened.ids(for: userId)
            }
    }

    /// 札のあいだ
    private static let spacing: CGFloat = 10
    /// 左右の余白（1枚の日の札と同じ）
    private static let margin: CGFloat = 16
    /// 画面の右端に見せる次の札の幅（めくれることの合図）
    private static let peek: CGFloat = 24

    @ViewBuilder
    private var content: some View {
        let choices = HomeTopCard.cards(now: Date(), plans: plansOwner == auth.userId ? plans : [],
                                        myPhotos: myPhotos, openedBookDays: openedBooks, spots: spots)
        if choices.count == 1, let only = choices.first {
            // 1枚の日はいまと同じ（左右 16 の余白で画面いっぱい）
            card(for: only, inCarousel: false)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(choices, id: \.slot) { choice in
                        card(for: choice, inCarousel: true)
                            // 渡る幅は左右の余白を除いたもの。**右の余白は中身を切らない**ので
                            // 次の札はその 16 の上にも見える——見せ幅から余白ぶんを戻して引く
                            // （引き忘れると 24 ではなく 40 見えていた）
                            .containerRelativeFrame(.horizontal) { width, _ in
                                max(width - Self.spacing - (Self.peek - Self.margin), 0)
                            }
                    }
                }
                // 1枚ずつ止まる目印は**並びに直接**付ける（Apple の例と同じ。間に別の
                // 修飾を挟むと子に届くかが仕様から読めない）
                .scrollTargetLayout()
                // **背を揃える。** いちばん高い札（今日のテーマは「参加する」のぶん高い）に
                // 合わせ、めくるたびに下の一覧が上下しないようにする
                .fixedSize(horizontal: false, vertical: true)
            }
            // 1枚ずつ止まり、札の左端は余白 16 の位置（1枚の日の札と同じ）。
            // **最後の札だけは右端に寄せて止まる**——流せるのは中身の
            // 右端までなので、左に1枚前の札の端が見える（横の並びの普通の止まり方）
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, Self.margin, for: .scrollContent)
        }
    }

    /// 札1枚。`inCarousel` のときは外の余白を持たず、並びの高さいっぱいに伸びる
    @ViewBuilder
    private func card(for choice: HomeTopCard.Choice, inCarousel: Bool) -> some View {
        switch choice {
        case .departure(let plan, let daysUntil):
            NavigationLink {
                TripPlansView()
                    .onAppear { reloadPlansOnReturn = true }
            } label: {
                card(eyebrow: "TRIP PLAN", eyebrowLabel: L("旅行プラン", "Trip plan"),
                     title: planTitle(plan),
                     line: daysUntil == 0
                        ? L("今日から · 1日目", "Starts today · Day 1")
                        : L("出発まで \(daysUntil) 日", daysUntil == 1 ? "1 day to go" : "\(daysUntil) days to go"),
                     detail: plan.itemCount > 0 ? TripPlanText.placeCount(plan.itemCount) : nil,
                     backdrop: nil, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
        case .onTrip(let plan, let dayNumber):
            Button {
                MissionRouter.shared.post()
            } label: {
                card(eyebrow: "ON TRIP", eyebrowLabel: L("旅の最中", "On a trip"),
                     title: planTitle(plan),
                     line: L("\(dayNumber)日目 · 写真を投稿する", "Day \(dayNumber) · Post a photo"),
                     detail: nil,
                     backdrop: nil,
                     // 押すと投稿画面が開く（別の画面へ進む「›」ではない）
                     trailingSymbol: "plus", inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
        case .bookReady(let trip):
            NavigationLink {
                TripBookView(trip: trip)
                    // **開いたら札を下げる**（何度も同じ知らせを出さない）。
                    // 🔴 **ここでは印を残すだけ**——いま札を差し替えると、押した元の
                    // リンクが裏で消え、開いたばかりの一冊が勝手に閉じることがある。
                    // 差し替えはホームに戻ってきたとき（`body` の `onAppear`）
                    .onAppear { opened.mark(HomeTopCard.bookKey(trip), for: auth.userId) }
            } label: {
                card(eyebrow: "TRIP BOOK", eyebrowLabel: L("旅の一冊", "Trip book"),
                     title: L("旅の一冊ができました", "Your trip book is ready"),
                     line: "\(TripBook.title(of: trip)) · \(TripBook.daysLabel(trip.days)) · "
                        + L("\(trip.photos.count)枚", "\(trip.photos.count) photos"),
                     detail: nil,
                     backdrop: trip.cover, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
        case .oneYearAgo(let photo, let byUploadDate):
            NavigationLink {
                PhotoDetailView(photo: photo, context: [photo])
            } label: {
                card(eyebrow: "ONE YEAR AGO", eyebrowLabel: L("1年前", "A year ago"),
                     title: byUploadDate ? L("1年前に投稿", "Posted a year ago")
                                         : L("1年前の今ごろ", "A year ago"),
                     line: yearAgoLine(photo),
                     detail: nil,
                     backdrop: photo, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
        case .inSeason(let spot, let guide):
            NavigationLink {
                OfficialSpotView(spot: spot, spots: spots, photos: themePhotos)
            } label: {
                card(eyebrow: "THIS SEASON", eyebrowLabel: L("この季節の撮影スポット", "Photo spot for this season"),
                     title: spot.name,
                     line: guide,
                     // **写真を出すなら作者とライセンスも出す**（CC BY・CC BY-SA の条件。
                     // 薄い背景でも写真は写真）
                     detail: [spot.regionLabel, spot.photo?.credit].compactMap { $0 }.joined(separator: "\n"),
                     backdrop: nil, backdropURL: spot.photo?.url, inCarousel: inCarousel)
            }
            .buttonStyle(.plain)
        case .theme:
            DailyThemeCard(photos: themePhotos, myPhotos: myPhotos, inCarousel: inCarousel)
        }
    }

    // MARK: - 札1枚（今日のテーマの札と同じ地・角・余白）

    private func card(eyebrow: String, eyebrowLabel: String, title: String, line: String,
                      detail: String?, backdrop: Photo?, backdropURL: URL? = nil,
                      trailingSymbol: String = "chevron.right", inCarousel: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow)
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    // 英字の眉は読み上げでは日本語で（今日のテーマの札と同じ）
                    .accessibilityLabel(eyebrowLabel)
                Text(title)
                    .font(JPFont.screenTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(2)
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.muted2)
                    .lineLimit(2)
                if let detail {
                    // **2行まで。** 写真の作者名には100文字を超える機械文がある（Commons の
                    // 「No machine-readable author provided…」）。並びは背を揃えるので、
                    // 1枚が高くなると全部の札が高くなり、下の写真の一覧が押し下がる。
                    // 切るのは真ん中——末尾のライセンス名を残す
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.muted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: trailingSymbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WebTheme.muted)
        }
        .padding(16)
        // 並びの中では高さいっぱい（隣の札と背を揃える）・文字は上に寄せる
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: inCarousel ? .infinity : nil,
               alignment: inCarousel ? .topLeading : .leading)
        .background(alignment: .trailing) {
            if let backdrop {
                // **写真は右側に薄く**（今日のテーマの札と同じ——文字を読めなくしない）
                RemoteImage(url: backdrop.gridImageURL, alignment: backdrop.gridAlignment)
                    .frame(width: 160)
                    .opacity(0.35)
                    .mask {
                        LinearGradient(colors: [Color.black.opacity(0), Color.black],
                                       startPoint: .leading, endPoint: .trailing)
                    }
            } else if let backdropURL {
                // 撮影スポットの写真（`Photo` ではない）。薄さ・幅は上と同じ
                RemoteImage(url: backdropURL)
                    .frame(width: 160)
                    .opacity(0.35)
                    .mask {
                        LinearGradient(colors: [Color.black.opacity(0), Color.black],
                                       startPoint: .leading, endPoint: .trailing)
                    }
            }
        }
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .padding(.horizontal, inCarousel ? 0 : 16)
    }

    private func planTitle(_ plan: TripPlan) -> String {
        let title = plan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L("旅行プラン", "Trip plan") : title
    }

    /// 撮影地があれば撮影地、無ければ題。どちらも無ければ一言だけ
    private func yearAgoLine(_ photo: Photo) -> String {
        let place = (photo.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty { return place }
        let title = photo.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L("あの日の1枚", "A photo from that day") : title
    }

    // MARK: - 読み込み

    /// 撮影スポットの索引。**取れたら二度と取りに行かない**（画面が生きている間）。
    /// 取れなかった回は空のまま（札が出ないだけ）
    private func loadSpots() async {
        guard spots.isEmpty else { return }
        let fetched = try? await environment.spots.fetchIndex()
        guard !Task.isCancelled, let fetched else { return }
        spots = fetched
    }

    private func load() async {
        let userId = auth.userId
        // 🔴 **人が替わったら、まず前の人のプランを捨てる**（取れなかった回に残さない）
        if plansOwner != userId {
            plans = []
            plansOwner = nil
            loadedKey = nil
        }
        guard userId != nil else { return }
        let key = "\(userId ?? "-")#\(reloadToken)#\(returnReloads)"
        guard loadedKey != key else { return }
        // ⚠️ `if let x = try? await …` は構文検査（tree-sitter）が読めない。2文に割る
        let fetched = try? await environment.trips.list()
        // **画面を離れて止められた・待っている間に人が替わった回は書かない**
        guard !Task.isCancelled, auth.userId == userId else { return }
        guard let fetched else { return }
        plans = fetched
        plansOwner = userId
        loadedKey = key
    }
}
