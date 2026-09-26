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
    @State private var showDistanceNote = false
    @State private var showCountriesNote = false
    /// 一度でもこの画面が出たか。**戻ってきた回だけ読み直す**ための印
    @State private var didAppear = false
    /// カバー写真が出せたか（板 05c／出せなければ 05d）。見出しを重ねるかを決める
    @State private var hasCover = false
    /// 下の「投稿」の画面を閉じた合図（`TabRouter.postSheetsClosed`）
    @ObservedObject private var tabRouter = TabRouter.shared
    /// BGM の再生の丸（再生中かどうかで印を変える）
    @ObservedObject private var player = MusicPreviewPlayer.shared

    /// 板 05c: 3列・隙間 4pt・角なし
    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
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
        // **ログイン中は上のバーを出さない**（板 05c・05d）。カバーが画面の上端から
        // 敷かれ、設定は右上のガラスの丸（`settingsButton`）。未ログインでは
        // ログイン画面なので、これまでどおりバーに設定だけ置く
        .toolbar(auth.userId == nil ? .automatic : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if auth.userId == nil {
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape")
                            .webToolbarIcon()
                            .accessibilityLabel(L("設定", "Settings"))
                    }
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
        // **下の「投稿」から投稿して閉じたら読み直す。** シートは `RootView` に
        // あるので、閉じても `onAppear` は来ない
        .onChange(of: tabRouter.postSheetsClosed) { _, _ in
            guard auth.userId != nil else { return }
            Task { await model.load() }
        }
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

    /// **カバーは画面の上端から**（時計の裏まで）。無い人は安全域の下から。
    /// 安全域の高さは GeometryReader で測り（こちらは安全域を無視させない）、
    /// 上端まで伸ばすのは中のスクロールだけ。設定の丸はこの高さぶん下げて、
    /// 時計の裏に入れない
    private var content: some View {
        GeometryReader { geo in
            scroll(topInset: geo.safeAreaInsets.top)
                .ignoresSafeArea(edges: hasCover ? .top : [])
        }
    }

    private func scroll(topInset: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // **設定の丸は中身と一緒に流す。** 画面に留めると、送ったときに
                // 格子の右上の写真に被さり、そこを押すと設定が開いた
                // 板: 見出し・数・旅の実績の間は 12pt、その下の段は 14pt
                VStack(alignment: .leading, spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        // **丸を先に置く**（読み上げで見出しの途中に「設定」が挟まらない）。
                        // 見た目は前に出す
                        settingsButton
                            .padding(.top, hasCover ? topInset : 0)
                            .zIndex(1)
                        if let profile = model.profile {
                            // カバーと見出しは間を空けずに重ねる（板 05c）。カバーが無ければ
                            // 右上の設定の丸の下から始める（板 05d）
                            VStack(alignment: .leading, spacing: 0) {
                                ProfileCover(url: profile.coverURL(cacheBust: model.avatarCacheBust),
                                             reserve: hasCover) { hasCover = $0 }
                                header(profile)
                            }
                        } else {
                            // 読み込み中・失敗: 丸の高さだけ空けて、下の中身に被せない
                            Color.clear.frame(height: 44)
                        }
                    }
                    if model.profile != nil {
                        stats
                        travelRecord
                    }
                }
                if let profile = model.profile {
                    bgmCard(profile)
                    profileSetupNotice(profile)
                }
                // **「投稿する」とストーリーの行は置かない**（整理案 05c）。
                // 下の札の「投稿」とホームのストーリーの行と入口が重なっていた。
                // 旅の記録は下のタブへ移した。**編集・アルバム・お気に入りの
                // ボタンの列も置かない**——編集は見出しの右、お気に入りは下のタブ、
                // アルバムは設定から入る（`SettingsView`）
                highlightsRow
                tabPicker
                photoArea
            }
        }
        .refreshable { await model.load() }
    }

    /// 右上の設定（板: 44pt のガラスの丸）。**上のバーを出さないので、ここが入口**
    private var settingsButton: some View {
        NavigationLink { SettingsView() } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .jpGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 8)
        .accessibilityLabel(L("設定", "Settings"))
    }

    /// 見出し（板 05c・05d）: 84pt のアイコン（黒い 3pt の縁）と右に「プロフィールを
    /// 編集」、その下に明朝 26 の名前・「@ユーザー名 · 📍居住地」・ひとこと
    private func header(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                RemoteImage(url: profile.avatarURL(cacheBust: model.avatarCacheBust))
                    .frame(width: Self.avatarSize, height: Self.avatarSize)
                    .clipShape(Circle())
                    // **板どおり黒の 3pt の縁**（写真の上でも丸が割れない）。
                    // 本人の色の輪（`themeColor`）は板に無いので出さない。
                    // ⚠️ 人のページ（`UserProfileView`）はまだ色の輪を出している（板 31 で揃える）
                    .coverCutout(true)
                Spacer(minLength: 8)
                NavigationLink { ProfileEditView() } label: {
                    Text(L("プロフィールを編集", "Edit profile"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                        // 見た目は 36pt、押せる高さは 44pt
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // 実機の絵の道しるべ（見出しが描けた＝読み込みが済んだ目印）
                .accessibilityIdentifier("mypage.edit")
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(profile.name)
                        .font(JPFont.display(26, relativeTo: .title))
                        .foregroundStyle(Color.white)
                    VerifiedBadge(isVerified: profile.verified)
                }
                if let line = ProfileLine.handleAndHome(username: profile.username,
                                                        home: profile.homeLocation) {
                    // 居住地は**地図には出さない**（住んでいる場所はピンにしない）
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                }
                // ひとこと。**持っているのに一度も出していなかった**
                ForEach(ProfileLine.about(status: profile.statusText, bio: profile.bio), id: \.self) { text in
                    Text(text)
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(WebTheme.muted2)
                }
            }
        }
        .padding(.horizontal, 20)
        // カバーがあればアイコンを下端に重ねる（板: 180pt の帯に 84pt の丸を 50pt）。
        // 無ければ右上の設定の丸の下から（板 05d）
        .padding(.top, hasCover ? -Self.avatarOverlap : 49)
    }

    /// 見出しのアイコン（板 84pt）と、カバーの下端へ引き上げる量（板 50pt）。
    /// 人のページ（64pt・28pt）とは別——あちらは板 31
    private static let avatarSize: CGFloat = 84
    private static let avatarOverlap: CGFloat = 50

    /// 数の並び（板 05c: 投稿・フォロワー・フォロー中の3列・等幅の数字 18 と名前）。
    /// 列は幅を三等分し、押せる高さは 44pt
    private var stats: some View {
        // 板: 3列の等幅。等幅の数字（18）の下に小さい名前（10）
        HStack(alignment: .top, spacing: 8) {
            statCell(value: "\(model.photos.count)", label: L("投稿", "Posts"))
            NavigationLink {
                FollowListView(userId: model.profile?.userId ?? "", kind: .followers)
            } label: {
                statCell(value: "\(model.followers)", label: L("フォロワー", "Followers"))
            }
            .buttonStyle(.plain)
            NavigationLink {
                FollowListView(userId: model.profile?.userId ?? "", kind: .following)
            } label: {
                statCell(value: "\(model.following)", label: L("フォロー中", "Following"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(JPFont.mono(18, relativeTo: .title3))
                .foregroundStyle(Color.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(WebTheme.faint)
        }
        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// 旅の実績（モック2-3）。**訪れた国・地域**と**写真をつないだ距離**を
    /// **小さな1行**で出す（整理案 05c・2026-09-26）。以前は幅いっぱいの
    /// 帯を2本重ねていて、自分の写真が画面の下へ押し出されていた。
    ///
    /// どちらも**数えた値**で、どちらも**そのままの意味ではない**ので、
    /// それぞれ押すと計算の中身が出る。**0 のものは出さない**——
    /// 「訪れた国 0」は実績にならず、「まだ国名を書いていない」を
    /// 「行っていない」と読ませてしまう
    @ViewBuilder
    private var travelRecord: some View {
        let countries = VisitedCountries.count(in: model.photos)
        let km = TravelDistance.total(of: model.photos)
        if countries > 0 || km > 0 {
            HStack(spacing: 14) {
                if countries > 0 {
                    recordItem(label: L("訪れた国・地域", "Countries"), value: "\(countries)") {
                        showCountriesNote = true
                    }
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
                if km > 0 {
                    recordItem(label: L("写真をつないだ距離", "Distance between photos"),
                               value: "\(TravelDistance.formatted(km)) km") {
                        showDistanceNote = true
                    }
                    .alert(L("写真をつないだ距離", "Distance between photos"),
                           isPresented: $showDistanceNote) {
                        Button(Labels.Common.close, role: .cancel) {}
                    } message: {
                        Text(distanceNote)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
    }

    /// 1行の中の1項目。**押せる高さは 44pt**（見た目は小さな字のまま）
    private func recordItem(label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(WebTheme.muted2)
                    // 幅の狭い端末（SE など）で2項目が1行に収まるように、折り返さずに少しだけ縮める
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(JPFont.mono(13, medium: true, relativeTo: .caption))
                    .foregroundStyle(WebTheme.foreground)
            }
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L("数え方を表示", "Shows how this is counted"))
    }

    /// **「旅した距離」とだけ書かない。** 実際に歩いた・乗った距離だと
    /// 読まれる（指示書 8-3）。
    private var distanceNote: String {
        L("撮影地の分かる写真を、古い順に直線で結んだ合計です。実際に歩いた・乗った距離ではありません（道のりではなく直線で、撮っていない区間は飛び、座標は約1kmに丸めてあります）。",
          "The straight-line total between photos that have coordinates, oldest first. Not the distance you actually travelled.")
    }


    /// プロフィールのBGM（モック2-4）。
    ///
    /// **入れている人にだけ出す。** サーバーは前から `songs` を返していて、
    /// アプリが復号していなかっただけだった（⛔ にしていたのは誤り）。
    /// 曲は `MusicPreviewPlayer` に通す——**専用の再生器を作らない**
    /// （画面をまたいだ操作は `MiniPlayerBar` が受け持っている）。
    ///
    /// 板 05c: 高さ 48pt の札（地 白7%・縁 白8%・角丸12）。36pt の絵、
    /// 「曲名 · アーティスト」と「BGM · 30秒の試聴」、右に白い 40pt の再生の丸
    @ViewBuilder
    private func bgmCard(_ profile: UserProfile) -> some View {
        if let song = profile.bgm {
            let playing = player.isPlaying(song.previewURL)
            HStack(spacing: 10) {
                RemoteImage(url: song.artworkURL)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SongSticker.text(for: song) ?? song.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(WebTheme.foreground)
                        .lineLimit(1)
                    Text(L("BGM · 30秒の試聴", "BGM · 30-second preview"))
                        .font(.caption2)
                        .foregroundStyle(WebTheme.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    player.toggle(song.previewURL, song: song)
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .frame(width: 40, height: 40)
                        .background(WebTheme.accentBackground, in: Circle())
                        // 見た目は 40pt、押せる範囲は 44pt
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playing ? L("止める", "Pause") : L("再生", "Play"))
            }
            .padding(.leading, 6)
            .padding(.trailing, 4)
            .frame(minHeight: 48)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 20)
        }
    }

    /// ストーリーハイライト（モック2-5）。
    ///
    /// **サーバーにある本物の輪**（`api-user/src/highlights.ts`）。
    /// 以前はここに「旅の一冊」の丸い並びを出していた——サーバーに
    /// ハイライトが無かったので、いちばん近いものを当てていた。
    /// develop でハイライトそのものが入ったので、本物に差し替える。
    /// **旅の一冊は消していない**（下のタブの「旅の記録」から入る）。
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

    /// 整理案 05c の4つ（投稿 / 旅の記録 / 行きたい場所 / お気に入り）。
    /// **既定の `segmented` を使わない**——黒地の上で帯だけ明るく浮く
    /// 板 05c: 下線の札（印＋名前・13px・高さ 44）。選んでいる札は白い字と
    /// 下の 2pt の白い線、下に白12% の1本線
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.tabs(isMe: true)) { option in
                let selected = tab == option
                Button {
                    tab = option
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.systemImage)
                            .font(.system(size: 13))
                        Text(option.label)
                            .font(.footnote.weight(selected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? Color.white : WebTheme.faint)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(selected ? Color.white : Color.clear)
                            .frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                // 実機の絵の道しるべ（`ScreenshotTests`）。**位置で探させない**
                // ——以前は写真の上の「旅の記録」の札に付けていた
                .accessibilityIdentifier("profile.tab.\(option.rawValue)")
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
        .padding(.horizontal, 16)
    }

    /// 旅の記録（旅の一冊の棚）。**自分の公開写真から**その場でまとめる
    /// ——下書きは旅に入れない（見せていない写真が一冊に紛れ込む）。
    /// 背表紙は `TripShelf`。**旅の一覧の画面（`TripsView`）はここへ畳んだ**
    /// ——入口がマイページの札1つだけだった
    @ViewBuilder
    private var tripsArea: some View {
        let trips = TripBook.trips(from: model.photos.filter { $0.published != false })
        if trips.isEmpty && model.isLoading {
            // **読み込み中に「空」の文言を出さない**（初回は写真がまだ0枚）
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(24)
        } else if trips.isEmpty {
            // **なぜ空なのかを言う**
            Text(L("同じころに撮った写真が2枚たまると、ひとつの旅にまとまります",
                   "Two or more photos taken around the same time become a trip"))
                .font(.footnote)
                .foregroundStyle(WebTheme.faint)
                .frame(maxWidth: .infinity)
                .padding(24)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(trips) { trip in
                    NavigationLink {
                        TripBookView(trip: trip)
                    } label: {
                        TripShelf(trip: trip)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trips.book")
                }
            }
            .padding(.horizontal, 16)
        }
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
                .foregroundStyle(WebTheme.danger)
                .padding(.horizontal, 16)
        }
        if let error = model.errorMessage {
            ErrorBanner(message: error) { Task { await model.load() } }
        } else if tab == .trips {
            // **写真の有無とは無関係に、ここで空の理由まで言う**
            tripsArea
        } else if tab == .wishlist {
            // **写真の有無とは無関係。** 行きたい場所は台帳の話で、
            // 1枚も撮っていない人にも中身がある
            wishlistArea
        } else if model.photos.isEmpty && !model.isLoading {
            // **この文言は「投稿」の話。** 以前はタブの判定より前に
            // 置いてあったので、写真が0枚の人は地図もお気に入りも
            // 「まだ写真がありません」に潰れていた
            ErrorBanner(message: L("まだ写真がありません", "No photos yet"))
        } else if tab == .favorites {
            favoritesArea
        } else {
            LazyVGrid(columns: columns, spacing: 4) {
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
    /// 印は左上（板 05c: ピンは 22pt の黒い丸、下書きは黒い小さな札）
    private func gridCell(_ photo: Photo) -> some View {
        PhotoFrame(photo: photo, corner: 0)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    if model.isPinned(photo.id) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.55), in: Circle())
                            .accessibilityLabel(L("ピン留め中", "Pinned"))
                    }
                    if photo.published == false {
                        Text(L("下書き", "Draft"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6), in: Capsule())
                    }
                }
                .padding(6)
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
         gallery: PublicGalleryService = PublicGalleryService(liveURL: AppConfig.livePhotosURL)) {
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
