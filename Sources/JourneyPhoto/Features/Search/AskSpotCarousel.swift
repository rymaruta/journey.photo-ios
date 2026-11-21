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

/// 読み込み中の骨格（版3「待ち時間」・2026-11-21 判断 札 #675）。押した直後から出す: 「✦ 答えを用意しています」と頭の文の2行。
/// 字から答えの種類が分かるときは、その形の骨格を続けて出す（札は写真の札2枚、流れは日の見出しと番号の丸3つ）。
/// 動きを減らす設定では脈打たない
struct AskLoadingSkeleton: View {
    var kind: AskAnswerKind? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AskText.loading, systemImage: "sparkle")
                .font(.system(size: 13))
                .foregroundStyle(WebTheme.text2)
            VStack(alignment: .leading, spacing: 10) {
                bone(height: 20).padding(.trailing, 40)
                // 2行目は幅 60%
                bone(height: 20).padding(.trailing, 140)
            }
            switch kind {
            case .cards?, .compare?:
                cards
            case .plan?:
                plan
            default:
                EmptyView()
            }
        }
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            // UI テストのときは脈打たない（終わらない動きが残ると、アプリが静まらず閉じにくい・回 1619、1626 の調べ）
            guard !reduceMotion, !AskFixture.isOn, !PerfRecorder.shared.isEnabled else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
        }
    }

    private var cards: some View {
        HStack(spacing: AskSpotCarousel.gap) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    bone(height: AskSpotCarousel.photoHeight, radius: 0)
                    VStack(alignment: .leading, spacing: 8) {
                        bone(height: 18).frame(width: AskSpotCarousel.bodyWidth * 0.6)
                        bone(height: 13).frame(width: AskSpotCarousel.bodyWidth * 0.85)
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
    }

    /// 流れの骨格（日の見出し 70、番号の丸の縁 白の段 8、写真 44、名前と札の2本）
    private var plan: some View {
        VStack(alignment: .leading, spacing: 4) {
            bone(height: 13).frame(width: 70)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().strokeBorder(WebTheme.surface8, lineWidth: 1.4).frame(width: 24, height: 24)
                    bone(height: 44, radius: 10).frame(width: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        bone(height: 16).frame(width: 150)
                        bone(height: 12).frame(width: 80)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 56)
            }
        }
        .accessibilityIdentifier("search.ask.planSkeleton")
    }

    private func bone(height: CGFloat, radius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(WebTheme.surface4)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}

/// 札の並びの調べ（UI テストのときだけ数える・回 1644 の「大きな字で閉じられない」「札の左の数字と絵が合わない」の調べ）。
/// 並び（`AskSpotCarousel`）の body、onGeometryChange、送り（scrollTo）、地図のカメラの動き、画像の読み込みを時刻つきで数え、
/// 札の左、並びの左、頭の文の左を、答えの画面の名前付きの座標（`space`）で持つ。描き直しを起こさないよう、状態ではなく参照で持つ
final class AskCarouselStats: @unchecked Sendable {
    static let shared = AskCarouselStats()
    /// 答えの画面（`AskThreadView`）の名前付きの座標。原点は答えの画面の左端（左右の余白の外）
    static let space = "askThread"

    enum Kind: String, CaseIterable { case body, geo, scroll, mapCam }

    private let lock = NSLock()
    private var events: [Kind: [Date]] = [:]
    private var appearedAt: Date?
    private var imagesStarted = 0
    private var imagesInFlight = 0
    private var positions: [String: CGFloat] = [:]

    var isOn: Bool { AskFixture.isOn }

    func hit(_ kind: Kind) {
        guard isOn else { return }
        lock.lock(); defer { lock.unlock() }
        var list = events[kind, default: []]
        list.append(Date())
        if list.count > 4000 { list.removeFirst(list.count - 4000) }
        events[kind] = list
    }

    func appeared() {
        guard isOn else { return }
        lock.lock(); defer { lock.unlock() }
        if appearedAt == nil { appearedAt = Date() }
    }

    func position(_ name: String, _ x: CGFloat) {
        guard isOn else { return }
        lock.lock(); defer { lock.unlock() }
        positions[name] = x
    }

    func imageStarted() {
        guard isOn else { return }
        lock.lock(); defer { lock.unlock() }
        imagesStarted += 1
        imagesInFlight += 1
    }

    func imageEnded() {
        guard isOn else { return }
        lock.lock(); defer { lock.unlock() }
        imagesInFlight -= 1
    }

