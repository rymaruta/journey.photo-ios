import SwiftUI

// 「AI に頼む」の答えの見た目 案A（札 #663・2026-11-20 owner 承認「推奨いいね」）。
// 模型: Artifact「AI に頼む 答えの見た目」（https://claude.ai/artifact/JQU5fnbW8J6RjKqT7P8qpU）の A。
// 値は模型どおり（板「journey.photo iOS」の黒塗りの真鍮。DesignSystem 01〜05、Components 01〜06）。
// - はじめの1〜2文は明朝 20pt（4行を超えるときは 18pt・`AskAnswerShape.leadPointSize`）
// - 写真の大きな札（幅 268、写真の高さ 190、角 16）を横に送る。札には名前（明朝 18）、理由1行（13、text-2）、
//   おすすめの季節と撮影に向く時間帯のチップ（台帳に欄がある所だけ）、「行きたい」（高さ 36、当たり 44）
// - 札を送ると地図のピンが大きくなり（`SpotMapMarker.selected`）、ピンを押すと札がその場所へ送られる
// - 札を押すと観光スポットの頁、写真を押すと持ち主の写真の詳細へ（写真の格子は `AskThreadView.photoGrid`）
// - 圏外では地図を出さない。写真を控えていない所は印だけ

/// 頭の1〜2文（明朝）。断りの1行も同じ所に 18pt で置く
struct AskLead: View {
    let text: String
    var small = false

    var body: some View {
        let size = AskAnswerShape.leadPointSize(text, small: small)
        Text(text)
            .font(JPFont.display(size, relativeTo: .title3))
            .tracking(size * 0.02)
            // 模型の行の高さ 1.55
            .lineSpacing(size * 0.3)
            .foregroundStyle(WebTheme.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 圏外の帯（模型 `.band.off`: 地 surface-2、縁 白 8%、角 12、電波なしの印、題 13 の 600、添え 12 の text-2）
struct AskOfflineBand: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WebTheme.text2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("電波が届かないので AI に聞けません", "No signal, so AI isn't available"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WebTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("前に見た観光スポットから選びました", "Picked from spots you've already seen"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: WebTheme.minTapTarget)
        .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("search.ask.offline")
    }
}

/// 読み込み中の骨格（模型 A: 文の2行 → 写真の札2枚 → 地図）。動きを減らす設定では脈打たない
struct AskLoadingSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AskText.loading, systemImage: "sparkle")
                .font(.system(size: 13))
                .foregroundStyle(WebTheme.text2)
            VStack(alignment: .leading, spacing: 10) {
                bone(height: 20)
                // 2行目は幅 70%（390pt の画面で右に約 107pt あける）
                bone(height: 20).padding(.trailing, 107)
            }
            HStack(spacing: AskSpotCarousel.gap) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 0) {
                        bone(height: AskSpotCarousel.photoHeight, radius: 0)
                        VStack(alignment: .leading, spacing: 8) {
                            bone(height: 18).frame(width: AskSpotCarousel.bodyWidth * 0.6)
                            bone(height: 12).frame(width: AskSpotCarousel.bodyWidth * 0.85)
                            HStack {
                                Spacer(minLength: 0)
                                bone(height: 36, radius: 18).frame(width: AskSpotCarousel.bodyWidth * 0.4)
                            }
                        }
                        .padding(12)
                    }
                    .frame(width: AskSpotCarousel.cardWidth)
                    .clipShape(RoundedRectangle(cornerRadius: AskSpotCarousel.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: AskSpotCarousel.cardRadius)
                        .strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, -JPSpace.gutter)
            .clipped()
            bone(height: AskSpotCarousel.mapHeight, radius: AskSpotCarousel.mapRadius)
        }
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
        }
    }

    private func bone(height: CGFloat, radius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(WebTheme.surface4)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}

/// 写真の札を横に送る並びと地図（案A）
struct AskSpotCarousel: View {
    let spots: [OfficialSpot]
    /// AI の理由（`spotId` → 1行）。無い所は台帳の案内の文
    let reasons: [String: String]
    let showsMap: Bool
    let officialSpots: [OfficialSpot]
    let photos: [Photo]
    let photosKnown: Bool

    /// 模型 `.bcard` の寸法
    static let cardWidth: CGFloat = 268
    /// 札の中の幅（左右の余白 12 ずつを除く）
    static let bodyWidth: CGFloat = 244
    static let photoHeight: CGFloat = 190
    static let cardRadius: CGFloat = 16
    static let gap: CGFloat = 12
    static let mapHeight: CGFloat = 160
    static let mapRadius: CGFloat = 14

    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 前に出ている札（送ると替わる。地図のピンを大きくする）
    @State private var current: String?
    /// ピンを押して送る先
    @State private var scrollTarget: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                JPEyebrowLine(L("観光スポット", "Spots"))
                Text("\((index(of: current) ?? 0) + 1) / \(spots.count)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(WebTheme.text3)
                    .accessibilityLabel(L("\(spots.count)か所のうち \((index(of: current) ?? 0) + 1) か所目",
                                          "\((index(of: current) ?? 0) + 1) of \(spots.count)"))
                    .accessibilityIdentifier("search.ask.count")
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Self.gap) {
                        ForEach(spots) { spot in
                            AskSpotCard(spot: spot, reason: reasons[spot.spotId] ?? AskLibrary.guide(for: spot, query: .init()),
                                        officialSpots: officialSpots, photos: photos, photosKnown: photosKnown)
                                // 大きな字では札の幅を画面の 86% に広げる（模型の「確かめていないこと」の想定）
                                .containerRelativeFrame(.horizontal) { w, _ in
                                    dynamicType.isAccessibilitySize ? w * 0.86 : Self.cardWidth
                                }
                                .id(spot.spotId)
                                // 前に出ている札: 左の余白（16）の所に、札の半分より近く来たもの
                                .onGeometryChange(for: Bool.self, of: { geo in
                                    abs(geo.frame(in: .scrollView).minX - JPSpace.gutter) < geo.size.width / 2
                                }) { front in
                                    if front, current != spot.spotId { current = spot.spotId }
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                // 回 1619 の絵 11z2: contentMargins では1枚目の札の左が約 6pt（模型は 16）に寄った。
                // 横に送って止まる位置（viewAligned）も含めて、安全域の余白で 16 にそろえる
                .safeAreaPadding(.horizontal, JPSpace.gutter)
                // 札の並びは画面の端まで（左右の余白の分だけ外へ出す）
                .padding(.horizontal, -JPSpace.gutter)
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .leading)
                    }
                    current = target
                    scrollTarget = nil
                }
            }
            if showsMap, spots.contains(where: { $0.coords != nil }) {
                AskPinsMap(spots: spots.filter { $0.coords != nil }, officialSpots: officialSpots, photos: photos,
                           photosKnown: photosKnown, current: current ?? spots.first?.spotId,
                           onPick: { spot in scrollTarget = spot.spotId })
                    .frame(height: Self.mapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Self.mapRadius))
                    .overlay(RoundedRectangle(cornerRadius: Self.mapRadius).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.825), value: current)
                    .accessibilityIdentifier("search.ask.map")
            }
        }
    }

    private func index(of id: String?) -> Int? {
        guard let id else { return nil }
        return spots.firstIndex { $0.spotId == id }
    }
}

