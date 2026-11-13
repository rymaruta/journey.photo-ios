import SwiftUI

/// **DM に届いた撮影スポットの札**（資料「SNS をもっと SNS に」⑤「一緒に行こう」の受けた人の画面・1.1.83・2026-11-12）。
///
/// 文の中の撮影スポットの頁のリンク（`DMSpotShare.slug`）から、端末の撮影スポットの索引を引いて描く。
/// 並び（資料の模型どおり）: 写真 130（枠の余りがあれば伸びる）→ 真鍮の眉「一緒に行こう」→ 明朝 18 の名前 →
/// 12 の「観光スポット」と地域 → 真鍮の塗りに墨の「行きたい場所に入れる」（見た目 36・当たり 44）→ 出典を1行（CC の表示条件）。
/// 札（写真と名前）を押すと撮影スポットの頁。札の幅は 240（資料「画面デザインの案」第1章の模型 `.spot{width:240}`）。
///
/// 🔴 **札の枠の高さは、読み込み中・読めた・読めないで同じ**（`DMSpotCardBox`・2026-11-12 DM の会話が固まる件・1.1.85）。
/// 会話の行は `LazyVStack` に並ぶ。札の高さが読み込み中（250）から読み終えた札の高さに替わると、
/// 会話を払った直後から配置のやり直しが終わらなくなった（Mac run 1186・1190 の `DMHANG` の行:
/// 直す前は払い1回 60.8〜61.2 秒で固まる。札の高さを固定した版 `SpotCardFixed` は 3.1 秒。
/// 読み終えた中身を覚えるだけの直しでは、1回目に開いた会話（作り直しなし・読み込み1回）が 61.2 秒で固まった。
/// この枠にした run 1191 では 3.0〜3.2 秒で固まらず、枠と覚える直しを戻すと 61.1・61.2 秒で固まった）。
/// 枠の高さは、いちばん大きい札（名前2行・出典あり）の見本を同じ字で組んで決める（大きな文字の設定でも切れない）。
///
/// 索引に無い・読めないときも同じ枠の中に、届いたリンクをそのまま出す（`fallback`）——黙って消さない。
struct DMSpotCard: View {
    let slug: String
    let mine: Bool
    /// 札が作れなかったときに出す文（届いたリンクそのもの）
    let fallback: String

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter

    private typealias Phase = DMSpotCardPhase
    /// 読み終えた中身から始める（`DMSpotCardMemory`）。作り直した行で読み込み中の灰色が一瞬出ず、
    /// 索引だけの行の詳細を取り直さない（高さは枠で決まるので、固まる件の直しはこちらではない）
    @State private var phase: Phase

    init(slug: String, mine: Bool, fallback: String) {
        self.slug = slug
        self.mine = mine
        self.fallback = fallback
        _phase = State(initialValue: DMSpotCardMemory.phase(for: slug) ?? .loading)
    }

    static let width: CGFloat = 240
    static let photoHeight: CGFloat = 130

    var body: some View {
        DMSpotCardBox { phaseView }
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            .padding(.top, JPSpace.xxs)
            .task(id: slug) {
                // 読み終えた中身で始まった札は読み直さない
                guard phase == .loading else { return }
                await load()
            }
    }

    /// 枠の中の中身（どれも枠いっぱいに広がる）
    @ViewBuilder private var phaseView: some View {
        switch phase {
        case .loading:
            RoundedRectangle(cornerRadius: JPRadius.l)
                .fill(WebTheme.surface3)
                .accessibilityElement()
                .accessibilityLabel(L("観光スポットを読み込み中", "Loading the spot"))
        case .found(let spot, let index):
            card(spot, index: index)
        case .missing:
            missingCard
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
                    // 写真は 130 から、枠の余り（名前が1行・出典が無い分）まで伸びる（`DMSpotCardPhotoPlaceholder.grows`）
                    if let photo = spot.photo {
                        Color.clear
                            .frame(minHeight: Self.photoHeight, maxHeight: .infinity)
                            .overlay(RemoteImage(url: photo.url))
                            .clipped()
                            .accessibilityHidden(true)
                    } else {
                        // 写真の無い観光スポットも写真の場所を取る（枠の上が空かないように・2026-11-12 判断）
                        DMSpotCardPhotoPlaceholder(grows: true)
                    }
                    DMSpotCardText(name: spot.name, region: spot.regionLabel)
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
            // 名前が1行のとき・出典が無いときの余りは、写真の高さに回す（上の写真が伸びる）。
            // 2026-11-13 デザインの点検: 前は余りをここ（ボタンの上）に `Spacer` で置き、兼六園のような1行の名前で
            // 地域の行とボタンの間が約1行分空いていた。枠の高さ（`DMSpotCardBox`）は変えない——中の配置だけ
            Button {
                guard !wanted else { return }
                Task {
                    let outcome = await WishlistSync.set(key, wanted: true, store: wishlist,
                                                         service: environment.savedSpots)
                    if let notice = WishlistSync.notice(for: outcome) { toasts.show(notice.text, kind: notice.kind) }
                }
            } label: {
                DMSpotCardWishLabel(wanted: wanted)
            }
            .buttonStyle(.plain)
            .disabled(wanted || wishlist.isSending(key))
            .accessibilityIdentifier("dm.spotCard.wish")
            // 出典（CC BY・BY-SA の表示条件）。写真の下ではなく札の下端に置く（押す先を重ねない）
            if let photo = spot.photo {
                DMSpotCardCredit(text: SpotPrefectureIndex.creditText(photo))
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(DMSpotCardSurface())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dm.spotCard")
    }

    /// 札が作れなかったとき（索引に無い・読めない）。同じ枠に、写真の場所の印と眉と、届いたリンクをそのまま出す。
    /// 2026-11-12 判断: 枠の高さをそろえる（読めないは読み込み中のあとに分かるので、最初からこの形では出せない。
    /// 高さが替わると固まる件に戻る）
    private var missingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            DMSpotCardPhotoPlaceholder()
            VStack(alignment: .leading, spacing: JPSpace.xxs) {
                Text(DMSpotShare.eyebrow)
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityHidden(true)
                Link(destination: URL(string: fallback) ?? AppConfig.siteBaseURL) {
                    Text(fallback)
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.accent)
                        .underline()
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("dm.spotCard.link")
            }
            .padding(.horizontal, JPSpace.s)
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(DMSpotCardSurface())
    }

    /// 端末の索引からスラッグで引き、写真の無い行は詳細を重ねる。見つからなければリンクの文のまま
    private func load() async {
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
        DMSpotCardMemory.remember(settled, for: slug, failed: failed)
        phase = settled
    }
}

// MARK: - 枠（高さは中身によらない）

/// **観光スポットの札の枠**（2026-11-12・DM の会話が固まる件・1.1.85）。
///
/// 大きさは、いちばん大きい札（`DMSpotCardSkeleton`: 写真 130・名前2行・種類と地域・ボタン・出典）を
/// 同じ字で組んだ見本で決め、中身はその上に重ねて枠いっぱいに広げる。**中身が何でも枠の大きさは替わらない**
/// （`DMSpotCardBoxTests` が確かめる）。見本は見えず、読み上げにも出ない。
struct DMSpotCardBox<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        DMSpotCardSkeleton()
            .hidden()
            .accessibilityHidden(true)
            .overlay(alignment: .top) {
                content()
                    .frame(width: DMSpotCard.width)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
    }
}