    /// 「閉じる直前の1秒（読んだ時の直前1秒）」と「答えが出てから2秒後の1秒」の回数と、位置と画像の数
    func summary(now: Date = Date()) -> String {
        lock.lock(); defer { lock.unlock() }
        func count(_ k: Kind, _ from: Date, _ to: Date) -> Int {
            (events[k] ?? []).filter { $0 >= from && $0 < to }.count
        }
        let last = Kind.allCases.map { "\($0.rawValue)=\(count($0, now.addingTimeInterval(-1), now))" }.joined(separator: ",")
        var at2 = "-"
        if let a = appearedAt {
            let from = a.addingTimeInterval(2), to = a.addingTimeInterval(3)
            at2 = Kind.allCases.map { "\($0.rawValue)=\(count($0, from, to))" }.joined(separator: ",")
        }
        let total = Kind.allCases.map { "\($0.rawValue)=\(events[$0]?.count ?? 0)" }.joined(separator: ",")
        let pos = positions.keys.sorted().map { "\($0)=" + String(format: "%.1f", positions[$0] ?? -1) }.joined(separator: ",")
        return "last1s=[\(last)] at2s=[\(at2)] total=[\(total)] pos=[\(pos)] images=\(imagesInFlight)/\(imagesStarted)"
    }
}

/// 写真の札を横に送る並びと地図（案A）
struct AskSpotCarousel: View {
    let spots: [OfficialSpot]
    /// AI の理由（`spotId` → 1行）。無い所は台帳の案内の文
    let reasons: [String: String]
    let showsMap: Bool
    /// 並べ直しが終わったか（案内の文の詳細を読み終えた）。終わってから1枚目の位置を1回だけそろえる
    var settled = true
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
    /// 札の並びの見えている幅（大きな字の札の幅と、ピンで送る先の位置に使う）
    @State private var containerWidth: CGFloat = 0
    /// 1枚目の札の画面の上の左端と幅（UI テストのときだけ `search.ask.cardProbe` に出す・回 1619〜1635 の約 6pt の調べ）
    @State private var firstCardFrame: CGRect = .zero
    /// 最初の位置へ1回だけ送り直したか
    @State private var placedFirst = false
    /// 札の並び（横に送る枠）の画面の上の左端
    @State private var scrollFrameX: CGFloat = 0
    /// 1枚目の札の位置が替わった記録（UI テストのときだけ・回 1641 の調べ）。「+経過ms 何が x=札の左 sv=枠の左」
    @State private var cardLog: [String] = []
    @State private var appearedAt = Date()
    /// 答えが出た直後と 0.5 秒後の1枚目の札の左
    @State private var firstXAtAppear: CGFloat?
    @State private var firstXAfterHalf: CGFloat?

    /// 札1枚の幅（大きな字では見えている幅の 86%）
    private var cardWidth: CGFloat {
        dynamicType.isAccessibilitySize && containerWidth > 0 ? containerWidth * 0.86 : Self.cardWidth
    }

