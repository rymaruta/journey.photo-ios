import SwiftUI

/// **DM に届いた撮影スポットの札**（資料「SNS をもっと SNS に」⑤「一緒に行こう」の受けた人の画面・1.1.83・2026-11-12）。
///
/// 文の中の撮影スポットの頁のリンク（`DMSpotShare.slug`）から、端末の撮影スポットの索引を引いて描く。
/// 並び（資料の模型どおり）: 写真 130（出典を1行・CC の表示条件）→ 真鍮の眉「一緒に行こう」→ 明朝 18 の名前 →
/// 12 の「撮影スポット · 地域」→ 白の塗りに墨の「行きたい場所に入れる」（見た目 36・当たり 44）。
/// 札（写真と名前）を押すと撮影スポットの頁。札の幅は 240（写真の札 `DMPhotoQuote` の 220 と近い幅）。
///
/// 索引に無い・読めないときは札を作らず、リンクの文をそのまま出す（`fallback`）——黙って消さない。
struct DMSpotCard: View {
    let slug: String
    let mine: Bool
    /// 札が作れなかったときに出す文（届いたリンクそのもの）
    let fallback: String

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter

    private typealias Phase = DMSpotCardPhase
    /// 🔴 **読み終えた中身から始める**（`DMSpotCardMemory`・2026-11-12 DM の会話が固まる件・1.1.85）。
    /// 会話の行は `LazyVStack` が作り直す。`@State` だけに持つと、作り直すたびに「読み込み中」（高さ 250）から始まり、
    /// 読み終えると札の高さに替わる——この高さの替わりで、会話を払った直後から配置のやり直しが終わらなくなっていた
    /// （Mac run 1186: 印なし 61.1・61.0・60.9 秒で固まる／札の高さを固定・状態を替えない・札を出さないでは 1.7〜3.1 秒）
    @State private var phase: Phase

    init(slug: String, mine: Bool, fallback: String) {
        self.slug = slug
        self.mine = mine
        self.fallback = fallback
        let start: Phase
        if DMHangProbe.spotCardStatic {
            start = .missing
        } else if DMHangProbe.revertSpotFix {
            // `-JPDMRevertSpotFix`（UI テストの事実取りだけ）: 直す前の形（いつも「読み込み中」から）
            start = .loading
        } else {
            start = DMSpotCardMemory.phase(for: slug) ?? .loading
        }
        _phase = State(initialValue: start)
    }

    static let width: CGFloat = 240
    static let photoHeight: CGFloat = 130

    var body: some View {
        Group {
            switch phase {
            case .loading:
                RoundedRectangle(cornerRadius: JPRadius.l)
                    .fill(WebTheme.surface3)
                    .frame(width: Self.width, height: Self.photoHeight + 120)
                    .accessibilityLabel(L("観光スポットを読み込み中", "Loading the spot"))
            case .found(let spot, let index):
                card(spot, index: index)
            case .missing:
                Link(destination: URL(string: fallback) ?? AppConfig.siteBaseURL) {
                    Text(fallback)
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.accent)
                        .underline()
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, JPSpace.m)
                        .padding(.vertical, 10)
                        .background(WebTheme.surface3, in: RoundedRectangle(cornerRadius: DMLook.bubbleRadius))
                }
                .accessibilityIdentifier("dm.spotCard.link")
            }
        }
        // `-JPDMSpotCardFixed`（UI テストの事実取りだけ・`DMHangProbe`）: どの状態でも同じ高さ
        .frame(height: DMHangProbe.spotCardFixed ? DMHangProbe.spotCardFixedHeight : nil, alignment: .top)
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(.top, JPSpace.xxs)
        .onAppear { DMHangProbe.count("spotCard.appear") }
        .onDisappear { DMHangProbe.count("spotCard.disappear") }
        .task(id: slug) {
            // `-JPDMSpotCardStatic`（UI テストの事実取りだけ）: 読み込まず、いつもリンクの文（状態が替わらない）
            if DMHangProbe.spotCardStatic {
                phase = .missing
                return
            }
            // 読み終えた中身で始まった札は読み直さない（高さを替えない）
            guard phase == .loading else { return }
            await load()
        }
    }

    private func card(_ spot: OfficialSpot, index: [OfficialSpot]) -> some View {
        let key = SavedSpotKey.official(spot.slug)
        let wanted = wishlist.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                OfficialSpotView(spot: spot, spots: index, photos: [], photosKnown: false)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    if let photo = spot.photo {
                        Color.clear
                            .frame(height: Self.photoHeight)
                            .overlay(RemoteImage(url: photo.url))
                            .clipped()
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DMSpotShare.eyebrow)
                            .jpEyebrow()
                            .foregroundStyle(WebTheme.accent)
                        Text(spot.name)
                            .font(JPFont.rowTitle)
                            .foregroundStyle(WebTheme.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        // 種類と地域は中黒で区切らず、字の太さ・色と 6pt の間で分ける（2026-11-12 の決まり）
                        HStack(spacing: 6) {
                            Text(DMSpotShare.kindLabel)
                                .font(JPFont.caption.weight(.semibold))
                                .foregroundStyle(WebTheme.text2)
                            if let region = spot.regionLabel, !region.isEmpty {
                                Text(region)
                                    .font(JPFont.caption)
                                    .foregroundStyle(WebTheme.text3)
                            }
                        }
                        .lineLimit(1)
                    }
                    .padding(.horizontal, JPSpace.s)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DMSpotShare.spoken(name: spot.name, region: spot.regionLabel, mine: mine))
            // 子を畳む（`.ignore`）とボタンの印が落ちる（Mac run 1096 で `dm.spotCard.open` が Button として見つからなかった）。
            // 送るシートの丸（`SendSheet.actionLabel`）と同じく、印を付け直す
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(L("観光スポットのページを開きます", "Opens the spot page"))
            .accessibilityIdentifier("dm.spotCard.open")
            Button {
                guard !wanted else { return }
                Task {
                    let outcome = await WishlistSync.set(key, wanted: true, store: wishlist,
                                                         service: environment.savedSpots)
                    if let notice = WishlistSync.notice(for: outcome) { toasts.show(notice.text, kind: notice.kind) }
                }
            } label: {
                // フォローの札（`FollowPill`）と同じ色で、札の幅いっぱい（資料の模型）。見た目 36・当たり 44
                Text(wanted ? DMSpotShare.addedToWishlist : DMSpotShare.addToWishlist)
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(wanted ? Color.white : WebTheme.accentText)
                    // 2026-11-12（確かめ役の指摘・板 DM）: DM の画面の主ボタン（送る・承認）と同じ accent-fill に墨
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(wanted ? Color.white.opacity(0.12) : WebTheme.accentFill, in: Capsule())
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(wanted || wishlist.isSending(key))
            .padding(.horizontal, JPSpace.s)
            .padding(.top, JPSpace.xxs)
            .padding(.bottom, JPSpace.xs)
            .accessibilityIdentifier("dm.spotCard.wish")
            // 出典（CC BY・BY-SA の表示条件）。写真の下ではなく札の下端に置く（押す先を重ねない）
            if let photo = spot.photo {
                Text(SpotPrefectureIndex.creditText(photo))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, JPSpace.s)
                    .padding(.bottom, JPSpace.xs)
            }
        }
        .frame(width: Self.width)
        // 札の地は板どおり surface-1（`WebTheme.card`・確かめ役の指摘・2026-11-12）
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dm.spotCard")
    }

    /// 端末の索引からスラッグで引き、写真の無い行は詳細を重ねる。見つからなければリンクの文のまま
    private func load() async {
        DMHangProbe.count("spotCard.load")
        guard let index = try? await environment.spots.fetchIndex() else {
            if !Task.isCancelled { settle(.missing, failed: true) }
            return
        }
        guard let row = index.first(where: { $0.slug == slug }), !row.isDraft else {
            if !Task.isCancelled { settle(.missing, failed: false) }
            return
        }
        let detailed = row.isIndexOnly ? await environment.spots.withDetails([row], for: [row]).first ?? row : row
        guard !Task.isCancelled else { return }
        settle(.found(detailed, index), failed: false)
    }

    /// 読み終えた中身を札に映し、作り直した札が同じ中身から始まるよう覚える
    private func settle(_ settled: Phase, failed: Bool) {
        DMHangProbe.count("spotCard.settle")
        if !DMHangProbe.revertSpotFix { DMSpotCardMemory.remember(settled, for: slug, failed: failed) }
        phase = settled
    }
}

