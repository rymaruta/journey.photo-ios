import SwiftUI

/// 自分のページ。ログインしていなければログイン画面を出す。
struct MyPageView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model = MyPageViewModel()
    /// 「行きたい」の台帳のスポットの名前を引く索引（`app/data/spots.json`）。
    /// 取れなければ空——鍵のぶんは slug から起こした名前で行だけ出す
    @State private var officialSpots: [OfficialSpot] = []
    /// いいねした写真を引き当てる先。**公開一覧**——自分の写真だけを
    /// 探していたので、**他人の写真へのいいねが一度も出なかった**
    @State private var feed: [Photo] = []
    /// サーバーが返したいいねの ID。取れなければ nil（端末の控えだけ出す）
    @State private var serverLikeIds: [String]?
    @State private var likesStatus: LikedPhotos.Status = .loading
    @State private var tab: ProfileTab = .posts
    @State private var showPostSheet = false
    @State private var showDistanceNote = false
    @State private var showCountriesNote = false
    @State private var showPhotoUpload = false
    @State private var showStoryComposer = false
    /// ストーリーの行に「読み直せ」と言うための数
    @State private var storiesReload = 0
    /// 一度でもこの画面が出たか。**戻ってきた回だけ読み直す**ための印
    @State private var didAppear = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        Group {
            if auth.isResolving {
                // 確認が終わるまでログイン画面を出さない（ちらつきを作らない）
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if auth.userId == nil {
                SignInView(reason: nil)
            } else {
                content
            }
        }
        .webScreen()
        .navigationTitle(Labels.Navigation.mypage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // **ここだけ見出しが違っていた。** 他の札（ホーム・さがす・
            // マップ）はロゴを出すのに、マイページは大きな字で
            // 「マイページ」——実機の絵（run 47）で、札を移った瞬間に
            // 別のアプリに見えた。`AppHeader` の注記が避けると書いていた形
            ToolbarItem(placement: .principal) {
                AppLogo()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Image(systemName: "gearshape")
                        .webToolbarIcon()
                        .accessibilityLabel(L("設定", "Settings"))
                }
            }
        }
        .task(id: auth.userId) {
            guard auth.userId != nil else { return }
            await model.load()
        }
        // いいねした写真。**ログイン状態が決まってから**聞く
        .task(id: auth.userId) { await loadLikes() }
        // 「行きたい」のスポットの名前を引く索引。**取れなくても行は出る**
        .task(id: auth.userId) {
            guard auth.userId != nil else { return }
            officialSpots = (try? await environment.spots.fetchIndex()) ?? officialSpots
        }
        // **戻ってきたら読み直す。** この画面から押して出る先
        // （プロフィール編集・写真の詳細）はどれも `NavigationLink` で、
        // 閉じる合図を受け取る口が無い。保存しても削除しても、
        // マイページは古いままだった。
        // 初回は `.task` が読むので、2度目以降だけ走らせる
        .onAppear {
            guard didAppear else { didAppear = true; return }
            guard auth.userId != nil else { return }
            Task { await model.load() }
        }
    }

    /// **段ごとに割ってある**（`UploadView` と同じ理由——長い ViewBuilder は
    /// 型検査が終わらなくなることがある。落ちたときに場所も分かりやすい）。
    /// 表示名がまだ無い人へ。**Web の `ProfileSetupBanner` と同じ。**
    /// 名前を決めない限り、検索に出てこず「（IDの頭）」で呼ばれる。
    /// 本人には気づきようがないので、こちらから伝える。
    @ViewBuilder
    private func profileSetupNotice(_ profile: UserProfile) -> some View {
        if ProfileSetup.needsName(displayName: profile.displayName, username: profile.username) {
            NavigationLink {
                ProfileEditView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.text.rectangle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("名前を決めましょう", "Choose a display name"))
                            .font(.subheadline.weight(.semibold))
                        Text(L("名前が無いと、ほかの人の検索に出てきません",
                               "Without a name you won't appear in search"))
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(WebTheme.foreground)
                .padding(12)
                .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    /// 旅の一冊へ。**撮った本人の記録なので、持ち場はここ**
    /// （タブは指示書の並び——ホーム／探す／投稿／マップ／マイページ）。
    private var tripsLink: some View {
        NavigationLink {
            TripsView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "book.closed")
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("旅の記録", "Your trips"))
                        .font(.subheadline.weight(.semibold))
                    Text(L("同じころに撮った写真が、ひとつの旅になります",
                           "Photos taken around the same time become a trip"))
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(WebTheme.foreground)
            .padding(12)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**
        .accessibilityIdentifier("trips.entry")
        .padding(.horizontal, 16)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let profile = model.profile {
                    header(profile)
                    stats
                    travelRecord
                    bgmCard(profile)
                    profileSetupNotice(profile)
                }
                postButton
                StoriesRow(reloadToken: storiesReload)
                tripsLink
                shortcuts
                highlightsRow
                tabPicker
                photoArea
            }
        }
        .refreshable { await model.load() }
        .sheet(isPresented: $showPostSheet) {
            PostSheet { kind in
                switch kind {
                case .photo: showPhotoUpload = true
                case .story: showStoryComposer = true
                }
            }
        }
        .sheet(isPresented: $showPhotoUpload, onDismiss: { Task { await model.load() } }) {
            NavigationStack { UploadView() }
        }
        // **帰ってきたら読み直す。** `StoriesRow` は自分の `+` から出した
        // シートしか見ていないので、ここから出した回は投稿しても並ばなかった
        .sheet(isPresented: $showStoryComposer, onDismiss: { storiesReload += 1 }) {
            NavigationStack { StoryComposerView() }
        }
    }

    @ViewBuilder
    private func themeRing(_ hex: String?) -> some View {
        if let hex, let color = Color(hex: hex) {
            Circle().strokeBorder(color, lineWidth: 3)
        }
    }

    private func header(_ profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: profile.avatarURL(cacheBust: model.avatarCacheBust))
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                // **本人が選んだ色を輪にする**（Web の `themeRingGradient` と
                // 同じ置き場所）。選んでいなければ輪を出さない
                .overlay(themeRing(profile.themeColor))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile.name).font(.headline)
                    VerifiedBadge(isVerified: profile.verified)
                }
                // ユーザー名（モック2-1 の `@yuki_travel`）。
                // **名前と同じ行に置かない**——長い名前で片方が切れる
                if let username = profile.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.footnote)
                        .foregroundStyle(WebTheme.faint)
                }
                // ひとこと。**持っているのに一度も出していなかった**
                if let status = profile.statusText, !status.isEmpty {
                    Text(status).font(.footnote).foregroundStyle(WebTheme.muted2)
                }
                if let bio = profile.bio, !bio.isEmpty {
                    Text(bio).font(.footnote).foregroundStyle(.secondary)
                }
                // 居住地（モック2-1 の「📍Tokyo, Japan」）。
                // **地図には出さない**——住んでいる場所はピンにしない
                if let home = profile.homeLocation, !home.isEmpty {
                    Label(home, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }


    /// 数の並び（提案の絵）。**投稿・いいね・フォロワー・フォロー中**
    ///
    /// **両端を 16pt の余白に揃える。** 下の「旅の実績」が端から端までの
    /// 帯なので、ここが左詰めのままだと右端だけ段違いになる。
    /// 丸の幅は中身のまま（数字の大きさを変えない）で、**間を均等に開ける**。
    /// 収まらない幅（英語表記・桁の多い数）では、これまでどおり横に流す
    private var stats: some View {
        ViewThatFits(in: .horizontal) {
            statsRow(spread: true)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                statsRow(spread: false)
                    .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func statsRow(spread: Bool) -> some View {
        // 間の Spacer は最小 0 なので、詰めたときの間隔は `spacing` の 8 のまま
        HStack(spacing: 8) {
            statPill(systemImage: "photo.on.rectangle",
                     value: "\(model.photos.count)", label: L("投稿", "Posts"))
            if spread { Spacer(minLength: 0) }
            NavigationLink {
                FollowListView(userId: model.profile?.userId ?? "", kind: .followers)
            } label: {
                statPill(systemImage: "person.2", value: "\(model.followers)",
                         label: L("フォロワー", "Followers"))
            }
            .buttonStyle(.plain)
            if spread { Spacer(minLength: 0) }
            NavigationLink {
                FollowListView(userId: model.profile?.userId ?? "", kind: .following)
            } label: {
                statPill(systemImage: "person", value: "\(model.following)",
                         label: L("フォロー中", "Following"))
            }
            .buttonStyle(.plain)
        }
    }

    private func statPill(systemImage: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WebTheme.foreground)
            Text(label)
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(WebTheme.surface, in: Capsule())
    }

    /// 旅の実績（モック2-3）。**訪れた国・地域**と**写真をつないだ距離**を縦に並べる。
    ///
    /// **2本とも端から端までの帯にする。** 中身の幅のまま中央に寄せていた頃は、
    /// 長さの違う2本が互いにも上の段ともずれていた。項目名は左、**数字は右に
    /// 揃える**ので、2つの数字が縦に並んで読める。
    ///
    /// どちらも**数えた値**で、どちらも**そのままの意味ではない**ので、
    /// それぞれ押すと計算の中身が出る。
    @ViewBuilder
    private var travelRecord: some View {
        let countries = VisitedCountries.count(in: model.photos)
        VStack(spacing: 8) {
            // **0 のときは出さない。** 「訪れた国 0」は実績にならないし、
            // 「まだ国名を書いていない」を「行っていない」と読ませてしまう
            if countries > 0 {
                Button {
                    showCountriesNote = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .foregroundStyle(Color(red: 0.42, green: 0.68, blue: 1.0))
                        Text(L("訪れた国・地域", "Countries and regions"))
                            .font(.subheadline)
                            .foregroundStyle(WebTheme.muted2)
                        Spacer(minLength: 8)
                        Text("\(countries)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(WebTheme.foreground)
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Capsule())
                    .background(WebTheme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .alert(L("訪れた国・地域", "Countries and regions"),
                       isPresented: $showCountriesNote) {
                    Button(Labels.Common.close, role: .cancel) {}
                } message: {
                    // **数え方をそのまま書く。** 「思ったより少ない」の答えが
                    // ここにある（国名を書いた写真しか数えていない）
                    Text(L("撮影地に国・地域の名前が書かれている写真だけを数えています。地名から国を推測はしません。撮影地に国名を足すと、この数もサイトの地名ページも増えます。",
                           "Counts only photos whose location text names a country or region. We don't guess a country from a place name. Adding the country to your location text raises this number."))
                }
            }
            distancePill
        }
    }

    /// 写真をつないだ距離。**実際に移動した距離ではない**ので、そう書く
    /// （指示書 8-3）。押すと計算の中身を出す。
    @ViewBuilder
    private var distancePill: some View {
        let km = TravelDistance.total(of: model.photos)
        if km > 0 {
            Button {
                showDistanceNote = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe.asia.australia")
                        .foregroundStyle(Color(red: 0.42, green: 0.68, blue: 1.0))
                    Text(L("写真をつないだ距離", "Distance between photos"))
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.muted2)
                    Spacer(minLength: 8)
                    Text("\(TravelDistance.formatted(km)) km")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WebTheme.foreground)
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Capsule())
                .background(WebTheme.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .alert(L("写真をつないだ距離", "Distance between photos"),
                   isPresented: $showDistanceNote) {
                Button(Labels.Common.close, role: .cancel) {}
            } message: {
                Text(distanceNote)
            }
        }
    }

    /// **「旅した距離」とだけ書かない。** 実際に歩いた・乗った距離だと
    /// 読まれる（指示書 8-3）。
    private var distanceNote: String {
        L("撮影地の分かる写真を、古い順に直線で結んだ合計です。実際に歩いた・乗った距離ではありません（道のりではなく直線で、撮っていない区間は飛び、座標は約1kmに丸めてあります）。",
          "The straight-line total between photos that have coordinates, oldest first. Not the distance you actually travelled.")
    }

    private var postButton: some View {
        // **投稿の入口はここ1つ。** Web も 2026-09-20 に画面右下の
        // 「＋」を撤去して、マイページの「投稿する」に集めた
        Button {
            showPostSheet = true
        } label: {
            // 🔴 **`.borderedProminent` を使わない**（同意画面と同じ理由）。
            // `RootView` の `.tint(WebTheme.foreground)` が白なので、
            // 白地に白い字＝**ただの白い帯**になる。run 60 の実機の絵で、
            // マイページの一番上がそうなっていた
            Label(L("投稿する", "Create"), systemImage: "plus")
                .frame(maxWidth: .infinity)
                .webPrimaryButton()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var shortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                NavigationLink(L("プロフィールを編集", "Edit profile")) { ProfileEditView() }
                    .buttonStyle(.bordered)
                NavigationLink(Labels.Navigation.albums) { AlbumsView() }
                    .buttonStyle(.bordered)
                NavigationLink(Labels.Navigation.favorites) { FavoritesView() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
        }
        .font(.footnote)
    }

    /// プロフィールのBGM（モック2-4）。
    ///
    /// **入れている人にだけ出す。** サーバーは前から `songs` を返していて、
    /// アプリが復号していなかっただけだった（⛔ にしていたのは誤り）。
    /// 曲は `MusicPreviewPlayer` に通す——**専用の再生器を作らない**
    /// （画面をまたいだ操作は `MiniPlayerBar` が受け持っている）。
    @ViewBuilder
    private func bgmCard(_ profile: UserProfile) -> some View {
        if let song = profile.bgm {
            SongRow(song: song)
                .padding(12)
                .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
        }
    }

    /// ストーリーハイライト（モック2-5）。
    ///
    /// **サーバーにある本物の輪**（`api-user/src/highlights.ts`）。
    /// 以前はここに「旅の一冊」の丸い並びを出していた——サーバーに
    /// ハイライトが無かったので、いちばん近いものを当てていた。
    /// develop でハイライトそのものが入ったので、本物に差し替える。
    /// **旅の一冊は消していない**（上の「旅の記録」から入る）。
    @ViewBuilder
    private var highlightsRow: some View {
        if let userId = auth.userId {
            HighlightsRow(userId: userId, isMine: true)
        }
    }

    /// いいねした写真。**サーバーの一覧と、この端末の控えの和**。
    ///
    /// 以前は**自分の写真の中から**端末の控えに一致するものを探していたので、
    /// **他人の写真へのいいねが一度も出なかった**（自分の写真を自分で
    /// いいねしたときだけ出る状態）。さらに別の端末で押したぶんも
    /// 出なかった——同じ写真の詳細は「いいね済み」と出るのに。
    @ViewBuilder
    private var favoritesArea: some View {
        let ids = LikedPhotos.ids(serverIds: serverLikeIds, deviceIds: favorites.ids)
        let liked = LikedPhotos.resolve(ids, in: [feed, model.photos])
        VStack(alignment: .leading, spacing: 10) {
            if likesStatus == .partial {
                // **端末のぶんは消さない。** 足りていないことだけ伝える
                ErrorBanner(message: L("サーバーのいいねを取れませんでした。この端末に覚えているぶんだけ出しています",
                                       "Couldn't reach the server — showing what's on this device")) {
                    Task { await loadLikes() }
                }
            }
            if liked.isEmpty {
                // **「まだ」と「0件」を混ぜない。** 取得中に「ありません」と
                // 言い切ると、別の端末で押したぶんが届く前に「無い」と読まれる
                if likesStatus == .loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ErrorBanner(message: L("いいねした写真はまだありません", "No liked photos yet"))
                }
            } else {
                PhotoGrid(photos: liked) { photo in
                    PhotoDetailView(photo: photo, context: liked)
                }
            }
        }
    }

    /// 行きたい場所（モック2）。**この端末に覚えたもの**で、
    /// サーバーには無い（`WishlistStore`）。
    @ViewBuilder
    private var wishlistArea: some View {
        // **撮影地から導いた地点**のうち、「行きたい」に入れたもの
        let places = DerivedSpot.all(in: model.photos)
        let wanted = places.filter { wishlist.contains($0.slug) }
        // 台帳の撮影スポット（`SPOT-<slug>`）。索引と突き合わせて名前を引く。
        // **索引が無くても行は出す**（`OfficialWishlist`）——スポットの画面で
        // 押した直後に「まだありません」と言わない
        let officialRows = OfficialWishlist.rows(keys: wishlist.spotIds, index: officialSpots)
        VStack(alignment: .leading, spacing: 10) {
            // **どこに残るかを書く。** 機種を変えると消えるものを、
            // 消えないものと同じ顔で出さない
            Text(L("この端末に覚えています（他の端末や Web には出ません）",
                   "Kept on this device only"))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
                .padding(.horizontal, 16)

            // **「まだ無い」と「台帳が取れていない」を分ける**（`ProfileSections`）。
            // 数えるのは撮影地の行とスポットの行の両方
            switch ProfileSections.wishlist(ledgerCount: places.count,
                                            wantedCount: wanted.count + officialRows.count,
                                            savedIdCount: wishlist.spotIds.count) {
            case .couldNotLoad:
                ErrorBanner(message: L("写真の一覧を取れませんでした。通信を確かめて、引き下げて読み直してください",
                                       "Couldn't load the photos. Pull to refresh."))
            case .empty:
                ErrorBanner(message: L("まだありません。スポットの画面で「行きたい」を押すとここに並びます",
                                       "Nothing yet. Tap “Want to go” on a place."))
            case .list:
                ForEach(wanted) { place in
                    NavigationLink {
                        SpotDetailView(spot: place, photos: model.photos)
                    } label: {
                        wishlistRow(place)
                    }
                    .buttonStyle(.plain)
                }
                // 台帳のスポット。**索引に無い鍵は行だけ**（開く先が無い）
                ForEach(officialRows) { row in
                    if let spot = row.spot {
                        NavigationLink {
                            OfficialSpotView(spot: spot, spots: officialSpots, photos: model.photos)
                        } label: {
                            officialWishlistRow(row)
                        }
                        .buttonStyle(.plain)
                    } else {
                        officialWishlistRow(row)
                    }
                }
            }
        }
    }

    /// 台帳のスポットの行。撮影地の行と同じ並びで、表紙の代わりに印（写真が無い）
    private func officialWishlistRow(_ row: OfficialWishlist.Row) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle")
                .font(.title3)
                .foregroundStyle(WebTheme.muted2)
                .frame(width: 56, height: 56)
                .background(WebTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let region = row.regionLabel {
                        Text(region)
                            .font(.caption)
                            .foregroundStyle(WebTheme.muted2)
                            .lineLimit(1)
                    }
                    if row.spot?.isDraft ?? false {
                        Text(L("下書き", "Draft"))
                            .font(.caption)
                            .foregroundStyle(WebTheme.faint)
                    }
                }
            }
            Spacer(minLength: 8)

            // **一覧からも外せる。** 索引に無い鍵はここでしか外せない
            Button {
                wishlist.set(row.key, wanted: false)
            } label: {
                Image(systemName: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(row.name) を「行きたい」から外す", "Remove \(row.name)"))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
        .accessibilityIdentifier("mypage.officialWish")
    }

    private func wishlistRow(_ spot: DerivedSpot.Place) -> some View {
        HStack(spacing: 12) {
            // 代表写真は**いちばん多く押された1枚**（数えた値）
            RemoteImage(url: spot.cover?.gridImageURL)
                .frame(width: 56, height: 56)
                .background(WebTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(spot.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                let place = spot.broader.joined(separator: " ・ ")
                if !place.isEmpty {
                    Text(place)
                        .font(.caption)
                        .foregroundStyle(WebTheme.muted2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)

            // **一覧からも外せる。** 外すのに詳細まで行かせない
            Button {
                wishlist.set(spot.slug, wanted: false)
            } label: {
                Image(systemName: "heart.fill")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(spot.label) を「行きたい」から外す", "Remove \(spot.label)"))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
    }

    /// モック2・11 の4つ（投稿 / 行きたい場所 / マップ / お気に入り）。
    /// **既定の `segmented` を使わない**——黒地の上で帯だけ明るく浮く
    private var tabPicker: some View {
        HStack(spacing: 6) {
            ForEach(ProfileTab.tabs(isMe: true)) { option in
                let selected = tab == option
                Button {
                    tab = option
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(selected ? AnyShapeStyle(WebTheme.foreground)
                                             : AnyShapeStyle(Color.clear),
                                    in: Capsule())
                        .foregroundStyle(selected ? WebTheme.accentText : WebTheme.muted2)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(WebTheme.surface, in: Capsule())
        .padding(.horizontal, 16)
    }

    /// いいねした写真を読む。**未ログインなら聞きに行かない**
    /// （端末の控えが答え）。
    private func loadLikes() async {
        guard auth.userId != nil else {
            serverLikeIds = nil
            likesStatus = .deviceOnly
            return
        }
        likesStatus = .loading
        // 引き当て先。公開一覧が取れなくても、自分の写真の分は出せる
        async let feedTask = environment.gallery.fetchPhotos()
        async let idsTask = environment.social.myLikedPhotoIds()
        feed = (try? await feedTask) ?? feed
        let ids = try? await idsTask
        if let ids {
            serverLikeIds = ids
            likesStatus = .ready
        } else {
            serverLikeIds = nil
            likesStatus = .partial
        }
    }

    @ViewBuilder
    private var photoArea: some View {
        if let action = model.actionMessage {
            // **一覧の代わりではなく、一覧に添える。**
            Text(action)
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
        }
        if let error = model.errorMessage {
            ErrorBanner(message: error) { Task { await model.load() } }
        } else if tab == .wishlist {
            // **写真の有無とは無関係。** 行きたい場所は台帳の話で、
            // 1枚も撮っていない人にも中身がある
            wishlistArea
        } else if model.photos.isEmpty && !model.isLoading {
            // **この文言は「投稿」の話。** 以前はタブの判定より前に
            // 置いてあったので、写真が0枚の人は地図もお気に入りも
            // 「まだ写真がありません」に潰れていた
            ErrorBanner(message: L("まだ写真がありません", "No photos yet"))
        } else if tab == .map {
            // **自分の写真だけの地図。** 全員の地図はマップのタブにある
            MyPhotosMap(photos: model.photos)
        } else if tab == .favorites {
            favoritesArea
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(model.photos) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo, fromPublicFeed: false, context: model.photos)
                    } label: {
                        gridCell(photo)
                    }
                    .buttonStyle(.plain)
                    // **長押しでピン留め**（Web の「先頭にピン留め」と同じ操作）。
                    // 一覧の見た目は変えず、操作だけ足す
                    .contextMenu {
                        let pinned = model.isPinned(photo.id)
                        Button {
                            Task { await model.setPinned(photo.id, pinned: !pinned) }
                        } label: {
                            Label(pinned ? L("ピン留めを解除", "Unpin")
                                         : L("先頭にピン留め", "Pin to top"),
                                  systemImage: pinned ? "pin.slash" : "pin")
                        }
                    }
                }
            }
        }
    }

    /// 一覧の1枚。**下書き（非公開）は一目で分かるようにする**
    /// ——公開したつもりの写真が出ていない、がいちばん困る。
    private func gridCell(_ photo: Photo) -> some View {
        ZStack(alignment: .topTrailing) {
            PhotoFrame(photo: photo)
            if model.isPinned(photo.id) {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .padding(4)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(4)
                    .accessibilityLabel(L("ピン留め中", "Pinned"))
            }
            if photo.published == false {
                Text(L("下書き", "Draft"))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(4)
            }
        }
    }
}

@MainActor
final class MyPageViewModel: ObservableObject {

    @Published private(set) var profile: UserProfile?
    /// 留めている写真。**サーバーが返した一覧をそのまま持つ**
    /// （増減の結果は向こうが決める——3枚の上限も、消えた写真の掃除も）
    @Published private(set) var pinnedIds: [String] = []
    @Published private(set) var photos: [Photo] = []
    @Published private(set) var isLoading = false
    /// **読み込みに失敗した**。画面はこの時だけ一覧の代わりに知らせを出す。
    @Published var errorMessage: String?
    /// **操作が断られた**（ピン留めの上限など）。一覧は出したまま添える。
    ///
    /// 読み込みの失敗と混ぜると、ピン留めを断られた瞬間に写真グリッドごと
    /// 知らせに差し替わり、**解除する長押しメニューまで消える**——
    /// 断られた人が直す手立てを画面から奪ってしまう。
    @Published var actionMessage: String?

    /// アイコンは固定キーで中身が差し替わる（サーバーは `no-store`）。
    /// 読み直すたびに別の URL にして、古い絵が残らないようにする。
    private(set) var avatarCacheBust = ""

    private let profiles: ProfileService
    private let photoService: PhotoService
    private let social: SocialService

    /// フォロワー／フォロー中の数（提案の絵の並び）。
    /// **数え札はサーバーが持っている**（`followstats#`）ので、
    /// 一覧の長さから数えない——50人で切ったぶんが落ちる
    @Published private(set) var followers = 0
    @Published private(set) var following = 0

    /// 公開一覧。**鍵の要らない経路で描くときだけ使う**（下の `loadPublicly`）。
    private let gallery: PublicGalleryService

    /// - Parameters:
    ///   - api: 叩き先。**テストで差し替えるため**に開けてある。
    ///   - gallery: 公開写真の出どころ。同上（既定は本物のサイトを叩く）。
    init(api: APIClient = APIClient(tokenProvider: CognitoTokenProvider()),
         gallery: PublicGalleryService = PublicGalleryService()) {
        self.profiles = ProfileService(api: api)
        self.photoService = PhotoService(api: api)
        self.social = SocialService(api: api)
        self.gallery = gallery
    }

    func load() async {
        // **2本同時に走らせない。** タブの出入りでは `.task(id:)` と
        // `.onAppear` の両方が走ることがあり、`defer` で片方が先に
        // `isLoading` を解くと、もう片方の途中で「まだ写真がありません」が
        // 一瞬出る。片方が失敗すれば知らせに差し替わる
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        avatarCacheBust = String(Int(Date().timeIntervalSince1970))
        // 🔴 **鍵を持たずに入っている回は、鍵の要る口を叩かない。**
        //
        // `AuthStore` の `PreviewSession`（Debug のみ）は利用者 ID だけを
        // 入れてトークンを作らない。そこに書いてある約束は「作品の格子は
        // **本物のデータで描かれる**」だったが、ここは `/user/profile` と
        // `/user/photos`（どちらも鍵が要る）しか見ていなかったので、
        // **読み込みごと失敗して「ログインが必要です」しか出ていなかった**
        // （run 63・64 のマイページの絵がそれ）。
        //
        // 逃がす先は**人のページと同じ経路**（`UserProfileView`）——
        // 公開プロフィールと、公開一覧から自分のぶんを選り分ける。
        // **嘘の中身は出ない**（下書き＝非公開は公開一覧に無いので出ない）。
        if let previewId = PreviewSession.userId {
            await loadPublicly(userId: previewId)
            return
        }
        do {
            async let profile = self.profiles.myProfile()
            async let photos = self.photoService.myPhotos()
            self.profile = try await profile
            // 自分のページでも、留めた写真は先頭（他人から見えている並びと揃える）
            self.pinnedIds = self.profile?.pinnedPhotoIds ?? []
            self.photos = PhotoPinning.pinnedFirst(try await photos, pinned: self.pinnedIds)
            // **数が取れなくても画面は出す**（0 のままになるだけ）。
            //
            // **`if let x = try? await …` と書かない。** 手元の構文検査
            // （tree-sitter）が読めず、`verify.sh` が「構文が壊れている」と
            // 言う（CLAUDE.md に記録のある制約）。文を分ける
            if let userId = self.profile?.userId {
                let stats = try? await self.social.followStats(userId: userId)
                if let stats {
                    self.followers = stats.followers
                    self.following = stats.following
                }
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
        }
    }

    /// 鍵を持たない回の読み込み（`PreviewSession` のときだけ通る）。
    ///
    /// **`myPhotos()` を使わない**——あれは下書きまで返す代わりに鍵が要る。
    /// ここは公開されているぶんだけで足りる。
    private func loadPublicly(userId: String) async {
        let publicProfile = try? await self.profiles.publicProfile(userId: userId)
        self.profile = publicProfile
        self.pinnedIds = publicProfile?.pinnedPhotoIds ?? []
        let all = try? await self.gallery.fetchPhotos()
        if let all {
            let mine = all.filter { ($0.userId ?? $0.uploadedBy) == userId }
            self.photos = PhotoPinning.pinnedFirst(mine, pinned: self.pinnedIds)
        }
        let stats = try? await self.social.followStats(userId: userId)
        if let stats {
            self.followers = stats.followers
            self.following = stats.following
        }
    }

    func isPinned(_ photoId: String) -> Bool { pinnedIds.contains(photoId) }

    /// ピン留めの増減。
    ///
    /// **画面を先に動かさない。** 3枚の上限はサーバーが持っていて
    /// （`userProfile.ts`）、断られたときにそのときの一覧も返ってくる。
    /// 先に動かすと「留まったように見えて、次の読み込みで戻る」になる。
    func setPinned(_ photoId: String, pinned: Bool) async {
        do {
            pinnedIds = try await profiles.setPinned(photoId: photoId, pinned: pinned)
            photos = PhotoPinning.pinnedFirst(photos, pinned: pinnedIds)
            actionMessage = nil
        } catch {
            // 上限（409）のときは、サーバーが「ピン留めは3枚までです」を返す。
            // **一覧を消さない側に入れる**——消すと解除する手立てが無くなる
            actionMessage = (error as? LocalizedError)?.errorDescription
                ?? L("ピン留めを変えられませんでした", "Couldn't change the pin")
            // **断られたら、サーバーが持っている一覧に揃える。**
            //
            // 揃えないと、別の端末で留めたぶんが画面に出ないまま
            // 「3枚までです」と言われ続ける——**見えていないものは
            // 外せない**ので、画面の中に直す手立てが無くなる
            // （`userProfile.ts` が 409 の本体にも今の一覧を入れているのは
            //  そのため。`APIError` は本体を持ち歩かないので引き直す）。
            // `if let x = try? await …` と1行で書かない
            // ——`Tools/check-swift-syntax.js` が使っている tree-sitter の
            // 文法が解釈できず、検査が赤くなる（Swift としては正しい）
            let fresh = try? await profiles.myProfile()
            if let ids = fresh?.pinnedPhotoIds {
                pinnedIds = ids
                photos = PhotoPinning.pinnedFirst(photos, pinned: pinnedIds)
            }
        }
    }
}