    var body: some View {
        let _ = AskCarouselStats.shared.hit(.body)
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
                                .frame(width: cardWidth)
                                .id(spot.spotId)
                                // 前に出ている札: 左の余白（16）の所に、札の半分より近く来たもの
                                .onGeometryChange(for: Bool.self, of: { geo in
                                    abs(geo.frame(in: .scrollView).minX - JPSpace.gutter) < geo.size.width / 2
                                }) { front in
                                    AskCarouselStats.shared.hit(.geo)
                                    if front, current != spot.spotId { current = spot.spotId }
                                }
                                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                                    guard AskFixture.isOn, spot.spotId == spots.first?.spotId else { return }
                                    AskCarouselStats.shared.hit(.geo)
                                    // 位置が変わらないなら書かない（描き直しの輪を作らない）
                                    guard frame != firstCardFrame else { return }
                                    firstCardFrame = frame
                                    if firstXAtAppear == nil { firstXAtAppear = frame.minX }
                                    note("card")
                                }
                                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(AskCarouselStats.space)).minX }) { x in
                                    if spot.spotId == spots.first?.spotId { AskCarouselStats.shared.position("card", x) }
                                }
                        }
                    }
                    // 回 1619・1626 の絵 11z2: contentMargins でも safeAreaPadding でも1枚目の札の左が約 6pt（模型は 16）だった。
                    // 余白は並びの中に直に付ける（2026-11-20 判断）。止まる位置は `AskCardSnap` が札の幅＋12 ごとにそろえる
                    .padding(.horizontal, JPSpace.gutter)
                }
                .scrollTargetBehavior(AskCardSnap(step: cardWidth + Self.gap))
                // 札の並びは画面の端まで（左右の余白の分だけ外へ出す）
                .padding(.horizontal, -JPSpace.gutter)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
                    AskCarouselStats.shared.hit(.geo)
                    if frame.width != containerWidth { containerWidth = frame.width }
                    if frame.minX != scrollFrameX { scrollFrameX = frame.minX }
                    note("width")
                    placeFirstIfSettled(proxy)
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(AskCarouselStats.space)).minX }) { x in
                    AskCarouselStats.shared.position("scroll", x)
                }
                // 回 1619〜1641 の絵 11z2、11z5: 答えが出た直後だけ1枚目の札の左が約 6pt（少しあとの絵、送ったあと、大きな字では 16）。
                // 並べ直し（並びの幅が決まる、案内の文の詳細が届く）が終わってから1回だけ、1枚目を左から 16 へ送り直す（動きなし）。
                // どの変化のあとにずれるかは `search.ask.cardProbe` の記録で見る
                .onChange(of: settled) { _, _ in
                    note("settled=\(settled)")
                    placeFirstIfSettled(proxy)
                }
                .onChange(of: spots) { _, _ in note("spots") }
                .task {
                    guard AskFixture.isOn else { return }
                    AskCarouselStats.shared.appeared()
                    appearedAt = Date()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    firstXAfterHalf = firstCardFrame.minX
                    note("t500")
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    AskCarouselStats.shared.hit(.scroll)
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                        // 札の左を見えている所の左から 16 に置く（`scrollTo` の anchor は札と並びの同じ割合の点をそろえる）
                        proxy.scrollTo(target, anchor: AskCardSnap.anchor(container: containerWidth, card: cardWidth))
                    }
                    current = target
                    scrollTarget = nil
                }
            }
            if AskFixture.isOn {
                Text(".")
                    .font(.caption2)
                    .foregroundStyle(Color.clear)
                    .accessibilityIdentifier("search.ask.cardProbe")
                    .accessibilityValue(String(format: "firstX=%.1f x0=%.1f x500=%.1f firstW=%.1f firstH=%.1f container=%.1f card=%.1f sv=%.1f",
                                               firstCardFrame.minX, firstXAtAppear ?? -1, firstXAfterHalf ?? -1,
                                               firstCardFrame.width, firstCardFrame.height, containerWidth, cardWidth,
                                               scrollFrameX)
                                        + " placed=\(placedFirst) settled=\(settled) log=[" + cardLog.joined(separator: ";") + "]")
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

    /// 並べ直しが終わっていて（幅が決まり、詳細を読み終えた）、まだなら、1枚目を左から 16 へ1回だけ送り直す
    private func placeFirstIfSettled(_ proxy: ScrollViewProxy) {
        guard !placedFirst, settled, containerWidth > 0, let first = spots.first?.spotId else { return }
        placedFirst = true
        AskCarouselStats.shared.hit(.scroll)
        proxy.scrollTo(first, anchor: AskCardSnap.anchor(container: containerWidth, card: cardWidth))
        note("placed")
    }

    /// 1枚目の札の位置の記録に1行足す（UI テストのときだけ・同じ値が続くときは足さない・24 行まで）
    private func note(_ what: String) {
        guard AskFixture.isOn else { return }
        let ms = Int(Date().timeIntervalSince(appearedAt) * 1000)
        let entry = String(format: "%@ x=%.1f sv=%.1f w=%.0f", what, firstCardFrame.minX, scrollFrameX, containerWidth)
        if let last = cardLog.last, last.hasSuffix(entry) { return }
        if cardLog.count >= 24 { return }
        cardLog.append("+\(ms) " + entry)
        if cardLog.count > 24 { cardLog.removeFirst(cardLog.count - 24) }
    }

    private func index(of id: String?) -> Int? {
        guard let id else { return nil }
        return spots.firstIndex { $0.spotId == id }
    }
}

/// 札の並びの止まる位置（札の幅＋すき間ごと）。並びの中の左の余白 16 の分は動かさないので、どの札も左から 16 に止まる
struct AskCardSnap: ScrollTargetBehavior {
    let step: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.x = Self.snapped(target.rect.minX, step: step,
                                            maxOffset: context.contentSize.width - context.containerSize.width)
    }

    /// 止まる位置（いちばん近い札の頭。端を越えない）
    nonisolated static func snapped(_ x: CGFloat, step: CGFloat, maxOffset: CGFloat) -> CGFloat {
        guard step > 0 else { return x }
        let upper = max(0, maxOffset)
        return min(upper, max(0, (x / step).rounded() * step))
    }

    /// `scrollTo` の anchor（札の左が見えている所の左から 16 に来る割合）
    nonisolated static func anchor(container: CGFloat, card: CGFloat) -> UnitPoint {
        UnitPoint(x: anchorX(container: container, card: card), y: 0)
    }

    /// anchor の横の割合（札の左 = 割合 ×（並びの幅 − 札の幅）= 16）
    nonisolated static func anchorX(container: CGFloat, card: CGFloat) -> CGFloat {
        let room = container - card
        guard room > 0 else { return 0 }
        return min(1, JPSpace.gutter / room)
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
                // 回 1650 の数字: 札の枠（268）も並びの左（16）も合っていたのに、絵では札の左が約 7pt だった。写真を高さ 190 で
                // 埋めると横長の写真は幅が約 285 になり、`.frame(maxWidth: .infinity)` は大きい子を縮めないので、札の中身が
                // 枠の左右へ約 9pt ずつはみ出していた（大きな字の札は幅 346 で写真より広く、はみ出さない）。
                // minWidth: 0 で、写真の枠を札の幅に合わせる（みんなの写真の格子と同じ）
                .frame(minWidth: 0, maxWidth: .infinity)
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
