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
    /// 引き下げ・「もう一度試す」の読み直しの最中（重ねて走らせない）
    @State private var isReloading = false
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
    /// 一度でもこの画面が出たか。**戻ってきた回だけ読み直す**ための印
    @State private var didAppear = false
    /// いまこの画面が出ているか（`onAppear`〜`onDisappear`）。詳細を上に
    /// 積んでいる間もこの画面は `savedPhotos.ids` を購読し続けるので、
    /// **出ていない間は保存の ID を取り込まない**——取り込むと格子の段の ID
    /// （`EditorialLayout.Row.id` は隣の写真まで含む）が変わり、開いている詳細が閉じる
    @State private var isOnScreen = false
    /// お気に入りのタブから落とす「見せない」の写し。**前面が確定したときだけ取る**
    @State private var dropped = ModerationSnapshot()
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?
    /// 「行きたい場所」の行を作る鍵の写し（`wishlist.spotIds`）。**画面に出ている間だけ
    /// 取り直す**——描くたびに今の集合から作ると、開いたスポットで♥を外した瞬間に
    /// 元の行が消え、そのスポットの画面が閉じる（`savedIds` と同じ形）
    @State private var wishIds: Set<String> = []
    @EnvironmentObject private var hidden: ModerationStore
    /// カバー写真が出せたか（板 05c／出せなければ 05d）。見出しを重ねるかを決める
    @State private var hasCover = false
    /// カバーが**無いと確かめられた**（HEAD が「無い」と答えた）。真鍮の額縁を出す（#304・板 52）。読み込み中・分からないときは false。
    /// 2026-10-18 見直し: 絵を読めなかっただけ（圏外など）では出さない——カバーがある人に「ここにあなたの1枚」を見せない
    @State private var coverMissing = false
    /// 額縁を出しているか（見本の `-JPPreviewNoCover` では、カバーがあっても額縁で撮る）
    private var showsCoverFrame: Bool { PreviewSession.forcesNoCover || (coverMissing && !hasCover) }
    /// 帯（カバーか額縁）の下端にアイコンを重ねる並びにするか
    private var bandShown: Bool { hasCover || showsCoverFrame }
    /// 下の「投稿」の画面を閉じた合図（`TabRouter.postSheetsClosed`）
    @ObservedObject private var tabRouter = TabRouter.shared
    /// 旅のトランクの口が在るか（無い間は入口を出さない・2026-10-17）
    @ObservedObject private var trunkAvailability = TrunkAvailability.shared
    @State private var trunkForeground = TrunkForegroundGate()
    @Environment(\.scenePhase) private var scenePhase
    /// 端末の写真の一冊（旅の記録のタブ・2026-10-16）
    @ObservedObject private var deviceTrips = DeviceTripShelfStore.shared
    /// 名前の横の画面（名前の行を押すと開く・板 BadgePicker）
    @State private var showNameSide = false
    /// 画面写真の試験だけの Pro の案内（`PreviewSession.opensPaywall`）。出したか・出ているか
    @State private var previewPaywallShown = false
    @State private var showPreviewPaywall = false
    /// 明朝 26 の名前の行の高さの見込み（文字サイズの設定で伸びる）
    @ScaledMetric(relativeTo: .title) private var nameLineHeight: CGFloat = 36

    /// 板 v2 MyPage: 3列・隙間 2pt・縦長 4:5・角なし（`ProfileV2`）
    private let columns = ProfileV2.gridItems

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
        // 自分の一覧の絞った写真は期限つきの URL（`/user/photos` が署名する）。期限切れで
        // 割れたら読み直して新しい URL をもらう（2026-10-18・札 #294・`SignedImageExpiry`）
        .task(id: auth.userId) {
            guard auth.userId != nil else { return }
            var gate = SignedImageRefetchGate()
            for await url in SignedImageExpiry.signals() {
                // **この画面の写真のときだけ**・15秒に1回まで（ホームの1枚でマイページを読み直さない）
                guard model.photos.containsImageURL(url), gate.shouldRefetch(after: url, now: Date()) else { continue }
                await model.load(for: auth.userId)
            }
        }
        // **外で書き換えたプロフィールを取り直す。** `load()` は走っている間の
        // 2本目を捨てるので、ここはプロフィールだけを読み直す
        .onChange(of: auth.profileRevision) { _, _ in
            let expected = auth.userId
            Task { await model.reloadProfile(expecting: expected) }
        }
        // 保存した写真の引き当て先（公開一覧）
        .task(id: auth.userId) { await loadFeed() }
        .task(id: auth.userId) { await trunkAvailability.refresh(userId: auth.userId, service: environment.trunk) }
        // 前面に戻ったときは間を空けずに確かめ直す（`TrunkAvailabilityRule.recheckInterval` の注記）。
        // 2026-10-18: **裏から戻ったときだけ**（通知センター・Face ID からの戻りでは読まない・`TrunkForegroundGate`）。
        // 読めた中身は入口の札の数にも入る（`TrunkEntryStore.read`・1回で両方）
        .onChange(of: scenePhase) { _, phase in
            if trunkForeground.shouldRecheck(isBackground: phase == .background, isActive: phase == .active) {
                Task { await trunkAvailability.refresh(userId: auth.userId, service: environment.trunk, force: true) }
            }
        }
        // 「行きたい」のスポットの名前を引く索引。**取れなくても行は出る**
        .task(id: auth.userId) {
            guard auth.userId != nil else { return }
            officialSpots = (try? await environment.spots.fetchIndex()) ?? officialSpots
        }
        // 「行きたい」のスポットの詳細（行の写真・地図の札）。分けた置き場の索引だけの行のときだけ読む
        // （`SpotDetailNeeds`・2026-10-07）
        .task(id: SpotDetailNeeds.key(SpotDetailNeeds.wished(wishIds, spots: officialSpots))) {
            let needs = SpotDetailNeeds.wished(wishIds, spots: officialSpots)
            guard !needs.isEmpty else { return }
            let merged = await environment.spots.withDetails(officialSpots, for: needs)
            guard !Task.isCancelled else { return }
            officialSpots = merged
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
            // 上げた写真は読み直しを待たずに先に並べる（索引が遅れて返らないことがある・`PostedPhotos`）
            model.showPosted(tabRouter.lastPosted, for: auth.userId)
            Task { await model.load(for: auth.userId) }
        }
        .onAppear {
            switch front.appear() {
            case .first:
                landOnScreen(reload: false)
                didAppear = true
            case .returning:
                // スワイプ途中で絞り／読み直しすると押した元が消えて詳細が閉じる
                frontSettle?.cancel()
                frontSettle = Task {
                    try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                    guard !Task.isCancelled, front.confirm() else { return }
                    landOnScreen(reload: true)
                }
            }
        }
        .onChange(of: tab) { _, next in
            if next == .favorites { refreshSavedIds() }
        }
        .onDisappear {
            frontSettle?.cancel()
            frontSettle = nil
            front.disappear()
            isOnScreen = false
        }
        // 名前の横の画面。決めたら `auth.noteProfileChanged()` が上の読み直しを起こす
        .sheet(isPresented: $showNameSide) {
            if let profile = model.profile {
                NameSideBadgeView(profile: profile)
            }
        }
        // 画面写真の試験だけの Pro の案内（`PreviewSession.opensPaywall`・Debug のみ・1度だけ）
        .fullScreenCover(isPresented: $showPreviewPaywall) { PaywallView() }
        .task {
            guard PreviewSession.opensPaywall, !previewPaywallShown else { return }
            previewPaywallShown = true
            showPreviewPaywall = true
        }
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

    /// 前面確定後: 写し・保存 ID・必要なら読み直し
    private func landOnScreen(reload: Bool) {
        isOnScreen = true
        // 詳細でしおりを外したぶん・ブロック／通報したぶんは、戻ってきたこの時点で落とす
        refreshSavedIds()
        dropped = hidden.snapshot
        wishIds = wishlist.spotIds
        guard reload, auth.userId != nil else { return }
        Task { await model.load(for: auth.userId) }
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
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(WebTheme.foreground)
                .padding(JPSpace.s)
                // v2 の札（#0E0E0F・白 8% の縁・角 14）。白 7% の札から寄せた
                .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
                .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, ProfileV2.gutter)
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
                                ProfileCover(url: PreviewSession.forcesNoCover ? nil
                                                : profile.coverURL(cacheBust: ProfileImageVersions.shared.token(for: profile.userId)),
                                             reserve: hasCover) { loaded in
                                    hasCover = loaded
                                    coverMissing = false
                                    guard !loaded else { return }
                                    let uid = profile.userId
                                    Task {
                                        let exists = await ProfileImageFromPhoto.exists(userId: uid, kind: .cover)
                                        // 待つ間に人が替わった・絵が出た回は使わない
                                        guard model.profile?.userId == uid, !hasCover else { return }
                                        coverMissing = CoverFrameRule.shows(exists: exists)
                                    }
                                }
                                // カバーが無ければ、帯の場所に真鍮の額縁（自分のページだけ・板 52）
                                if showsCoverFrame { CoverFrameBand() }
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
                        // 旅のトランクの入口（2026-10-18）。読み込み・状態・見た目は部品の側（`TrunkProfileChip`）
                        if TrunkEntryRule.shows(signedIn: auth.userId != nil, available: trunkAvailability.isAvailable) {
                            TrunkProfileChip(ownerName: model.profile?.name)
                        }
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
                // アルバムと旅行プランは下の「旅の記録」のタブの札（`tripToolsCard`）
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
        .refreshable { await reloadAll() }
    }

    /// 引き下げ・「もう一度試す」の読み直し。**重ねて走らせない**（続けて押すと古い回が
    /// 新しい回を上書きした・2026-10-02 のレビュー）
    private func reloadAll() async {
        guard !isReloading else { return }
        isReloading = true
        defer { isReloading = false }
        await model.load(for: auth.userId)
        // 保存した写真の引き当て先（公開一覧）も読み直す。保存の ID は
        // **端末の控えを写すだけ**で、サーバーには聞き直さない——保存の一覧の
        // 読み取りも強い整合でなく（`userList.ts` の `readUserRows`）、外した
        // 直後に入れ替えると外した保存が控えに戻る（いいねで踏んだのと同じ形）。
        // サーバーに合わせるのは起動時・ログイン時の `syncSaves` だけ
        await loadFeed(force: true)
        refreshSavedIds()
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
        .padding(.trailing, JPSpace.s)
        .accessibilityLabel(L("設定", "Settings"))
    }

    /// 見出し（板 v2 MyPage・MyPageNoCover）。
    ///
    /// - **カバーがある人**: 88pt のアイコン（黒い 4pt の縁）をカバーの下端に 44pt 重ね、右に
    ///   「プロフィールを編集」。その下に明朝 26 の名前・「@ユーザー名 · (線のピン)居住地」・ひとこと
    /// - **カバーが無い人**（板 MyPageNoCover）: 帯も灰色の空き地も置かず、72pt のアイコンと名前・
    ///   @ユーザー名を**横に並べて上を詰める**。編集は数の並びの右へ（`stats`）
    private func header(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            if bandShown {
                HStack(alignment: .bottom) {
                    avatar(profile, side: ProfileCover.avatarSize)
                        // **板どおり黒の縁**（写真の上でも丸が割れない）。
                        // 本人の色の輪（`themeColor`）は板に無いので出さない（人のページも同じ）
                        .coverCutout(true)
                    Spacer(minLength: 8)
                    editLink(short: false)
                }
                VStack(alignment: .leading, spacing: JPSpace.xxs) {
                    nameLine(profile)
                    handleLine(profile)
                    aboutLines(profile)
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    avatar(profile, side: ProfileCover.compactAvatarSize)
                    VStack(alignment: .leading, spacing: 2) {
                        nameLine(profile)
                        handleLine(profile)
                    }
                    // 右上の設定の丸に名前が潜らない
                    Spacer(minLength: WebTheme.minTapTarget)
                }
                aboutLines(profile)
            }
        }
        .padding(.horizontal, ProfileV2.gutter)
        // カバーがあればアイコンを下端に重ねる（板 v2: 196pt の帯に 88pt の丸を 44pt）。
        // 無ければ右上の設定の丸の高さから（板 MyPageNoCover・丸と並ぶ）
        .padding(.top, bandShown ? -ProfileCover.avatarOverlap : 0)
    }

    private func avatar(_ profile: UserProfile, side: CGFloat) -> some View {
        RemoteImage(url: profile.avatarURL(cacheBust: ProfileImageVersions.shared.token(for: profile.userId)))
            .frame(width: side, height: side)
            .background(WebTheme.card)
            .clipShape(Circle())
    }

    @ViewBuilder
    private func handleLine(_ profile: UserProfile) -> some View {
        if let line = ProfileLine.handleAndHome(username: profile.username,
                                                home: profile.homeLocation) {
            ProfileHandleLine(line: line, showsPin: true)
        }
    }

    /// ひとこと。**持っているのに一度も出していなかった**。v2: 本文 15・text-2・行間 1.7
    private func aboutLines(_ profile: UserProfile) -> some View {
        ForEach(ProfileLine.about(status: profile.statusText, bio: profile.bio), id: \.self) { text in
            Text(text)
                .font(JPFont.body)
                .lineSpacing(6)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, JPSpace.xxs)
        }
    }

    /// 「プロフィールを編集」。カバーが無い人は数の並びの右に短く「編集」（板 MyPageNoCover）。
    /// どちらも同じ目印（画面写真の試験が「読み込みが済んだ」の印に待つ）
    private func editLink(short: Bool) -> some View {
        NavigationLink { ProfileEditView() } label: {
            // v2: 線の副ボタン（白 14% の縁・見た目 36・当たり 44・`ProfileOutlinePill`）
            ProfileOutlinePill(title: short ? L("編集", "Edit") : L("プロフィールを編集", "Edit profile"))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("プロフィールを編集", "Edit profile"))
        // 実機の絵の道しるべ（見出しが描けた＝読み込みが済んだ目印）
        .accessibilityIdentifier("mypage.edit")
    }

    /// 名前の行（板 05c・BadgePicker）: 明朝 26 の名前 → 公式の封印 → Pro マーク → 選んだバッジ。
    /// **行ごと押すと名前の横の画面**（バッジを選ぶ・Pro マークの形を選ぶ）。押せる高さは 44pt、
    /// 並びの上では今までの行の高さのまま（上下に張り出す）
    private func nameLine(_ profile: UserProfile) -> some View {
        Button { showNameSide = true } label: {
            HStack(spacing: 4) {
                Text(profile.name)
                    .font(JPFont.screenTitle)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                NameMarks(profile: profile, nameSize: 26, relativeTo: .title, fit: .mincho, showsBadge: true)
            }
            .frame(minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
            .padding(.vertical, -nameTapSlack)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MyPageNameLine.label(profile))
        .accessibilityHint(L("名前の横のバッジを選ぶ", "Choose the badge next to your name"))
        // 画面の見出しは名前（人のページと同じ）
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("mypage.nameLine")
    }

    /// 名前の行の、見た目より外へ押せる範囲を張り出す量（上下それぞれ）。
    /// **44pt に足りない分だけ**張り出し、並びの高さは変えない。明朝 26 の行は既定の文字の
    /// 大きさで約 36pt（実機で測っていない）。文字を大きくして行が 44pt を超えたら張り出さない
    /// ——超えても張り出すと、下の「@ユーザー名」の行に重なる
    private var nameTapSlack: CGFloat { max(0, (WebTheme.minTapTarget - nameLineHeight) / 2) }

    /// 数の並び（板 05c: 投稿・フォロワー・フォロー中の3列・数字（`JPFont.statNumber`）と名前）。
    /// 列は幅を三等分し、押せる高さは 44pt
    private var stats: some View {
        // 板 v2: カバーがあれば3列の等幅。無ければ左に詰めて間 24・右に「編集」（MyPageNoCover）
        HStack(alignment: bandShown ? .top : .center, spacing: bandShown ? JPSpace.xs : JPSpace.xl) {
            statCell(value: ProfileLine.statValue(model.photoCount), label: L("投稿", "Posts"))
            NavigationLink {
                FollowListView(userId: model.profile?.userId ?? auth.userId ?? "", kind: .followers)
            } label: {
                statCell(value: ProfileLine.statValue(model.followerCount), label: L("フォロワー", "Followers"))
            }
            .buttonStyle(.plain)
            NavigationLink {
                FollowListView(userId: model.profile?.userId ?? auth.userId ?? "", kind: .following)
            } label: {
                statCell(value: ProfileLine.statValue(model.followingCount), label: L("フォロー中", "Following"))
            }
            .buttonStyle(.plain)
            if !bandShown {
                Spacer(minLength: 0)
                editLink(short: true)
            }
        }
        .padding(.horizontal, ProfileV2.gutter)
    }

    /// - Parameter value: nil は読み込み中。**数を出さずに高さだけ取る**（出たときに並びが動かない）
    /// 形は人のページと同じ `ProfileStat`（v2: 数字の下に 12pt の text-3 の名前）
    private func statCell(value: String?, label: String) -> some View {
        ProfileStat(value: value, label: label)
        .frame(maxWidth: bandShown ? .infinity : nil, minHeight: WebTheme.minTapTarget, alignment: .leading)
        .contentShape(Rectangle())
        // **押せる高さは 44pt のまま、並びの上では字の高さだけ取る**（板: 数の下は
        // すぐ 12pt で旅の実績の行）。44pt で場所を取ると、数と旅の実績の間が
        // 板の倍近く空いていた。押せる範囲は下の旅の実績の行と重ならない量だけ詰める
        .padding(.vertical, -Self.statTapSlack)
        .accessibilityElement(children: .combine)
    }

    /// 数の札の、見た目より外へ押せる範囲を張り出す量（上下それぞれ）
    private static let statTapSlack: CGFloat = 5

    /// 旅の記録（モック2-3 → 案 H1「星図」2026-10-14）。**訪れた国・地域**と**写真をつないだ距離**、
    /// その距離の元になった**写真をつないだ線**（`TravelRecordView`）。
    ///
    /// どちらも**数えた値**で、どちらも**そのままの意味ではない**ので、
    /// それぞれ押すと計算の中身が出る。**0 のものは出さない**——
    /// 「訪れた国 0」は実績にならず、「まだ国名を書いていない」を
    /// 「行っていない」と読ませてしまう。
    ///
    /// 節は人のページと同じ部品（`TravelRecordSection`・2026-10-16 判断）。マイページは
    /// **自分の写真すべて**から作る（今までどおり・人のページは公開写真だけ）
    @ViewBuilder
    private var travelRecord: some View {
        let summary = ProfileTravelRecord.Summary(photos: model.photos)
        if !summary.isEmpty {
            TravelRecordSection(summary: summary, isMine: true)
        }
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
                .padding(.horizontal, ProfileV2.gutter)
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
                // v2: 読み込みは中身と同じ形の骨格（0.3 秒より早ければ出さない）
                JPLoadingState(kind: .grid)
            case .none:
                // 2026-10-16: 保存は写真の詳細のしおりから。写真に出会う所（ホーム）へ1手
                EmptyState(message: SavedPhotosView.emptyMessage,
                           actionTitle: MyPageEmpty.browseTitle, actionIdentifier: "mypage.emptySaved") {
                    tabRouter.openHome()
                }
            case .nothingShown:
                EmptyState(message: LikedPhotos.nothingShownMessage)
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
            // 板 v2 MyPage（保存）: 投稿と同じ 3 列・縦長 4:5 の格子と、何の一覧かの一行
            LazyVGrid(columns: columns, spacing: ProfileV2.gridSpacing) {
                ForEach(saved) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo, fromPublicFeed: isPublic(photo), context: saved)
                    } label: {
                        PhotoFrame(photo: photo, aspect: ProfileV2.gridAspect, corner: 0)
                            .background(WebTheme.card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.accessibilityText)
                }
            }
            Text(L("しおりで保存した写真。あなただけに見え、作者には届きません（いいねした写真はメニューの「いいねした写真」）",
                   "Photos you bookmarked. Only you can see them, and the photographer isn't notified (liked photos are under Liked Photos in the menu)."))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, ProfileV2.gutter)
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
                // v2 WishlistTab B2: 行と同じ形の骨格
                JPLoadingState(kind: .rows)
                    .padding(.horizontal, ProfileV2.gutter)
            case .couldNotLoad:
                ErrorBanner(message: L("写真の一覧を取れませんでした。通信を確かめて、引き下げて読み直してください",
                                       "Couldn't load the photos. Pull to refresh."),
                            isBusy: isReloading) {
                    Task { await reloadAll() }
                }
            case .empty:
                // v2 WishlistTab B1: 何が無いか（明朝の見出し）→ どうすれば埋まるか → 一手
                // 2026-10-16: 見出しと本文で「まだありません」を重ねない（本文は「どうすれば埋まるか」だけ）
                EmptyState(title: L("行きたい場所はまだありません", "No places yet"),
                           message: MyPageEmpty.wishlistMessage)
                // 板 WishlistTab の B1（空）の「撮影スポットを探す」
                FindSpotsButton()
                    .frame(maxWidth: .infinity)
            case .list:
                // 「地図で見る」（保存を地図で見る・2026-10-03）。並べるのは下の一覧と同じ行
                wishlistMapLink(SavedSpotsMap.split(places: wanted, officialRows: officialRows),
                                pool: pool,
                                photosKnown: !sourceFailed && feedLoaded && model.hasLoadedPhotos)
                // 公開一覧の失敗のときだけ（自分の写真の失敗は上の一行が既に言う）
                if ProfileSections.wishlistPartlyMissing(shownCount: reachable + officialRows.count,
                                                         savedIdCount: wishIds.count,
                                                         sourceFailed: feedFailed) {
                    HStack(spacing: 8) {
                        Text(L("一部の場所を読み込めませんでした。引き下げて読み直してください",
                               "Some places couldn't be loaded. Pull to refresh."))
                            .font(.footnote)
                            .foregroundStyle(WebTheme.danger)
                        Spacer(minLength: 0)
                        // 引き下げを知らない人にも出口を（2026-10-02 の調査）
                        RetryButton(isBusy: isReloading, compact: true) { Task { await reloadAll() } }
                    }
                    .padding(.horizontal, ProfileV2.gutter)
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
                            OfficialSpotView(spot: spot, spots: officialSpots, photos: pool,
                                             // pool には自分の写真が混ざり、公開一覧が取れなくても空にならない。
                                             // pool の空では決めず、読み込みの状態だけで決める
                                             photosKnown: !sourceFailed && feedLoaded && model.hasLoadedPhotos)
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

    /// 「地図で見る」の小さな文字ボタン（板 DesignSystem「『地図で見る』など小さな文字ボタンは
    /// min-height 44」）。黒地の上の手がかりなので真鍮（owner の好み「デザインの箇所は白より真鍮」）。
    /// 件数は数なので白（数は合図ではない・CLAUDE.md の実例）
    private func wishlistMapLink(_ split: SavedSpotsMap.Split, pool: [Photo], photosKnown: Bool) -> some View {
        HStack(spacing: JPSpace.s) {
            // v2 WishlistTab: 節の見出しは眉（真鍮＋消える線）。見出しの読み上げは部品が付ける
            JPEyebrowLine(L("すべての行きたい場所 · \(split.count)", "All places · \(split.count)"))
            NavigationLink {
                SavedSpotsMapView(split: split, officialSpots: officialSpots, photos: pool,
                                  photosKnown: photosKnown)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.footnote)
                        .accessibilityHidden(true)
                    Text(L("地図で見る", "View on map"))
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(WebTheme.accent)
                .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("行きたい場所を地図で見る", "View places on a map"))
            .accessibilityIdentifier("mypage.wishlistMap")
        }
        .padding(.horizontal, ProfileV2.gutter)
    }

    /// 台帳のスポットの行。撮影地の行と同じ並び。
    ///
    /// 🔴 **台帳に写真（Wikimedia Commons）があれば表紙に敷く**（2026-10-03 owner「ピンだけで悲しい」）。
    /// 写真の無い行（索引に無い鍵・写真の無いスポット）だけ印を出す。出典は開いた先の
    /// スポットの画面に出る（地図の一覧の丸い写真と同じ扱い・`PhotoMapView.spotRow`）。
    /// 小さな枠なので**縮めて読む**（元の画像をそのまま展開しない）
    private func officialWishlistRow(_ row: OfficialWishlist.Row) -> some View {
        HStack(spacing: 12) {
            Group {
                if let photo = row.spot?.photo {
                    // 台帳の写真は縦横比を持たないので、2:1 までの形と見込んで読む（56pt なら 512px）
                    // 縮小版があればそれを読む（無い・読めなければ元の画像・`SpotThumbImage`）
                    SpotThumbImage(image: photo, assumedRatioLimit: 2)
                } else {
                    // 写真の無い行は真鍮の旗の札（板 v2 WishlistTab「無ければ真鍮の旗の札」・黒地の上）
                    Image(systemName: "flag")
                        .font(.title3)
                        .foregroundStyle(WebTheme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(WebTheme.card)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                // v2: 場所の名前は明朝（下限の 18。板の 16 は明朝の下限を割るので上げた）
                Text(row.name)
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let region = row.regionLabel {
                        Text(region)
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
                            .lineLimit(1)
                    }
                    if row.spot?.isDraft ?? false {
                        Text(L("下書き", "Draft"))
                            .font(JPFont.caption)
                            .foregroundStyle(WebTheme.text3)
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
                // v2 WishlistTab: 外すのは真鍮の旗（行きたい＝旗・`PhotoTripSection` と同じ印）。
                // 黒地の上なので真鍮。いいねのハート（白）と紛れない
                Image(systemName: "flag.fill")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.accent)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(row.name) を「行きたい」から外す", "Remove \(row.name)"))
        }
        .padding(.horizontal, ProfileV2.gutter)
        .frame(minHeight: 72)
        .overlay(alignment: .bottom) { wishlistDivider }
        .accessibilityIdentifier("mypage.officialWish")
    }

    private func wishlistRow(_ spot: DerivedSpot.Place) -> some View {
        HStack(spacing: 12) {
            // 代表写真は**いちばん多く押された1枚**（数えた値）
            RemoteImage(url: spot.cover?.gridImageURL)
                .frame(width: 56, height: 56)
                .background(WebTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.s))

            VStack(alignment: .leading, spacing: 2) {
                Text(LocationMatch.display(spot.label))
                    .font(JPFont.rowTitle)
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                let place = spot.broader.map { LocationMatch.display($0) }.joined(separator: " ・ ")
                if !place.isEmpty {
                    Text(place)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
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
                // v2 WishlistTab: 外すのは真鍮の旗（行きたい＝旗・`PhotoTripSection` と同じ印）。
                // 黒地の上なので真鍮。いいねのハート（白）と紛れない
                Image(systemName: "flag.fill")
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.accent)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(LocationMatch.display(spot.label)) を「行きたい」から外す", "Remove \(LocationMatch.display(spot.label))"))
        }
        .padding(.horizontal, ProfileV2.gutter)
        .frame(minHeight: 72)
        .overlay(alignment: .bottom) { wishlistDivider }
    }

    /// 行の間の線（板 v2 の `.sr`: 下に白 8%）。端の 16 から引く
    private var wishlistDivider: some View {
        Rectangle()
            .fill(WebTheme.hairline)
            .frame(height: JPStroke.hairline)
            .padding(.horizontal, ProfileV2.gutter)
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

    /// 旅の記録（旅の一冊の棚）。**自分の写真から**その場でまとめる（`TripBook.shelfTrips`）
    /// ——日付で束ねるのは公開写真だけ。1つの投稿にまとめた束は非公開でも一冊（自分だけの印付き）。
    /// マイページは本人にしか出ない
    /// 棚は `TripShelfList`。**旅の一覧の画面（`TripsView`）はここへ畳んだ**
    /// ——入口がマイページの札1つだけだった
    @ViewBuilder
    private var tripsArea: some View {
        let trips = TripBook.shelfTrips(from: model.photos)
        // 端末の写真の一冊（2026-10-16・`DeviceTripSection`）。投稿済みの日がある旅は外す
        let posted = LibraryTrips.postedShots(of: model.photos)
        let hasDeviceBooks = !deviceTrips.books(posted: posted, isMine: true).isEmpty
        if trips.isEmpty && model.isLoading {
            // **読み込み中に「空」の文言を出さない**（初回は写真がまだ0枚）。v2: 行の骨格
            JPLoadingState(kind: .rows)
                .padding(.horizontal, ProfileV2.gutter)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                // 背表紙の列と説明文は `TripShelfList`（旅の側の部品）
                // 公開一覧に載っている写真だけ個別ページが在る（`LikedPhotos.fromPublicFeed`）。
                // **投稿した一冊が0で端末の一冊があるときは「まだ旅はありません」を出さない**（棚に旅が並んでいる）
                if !trips.isEmpty || !hasDeviceBooks {
                    TripShelfList(trips: trips, isPublic: LikedPhotos.fromPublicFeed(dropped.visible(feed)))
                }
                DeviceTripSection(store: deviceTrips, posted: posted)
                tripToolsCard
            }
        }
    }

    /// 旅の記録の下の、共同アルバムと旅行プランの入口（2026-10-07）。
    ///
    /// **入口がメニューと設定の奥にしか無かった。** 板 05c に寄せたときにマイページの
    /// ボタンの列を外し、アルバムは設定・旅行プランはメニューからだけになった。
    /// どちらも「旅」の道具なので、旅の記録のタブに置く（板 MyPage の旅の記録にも
    /// 「行きたい場所から旅行プランを作る」の行がある）。形は設定・メニューと同じ札と行
    private var tripToolsCard: some View {
        JPCard {
            // 旅のトランク（2026-10-17 owner 承認・モック「旅のトランク」）。投稿のお礼に届くラベルを貼っていく。
            // **口が読めたことのある人にだけ出す**（サーバーが出ていない間は隠す・`TrunkAvailability`）
            // 2026-10-18 判断: 入口はマイページの上の札（`TrunkProfileChip`）と設定にも出したが、**この行は残す**。
            // 旅の道具（アルバム・旅行プラン・すれちがい帳）と同じ並びで探す人がいる。画面写真の試験の道もここ
            if trunkAvailability.isAvailable {
                NavigationLink { TrunkView(ownerName: model.profile?.name) } label: {
                    JPRowLabel(title: L("旅のトランク", "Travel trunk"), systemImage: "suitcase",
                               detail: L("投稿のお礼に届いた旅のラベルを貼っていく",
                                         "Stick the travel labels you get for posting"))
                }
                .buttonStyle(JPRowButtonStyle())
                .accessibilityIdentifier("trips.trunk")
                JPCardDivider()
            }
            // 写真で作るキャンプ場（2026-10-18・板「写真で作るキャンプ場」）。撮った写真を切り絵にして浮かぶ島に立てる。
            // 端末の中だけで動くので、トランクと違ってサーバーの口を待たずに出す
            NavigationLink { CampHomeView(ownerName: model.profile?.name) } label: {
                JPRowLabel(title: L("キャンプ場", "Campsite"), systemImage: "tent",
                           detail: L("撮った森や空を切り絵にして、浮かぶ島に立てる",
                                     "Turn the woods and skies you shoot into paper cutouts on a floating island"))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("trips.camp")
            JPCardDivider()
            NavigationLink { AlbumsView() } label: {
                JPRowLabel(title: Labels.Navigation.albums, systemImage: "rectangle.stack",
                           detail: L("招待リンクで、旅の仲間と写真を集める",
                                     "Collect photos with your travel companions via an invite link"))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("trips.albums")
            JPCardDivider()
            NavigationLink { TripPlansView() } label: {
                JPRowLabel(title: L("旅行プラン", "Trip plans"), systemImage: "calendar",
                           detail: L("行きたい場所を、回る順に並べる",
                                     "Put the places you want to visit in order"))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("trips.plans")
            JPCardDivider()
            // すれちがい帳（板 PassBook の戻り先がマイページ・2026-10-16）。旅先で受け取ったカード
            NavigationLink { PassBookView() } label: {
                JPRowLabel(title: L("すれちがい帳", "Pass book"), systemImage: "rectangle.portrait.on.rectangle.portrait",
                           detail: L("旅先ですれちがった人から届いたカード",
                                     "Cards from people you passed on your travels"))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("trips.passBook")
        }
        .padding(.horizontal, ProfileV2.gutter)
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
                .padding(.horizontal, ProfileV2.gutter)
        } else if tab == .wishlist || tab == .favorites, let error = model.errorMessage {
            // この2つは読み込みの失敗で覆わないが、**自分の写真から導くぶん**
            // （撮影地の地点・自分の非公開写真の保存）は欠けるので、一行添える
            Text(error)
                .font(.footnote)
                .foregroundStyle(WebTheme.danger)
                .padding(.horizontal, ProfileV2.gutter)
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
            // **旅の記録のタブでは、共同アルバム・旅行プランの札を残す**（2026-10-07 判断）。
            // どちらも自分の写真の読み込みと無関係なのに、最初の読み込みの失敗で入口ごと消えていた
            if tab == .trips {
                tripToolsCard
            }
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
            // 2026-10-16: 次の一手を1つ（「写真を投稿」・下の「投稿」と同じ道 `TabRouter.openPost`）
            EmptyState(message: L("まだ写真がありません", "No photos yet"),
                       actionTitle: MyPageEmpty.postTitle, actionIdentifier: "mypage.emptyPost") {
                tabRouter.openPost(.photo)
            }
        } else {
            let multiple = PhotoGroups.multiPhotoIds(model.photos)
            LazyVGrid(columns: columns, spacing: ProfileV2.gridSpacing) {
                ForEach(model.photos) { photo in
                    NavigationLink {
                        PhotoDetailView(photo: photo, fromPublicFeed: false, context: model.photos)
                    } label: {
                        gridCell(photo, multiple: multiple.contains(photo.id))
                    }
                    .buttonStyle(.plain)
                    // 撮影の試験が自分の写真を開く目印（`ScreenshotTests`）
                    .accessibilityIdentifier("mypage.photo")
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
    ///
    /// v2（板 MyPage・2026-10-14）: 縦長 4:5。ピン留めと複数枚は右上の白い印（影つき・写真の上は白だけ）、
    /// 下書きは写真を 55% に沈めて左下に「下書き」の札（黒 60%・12pt）。**印は読み上げない**
    /// （格子の1枚の値として読む）
    private func gridCell(_ photo: Photo, multiple: Bool) -> some View {
        let draft = photo.published == false
        return PhotoFrame(photo: photo, aspect: ProfileV2.gridAspect, corner: 0)
            .opacity(draft ? 0.55 : 1)
            .background(WebTheme.card)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: JPSpace.xxs) {
                    if model.isPinned(photo.id) {
                        Image(systemName: "pin.fill")
                    }
                    if multiple {
                        Image(systemName: "square.on.square")
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                .padding(6)
                .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) {
                if draft {
                    Text(L("下書き", "Draft"))
                        .font(JPFont.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, JPSpace.xs)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .padding(6)
                        .accessibilityHidden(true)
                }
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

    private let profiles: ProfileService
    private let photoService: PhotoService
    private let social: SocialService

    /// フォロワー／フォロー中の数（提案の絵の並び）。
    /// **数え札はサーバーが持っている**（`followstats#`）ので、
    /// 一覧の長さから数えない——50人で切ったぶんが落ちる
    @Published private(set) var followers = 0
    @Published private(set) var following = 0
    /// フォロー数を読めたか（nil: まだ・false: 取れなかった）。**数の 0 と見分ける**——
    /// 読み込み中・失敗のあいだ「0」と出ていた（人のページの `PhotoCount` と同じ決まりにする）
    @Published private(set) var followStatsRead: Bool?

    /// 画面に出す写真の数。**読み終えるまで言わず、取れなければ「—」**（`ProfileLine.PhotoCount`）
    var photoCount: ProfileLine.PhotoCount {
        if hasLoadedPhotos { return .loaded(photos.count) }
        return errorMessage != nil ? .failed : .pending
    }
    var followerCount: ProfileLine.PhotoCount { followCount(followers) }
    var followingCount: ProfileLine.PhotoCount { followCount(following) }

    private func followCount(_ value: Int) -> ProfileLine.PhotoCount {
        switch followStatsRead {
        case true?: return .loaded(value)
        case false?: return .failed
        // まだ取りに行けていない（プロフィールで落ちた）回も、読み込みが失敗していれば「—」
        case nil: return errorMessage != nil ? .failed : .pending
        }
    }

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
        // 先に足した控えは、この読み直しが**成功・失敗・取り消しのどれで終わっても**手放す
        // （残すと、あとで消した写真が次の読み直しで戻る・`PostedPhotos.keepSeconds`）
        defer { if gen == generation { justPosted = nil } }
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
                // 投稿したばかりでまだ索引に無い写真も残す（`showPosted`・id で重複を除く）
                let merged = PostedPhotos.merge(loaded: loadedPhotos, posted: justPosted?.photos(at: Date()) ?? [],
                                                owner: activeUser)
                self.photos = PhotoPinning.pinnedFirst(merged, pinned: self.pinnedIds)
                hasLoadedPhotos = true
                serverRead = ServerRead(owner: activeUser, publishedIds: loadedPhotos.filter { $0.published != false }.map(\.id),
                                        startedAt: startedAt)
            }
            let loadedStats = await stats
            guard gen == generation else { return }
            if let loadedStats {
                self.followers = loadedStats.followers
                self.following = loadedStats.following
                followStatsRead = true
            } else if followStatsRead != true, !Task.isCancelled {
                // 一度読めた数は、読み直しの失敗で「—」にしない
                followStatsRead = false
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
            followStatsRead = true
        } else if gen == generation, followStatsRead != true, !Task.isCancelled {
            followStatsRead = false
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
        justPosted = nil
        pinnedIds = []
        profile = nil
        followers = 0
        following = 0
        followStatsRead = nil
        errorMessage = nil
        // 前の人あての知らせ（読み直しの失敗・ピン留めの断り）も残さない
        actionMessage = nil
        reloadError = nil
        hasLoadedPhotos = false
        // 前の人の「公開中」の答えも手放す
        serverRead = nil
    }

    /// 投稿したばかりで、まだ読み直しの結果に合わせていない写真（`PostedPhotos.Pending`）。
    /// 次の読み直しが終わったら（成功・失敗・取り消しのどれでも）手放す。`keepSeconds` を過ぎた控えは使わない。
    /// 読めた回に索引がまだ返さなくても一覧には残り、その次の読み直しはサーバーの答えだけになる
    private var justPosted: PostedPhotos.Pending?

    /// 投稿画面を閉じた（`TabRouter.lastPosted`）。保存の応答の行を**読み直しの前に**一覧へ足す。
    /// 人が替わっていたら何もしない。まだ一度も読めていなければ一覧には触らず、読めた回に合わせる。
    /// **公開範囲を絞った写真は足さない**（`PostedPhotos.showable`・署名の無い URL で画像が出ない）
    func showPosted(_ posted: [Photo], for userId: String?, at now: Date = Date()) {
        let shown = PostedPhotos.showable(posted)
        guard let userId, userId == activeUser, !shown.isEmpty else { return }
        justPosted = PostedPhotos.Pending(photos: shown, receivedAt: now)
        guard hasLoadedPhotos else { return }
        photos = PhotoPinning.pinnedFirst(PostedPhotos.merge(loaded: photos, posted: shown, owner: userId),
                                          pinned: pinnedIds)
    }

    func isPinned(_ photoId: String) -> Bool { pinnedIds.contains(photoId) }

    /// ピン留めは1本ずつ。先の要求の答えが後から着くと、あとの留めを画面から消す
    private var pinTail: Task<Void, Never>?

    /// ピン留めの増減。
    ///
    /// **画面を先に動かさない。** 3枚の上限はサーバーが持っていて
    /// （`userProfile.ts`）、断られたときにそのときの一覧も返ってくる。
    /// 先に動かすと「留まったように見えて、次の読み込みで戻る」になる。
    func setPinned(_ photoId: String, pinned: Bool) async {
        // 🔴 **重ねて送らない**（2026-10-17）。長押しを続けて2枚留めると、先に返った
        // 古い一覧が、後の留めを画面から消していた。1本終わってから次を送る。
        // 押した時点の人を渡す——待ち行列の中で人が替わったら、その1本は送らない
        let user = activeUser
        let gen = generation
        let earlier = pinTail
        let job = Task { @MainActor in
            await earlier?.value
            await self.writePin(photoId, pinned: pinned, user: user, generation: gen)
        }
        pinTail = job
        await job.value
    }

    /// ピン留めを1本送って、**押した人の画面にだけ**書く
    private func writePin(_ photoId: String, pinned: Bool, user: String?, generation gen: Int) async {
        // 🔴 **人が替わったあとの答えは書かない**（2026-10-17）。
        // 読み込みは `generation` で捨てているのに、ここだけ書いていたので、
        // ログアウトしたあとに返った前の人のピンが次の人の画面に残った
        let still = { gen == self.generation && user == self.activeUser }
        guard still() else { return }
        do {
            let ids = try await profiles.setPinned(photoId: photoId, pinned: pinned)
            guard still() else { return }
            pinnedIds = ids
            photos = PhotoPinning.pinnedFirst(photos, pinned: pinnedIds)
            actionMessage = nil
        } catch {
            guard still() else { return }
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
            guard still() else { return }
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

/// マイページの空の画面の文言（2026-10-16・行き止まりの直し）。画面を持たないのでテストから読める
enum MyPageEmpty {
    /// 投稿0枚の次の一手（下の「投稿」の「写真を投稿」と同じ語）
    static var postTitle: String { L("写真を投稿", "Post a photo") }
    /// 保存0枚の次の一手（写真に出会うホームへ）
    static var browseTitle: String { L("写真を見に行く", "Browse photos") }
    /// 行きたい場所0件の本文。見出しが「まだありません」と言うので、ここは埋め方だけ
    static var wishlistMessage: String {
        L("撮影スポットの画面で「行きたい」を押すと、ここに並びます",
          "Tap “Want to go” on a place to add it here.")
    }
}
