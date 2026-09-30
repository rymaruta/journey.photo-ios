import SwiftUI

/// 自分のページ。ログインしていなければログイン画面を出す。
struct MyPageView: View {

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var savedPhotos: SavedPhotosStore
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var toasts: ToastCenter
    @StateObject private var model = MyPageViewModel()
    /// 「行きたい」の台帳のスポットの名前を引く索引（`app/data/spots.json`）。
    /// 取れなければ空——鍵のぶんは slug から起こした名前で行だけ出す
    @State private var officialSpots: [OfficialSpot] = []
    /// 保存した写真を引き当てる先のうち**公開一覧**。もう一方の自分の写真は
    /// `model.photos`（`myPhotos()`・`PhotoPools` と同じ口）。公開一覧が無いと
    /// **他人の写真の保存が一度も出ない**
    @State private var feed: [Photo] = []
    /// 公開一覧を読み終えたか（「まだ」と「0件」を混ぜない）
    @State private var feedLoaded = false
    /// 最後の公開一覧の読み込みが失敗したか（「読み込めませんでした」はこの回だけ）
    @State private var feedFailed = false
    /// 「お気に入り」タブに出す保存の ID。**描画のたびに `savedPhotos.ids` を
    /// 読まない**——詳細でしおりを外した瞬間に `ForEach` から元の
    /// `NavigationLink` が消え、**見ている詳細が閉じる**（`SavedPhotosView`・
    /// `FavoritesView` と同じ理由）。取り直すのは戻ってきたとき・タブを開いたとき・
    /// 引き当て先を読み終えたとき（`refreshSavedIds`）。
    /// 写真の束ではなく ID を控えるのは、投稿を閉じた合図などで `model.photos`
    /// が読み直されても、控えた ID のぶんは引き当て直せるように
    @State private var savedIds: Set<String> = []
    @State private var tab: ProfileTab = .posts
    @State private var showDistanceNote = false
    @State private var showCountriesNote = false
    /// 一度でもこの画面が出たか。**戻ってきた回だけ読み直す**ための印
    @State private var didAppear = false
    /// いまこの画面が出ているか（`onAppear`〜`onDisappear`）。詳細を上に
    /// 積んでいる間もこの画面は `savedPhotos.ids` を購読し続けるので、
    /// **出ていない間は保存の ID を取り込まない**——取り込むと格子の段の ID
    /// （`EditorialLayout.Row.id` は隣の写真まで含む）が変わり、開いている詳細が閉じる
    @State private var isOnScreen = false
    /// お気に入りのタブから落とす「見せない」の写し。**戻ってきたときに取る**
    @State private var dropped = ModerationSnapshot()
    /// 「行きたい場所」の行を作る鍵の写し（`wishlist.spotIds`）。**画面に出ている間だけ
    /// 取り直す**——描くたびに今の集合から作ると、開いたスポットで♥を外した瞬間に
    /// 元の行が消え、そのスポットの画面が閉じる（`savedIds` と同じ形）
    @State private var wishIds: Set<String> = []
    @EnvironmentObject private var hidden: ModerationStore
    /// カバー写真が出せたか（板 05c／出せなければ 05d）。見出しを重ねるかを決める
    @State private var hasCover = false
    /// 下の「投稿」の画面を閉じた合図（`TabRouter.postSheetsClosed`）
    @ObservedObject private var tabRouter = TabRouter.shared

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
            await model.load(for: auth.userId)
        }
        // **外で書き換えたプロフィールを取り直す。** `load()` は走っている間の
        // 2本目を捨てるので、ここはプロフィールだけを読み直す
        .onChange(of: auth.profileRevision) { _, _ in
            let expected = auth.userId
            Task { await model.reloadProfile(expecting: expected) }
        }
        // 保存した写真の引き当て先（公開一覧）
        .task(id: auth.userId) { await loadFeed() }
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
        //
        // 🔴 **画面に出ている間だけ。** 旅の一冊などを上に積んだまま投稿すると、
        // 読み直しで元の行（`Trip.id` は写真の id をつないだもの）が変わるか、
        // 失敗の帯がタブごと差し替えて、開いている画面が閉じる。出ていない回は
        // 戻ってきたとき（`onAppear`）の読み直しが拾う
        .onChange(of: tabRouter.postSheetsClosed) { _, _ in
            guard auth.userId != nil, isOnScreen else { return }
            Task { await model.load(for: auth.userId) }
        }
        .onAppear {
            isOnScreen = true
            // 詳細でしおりを外したぶん・ブロック／通報したぶんは、戻ってきたこの時点で落とす
            refreshSavedIds()
            dropped = hidden.snapshot
            wishIds = wishlist.spotIds
            guard didAppear else { didAppear = true; return }
            guard auth.userId != nil else { return }
            Task { await model.load(for: auth.userId) }
        }
        .onChange(of: tab) { _, next in
            if next == .favorites { refreshSavedIds() }
        }
        .onDisappear { isOnScreen = false }
        // 「見せない」が変わったら、**画面に出ている間だけ**写しを取り直す
        // （詳細を開いている間に取り直すと押した元が消えて閉じる）。人が替わった回も
        // `hidden.use` が数を進めるのでここで拾う——`auth.userId` の変化の時点では
        // まだ前の人の控えのまま
        .onChange(of: hidden.revision) { _, _ in
            if isOnScreen { dropped = hidden.snapshot }
        }
        // 自分の一覧が「公開中」と答えた写真は、消した・非公開にした印を外す
        // （Web や別の端末で公開に戻した写真が、この端末でだけ出なかった）
        .onChange(of: model.serverRead) { _, read in
            guard let read else { return }
            let before = hidden.revision
            hidden.confirmPublished(read.publishedIds, for: read.owner, readStartedAt: read.startedAt)
            // 実際に外したときだけ一覧へ渡す
            if hidden.revision != before {
                Task { await environment.gallery.setHidden(hidden.snapshot) }
            }
        }
        // 「行きたい」も同じ。人が替わった回（`wishlist.use`）もここで拾う
        .onChange(of: wishlist.spotIds) { _, next in
            if isOnScreen { wishIds = next }
        }
        // 起動時の同期（`syncSaves`）が後から届いたぶんは拾う。**増えたときだけ**
        // ——減ったときに取り直すと、詳細でしおりを外した瞬間に詳細が閉じる。
        // **画面に出ている間だけ**（`isOnScreen`）。詳細の上で保存しても
        // 増えるので、そこで取り込むと詳細が閉じる。戻れば `onAppear` が拾う
        .onChange(of: savedPhotos.ids) { _, next in
            guard isOnScreen else { return }
            if next.isSuperset(of: savedIds) { savedIds = next }
        }
        // **人が替わったら前の人のぶんを持ち越さない。** 控えた保存の ID が
        // 前の人のままだと、次の人の ID は上位集合にならず取り込まれない
        // （公開一覧を読み終えるまで前の人の保存が見える）。空にしておけば
        // 次は必ず取り込まれる。自分の写真・公開一覧（フォロワー限定を含む）も
        // 前の人のもので、次の人の読み込みが落ちると引き当て先に残る
        .onChange(of: auth.userId) { _, _ in
            savedIds = []
            feed = []
            feedLoaded = false
            feedFailed = false
            model.forgetPhotos(for: auth.userId)
        }
    }

    private func refreshSavedIds() {
        savedIds = savedPhotos.ids
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
            ZStack(alignment: .top) {
                scroll(topInset: geo.safeAreaInsets.top)
                    .ignoresSafeArea(edges: hasCover ? .top : [])
                // **時計の裏に黒のぼかし**（`TopBarScrim`）。上のバーを出さないので、
                // 流した写真が時計・電池の字の真下を通って字が読めなくなっていた
                TopBarScrim(topInset: geo.safeAreaInsets.top)
            }
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
                // **札と中身は横に払っても切り替わる**（札を押すのと同じ）。
                // 払いを受けるのは札から下だけ——上のハイライトの列は横に流れる
                VStack(alignment: .leading, spacing: 14) {
                    tabPicker
                    photoArea
                }
                .contentShape(Rectangle())
                .simultaneousGesture(tabSwipe)
            }
        }
        .refreshable {
            await model.load(for: auth.userId)
            // 保存した写真の引き当て先（公開一覧）も読み直す。保存の ID は
            // **端末の控えを写すだけ**で、サーバーには聞き直さない——保存の一覧の
            // 読み取りも強い整合でなく（`userList.ts` の `readUserRows`）、外した
            // 直後に入れ替えると外した保存が控えに戻る（いいねで踏んだのと同じ形）。
            // サーバーに合わせるのは起動時・ログイン時の `syncSaves` だけ
            await loadFeed(force: true)
            refreshSavedIds()
        }
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
    /// 編集」、その下に明朝 26 の名前・「@ユーザー名 · (線のピン)居住地」・ひとこと
    private func header(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                RemoteImage(url: profile.avatarURL(cacheBust: model.avatarCacheBust))
                    .frame(width: ProfileCover.avatarSize, height: ProfileCover.avatarSize)
                    .clipShape(Circle())
                    // **板どおり黒の 3pt の縁**（写真の上でも丸が割れない）。
                    // 本人の色の輪（`themeColor`）は板に無いので出さない（人のページも同じ）
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
                        // 画面の見出しは名前（人のページと同じ）
                        .accessibilityAddTraits(.isHeader)
                    VerifiedBadge(isVerified: profile.verified, nameSize: 26, relativeTo: .title, fit: .mincho)
                }
                if let line = ProfileLine.handleAndHome(username: profile.username,
                                                        home: profile.homeLocation) {
                    ProfileHandleLine(line: line, showsPin: true)
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
        .padding(.top, hasCover ? -ProfileCover.avatarOverlap : 49)
    }

    /// 数の並び（板 05c: 投稿・フォロワー・フォロー中の3列・等幅の数字 18 と名前）。
    /// 列は幅を三等分し、押せる高さは 44pt
    private var stats: some View {
        // 板: 3列の等幅。等幅の数字（18）の下に小さい名前（10）
        HStack(alignment: .top, spacing: 8) {
            statCell(value: "\(model.photos.count)", label: L("投稿", "Posts"))
            NavigationLink {
                FollowListView(userId: model.profile?.userId ?? auth.userId ?? "", kind: .followers)
            } label: {
                statCell(value: "\(model.followers)", label: L("フォロワー", "Followers"))
            }
            .buttonStyle(.plain)
            NavigationLink {
                FollowListView(userId: model.profile?.userId ?? auth.userId ?? "", kind: .following)
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
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
        }
        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
        .contentShape(Rectangle())
        // **押せる高さは 44pt のまま、並びの上では字の高さだけ取る**（板: 数の下は
        // すぐ 12pt で旅の実績の行）。44pt で場所を取ると、数と旅の実績の間が
        // 板の倍近く空いていた。押せる範囲は下の旅の実績の行と重ならない量だけ詰める
        .padding(.vertical, -Self.statTapSlack)
        .accessibilityElement(children: .combine)
    }

    /// 数の札の、見た目より外へ押せる範囲を張り出す量（上下それぞれ）
    private static let statTapSlack: CGFloat = 5
    /// 旅の実績の札の同じ量（上下同じ）。数の札の張り出しと足して間の 12pt に収まる量。
    /// **上下で変えない**——変えると、間の「·」（素の字）だけが項目の字とずれる
    private static let recordTapSlack: CGFloat = 6

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
            // 板: 「訪れた国・地域 00 · 写真をつないだ距離 000 km」（12px・間 6px）
            HStack(spacing: 6) {
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
                if countries > 0 && km > 0 {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(WebTheme.faint)
                        .accessibilityHidden(true)
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
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    // 幅の狭い端末（SE など）で2項目が1行に収まるように、折り返さずに少しだけ縮める
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(JPFont.mono(12, relativeTo: .caption))
                    .foregroundStyle(Color.white)
            }
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        // 数の札と同じく、押せる高さは 44pt のまま並びの上では詰める
        .padding(.vertical, -Self.recordTapSlack)
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
    /// 見た目は `ProfileBgmCard`（再生器の見張りを札の中に閉じる）
    @ViewBuilder
    private func bgmCard(_ profile: UserProfile) -> some View {
        if let song = profile.bgm {
            ProfileBgmCard(song: song)
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

    /// お気に入り＝**保存した写真**（板 05c のタブ「お気に入り」・しおりの印・板 35）。
    ///
    /// 以前の中身はいいねした写真で、見出し（英語は "Saved"）と食い違い、
    /// 保存した写真を見返す場所がどこにも無かった（2026-09-26 のキャンバスとの
    /// 突き合わせ 6・8）。いいねした写真はメニューと設定から開く（`FavoritesView`）
    @ViewBuilder
    private var favoritesArea: some View {
        // ブロック・通報した人の写真を落とす（`FavoritesView`・`SavedPhotosView` と同じ）
        // **先に公開一覧を絞ってから引き当てる**（`SavedPhotosView` と同じ順）。引き当ててから
        // 絞ると、公開一覧の古い写しが先に当たって落ち、自分の非公開の写し（新しい方）が
        // 使われずに、非公開にした自分の写真が保存から消えた
        let publicPool = dropped.visible(feed)
        let saved = LikedPhotos.resolve(savedIds, in: [publicPool, model.photos])
        if saved.isEmpty {
            switch LikedPhotos.emptyState(idCount: savedIds.count, loaded: feedLoaded && !model.isLoading,
                                          failed: feedFailed) {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            case .none:
                ErrorBanner(message: SavedPhotosView.emptyMessage)
            case .nothingShown:
                ErrorBanner(message: LikedPhotos.nothingShownMessage)
            case .unresolved:
                ErrorBanner(message: SavedPhotosView.unresolvedMessage) {
                    Task {
                        await loadFeed()
                        await model.load(for: auth.userId)
                    }
                }
            }
        } else {
            // 保存は他人の写真と自分の写真が混ざる。公開一覧から引き当てた写真だけ
            // 個別ページが在る（`LikedPhotos.fromPublicFeed`・`SavedPhotosView` と同じ）
            let isPublic = LikedPhotos.fromPublicFeed(publicPool)
            PhotoGrid(photos: saved) { photo in
                PhotoDetailView(photo: photo, fromPublicFeed: isPublic(photo), context: saved)
            }
        }
    }

    /// 行きたい場所（モック2）。**サーバーの一覧の控え**（`WishlistStore`・`/user/spots`）。
    /// Web の「行きたい場所」と同じ一覧なので、「この端末に覚えています」の注記は外した
    @ViewBuilder
    private var wishlistArea: some View {
        // **撮影地から導いた地点**のうち、「行きたい」に入れたもの。
        // 🔴 **公開一覧（`feed`）と自分の写真を合わせて導く**（`ProfileSections.wishlistPool`）。
        // 「行きたい」は地図などで**他人の写真**から押すのがふつうで、自分の写真だけでは出ない
        // **ブロック・通報した人の写真を外してから導く**（お気に入りと同じ `dropped`）。
        // `feed` が絞られるのは取った時点だけで、その後のブロックも、同期の前に
        // 返った一覧も素通りして、行のサムネに出ていた
        // **自分の写真は落とさない**（`wishlistPool(own:feed:hidden:)`・main 側の決まり）
        let unfiltered = ProfileSections.wishlistPool(feed: feed, mine: model.photos)
        let pool = Self.wishlistPool(own: model.photos, feed: feed, hidden: dropped)
        let wanted = ProfileSections.wantedPlaces(keys: wishIds, pool: pool)
        // 「一部を読み込めませんでした」を数える側は**絞る前**で引く——ブロックした人の
        // 写真にしか無い撮影地は、読み込めていないのではなく見せないだけ
        // （公開一覧の失敗のときしか使わないので、そのときだけ導き直す）
        let reachable = feedFailed
            ? ProfileSections.wantedPlaces(keys: wishIds, pool: unfiltered).count
            : wanted.count
        // 自分の写真の初回が取れていない回も「取れていない」（非公開の写真・一覧に
        // まだ載っていない投稿の撮影地は、公開一覧からは引けない）
        let sourceFailed = feedFailed || model.errorMessage != nil
        // 台帳の撮影スポット（`SPOT-<slug>`）。索引と突き合わせて名前を引く。
        // **索引が無くても行は出す**（`OfficialWishlist`）——スポットの画面で
        // 押した直後に「まだありません」と言わない
        let officialRows = OfficialWishlist.rows(keys: wishIds, index: officialSpots)
        VStack(alignment: .leading, spacing: 10) {
            // **「まだ無い」と「取れていない」を分ける**（`ProfileSections`）。
            // 数えるのは撮影地の行とスポットの行の両方。「取れていない」は
            // **公開一覧の読み込みの失敗**で決める（件数の食い違いでは決めない）
            switch ProfileSections.wishlist(wantedCount: wanted.count + officialRows.count,
                                            savedIdCount: wishIds.count,
                                            // 読み直しのたびに輪へ戻さない（一度読めたら「読めた」）
                                            loaded: feedLoaded && model.hasLoadedPhotos,
                                            sourceFailed: sourceFailed) {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            case .couldNotLoad:
                ErrorBanner(message: L("写真の一覧を取れませんでした。通信を確かめて、引き下げて読み直してください",
                                       "Couldn't load the photos. Pull to refresh."))
            case .empty:
                ErrorBanner(message: L("まだありません。スポットの画面で「行きたい」を押すとここに並びます",
                                       "Nothing yet. Tap “Want to go” on a place."))
            case .list:
                // 公開一覧の失敗のときだけ（自分の写真の失敗は上の一行が既に言う）
                if ProfileSections.wishlistPartlyMissing(shownCount: reachable + officialRows.count,
                                                         savedIdCount: wishIds.count,
                                                         sourceFailed: feedFailed) {
                    Text(L("一部の場所を読み込めませんでした。引き下げて読み直してください",
                           "Some places couldn't be loaded. Pull to refresh."))
                        .font(.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .padding(.horizontal, 16)
                }
                ForEach(wanted) { place in
                    NavigationLink {
                        SpotDetailView(spot: place, photos: pool)
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
                // ログイン中はサーバーからも外す。失敗したら戻して知らせる（`WishlistSync`）
                Task {
                    let outcome = await WishlistSync.set(row.key, wanted: false, store: wishlist,
                                                         service: environment.savedSpots)
                    if let notice = WishlistSync.removalNotice(for: outcome) {
                        toasts.show(notice.text, kind: notice.kind)
                    }
                }
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
                // ログイン中はサーバーからも外す。失敗したら戻して知らせる（`WishlistSync`）
                Task {
                    let outcome = await WishlistSync.set(spot.slug, wanted: false, store: wishlist,
                                                         service: environment.savedSpots)
                    if let notice = WishlistSync.removalNotice(for: outcome) {
                        toasts.show(notice.text, kind: notice.kind)
                    }
                }
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
    /// 見た目は人のページと同じ下線の札（`ProfileTabBar`）
    private var tabPicker: some View {
        ProfileTabBar(tabs: ProfileTab.tabs(isMe: true), selection: $tab)
    }

    /// 横の払いでタブを切り替える。**`simultaneousGesture` で付ける**——`gesture` に
    /// すると縦のスクロールと写真を押す操作を奪う。判定は `ProfileTab.swiped`
    /// （はっきり横に動いたときだけ・端で回り込まない）
    private var tabSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard let next = ProfileTab.swiped(from: tab, in: ProfileTab.tabs(isMe: true),
                                                   dx: Double(value.translation.width),
                                                   dy: Double(value.translation.height))
                else { return }
                tab = next
            }
    }

    /// 旅の記録（旅の一冊の棚）。**自分の公開写真から**その場でまとめる
    /// ——下書きは旅に入れない（見せていない写真が一冊に紛れ込む）。
    /// 棚は `TripShelfList`。**旅の一覧の画面（`TripsView`）はここへ畳んだ**
    /// ——入口がマイページの札1つだけだった
    @ViewBuilder
    private var tripsArea: some View {
        let trips = TripBook.shelfTrips(from: model.photos)
        if trips.isEmpty && model.isLoading {
            // **読み込み中に「空」の文言を出さない**（初回は写真がまだ0枚）
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(24)
        } else {
            // 背表紙の列と説明文は `TripShelfList`（旅の側の部品）
            // 公開一覧に載っている写真だけ個別ページが在る（`LikedPhotos.fromPublicFeed`）
            TripShelfList(trips: trips, isPublic: LikedPhotos.fromPublicFeed(dropped.visible(feed)))
        }
    }

    /// 「行きたい」の地点を導く写真の集まり。自分の写真を先に、公開一覧を後に
    /// 並べ、**同じ写真は1枚に数える**（両方に載る自分の公開写真で枚数が倍にならない）。
    /// **公開一覧はブロックした人・非表示にした写真を落とす**——落とさないと、
    /// その写真が地点の代表（表紙）になって画面に出る。自分の写真は落とさない
    /// 寄せ方（ID で1枚・自分の写真が先）は `ProfileSections.wishlistPool` の1本に任せる
    nonisolated static func wishlistPool(own: [Photo], feed: [Photo],
                                         hidden: ModerationSnapshot) -> [Photo] {
        ProfileSections.wishlistPool(feed: hidden.visible(feed), mine: own)
    }

    /// 保存した写真の引き当て先（公開一覧）を読む。取れなくても自分の写真の分は出せる。
    /// 自分の写真（`model.photos`）の失敗は `model.errorMessage` が知らせる（手元に無ければタブごと）
    private func loadFeed(force: Bool = false) async {
        let fetched = try? await environment.gallery.fetchPhotos(force: force)
        guard !Task.isCancelled else { return }
        feedFailed = fetched == nil
        feed = fetched ?? feed
        feedLoaded = true
        refreshSavedIds()
    }

    @ViewBuilder
    private var photoArea: some View {
        // **読み直しの失敗は、格子の上に再試行つきで出す**（格子は残す）
        if let reloadError = model.reloadError {
            ErrorBanner(message: reloadError) { Task { await model.load(for: auth.userId) } }
        }
        if let action = model.actionMessage {
            // **一覧の代わりではなく、一覧に添える。**
            Text(action)
                .font(.footnote)
                .foregroundStyle(WebTheme.danger)
                .padding(.horizontal, 16)
        } else if tab == .wishlist || tab == .favorites, let error = model.errorMessage {
            // この2つは読み込みの失敗で覆わないが、**自分の写真から導くぶん**
            // （撮影地の地点・自分の非公開写真の保存）は欠けるので、一行添える
            Text(error)
                .font(.footnote)
                .foregroundStyle(WebTheme.danger)
                .padding(.horizontal, 16)
        }
        // **一度読めた中身は、読み直しの失敗で消さない。** 詳細から戻るたびに
        // 読み直すので、一瞬の圏外で格子・旅の記録・保存した写真まで
        // 知らせ1枚に置き換わっていた。読み直しの失敗はモデルが上の
        // `reloadError`（格子の上の知らせ）に入れる。`errorMessage` は
        // **一度も写真を読めていない回だけ**で、そのときだけ欄ごと知らせに替える。
        // **行きたい場所・お気に入りは自分の写真の読み込みと無関係**なので、
        // その失敗の知らせで覆わない（以前は端末だけで出せるタブまで知らせに置き換わっていた）
        if tab == .wishlist {
            // **写真の有無とは無関係。** 行きたい場所は台帳の話で、
            // 1枚も撮っていない人にも中身がある
            wishlistArea
        } else if tab == .favorites {
            // **写真の有無とは無関係。** 保存は他人の写真にもする
            favoritesArea
        } else if let error = model.errorMessage {
            ErrorBanner(message: error) { Task { await model.load(for: auth.userId) } }
        } else if tab == .trips {
            // **写真の有無とは無関係に、ここで空の理由まで言う**
            tripsArea
        } else if model.photos.isEmpty && !model.isLoading && model.reloadError == nil
                    && model.hasLoadedPhotos {
            // 一度も読めていない回（初回が知らせ無しで取り消された）には言わない
            // 読み直しに失敗した回は上の知らせ1枚だけ（「読めなかった」と
            // 「まだ無い」を2枚重ねて出さない）
            // **この文言は「投稿」の話。** 以前はタブの判定より前に
            // 置いてあったので、写真が0枚の人は地図もお気に入りも
            // 「まだ写真がありません」に潰れていた
            ErrorBanner(message: L("まだ写真がありません", "No photos yet"))
        } else {
            let multiple = PhotoGroups.multiPhotoIds(model.photos)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(model.photos) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo, fromPublicFeed: false, context: model.photos)
                    } label: {
                        gridCell(photo, multiple: multiple.contains(photo.id))
                    }
                    .buttonStyle(.plain)
                    // 何の写真か（題）を名前に、印（ピン・下書き・複数枚）を値にして読む。
                    // 名前だけ差し替えると中の印が読まれなくなる
                    .accessibilityLabel(photo.accessibilityText)
                    .accessibilityValue(ProfileLine.gridState(
                        pinned: model.isPinned(photo.id),
                        draft: photo.published == false,
                        multiple: multiple.contains(photo.id)))
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
    /// 印は左上（板 05c: ピンは 22pt の黒い丸、下書きは黒い小さな札）、
    /// 複数枚の投稿は右上。**印は読み上げない**（格子の1枚の値として読む）
    private func gridCell(_ photo: Photo, multiple: Bool) -> some View {
        PhotoFrame(photo: photo, corner: 0)
            .overlay(alignment: .topTrailing) {
                if multiple {
                    Image(systemName: "square.on.square")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .shadow(radius: 3)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    if model.isPinned(photo.id) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.55), in: Circle())
                            .accessibilityHidden(true)
                    }
                    if photo.published == false {
                        Text(L("下書き", "Draft"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6), in: Capsule())
                            .accessibilityHidden(true)
                    }
                }
                .padding(6)
            }
    }
}

@MainActor
final class MyPageViewModel: ObservableObject {

    @Published private(set) var profile: UserProfile?
    /// プロフィールを取りに行った順の番号と、いま出ている値の番号。
    /// **後から出した要求の答えだけが勝つ**——ログイン直後の `load()` は表示名の
    /// PUT より前に出るので、あとで返っても `reloadProfile` の答えを上書きしない。
    /// 失敗した要求は番号を進めない（残った印で良い答えを捨てない）
    private var profileRequestSeq = 0
    /// いまの人（`load(for:)`・`forgetPhotos(for:)` が入れる）
    private var activeUser: String?
    /// 人が替わった回数（`forgetPhotos`）。走っている読み込みの答えを捨てる目印
    private var generation = 0
    private var shownProfileSeq = 0
    /// 留めている写真。**サーバーが返した一覧をそのまま持つ**
    /// （増減の結果は向こうが決める——3枚の上限も、消えた写真の掃除も）
    @Published private(set) var pinnedIds: [String] = []
    @Published private(set) var photos: [Photo] = []
    /// **サーバーから読めた**自分の写真（公開中の id と、取りに行った時刻）。
    /// 画面はこれで「消した・非公開にした」印を外す（`ModerationStore.confirmPublished`）。
    /// `photos` の変化で見ない——ピン留めの並べ替えでも変わり、読み直しに失敗した古い
    /// 一覧で印を外していた
    struct ServerRead: Equatable {
        /// 答えの持ち主（受け取った時点の `auth.userId` ではなく、取りに行った人）
        let owner: String?
        let publishedIds: [String]
        let startedAt: Date
    }
    @Published private(set) var serverRead: ServerRead?
    @Published private(set) var isLoading = false
    /// **読み込みに失敗した**。画面はこの時だけ一覧の代わりに知らせを出す。
    @Published var errorMessage: String?
    /// **操作が断られた**（ピン留めの上限など）。一覧は出したまま添える。
    ///
    /// 読み込みの失敗と混ぜると、ピン留めを断られた瞬間に写真グリッドごと
    /// 知らせに差し替わり、**解除する長押しメニューまで消える**——
    /// 断られた人が直す手立てを画面から奪ってしまう。
    @Published var actionMessage: String?
    /// **一度読めた後の読み直しの失敗。** 格子の上に再試行つきの知らせを出す
    /// （格子は消さない）。`actionMessage`（ピン留めの断り）とは分ける——
    /// 同じ欄だと、ピン留めが通った瞬間に読み直しの失敗の知らせまで消えていた
    @Published private(set) var reloadError: String?

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

    /// 画面から呼ぶ読み込み。**誰の画面かを渡す。** 人が替わっていたら、
    /// ここで前の人のぶんを手放してから読む——`.onChange(of: userId)` と
    /// `.task(id: userId)` のどちらが先に走っても同じ結果になるように。
    /// ログインしていなければ何もしない
    func load(for userId: String?) async {
        guard let userId else { return }
        if userId != activeUser { forgetPhotos(for: userId) }
        await load()
    }

    func load() async {
        // **2本同時に走らせない。** タブの出入りでは `.task(id:)` と
        // `.onAppear` の両方が走ることがあり、`defer` で片方が先に
        // `isLoading` を解くと、もう片方の途中で「まだ写真がありません」が
        // 一瞬出る。片方が失敗すれば知らせに差し替わる
        guard !isLoading else { return }
        // この回の世代。**人が替わる（`forgetPhotos`）たびに進む**ので、
        // 替わった後に返った答えは何も入れない（A → ログアウト → A でも別の世代）
        let gen = generation
        isLoading = true
        let startedAt = Date()
        // 取り消された回に戻す（先に消したまま抜けると、写真0枚の欄に
        // 「まだ写真がありません」と嘘が出ていた）
        let previousError = errorMessage
        errorMessage = nil
        // 人が替わった後に返った回は、次の人の「読み込み中」を解かない
        defer { if gen == generation { isLoading = false } }
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
            await loadPublicly(userId: previewId, gen: gen)
            return
        }
        do {
            profileRequestSeq += 1
            let seq = profileRequestSeq
            async let profile = self.profiles.myProfile()
            async let photos = self.photoService.myPhotos()
            let loaded = try await profile
            // 🔴 **返ってくる間に人が替わっていたら、何も入れない。**
            // `onAppear` などの Task は人が替わっても止まらず、`forgetPhotos` で
            // 空にした後に前の人の写真（非公開を含む）・名前が入っていた
            guard gen == generation else { return }
            // **途中で外から書き換わったら、古い方で上書きしない**
            // （ログイン直後の表示名: この読み込みが PUT より前に出て後に返る）
            if seq > shownProfileSeq || self.profile == nil {
                self.profile = loaded
                shownProfileSeq = seq
            }
            // **フォロー数は写真と並べて取り、写真を待たせない。** 写真だけ落ちた回も
            // 名前・アイコン・フォロー数は出す（写真の欄だけが知らせになる）。
            // 数を写真の後ろに置くと写真の失敗で「0」と出る（a5259c0）、
            // 数を待ってから写真を入れると格子が往復1回ぶん遅れる（3ecb6a5）
            async let stats = self.followStatsIfAny(self.profile?.userId)
            var photosOutcome: Result<[Photo], Error>
            do {
                photosOutcome = .success(try await photos)
            } catch {
                photosOutcome = .failure(error)
            }
            if case .success(let loadedPhotos) = photosOutcome, gen == generation {
                // 自分のページでも、留めた写真は先頭（他人から見えている並びと揃える）
                self.pinnedIds = self.profile?.pinnedPhotoIds ?? []
                self.photos = PhotoPinning.pinnedFirst(loadedPhotos, pinned: self.pinnedIds)
                hasLoadedPhotos = true
                serverRead = ServerRead(owner: activeUser, publishedIds: loadedPhotos.filter { $0.published != false }.map(\.id),
                                        startedAt: startedAt)
            }
            let loadedStats = await stats
            guard gen == generation else { return }
            if let loadedStats {
                self.followers = loadedStats.followers
                self.following = loadedStats.following
            }
            _ = try photosOutcome.get()
        } catch is CancellationError {
            // 取り消された（画面を離れた・引き下げの途中で描き直された）。失敗と言わない
            // （読めたとも言わない——読み直しの失敗の知らせは残す）
            if gen == generation, errorMessage == nil { errorMessage = previousError }
            return
        } catch {
            // 人が替わった後に返った失敗は、次の人の画面に出さない
            guard gen == generation else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? Labels.Common.loadFailed
            // **一度読めていれば、読み直しの失敗は一覧に添える。** 戻ってくるたびに
            // 読み直すので、圏外で写真を開いて戻っただけで格子ごと知らせに置き換わっていた
            if hasLoadedPhotos {
                reloadError = message
            } else {
                errorMessage = message
            }
            return
        }
        // 読み直しの失敗の知らせは、次に読めたら消す
        reloadError = nil
    }


    /// フォロー数。**取れなければ nil**（数は 0 のまま・画面は出す）
    private func followStatsIfAny(_ userId: String?) async -> SocialService.FollowStats? {
        guard let userId else { return nil }
        let stats = try? await social.followStats(userId: userId)
        return stats
    }

    /// 自分の写真を**一度でも読めたか**。`profile` では決めない——プロフィールは写真より
    /// 先に入るので、初回に写真だけ落ちた回を「読めている」と取り違え、格子に
    /// 「まだ写真がありません」と嘘を出していた
    private(set) var hasLoadedPhotos = false

    /// 鍵を持たない回の読み込み（`PreviewSession` のときだけ通る）。
    ///
    /// **`myPhotos()` を使わない**——あれは下書きまで返す代わりに鍵が要る。
    /// ここは公開されているぶんだけで足りる。
    private func loadPublicly(userId: String, gen: Int) async {
        let publicProfile = try? await self.profiles.publicProfile(userId: userId)
        guard gen == generation else { return }
        self.profile = publicProfile
        self.pinnedIds = publicProfile?.pinnedPhotoIds ?? []
        let all = try? await self.gallery.fetchPhotos()
        if let all, gen == generation {
            let mine = all.filter { ($0.userId ?? $0.uploadedBy) == userId }
            self.photos = PhotoPinning.pinnedFirst(mine, pinned: self.pinnedIds)
            hasLoadedPhotos = true
        } else if all == nil, !Task.isCancelled, gen == generation, !hasLoadedPhotos {
            // 取れなかった回を言う（言わないと「読めた」にも「失敗」にもならず、輪のまま残る）
            errorMessage = Labels.Common.loadFailed
        }
        let stats = try? await self.social.followStats(userId: userId)
        if let stats, gen == generation {
            self.followers = stats.followers
            self.following = stats.following
        }
    }

    /// 人が替わったとき、前の人の写真を手放す。次の人の読み込みが落ちても、
    /// 前の人の写真（非公開を含む）が保存の引き当て先に残らないように。
    /// **見出し（名前・アイコン・カバー）とフォロー数も手放す**——フォロー数は
    /// 取れなかった回に上書きしないので、残すと前の人の数が次の人の数として出る
    /// - Parameter newUser: 次の人。**走っている前の人の読み込みの答えを捨てる**目印になる。
    ///   読み込み中の印も解く——解かないと、次の人の最初の読み込みが
    ///   「走っている」と見て何もせずに帰る
    ///   **同じ人のままなら何もしない**——`.task(id:)` の読み込みが先に走って
    ///   いた場合に、その回を捨ててしまわないように
    func forgetPhotos(for newUser: String? = nil) {
        if let newUser, newUser == activeUser { return }
        activeUser = newUser
        generation += 1
        isLoading = false
        photos = []
        pinnedIds = []
        profile = nil
        followers = 0
        following = 0
        errorMessage = nil
        // 前の人あての知らせ（読み直しの失敗・ピン留めの断り）も残さない
        actionMessage = nil
        reloadError = nil
        hasLoadedPhotos = false
        // 前の人の「公開中」の答えも手放す
        serverRead = nil
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

    /// プロフィールだけ読み直す（`AuthStore.profileRevision`）。**失敗したら今のまま。**
    /// 返ってくる間に人が替わっていたら捨てる（前の人の名前・アイコンを出さない）
    func reloadProfile(expecting userId: String?) async {
        guard let userId, userId == activeUser else { return }
        let gen = generation
        profileRequestSeq += 1
        let seq = profileRequestSeq
        let fresh = try? await profiles.myProfile()
        guard let fresh, fresh.userId == userId, gen == generation, seq > shownProfileSeq else { return }
        profile = fresh
        shownProfileSeq = seq
    }
}
