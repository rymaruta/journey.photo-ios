import SwiftUI

/// 他の人のプロフィール（板 31）。
///
/// 並びはマイページ（板 05c）と同じ部品で組む: カバー（`ProfileCover`）に 84pt の
/// アイコンを重ね、名前・「@ユーザー名 · 居住地」・ひとことと自己紹介、数の1行、
/// ストーリーハイライト、下線の札（`ProfileTabBar`）、写真の格子。
///
/// **上のバーは見えなくするが、消さない。** 板はバーを出さずにカバーの上に「戻る」と
/// 「この人の操作」の丸を浮かせる。バーを隠して自前の「戻る」を置くと、画面の左端から
/// 払って戻る操作が効かなくなる（`MyPageView` はタブの根なので戻る先が無く、隠せる）。
/// だから地を透かし（`toolbarBackground(.hidden)`）、中央の題を塞ぐ。
/// iOS 26 ではバーの戻ると右の項目がガラスの丸で描かれる＝板と同じ形になる。
/// **それより前の iOS では丸の地が無い**（矢印と「…」だけがカバーの上に乗る）
struct UserProfileView: View {

    let userId: String

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = UserProfileViewModel()
    /// この人の旅のトランク（板 ProfileTrunk・2026-10-18）。見せていない（404）・読めないときは段ごと出さない
    @StateObject private var trunk = TheirTrunkModel()
    @EnvironmentObject private var connectivity: Connectivity
    @State private var showBlockConfirm = false
    @State private var showUnfollowConfirm = false
    @State private var tab: ProfileTab = .posts
    /// スクロールの見えている高さ。札の中身を少なくともこの高さにして、短い札へ替えても札の行を跳ばさない
    @State private var viewportHeight: CGFloat = 0
    /// カバー写真が出せたか（板 31。出せなければ帯を出さない）
    @State private var hasCover = false
    /// 中身が時計の下に入ったか（`ScrolledUnderClock`）
    @State private var scrolledUnderClock = false
    @EnvironmentObject private var hidden: ModerationStore
    /// 格子と地図から落とす「見せない」の写し。**前面が確定したときだけ取る**
    /// ——見ている最中／スワイプ途中に絞ると、押した元が消えて詳細が閉じる
    @State private var dropped = ModerationSnapshot()
    @State private var front = FrontConfirm()
    @State private var frontSettle: Task<Void, Never>?
    @EnvironmentObject private var toasts: ToastCenter
    /// 画面に出ているか（`MyPageView` と同じ）。ブロックを解いたときの読み直しを、
    /// 出ている間だけその場で・出ていなければ戻ってきたときにする
    @State private var isOnScreen = false
    /// ブロックを解いたが、まだ読み直していない（画面に出ていなかった）
    @State private var reloadOnAppear = false
    /// 名前の横のバッジを押した → この人のバッジの棚
    @State private var showShelf = false

    /// 板 v2 UserProfile: 3列・隙間 2pt・縦長 4:5・角なし（マイページと同じ `ProfileV2`）
    private let columns = ProfileV2.gridItems