/// 観光スポットの札の状態（読み込み中・読めた・読めない）
enum DMSpotCardPhase: Equatable {
    case loading, found(OfficialSpot, [OfficialSpot]), missing

    static func == (a: DMSpotCardPhase, b: DMSpotCardPhase) -> Bool {
        switch (a, b) {
        case (.loading, .loading), (.missing, .missing): return true
        case let (.found(x, _), .found(y, _)): return x.spotId == y.spotId
        default: return false
        }
    }
}

/// **読み終えた札の中身（スラッグごと・アプリを閉じるまで）**（2026-11-12・DM の会話が固まる件・1.1.85）。
///
/// 会話の行は `LazyVStack` が画面の外で作り直し、そのたびに札の `@State` は初めの値に戻る。初めの値を
/// いつも「読み込み中」（高さ 250）にすると、作り直した札は読み込み中 → 読み終えた札と高さが替わり、
/// 会話を下へ払った直後から主スレッドが戻らなくなった（Mac run 1186 の `DMHANG` の行:
/// 印なしは払い1回 61.1・61.0・60.9 秒、札の高さを固定 `SpotCardFixed` は 3.1 秒、
/// 状態を替えない `SpotCardStatic` は 1.8 秒、札を出さない `NoSpotCard` は 1.8 秒）。
/// 作り直した札は、ここに覚えた中身から始める（読み込み中を挟まない＝高さが替わらない）。
///
/// 読めなかった（索引を取れない）ときの「読めない」は 60 秒だけ覚える（電波が戻ったら読み直せるように）。
/// 索引に無いスラッグの「読めない」と、読めた札はアプリを閉じるまで覚える
enum DMSpotCardMemory {
    static let failedLifetime: TimeInterval = 60

    private static let lock = NSLock()
    nonisolated(unsafe) private static var settled: [String: (phase: DMSpotCardPhase, expires: Date?)] = [:]

    static func phase(for slug: String, now: Date = Date()) -> DMSpotCardPhase? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = settled[slug] else { return nil }
        if let expires = entry.expires, now >= expires {
            settled[slug] = nil
            return nil
        }
        return entry.phase
    }

    static func remember(_ phase: DMSpotCardPhase, for slug: String, failed: Bool, now: Date = Date()) {
        guard phase != .loading else { return }
        lock.lock()
        defer { lock.unlock() }
        settled[slug] = (phase, failed ? now.addingTimeInterval(failedLifetime) : nil)
    }

    /// 試験だけ
    static func forgetAll() {
        lock.lock()
        settled = [:]
        lock.unlock()
    }
}
