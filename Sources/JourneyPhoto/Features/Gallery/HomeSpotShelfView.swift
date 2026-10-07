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
struct HomeSpotShelfView: View {

    let shelf: HomeSpotShelf.Shelf
    /// 撮影スポットの画面に渡す索引（近くの撮影スポット）
    let spots: [OfficialSpot]
    /// 撮影スポットの画面に渡す公開写真（この場所の写真）
    let photos: [Photo]
    /// 変わったら、本文が取れなかった場所を取り直す（引っぱって更新・前面に戻った・`HomeTopCardView` と同じ合図）
    var reloadToken: Int = 0

    @EnvironmentObject private var environment: AppEnvironment
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.spotShelf")
        .task(id: shelf.entries.map(\.spot.slug).joined(separator: ",") + "#\(reloadToken)") { await loadBodies() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(HomeSpotShelf.eyebrow(shelf.season))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityLabel(HomeSpotShelf.eyebrowSpoken(shelf.season))
                Text(HomeSpotShelf.heading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(HomeSpotShelf.note)
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
    }

    private func card(_ entry: HomeSpotShelf.Entry) -> some View {
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
                            Text(entry.spot.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WebTheme.foreground)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let region = entry.regionLabel {
                                Text(region)
                                    .font(.caption)
                                    .foregroundStyle(WebTheme.faint)
                                    .lineLimit(1)
                            }
                        }
                        Text(entry.guide)
                            .font(.footnote)
                            .foregroundStyle(WebTheme.muted2)
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
        }
        .frame(width: Self.cardWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 札の写真。**切り抜かない**（`.fit`・余白は黒）。本文を待つ間は空の地、写真が無ければ真鍮のピン
    @ViewBuilder
    private func photoArea(_ picture: HomeSpotShelf.Picture?, loaded: Bool) -> some View {
        ZStack {
            WebTheme.background
            if let picture {
                RemoteImage(url: picture.url, contentMode: .fit, onSettled: { ok in
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
