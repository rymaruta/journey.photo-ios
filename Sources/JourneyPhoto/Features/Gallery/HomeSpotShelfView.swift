import SwiftUI

/// ホームの「いまの季節のスポット」の段（板 Main の「THIS SEASON · いまの季節のスポット」・2026-10-03）。
///
/// どれを出すか・写真の選び方・通信の抑え方は `HomeSpotShelf` の注記。ここは描くのと、
/// **段に出ている数件の本文だけ**を取りに行く（`OfficialSpotService.fetchBody`）。
///
/// 見た目は板の札（地 白7%・角 14・余白 12・真鍮のピン・名前 15 Semibold・県 12・案内 13 の2行）に、
/// 作例の写真を上に足したもの。写真は**切り抜かない**（縦横比のまま・余白は黒）——作例の決まり
/// （CC BY-SA の写真を改変と受け取られる余地を作らない・docs/spot-samples-commons.md）。
/// 出典の1行は札の中の写真の下（真鍮のリンク＝黒地の上の出典のリンク・CLAUDE.md の owner の好み）。
/// 出典は撮影スポットへのリンクの**外**に置く（押す先が2つ重ならない）
///
/// **#417（2026-10-30 owner 採用）**:
/// - ④ 置き場所は「おすすめ」の中・写真の大1→2→2（5枚）の後ろ（`GalleryView.feedSection`）。フォロー中・新着では出さない
/// - ⑤ 見出しは眉「THIS SEASON · 秋」だけ（明朝の題は置かない・板 06「小さな段に明朝の題は置かない」）。
///   作例の注記は文を変えずに札の下へ。題の言葉（`HomeSpotShelf.heading`）は段の読み上げの名前に残す
/// - ⑥ 「行きたい」は札の幅いっぱいの帯（64）から、行の中の小ボタン（見た目 36・当たり 44・白 7% の地）へ
struct HomeSpotShelfView: View {

    let shelf: HomeSpotShelf.Shelf
    /// 撮影スポットの画面に渡す索引（近くの撮影スポット）
    let spots: [OfficialSpot]
    /// 撮影スポットの画面に渡す公開写真（この場所の写真）
    let photos: [Photo]
    /// 変わったら、本文が取れなかった場所を取り直す（引っぱって更新・前面に戻った・`HomeTopCardView` と同じ合図）
    var reloadToken: Int = 0

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter
    /// アクセシビリティ用の大きさでは出典の行数の上限を外す（`credit` の注記）
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 取りに行った本文（slug → 取れなければ nil）。**鍵が在る＝取りに行き終えた**。
    /// 取れた本文は画面が生きている間は取り直さない。取れなかった（nil）場所は `reloadToken` が変わったときに取り直す
    @State private var bodies: [String: SpotBody?] = [:]
    /// 読み込めなかった写真（Commons で消えた・差し替わった）。その1枚を出典ごと隠し、次の候補へ
    @State private var broken: Set<URL> = []