/// 枠の大きさを決める見本（いちばん大きい札と同じ部品・同じ字）
struct DMSpotCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DMSpotCardPhotoPlaceholder()
            // 名前は2行まで（`DMSpotCardText` の lineLimit）なので2行で組む。地域も字を入れて1行分を取る
            DMSpotCardText(name: "あ\nあ", region: "あ")
            DMSpotCardWishLabel(wanted: false)
            DMSpotCardCredit(text: "あ")
        }
        .frame(width: DMSpotCard.width)
    }
}

/// 札の地（板どおり surface-1 `WebTheme.card`・角 16・白 8% の細い縁）
private struct DMSpotCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WebTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: JPRadius.l))
            .overlay(RoundedRectangle(cornerRadius: JPRadius.l).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }
}

/// 写真の場所の代わり（写真の無い観光スポット・読めないとき・枠の見本）。灰の地に場所の印
struct DMSpotCardPhotoPlaceholder: View {
    /// 枠の余りまで伸びるか（読めた札の写真の場所）。**枠の見本（`DMSpotCardSkeleton`）では伸ばさない**——
    /// 見本は 130 のまま組んで枠の高さを決める
    var grows = false

    var body: some View {
        WebTheme.surface3
            .frame(minHeight: DMSpotCard.photoHeight, maxHeight: grows ? .infinity : DMSpotCard.photoHeight)
            .overlay(
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(WebTheme.text3)
            )
            .accessibilityHidden(true)
    }
}

/// 眉「一緒に行こう」・名前（明朝・2行まで）・種類と地域
struct DMSpotCardText: View {
    let name: String
    let region: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DMSpotShare.eyebrow)
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            Text(name)
                .font(JPFont.rowTitle)
                .foregroundStyle(WebTheme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            // 種類と地域は中黒で区切らず、字の太さ・色と 6pt の間で分ける（2026-11-12 の決まり）
            HStack(spacing: 6) {
                Text(DMSpotShare.kindLabel)
                    .font(JPFont.caption.weight(.semibold))
                    .foregroundStyle(WebTheme.text2)
                if let region, !region.isEmpty {
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
}

/// 「行きたい場所に入れる」の見た目（見た目 36・当たり 44）と、札の中の余白
struct DMSpotCardWishLabel: View {
    let wanted: Bool

    var body: some View {
        // フォローの札（`FollowPill`）と同じ形で、札の幅いっぱい（資料の模型）
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
            .padding(.horizontal, JPSpace.s)
            .padding(.top, JPSpace.xxs)
            .padding(.bottom, JPSpace.xs)
    }
}

/// 出典（CC BY・BY-SA の表示条件）を1行
struct DMSpotCardCredit: View {
    let text: String

    var body: some View {
        Text(text)
            .font(JPFont.caption)
            .foregroundStyle(WebTheme.text3)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, JPSpace.s)
            .padding(.bottom, JPSpace.xs)
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

/// **読み終えた札の中身（スラッグごと・アプリを閉じるまで）**（2026-11-12・1.1.85）。
///
/// 会話の行は `LazyVStack` が画面の外で作り直し、そのたびに札の `@State` は初めの値に戻る。
/// 作り直した札は、ここに覚えた中身から始める（読み込み中の灰色を一瞬挟まない・索引だけの行の詳細を取り直さない）。
/// 固まる件の直しは枠（`DMSpotCardBox`）の方。これだけでは、1回目に開いた会話が固まった（Mac run 1190 の test01: 61.2 秒）。
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