    /// ログインしていて、自分以外で、ブロック中でないページか
    /// （フォロー・一覧の丸・ハイライト・ブロックはこの時だけ。`ProfileLine.canAct`）。
    /// ブロックはこの画面でも起きるので、`hidden` の中身を毎回見る
    private var canAct: Bool {
        ProfileLine.canAct(viewerId: auth.userId, userId: userId, blocked: hidden.blockedUserIds)
    }
    private var isBlocked: Bool { hidden.blockedUserIds.contains(userId) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                scroll
                    // カバーがあれば画面の上端から敷く（戻るの丸がカバーの上に乗る）。
                    // 無ければ帯も灰色の空き地も置かず、バーの下から始める
                    .ignoresSafeArea(edges: hasCover ? .top : [])
                // **時計とバーの裏に黒のぼかし**（マイページと同じ `TopBarScrim`）。
                // バーの地を透かしているので、敷かないと上へ送った写真が時計・戻る・
                // 「…」の真下を流れて読めない。iOS 17〜25 は丸に地が無く、明るい
                // カバーの上でも矢印が沈む
                TopBarScrim(topInset: geo.safeAreaInsets.top, covered: scrolledUnderClock)
                    .animation(.easeOut(duration: 0.2), value: scrolledUnderClock)
            }
        }
        .webScreen()
        // 題は戻る文字（次の画面）と読み上げのために持つ。見えるところには出さない
        .navigationTitle(model.shownName ?? Labels.Navigation.profile)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { toolbarItems }
        // 名前の横のバッジから。**自分の頁なら自分の棚**（進み具合つき）、人なら持っているものだけ
        .navigationDestination(isPresented: $showShelf) {
            BadgeShelfView(mode: userId == auth.userId ? .mine : .other(userId: userId),
                           preloaded: model.profile)
        }
        .blockConfirmation(isPresented: $showBlockConfirm) {
            Task { await model.block(userId: userId, environment: environment, store: hidden, toasts: toasts) }
        }
        .onAppear {
            switch front.appear() {
            case .first:
                landOnScreen()
            case .returning:
                frontSettle?.cancel()
                frontSettle = Task {
                    try? await Task.sleep(nanoseconds: FrontConfirm.settleNanoseconds)
                    guard !Task.isCancelled, front.confirm() else { return }
                    landOnScreen()
                }
            }
        }
        .onDisappear {
            frontSettle?.cancel()
            frontSettle = nil
            front.disappear()
            isOnScreen = false
        }
        // 🔴 **ブロックを解いたら読み直す。** ブロックで格子を空にしたまま、下に残った
        // この画面で設定（ブロック中の人）から解くと、「0 写真」「まだありません」と
        // ブロック前のフォロワー数が出たままだった
        .onChange(of: isBlocked) { was, now in
            guard was, !now else { return }
            if isOnScreen {
                dropped = hidden.snapshot
                Task { await model.load(userId: userId, environment: environment, viewerId: auth.userId) }
                Task { await loadTrunk() }
            } else {
                reloadOnAppear = true
            }
        }
        // **見ている人が替わっても読み直す。** 相手だけを鍵にしていたので、開いたまま
        // 別の人でログインし直すと「フォロー中」が前の人の値のまま出て、押すと
        // 逆向きに送っていた（前の人が誰をフォローしているかも見えた）
        .task(id: "\(userId)|\(auth.userId ?? "")") {
            await model.load(userId: userId, environment: environment, viewerId: auth.userId)
        }
        // トランクは写真の一覧と別に読む（遅くても見出し・格子を待たせない）
        .task(id: "trunk|\(userId)|\(auth.userId ?? "")") { await loadTrunk() }
    }

    private func loadTrunk() async {
        await trunk.load(userId: userId, service: environment.trunk, signedIn: auth.userId != nil,
                         offline: connectivity.isOffline, isSelf: userId == auth.userId)
    }

    /// 前面確定後: 写しを当て、ブロック解除後の読み直しがあれば走らせる
    private func landOnScreen() {
        dropped = hidden.snapshot
        isOnScreen = true
        if reloadOnAppear {
            reloadOnAppear = false
            Task { await model.load(userId: userId, environment: environment, viewerId: auth.userId) }
            Task { await loadTrunk() }
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                // 板: 見出し・数・ハイライトの間は 14pt 前後（v2 の物差しで 12）、その下の札と格子は 16pt
                VStack(alignment: .leading, spacing: JPSpace.s) {
                    VStack(alignment: .leading, spacing: 0) {
                        ProfileCover(url: model.profile?.coverURL(cacheBust: model.cacheBust),
                                     reserve: hasCover) { hasCover = $0 }
                        header
                    }
                    if model.profile != nil {
                        counts
                        // 旅のトランク（板 ProfileTrunk: 数のすぐ下・訪れた場所の上）
                        theirTrunk
                        // とおまわり号を訪ねる（2026-10-19 第2段・板 CamperVisit）。互いのフォローはサーバーが見る
                        camperVisit
                        // 旅の記録と旅の一冊（2026-10-16 owner「他人のプロフィールでも旅の記録を」）。
                        // 板 UserProfile F33 の並び: 数 → 旅 → ハイライト。旅の記録はマイページと同じく数のすぐ下
                        travelRecord
                        tripsLine
                        if canAct {
                            // 板 31 の丸の列。**無い人には何も出さない**（`ProfileSections.showsHighlights`）。
                            // 見られるのは本人とフォロワーだけなので、**フォローを変えたら
                            // 作り直して読み直す**（鍵が変わる）。そのままだと外した後も
                            // 輪が残り、押すと 404 になる
                            HighlightsRow(userId: userId, isMine: false)
                                .id(ProfileLine.highlightsKey(userId: userId,
                                                              isFollowing: model.isFollowing))
                        }
                    }
                }

                // **端末にしか無い札は出さない**（`ProfileTab.tabs`）
                // 札の行と中身は横に払っても切り替わる（マイページと同じ部品・2026-10-24 判断）。
                // **地図の札の中身では払いを受けない**——地図を横に動かす操作とぶつかる（札の行では受ける）
                ProfileTabBar(tabs: ProfileTab.tabs(isMe: false), selection: $tab)
                    .modifier(ProfileTabSwipe(tabs: ProfileTab.tabs(isMe: false), selection: $tab))

                photoBanners
                ProfileTabPager(tabs: ProfileTab.tabs(isMe: false), selection: $tab,
                                minHeight: viewportHeight, swipeBlocked: [.map]) { page in
                    VStack(alignment: .leading, spacing: JPSpace.m) {
                        tabContent(page)
                    }
                }
            }
            // 中身が時計の下に入ったかを見る（入ったときだけ時計の下を黒で塗る・`TopBarScrim.covered`）
            .onGeometryChange(for: Bool.self) { proxy in
                ScrolledUnderClock.covered(contentMinY: proxy.frame(in: .scrollView).minY)
            } action: { scrolledUnderClock = $0 }
        }
        // 見えている高さ（札の中身の最低の高さ・`ProfileTabPager`）
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { viewportHeight = $0 }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // **中央は空けておく**（`AppHeader` と同じ塞ぎ方）。名前は下の見出しにある
        ToolbarItem(placement: .principal) {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
        if canAct {
            ToolbarItem(placement: .topBarTrailing) {
                // **通報は置かない。** サーバーが受けるのは写真の通報だけ
                // （`POST /photos/{id}/report`）で、人を通報する口が無い。
                // 押しても何も起きない項目は作らない（写真の詳細から通報できる）
                Menu {
                    Button(role: .destructive) { showBlockConfirm = true } label: {
                        Label(L("この人をブロック", "Block this person"), systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .webToolbarIcon()
                        .accessibilityLabel(L("この人の操作", "More actions"))
                }
            }
        }
    }

    /// 🔴 ブロック・通報した写真を落とした一覧。以前は読み込んだまま描いていて、
    /// 詳細でブロックして戻っても、その人の写真の格子と地図が押せた（審査 1.2）
    private var shownPhotos: [Photo] { dropped.visible(model.photos) }

    /// 旅のトランクの段（板 ProfileTrunk）。**読めて中身があるときだけ**出す——見せていない（404）・
    /// 読み込み中・失敗・ブロックの関係では、空の枠も灰色の空き地も置かない
    @ViewBuilder
    private var theirTrunk: some View {
        if trunk.showsOnProfile(blocked: isBlocked), let shown = trunk.trunk {
            NavigationLink {
                TheirTrunkView(userId: userId, ownerName: model.shownName, handle: model.profile?.username,
                               homeLocation: model.profile?.homeLocation, profile: model.profile, photos: shownPhotos,
                               photosReady: model.photoCount != .pending, model: trunk)
            } label: {
                TheirTrunkCard(trunk: shown, ownerName: model.shownName)
            }
            .buttonStyle(TrunkPressStyle())
            .padding(.horizontal, ProfileV2.gutter)
            .accessibilityIdentifier("profile.trunk")
        }
    }

    /// 友達の車を訪ねる行（2026-10-19 第2段）。**フォローしている人の頁だけ**に出す（訪ねる・贈る・薪は互いの
    /// フォローの友達だけ。相手がフォローし返していないときはサーバーの断り `notFriend` を行き先の画面で言う）。
    /// ログインしていない・自分・ブロックの関係では出さない（`canAct`）
    @ViewBuilder
    private var camperVisit: some View {
        if canAct, model.isFollowing || PreviewSession.camperSample {
            // 札の形はマイページの「写真で作るキャンピングカー」の行と同じ（`JPCard` の中の `JPRowLabel`）
            JPCard {
                NavigationLink {
                    CamperVisitView(userId: userId, ownerName: model.shownName)
                } label: {
                    JPRowLabel(title: L("とおまわり号を訪ねる", "Visit their Detour"), systemImage: "bus",
                               detail: L("部品を贈る・焚き火に薪をくべる", "Give a part or add wood to their fire"))
                }
                .buttonStyle(JPRowButtonStyle())
                .accessibilityIdentifier("profile.camper")
            }
            .padding(.horizontal, ProfileV2.gutter)
        }
    }

    /// 旅の記録（マイページと同じ `TravelRecordSection`）。**この人の公開写真だけ**から作り、
    /// ブロックの関係なら出さない（`ProfileTravelRecord.othersPhotos`・2026-10-16 判断）。
    /// 国も距離も無い人・読み込み中・取れなかった回は節ごと出さない（板 F33「灰色の空き地も置かない」）
    @ViewBuilder
    private var travelRecord: some View {
        let summary = ProfileTravelRecord.othersSummary(shownPhotos, blocked: isBlocked)
        if !summary.isEmpty {
            TravelRecordSection(summary: summary, isMine: false)
        }
    }

    /// 旅の一冊（板 F33「旅」の札）。公開写真だけを、マイページの棚と同じ規則で束ねる。
    /// 一冊も無ければ節ごと出さない
    @ViewBuilder
    private var tripsLine: some View {
        let shelf = ProfileTravelRecord.othersShelf(shownPhotos, blocked: isBlocked)
        if !shelf.trips.isEmpty {
            ProfileTripsLine(shelf: shelf)
        }
    }

    /// 札の上の知らせ（どの札でも同じ所に出す）
    @ViewBuilder
    private var photoBanners: some View {
        if let action = model.actionMessage {
            // **一覧の代わりではなく、一覧に添える**（マイページと同じ）
            Text(action)
                .font(.footnote)
                .foregroundStyle(WebTheme.danger)
                .padding(.horizontal, ProfileV2.gutter)
        }
    }

    /// 札ごとの中身。**`tab` ではなく渡された札で分ける**——選んでいない札も持ち続ける（`ProfileTabPager`）
    @ViewBuilder
    private func tabContent(_ tab: ProfileTab) -> some View {
        if let message = model.errorMessage {
            ErrorBanner(message: message) {
                Task { await model.load(userId: userId, environment: environment, viewerId: auth.userId) }
            }
        } else if model.photos.isEmpty && model.photoCount == .failed {
            // **取れなかったのを「まだありません」と言わない**（数の札も「—」）
            ErrorBanner(message: Labels.Common.loadFailed) {
                Task { await model.load(userId: userId, environment: environment, viewerId: auth.userId) }
            }
        } else if shownPhotos.isEmpty && !isBlocked && model.photoCount == .pending {
            // ブロックを解いて読み直すまでの間。「まだありません」と言わない（v2: 格子の骨格）
            JPLoadingState(kind: .grid)
        } else if shownPhotos.isEmpty && !model.isLoading {
            // 全部通報・持ち主をブロックして戻った回も、白紙にせず案内を出す
            EmptyState(message: L("公開された写真はまだありません", "No public photos yet"))
            // 板 v2 UserProfile（写真0）: 押せる一手は真鍮の下線のリンク（黒地の上のリンクは真鍮）
            findOthersLink
        } else if tab == .map && shownPhotos.isEmpty {
            // 🔴 **読み込み中の空の地図に「撮影地の分かる写真がありません」と言わない。**
            // 「読み終えて0枚」は上の枝で済んでいるので、ここに来るのは読み込み中だけ
            // （マイページの読み込み中と同じ骨格）
            JPLoadingState(kind: .rows)
                .padding(.horizontal, ProfileV2.gutter)
        } else if tab == .map {
            // 相手のページでも「どこで撮ったか」を出す（モック11 と同じ並び）
            // シートの中でブロック／通報して閉じたら、格子も絞り直す（`onAppear` は来ない）
            MyPhotosMap(photos: shownPhotos, isMine: false, onSheetDismiss: { dropped = hidden.snapshot })
        } else {
            LazyVGrid(columns: columns, spacing: ProfileV2.gridSpacing) {
                ForEach(shownPhotos) { photo in
                    NavigationLink { PhotoDetailView(photo: photo, context: shownPhotos) } label: {
                        PhotoFrame(photo: photo, aspect: ProfileV2.gridAspect, corner: 0)
                            .background(WebTheme.card)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 写真が0枚の人のページの一手（板 v2 UserProfile の「ほかの人の写真を探す」）。
    /// 探すのタブを開く。黒地の上のリンクなので真鍮・下線（色だけで言わない）・押せる高さ 44
    private var findOthersLink: some View {
        Button {
            TabRouter.shared.openSearch()
        } label: {
            Text(L("ほかの人の写真を探す", "Find other people's photos"))
                .font(JPFont.body)
                .underline()
                .foregroundStyle(WebTheme.accent)
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityHint(L("探すのタブを開きます", "Opens the Search tab"))
    }

    /// 見出し（板 v2 UserProfile）: 88pt のアイコン（黒い 4pt の縁）と右に「フォローする」、
    /// その下に明朝 26 の名前・「@ユーザー名 · 居住地」・ひとことと自己紹介。
    ///
    /// 2026-10-09 判断（owner）: 右のフォロー一覧の丸（人と＋の印）は消した。「フォローする」と
    /// 並んで「人を足す」に見え、行き先は下の数の札（フォロワー・フォロー中）と同じだったため。
    /// 一覧へは数の札から開く
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                // **ストーリーがあれば顔に輪を描き、押すとその人のストーリーから**（2026-10-22・`StoryAvatar`）
                StoryAvatar(userId: userId, name: model.shownName ?? "", diameter: ProfileCover.avatarSize) {
                    RemoteImage(url: model.profile?.avatarURL(cacheBust: model.cacheBust))
                        .background(WebTheme.card)
                } plain: {
                    RemoteImage(url: model.profile?.avatarURL(cacheBust: model.cacheBust))
                        .frame(width: ProfileCover.avatarSize, height: ProfileCover.avatarSize)
                        .background(WebTheme.card)
                        .clipShape(Circle())
                }
                .frame(width: ProfileCover.avatarSize, height: ProfileCover.avatarSize)
                // **板どおり黒の 3pt の縁**（板 31）。本人が選んだ色の輪（`themeColor`）は
                // 出さない——マイページ（板 05c）と揃える（owner の判断・2026-09-26）。
                // 色はプロフィール編集で選べ、Web（`themeRingGradient`）には出る
                .coverCutout(true)
                Spacer(minLength: 8)
                if canAct {
                    followButton
                }
            }
            VStack(alignment: .leading, spacing: JPSpace.xxs) {
                HStack(spacing: 6) {
                    Text(model.shownName ?? "—")
                        .font(JPFont.screenTitle)
                        .foregroundStyle(Color.white)
                        // 題は上のバーに出さないので、画面の見出しは名前が受け持つ
                        .accessibilityAddTraits(.isHeader)
                    // 公式の封印 → Pro マーク → 選んだバッジ。バッジを押すとこの人の棚
                    NameMarks(profile: model.profile, nameSize: 26, relativeTo: .title, fit: .mincho,
                              showsBadge: true, onBadgeTap: { _ in showShelf = true })
                }
                // 公開プロフィールの口（`toPublicProfile`）が username と居住地を返す
                if let line = ProfileLine.handleAndHome(username: model.profile?.username,
                                                        home: model.profile?.homeLocation) {
                    ProfileHandleLine(line: line, showsPin: false)
                }
                // ひとことと自己紹介。**以前は自己紹介だけ**で、ひとことを出していなかった
                // v2: 本文 15・text-2・行間 1.7
                ForEach(ProfileLine.about(status: model.profile?.statusText,
                                          bio: model.profile?.bio), id: \.self) { text in
                    Text(text)
                        .font(JPFont.body)
                        .lineSpacing(6)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, JPSpace.xxs)
                }
            }
        }
        .padding(.horizontal, ProfileV2.gutter)
        .padding(.top, hasCover ? -ProfileCover.avatarOverlap : 8)
    }

    /// 数の並び（板 v2 UserProfile: 数字の下に名前の札を間 24 で「フォロワー・フォロー中・写真」）。
    /// v1（板 31）は「000 フォロワー」の1行だった。形はマイページと同じ `ProfileStat`。
    ///
    /// 写真の数は**下の格子に並べている枚数そのもの**（公開一覧からこの人のぶんを
    /// 選り分けたもの）。**読み終えるまで出さず、取れなければ「—」**（`PhotoCount`）。
    /// ブロックして一覧を伏せたあとも出さない。
    /// 押して一覧を開けるのは、ログインしていて1人以上いるときだけ
    /// （`FollowCounts.isTappable`）。一覧の口は認証が要るので、未ログインで
    /// 押せると赤字だけの行き止まりになる。
    /// フォロワー・フォロー中も写真と同じく、読み終えるまで出さず取れなければ「—」
    /// （以前は読み込み中に 0 と出ていた。マイページの `statValue` と同じ決まり）
    private var counts: some View {
        HStack(alignment: .top, spacing: JPSpace.xl) {
            ForEach(ProfileLine.counts(followers: model.followerCount, following: model.followingCount,
                                       photos: isBlocked ? .pending : model.photoCount.shown(shownPhotos.count))) { item in
                switch item.kind {
                case .followers:
                    countLink(item, kind: .followers, count: model.followers)
                case .following:
                    countLink(item, kind: .following, count: model.following)
                case .photos:
                    countText(item)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ProfileV2.gutter)
    }

    @ViewBuilder
    private func countLink(_ item: ProfileLine.Count, kind: FollowListView.Kind, count: Int) -> some View {
        if FollowCounts.isTappable(signedIn: auth.userId != nil, count: count) {
            NavigationLink {
                FollowListView(userId: userId, kind: kind)
            } label: {
                countText(item)
                    // 押せる高さは 44pt、並びの上では字の高さに近く詰める
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
                    .padding(.vertical, -Self.countTapSlack)
            }
            .buttonStyle(.plain)
            // 一覧への口はここだけ（見出しの丸は 2026-10-09 に消した）。画面写真の試験が押す
            .accessibilityIdentifier(kind == .followers ? "profile.count.followers" : "profile.count.following")
        } else {
            countText(item)
        }
    }

    private func countText(_ item: ProfileLine.Count) -> some View {
        ProfileStat(value: item.value, label: item.label)
            .accessibilityElement(children: .combine)
    }

    /// 数の札の、見た目より外へ押せる範囲を張り出す量（上下それぞれ）。
    /// v2 の札は2段（数字 20＋名前 12 ≈ 42pt）なので、44 に足りない分だけ
    private static let countTapSlack: CGFloat = 1

    /// 「フォローする」（白 94% に墨）／「フォロー中 ▾」（線）。板 v2 UserProfile の見出しのボタン
    /// （`ProfileFollowButtonLabel`・見た目 40・当たり 44）。形で分ける——色だけで状態を言わない。
    ///
    /// 🔴 `.borderedProminent` は使わない——`RootView` の
    /// `.tint(WebTheme.foreground)` が白なので、白地に白い字＝
    /// **ただの白い帯**になる（run 60 の実機の絵で2か所そうだった）
    private var followButton: some View {
        Button {
            // 外すときだけ確認を挟む（`unfollowConfirmation`）
            if model.isFollowing {
                showUnfollowConfirm = true
            } else {
                Task {
                    await model.toggleFollow(userId: userId, environment: environment, follow: true)
                    // フォローで見えるストーリーが変わる。顔の輪の控えを読み直す
                    await StoryRingDirectory.shared.refresh(environment: environment, auth: auth)
                }
            }
        } label: {
            ProfileFollowButtonLabel(isFollowing: model.isFollowing)
        }
        .buttonStyle(.plain)
        // 送っている間は薄くする（押したことが見て分かる。二度押しは `toggleFollow` の頭で止める）
        .opacity(model.isWorking ? 0.6 : 1)
        .disabled(model.isWorking)
        .unfollowConfirmation(isPresented: $showUnfollowConfirm) {
            // **向きは押した時点で決める。** 確認が出ている間に読み込みが「もう外れていた」を
            // 書いても、「外す」を選んだのに follow を送らない
            Task {
                await model.toggleFollow(userId: userId, environment: environment, follow: false)
                // 外したら見えなくなるストーリーがある。顔の輪の控えを読み直す（読めなければ前の控えのまま・
                // 失敗の控えで圏外のたびには読まない・`StoryRingDirectory`）
                await StoryRingDirectory.shared.refresh(environment: environment, auth: auth)
            }
        }
    }
}

@MainActor
final class UserProfileViewModel: ObservableObject {

    @Published private(set) var profile: UserProfile?
    @Published private(set) var photos: [Photo] = []
    @Published private(set) var followers = 0
    @Published private(set) var following = 0
    /// フォロー数を読めたか（nil: まだ・false: 取れなかった）。**数の 0 と見分ける**
    /// ——読み込み中・失敗のあいだ「0」と出ていた（マイページの `followStatsRead` と同じ）
    @Published private(set) var followStatsRead: Bool?
    @Published private(set) var isFollowing = false
    /// 自分のフォロー一覧が取れず、**フォロー中かどうか分からない**。ボタンは「フォローする」で
    /// 出すが、押されたら送る前に取り直す（`toggleFollow`）——分からないまま送ると、
    /// フォロー中の人に follow を送り直していた（写真の詳細の `followLookupFailed` と同じ形）
    private var followUnknown = false
    /// 写真の数を言えるか。**配列の長さを直接出さない**（読み込み中・失敗で 0 になる）
    @Published private(set) var photoCount: ProfileLine.PhotoCount = .pending
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    /// フォロー・ブロックの失敗。**読み込みの失敗（`errorMessage`）と分ける**
    /// ——同じ欄だと、押し損ねただけで格子と地図が知らせ1枚に置き換わっていた
    @Published private(set) var actionMessage: String?

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

    private(set) var cacheBust = ""
    /// フォロー・ブロックが**受け付けられた**回数。**読み込みの間に増えたら、その読み込みの
    /// フォロワー数と「フォロー中か」は書かない**——読み込み中にフォローを押すと、押す前の
    /// 数と「フォローしていない」が後から届いて戻していた。断られた回は数えない。
    /// 「フォロー中」の数（この人が何人をフォローしているか）は押しても変わらないので止めない
    private var followWrites = 0
    /// ブロックが受け付けられた回数。**ブロックで変わるのは「フォロー中か」だけ**なので、
    /// こちらはフォロワー数を止めない
    private var blockWrites = 0

    /// 前回の読み込みで見ていた人
    private var lastViewerId: String??
    /// 読み込みの回。**後から始まった回があれば、前の回は何も書かない**——見ている人が
    /// 替わって `.task` が走り直すと、取り消された前の回が「読み込めませんでした」を
    /// 後から書き、成功した新しい回の格子を覆ったままになっていた
    private var loadSeq = 0

    func load(userId: String, environment: AppEnvironment, viewerId: String?) async {
        // 見ている人が替わったら「フォロー中」を先に倒す（読み直しの間も前の人の値を出さない）
        if let last = lastViewerId, last != viewerId {
            isFollowing = false
            followUnknown = false
        }
        lastViewerId = .some(viewerId)
        let writes = followWrites
        let blocks = blockWrites
        loadSeq += 1
        let seq = loadSeq
        let current = { seq == self.loadSeq }
        isLoading = true
        errorMessage = nil
        // 読み直したら前の操作の失敗も消す（再試行のあとに古い文が残る）
        actionMessage = nil
        // **読み直すたびに替えない**（`ProfileImageVersions`）。替わるのは本人が変えたとき・開き直したとき
        cacheBust = ProfileImageVersions.shared.token(for: userId)
        defer { if current() { isLoading = false } }

        // 人が替わった直後は前の人の数を出さない（取れなかった回に残すと嘘になる）
        if profile?.userId != userId {
            followers = 0
            following = 0
            followStatsRead = nil
        }

        // 🔴 **出している最中に取り消された回は失敗として書かない。** 戻ると `.task` が
        // 走り直し、読み終わる前に次の写真・ハイライトを開くと取り消される。それを失敗の帯
        // （`errorMessage`）にすると、格子ごと差し替わって開いたばかりの詳細が閉じた。
        // 取り消しは `APIError.unreachable` に化けて届くことがあるので、型ではなく
        // `Task.isCancelled` で見る。前の回に出していた中身はそのまま残す。
        // **まだ何も出していない回（`profile == nil`）は今までどおり書く**——書かないと
        // 見出しの無い画面に「まだありません」が出る（開いている詳細も無い）
        let keepsShown = { Task.isCancelled && self.profile != nil }
        do {
            let fetched = try await environment.profiles.publicProfile(userId: userId)
            guard current() else { return }
            profile = fetched
        } catch let error as APIError {
            guard current(), !keepsShown() else { return }
            // **「取れなかった」と「退会した」を混ぜない**
            if case .server(let status, _) = error, status == 404 {
                errorMessage = L("このユーザーは見つかりません（退会した可能性があります）", "This user was not found (they may have deleted their account)")
                return
            }
            errorMessage = error.errorDescription
            return
        } catch is CancellationError {
            // 取り消された（画面を離れた・引き下げの途中で描き直された）。
            // **出している最中なら失敗と言わない**が、まだ何も出していない初回は
            // 上と同じく書く（`keepsShown`）——黙って戻ると、見出しの無い画面に
            // 「まだありません」が出る
            guard current(), !keepsShown() else { return }
            errorMessage = Labels.Common.loadFailed
            return
        } catch {
            guard current(), !keepsShown() else { return }
            errorMessage = Labels.Common.loadFailed
            return
        }

        let stats = try? await environment.social.followStats(userId: userId)
        guard current() else { return }
        if let stats {
            if writes == followWrites { followers = stats.followers }
            following = stats.following
            followStatsRead = true
        } else if followStatsRead != true, !Task.isCancelled {
            // 一度読めた数は、読み直しの失敗で「—」にしない（マイページと同じ）
            followStatsRead = false
        }
        if viewerId != nil {
            // **取れなかった回は書かない**（`FollowListView` と同じ）。圏外で
            // 「フォローする」に戻すと、フォロー中の人に follow を送り直す
            let ids = try? await environment.social.myFollowingIds()
            guard current() else { return }
            if writes == followWrites, blocks == blockWrites {
                if let ids {
                    isFollowing = ids.contains(userId)
                    followUnknown = false
                } else {
                    followUnknown = true
                }
            }
        }
        // **その人の写真は公開 JSON から絞る。** 「ある人の公開写真」を返す
        // 口が api-user に無いため（Web も静的ページを書き出している）
        let all = try? await environment.gallery.fetchPhotos()
        guard current() else { return }
        // 読んでいる間にブロックした（`block` が格子を空にした）なら、写真を戻さない。
        // **失敗とも言わない**——取れなかった枝（下の else）に落とすと、初回は
        // 「読み込めませんでした」が出ていた（84aaf23 の回帰）
        guard blocks == blockWrites else { return }
        if let all {
            photos = PhotoPinning.pinnedFirst(all.filter { ($0.userId ?? $0.uploadedBy) == userId },
                                      pinned: profile?.pinnedPhotoIds ?? [])
            photoCount = .loaded(photos.count)
        } else {
            // 前の回に取れていた一覧は残す（数もそのまま）。一度も取れていなければ「—」
            switch photoCount {
            case .loaded: break
            case .pending, .failed: photoCount = .failed
            }
        }
    }

    /// 画面に出す名前。
    ///
    /// 🔴 **プロフィールの名前だけを見ていた。** `UserProfile.name` は
    /// 名前が無いとき「ユーザー」を返す＝**nil にならない**ので、
    /// この人の写真に添えられている名前（`displayName`）まで降りてこない。
    /// run 58 の実機の絵では、ホームと写真詳細が `luzhj` を出しているのに
    /// **人のページだけ「ユーザー」**だった（写真詳細で直したのと同じ形が
    /// ここにも残っていた＝3か所目）。
    ///
    /// **まだ何も取れていないうちは nil**——「ユーザー」と出してから
    /// 名前に入れ替わると、読み込みの途中が壊れて見える
    var shownName: String? { AuthorName.forProfilePage(profile: profile, photos: photos) }

    /// 🔴 **失敗は格子の上の一行（`actionMessage`）に出す**（`errorMessage` に入れない）。`errorMessage` は
    /// 読み込みの失敗で、写真の格子ごと差し替えて出す——圏外でフォローを押すと
    /// 格子が消えていた（マイページが `actionMessage` で分けたのと同じ形）
    /// - Parameter follow: 押したボタンの向き（フォローしたいか）。nil はいまの姿の逆
    func toggleFollow(userId: String, environment: AppEnvironment, follow: Bool? = nil) async {
        // 🔴 **送っている間の2回目は送らない。** `disabled` は描き直しの後にしか効かず、素早く2回押すと
        // 2本走り、先に終わった方の `defer` が `isWorking` を下ろして、もう1本の最中に押せる姿へ戻っていた
        // （2026-10-16 判断: 写真詳細の `toggleFollow` と同じ形で頭で止める）
        guard !isWorking else { return }
        isWorking = true
        actionMessage = nil
        defer { isWorking = false }
        // **押したボタンの向きを覚えておく**（「フォローする」を押した＝フォローしたい）。
        // 取り直した結果で向きを決め直すと、「フォロー中」を外そうとして何も送られない・
        // 逆向きに follow を送る、が起きた
        let wantsFollow = follow ?? !isFollowing
        // 押した時点で見ていた人。🔴 **押した人の答えだけを書く。** 待っている間にログアウトして
        // 別の人で入り直すと、前の人の「フォロー中」と数が次の人の画面に残っていた
        // （`FollowListView.setFollowing` の `auth.userId == viewer` と同じ守り）
        let viewer = lastViewerId
        // **分からないままフォローを送らない。** 取り直して、既にフォロー中なら送らずに姿だけ直す。
        // 外す方は取り直さない（外すのは何度送っても同じ）
        if followUnknown && wantsFollow {
            let ids: [String]
            do {
                ids = try await environment.social.myFollowingIds()
            } catch is CancellationError {
                return
            } catch {
                // 前の人の失敗を次の人の画面に出さない
                guard lastViewerId == viewer else { return }
                actionMessage = L("フォローの状態を確かめられませんでした", "Couldn't check follow status")
                return
            }
            // 待っている間に見ている人が替わったら、前の人の一覧を書かない
            guard lastViewerId == viewer else { return }
            followUnknown = false
            // 取り直した値を、先に始まっていた読み込みの古い答えで戻させない
            followWrites += 1
            if ids.contains(userId) {
                isFollowing = true
                return
            }
        }
        do {
            let result = wantsFollow
                ? try await environment.social.follow(userId: userId)
                : try await environment.social.unfollow(userId: userId)
            // 前の人の「フォロー中か」を次の人の画面に書かない（書くと followWrites が進み、
            // 次の人の読み込みも直さなくなる）
            guard lastViewerId == viewer else { return }
            followWrites += 1
            isFollowing = result.following
            // サーバーの答えは確かな値——外したあとにフォローし直すとき、また取り直しに行かない
            followUnknown = false
            followers = result.followers
            followStatsRead = true
        } catch {
            // 前の人が押した失敗を、次の人の画面に出さない
            guard lastViewerId == viewer else { return }
            actionMessage = (error as? LocalizedError)?.errorDescription ?? L("うまくいきませんでした", "That didn't work")
        }
    }

    /// ブロック後のフォロー数は次に読み込むまで古いまま（2026-09-30 判断: 同時の読み込み・
    /// 人の切り替え・失敗との組み合わせで回帰が続いたため）
    func block(userId: String, environment: AppEnvironment, store: ModerationStore,
               toasts: ToastCenter) async {
        actionMessage = nil
        // 控えるのは押した人の控えだけ（待っている間に人が替わったら書かない）
        let owner = store.owner
        // 押した時点で見ていた人。🔴 **前の人のブロックで次の人の格子を空にしない**
        // （2026-10-17）。答えが返ってから `photos = []` と `blockWrites` を進めていたので、
        // ログアウトして入り直したあとに、次の人の読み込みが写真を書き戻せなくなっていた
        let viewer = lastViewerId
        do {
            try await environment.moderation.block(userId: userId)
            // 人が替わっていたら、格子も `blockWrites` も触らない。
            // 進めたまま格子を空にすると、次の人の読み込みが写真を書き戻せない
            guard lastViewerId == viewer else { return }
            blockWrites += 1
            store.block(userId, for: owner)
            isFollowing = false
            followUnknown = false
            photos = []
            // 数も「読み込み中」に戻す。ブロックを解いたとき、読み直すまで「0 写真」と出ていた
            photoCount = .pending
            // **成功を赤字で出さない。** それまで `errorMessage` に入れて
            // いたので、うまくいった操作が「失敗」の見た目で出ていた
            toasts.show(L("ブロックしました。設定から解除できます。",
                          "Blocked. You can undo this in Settings."))
            await environment.gallery.setHidden(store.snapshot)
        } catch {
            guard lastViewerId == viewer else { return }
            actionMessage = (error as? LocalizedError)?.errorDescription ?? L("ブロックできませんでした", "Couldn't block")
        }
    }
}