    /// 札の幅と写真の高さ
    private static let cardWidth: CGFloat = 240
    private static let photoHeight: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(shelf.entries) { entry in
                        card(entry)
                    }
                }
                .padding(.horizontal, 16)
                // 背を揃える（案内・出典の行数が違っても札の下端が揃う）
                .fixedSize(horizontal: false, vertical: true)
            }
            // ⑤ 作例の注記は札の下（文は変えない）
            Text(HomeSpotShelf.note)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, JPSpace.gutter)
        }
        .accessibilityElement(children: .contain)
        // 眉だけになった段の名前（読み上げで段に入ったとき「いまの季節の撮影スポット」）
        .accessibilityLabel(HomeSpotShelf.heading)
        .accessibilityIdentifier("home.spotShelf")
        .task(id: shelf.entries.map(\.spot.slug).joined(separator: ",") + "#\(reloadToken)") { await loadBodies() }
    }

    /// ⑤ 眉だけ（板: 眉の行は min-height 44）。共通の節の見出しを題なしで使う
    private var header: some View {
        JPSectionHeading(eyebrow: HomeSpotShelf.eyebrow(shelf.season),
                         spoken: HomeSpotShelf.eyebrowSpoken(shelf.season))
            .frame(minHeight: WebTheme.minTapTarget)
            .padding(.horizontal, JPSpace.gutter)
    }

    private func card(_ entry: HomeSpotShelf.Entry) -> some View {
        let wishKey = SavedSpotKey.official(entry.spot.slug)
        let wanted = wishlist.contains(wishKey)
        let loaded = bodies[entry.spot.slug] != nil
        let spotBody = bodies[entry.spot.slug] ?? nil
        // **本文を待ってから決める**——先に代表写真を出すと、作例が届いた瞬間に写真が入れ替わる
        let picture = loaded ? HomeSpotShelf.picture(for: entry.spot, body: spotBody, season: shelf.season, broken: broken) : nil
        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                OfficialSpotView(spot: entry.spot, spots: spots, photos: photos)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    photoArea(picture, loaded: loaded)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(WebTheme.accent)
                                .accessibilityHidden(true)
                            // 場所の名前は明朝（v2 の板の場所の行・明朝の下限 18）
                            Text(entry.spot.name)
                                .font(JPFont.rowTitle)
                                .foregroundStyle(WebTheme.text)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let region = entry.regionLabel {
                                Text(region)
                                    .font(JPFont.caption)
                                    .foregroundStyle(WebTheme.text3)
                                    .lineLimit(1)
                            }
                        }
                        Text(entry.guide)
                            .font(JPFont.footnote)
                            .foregroundStyle(WebTheme.text2)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(12)
                }
                .frame(width: Self.cardWidth, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.spotShelf.card")
            if let picture {
                credit(picture)
            }
            // 2026-10-18 判断: 「行きたい」は札の**下端にそろえる**。出典の無い札（代表写真・ピンだけ）は
            // 出典の行の分だけ背が低く、そのままだとボタンが札ごとに上下にずれる。段は背をそろえている
            // （`fixedSize(vertical:)`＋札の `maxHeight: .infinity`）ので、ここで余りを空けて下へ送る
            Spacer(minLength: 0)
            // ホームで見つけた場所を、詳細へ入らずに「行きたい」へ保存できる。
            // ⑥（#417）: 行の中の小ボタン（見た目 36・当たり 44・白 7% の地・左寄せ）。保存済みは白 94% の塗り＋墨
            // （撮影スポットの画面の行動の札 `SpotDetailParts.actionLabel` と同じ色の組）
            Button {
                Task {
                    let outcome = await WishlistSync.toggle(wishKey, store: wishlist, service: environment.savedSpots)
                    if let notice = WishlistSync.notice(for: outcome) {
                        toasts.show(notice.text, kind: notice.kind)
                    }
                }
            } label: {
                wishLabel(wanted: wanted, busy: wishlist.isSending(wishKey))
            }
            .buttonStyle(.plain)
            .disabled(wishlist.isSending(wishKey))
            // 札の余白 12（板 padding 12）。上下は当たりの 4 を足して 8（＝札の下端まで 12）
            .padding(.horizontal, 12)
            .padding(.bottom, 12 - JPOutlineSize.inline.tapSlack)
            // どの場所の「行きたい」か・保存済みかを読み上げでも分かるように（塗りの色だけにしない）
            .accessibilityLabel(HomeSpotShelf.wishSpokenLabel(entry.spot.name))
            .accessibilityValue(HomeSpotShelf.wishSpokenValue(saved: wanted))
            .accessibilityIdentifier("home.spotShelf.wish")
        }
        .frame(width: Self.cardWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        // v2: 札の面（#0E0E0F）に白 8% の縁・角 14（写真の札）
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.m))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
    }

    /// ⑥ 「行きたい」の小ボタン（見た目 36・当たり 44）。待っている間は記号の代わりに輪（名前は替えない）
    private func wishLabel(wanted: Bool, busy: Bool) -> some View {
        HStack(spacing: 6) {
            if busy {
                ProgressView().controlSize(.mini)
                    .tint(wanted ? WebTheme.accentText : WebTheme.foreground)
            } else {
                Image(systemName: wanted ? "heart.fill" : "heart")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(L("行きたい", "Want to go"))
        }
        .jpCapsuleFace(font: JPOutlineSize.inline.font,
                       text: wanted ? WebTheme.accentText : WebTheme.foreground,
                       fill: wanted ? WebTheme.accentBackground : WebTheme.surface,
                       border: Color.clear, fullWidth: false,
                       minHeight: Self.wishHeight, textInset: Self.wishInset)
        .fixedSize()
        .padding(.vertical, JPOutlineSize.inline.tapSlack)
        .contentShape(Rectangle())
    }

    /// 「行きたい」の見た目の高さ（板 36＝行の中の小ボタン）と字の左右（板 padding 0 14）
    nonisolated static let wishHeight: CGFloat = JPHeight.inlineButton
    nonisolated static let wishInset: CGFloat = 14

    /// 札の写真。**切り抜かない**（`.fit`・余白は黒）。本文を待つ間は空の地、写真が無ければ真鍮のピン
    @ViewBuilder
    private func photoArea(_ picture: HomeSpotShelf.Picture?, loaded: Bool) -> some View {
        ZStack {
            WebTheme.background
            if let picture {
                // 2026-10-28 判断: **札の大きさ×画面の倍率まで縮めて**読む（`DownsampledRemoteImage`・ホームの
                // 大きい枠と同じ部品）。`RemoteImage`（`AsyncImage`）は表紙の元の大きさのまま展開していた。
                // 敷き方は `.fit` のままなので、長い辺は札の幅 240pt ぶんで足りる（縦長は高さ 150pt に収まる）
                DownsampledRemoteImage(url: picture.url, contentMode: .fit, onSettled: { ok in
                    if !ok { broken.insert(picture.url) }
                })
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel(picture.accessibilityLabel)
            } else if loaded {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: Self.cardWidth, height: Self.photoHeight)
        .clipped()
    }

    /// 出典の1行（題 / 写真: 作者 / ライセンス / Wikimedia Commons）。当たりは1行全体で 44pt 以上
    /// （`CreditLinksMenu`・撮影スポットの画面の作例と同じ部品）。
    ///
    /// 2026-10-03 判断: **3行まで・切るのは頭**。札は幅 240 で、題（Commons のファイル名）が長いと
    /// 段の背が伸び、下の写真の一覧が押し下がる。頭で切れば作者・ライセンス・出典（表示の条件の
    /// 3つ）は必ず残り、題も末尾は見える。全文は読み上げ（`accessibilityLabel`）とリンク先で読める。
    /// **アクセシビリティ用の大きさでは上限を外す**——大きな字で3行だと作者の途中で切れうる
    private func credit(_ picture: HomeSpotShelf.Picture) -> some View {
        CreditLinksMenu(links: picture.creditLinks, accessibilityLabel: picture.credit) {
            Text(picture.linkedCredit)
                .tint(WebTheme.accent)
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .truncationMode(.head)
                .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
                .multilineTextAlignment(.leading)
                .frame(width: Self.cardWidth - 24, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .accessibilityIdentifier("home.spotShelf.credit")
    }

    /// 段に出ている場所の本文だけを取る（取れたものは取り直さない・取れなかったものは取り直す
    /// `HomeSpotShelf.slugsToFetch`）。並べて取る（最大 `HomeSpotShelf.count` 本）
    private func loadBodies() async {
        let slugs = HomeSpotShelf.slugsToFetch(shelf.entries, bodies: bodies)
        guard !slugs.isEmpty else { return }
        let service = environment.spots
        await withTaskGroup(of: (String, SpotBody?).self) { group in
            for slug in slugs {
                group.addTask { (slug, await service.fetchBody(slug: slug)) }
            }
            for await (slug, fetched) in group {
                // 画面を離れて止められた回は書かない（取り消しを「無い」と覚えない）
                if Task.isCancelled { continue }
                bodies[slug] = .some(fetched)
            }
        }
    }
}

/// 「いまの季節のスポット」の段の中身（#417 ④）。決めるのは上の札（`HomeTopCardView`）、描くのは写真の一覧の中
struct HomeSeasonShelfSlot {
    let shelf: HomeSpotShelf.Shelf
    /// 撮影スポットの画面に渡す索引（近くの撮影スポット）
    let spots: [OfficialSpot]
}

/// 段を渡し直す合図（段の中身と、索引を書き換えた回数）
struct HomeSeasonShelfKey: Equatable {
    let shelf: HomeSpotShelf.Shelf?
    let spotsRevision: Int
}