/// 写真の大きな札1枚（模型 `.bcard`）。写真と名前を押すと観光スポットの頁
struct AskSpotCard: View {
    let spot: OfficialSpot
    let reason: String?
    let officialSpots: [OfficialSpot]
    let photos: [Photo]
    let photosKnown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                OfficialSpotView(spot: spot, spots: officialSpots, photos: photos, photosKnown: photosKnown)
            } label: {
                ZStack {
                    WebTheme.surface4
                    if let image = spot.photo {
                        SpotThumbImage(image: image, assumedRatioLimit: 2)
                    } else {
                        // 写真を控えていない所は印だけ（模型の圏外）
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 22))
                            .foregroundStyle(WebTheme.accent)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: AskSpotCarousel.photoHeight)
                .clipped()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("\(spot.name)の頁を開く", "Open \(spot.name)"))
            .accessibilityIdentifier("search.ask.spotPhoto")
            VStack(alignment: .leading, spacing: 6) {
                NavigationLink {
                    OfficialSpotView(spot: spot, spots: officialSpots, photos: photos, photosKnown: photosKnown)
                } label: {
                    Text(spot.name)
                        .font(JPFont.display(18, relativeTo: .title3))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.ask.spot")
                if let reason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 13))
                        .foregroundStyle(WebTheme.text2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("search.ask.spotReason")
                }
                HStack(alignment: .center, spacing: 8) {
                    AskSpotTags(spot: spot)
                    Spacer(minLength: 0)
                    AskWishButton(spot: spot)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: AskSpotCarousel.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: AskSpotCarousel.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: AskSpotCarousel.cardRadius).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.ask.card")
    }
}

/// おすすめの季節と撮影に向く時間帯のチップ（模型 `.tg`: 高さ 24、角 12、白 14% の縁、12、chip の字。時間帯は点線の縁）。
/// 台帳に欄がある所だけ。札の幅に収まるよう3つまで（季節を先に）
struct AskSpotTags: View {
    let spot: OfficialSpot

    nonisolated static func labels(_ spot: OfficialSpot) -> [(text: String, time: Bool)] {
        let seasons = SpotBodyText.seasonOrder.filter { spot.seasonKeys.contains($0) }.compactMap(SpotBodyText.seasonLabel)
        let times = SpotBodyText.timeOrder.filter { spot.timeKeys.contains($0) }.compactMap(SpotBodyText.timeLabel)
        return Array((seasons.map { ($0, false) } + times.prefix(1).map { ($0, true) }).prefix(3))
    }

    var body: some View {
        let tags = Self.labels(spot)
        HStack(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                Text(tag.text)
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.chipText)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(WebTheme.line, style: StrokeStyle(lineWidth: JPStroke.hairline, dash: tag.time ? [3, 2] : []))
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tags.isEmpty ? "" : L("向く季節と時間帯: ", "Best for: ") + tags.map(\.text).joined(separator: L("、", ", ")))
    }
}

/// 行動の札「行きたい」の小さい形（模型 `.wish.sm`: 見た目の高さ 36、当たり 44、白 8% の地、印だけ真鍮。
/// 入れたら真鍮 16% の地と真鍮の字。Components 01 と今の作りのまま・owner 承認済み）
struct AskWishButton: View {
    let spot: OfficialSpot

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter

    var body: some View {
        let key = SavedSpotKey.official(spot.slug)
        let wanted = wishlist.contains(key)
        Button {
            Task {
                let outcome = await WishlistSync.toggle(key, store: wishlist, service: environment.savedSpots)
                if let notice = WishlistSync.notice(for: outcome) { toasts.show(notice.text, kind: notice.kind) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: wanted ? "flag.fill" : "flag")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityHidden(true)
                Text(L("行きたい", "Want to go"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(wanted ? WebTheme.accent : WebTheme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(wanted ? WebTheme.accent.opacity(0.16) : Color.white.opacity(0.08), in: Capsule())
            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(wishlist.isSending(key))
        .accessibilityLabel(HomeSpotShelf.wishSpokenLabel(spot.name))
        .accessibilityValue(HomeSpotShelf.wishSpokenValue(saved: wanted))
        .accessibilityIdentifier("search.ask.wish")
    }
}
