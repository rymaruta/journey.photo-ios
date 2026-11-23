import SwiftUI

// 写真の閲覧数の画面（札 #707・案の頁「写真の閲覧数」版4・owner「閲覧数の画面ベースいい感じなのでブラッシュアップして」2026-11-23）。
// 言葉と数の書き方は `PhotoViews`（画面を持たない層）。デザインの板は PhotoDetail（いいねの段）と StoryInsights（シートの形）。

/// 写真の詳細の、いいねの段の下の1行（**自分の写真だけ**・呼ぶ側が `isMine` で出し分ける）。
/// 「（目の印）閲覧数 1,234回 ›」。押すと内訳のシート。状態: まだ閲覧されていない（押せない）／読み込み中／失敗／圏外
struct PhotoViewsRow: View {

    let photo: Photo
    /// 「リンクを送って見てもらう」の URL（個別の頁がある写真だけ・画像は渡さない）
    let shareURL: URL?

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var connectivity: Connectivity
    @State private var counts: PhotoViewCounts?
    @State private var failed = false
    @State private var showSheet = false
    /// 「再読み込み」で読み直す鍵
    @State private var reloads = 0

    /// 目の印の大きさ（案の模型 18px）
    static let eyeSize: CGFloat = 17

    private var state: PhotoViews.RowState {
        PhotoViews.rowState(counts: counts, failed: failed, offline: connectivity.isOffline)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget, alignment: .leading)
            .accessibilityIdentifier("photo.views")
            .task(id: "\(photo.id)#\(reloads)#\(connectivity.isOffline)") { await load() }
            .sheet(isPresented: $showSheet) {
                if let counts, PhotoViews.opensSheet(.loaded(counts)) {
                    PhotoViewsSheet(photo: photo, counts: counts, shareURL: shareURL)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: JPSpace.xs) {
                eye
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 76, height: 12)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("閲覧数を読み込み中", "Loading views"))
        case .loaded(let c) where c.total == 0:
            // 0回は押せない1行だけ（シートは開かない・owner 2026-11-23「これいらないな」・案の頁 版5）
            HStack(spacing: JPSpace.xs) {
                eye
                Text(PhotoViews.zero)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text3)
            }
            .accessibilityElement(children: .combine)
        case .loaded(let c):
            Button { showSheet = true } label: {
                HStack(spacing: JPSpace.xs) {
                    eye
                    Text(PhotoViews.label)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.text3)
                    Text(PhotoViews.times(c.total))
                        .font(JPFont.body.monospacedDigit())
                        .foregroundStyle(Color.white)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WebTheme.text3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(PhotoViews.rowText(state) ?? PhotoViews.label)
            .accessibilityHint(L("押すと内訳が出ます", "Shows the breakdown"))
        case .failed:
            HStack(spacing: JPSpace.xs) {
                Text(PhotoViews.failed)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.danger)
                Spacer(minLength: 0)
                Button(PhotoViews.retry) { failed = false; reloads += 1 }
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .buttonStyle(.plain)
            }
        case .offline:
            Text(PhotoViews.offline)
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text3)
        }
    }

    private var eye: some View {
        Image(systemName: "eye")
            .font(.system(size: Self.eyeSize, weight: .light))
            .foregroundStyle(Color.white.opacity(0.72))
            .accessibilityHidden(true)
    }

    private func load() async {
        // 読めた数は残す（圏外になっても消さない）。圏外のうちは読みに行かない
        guard !connectivity.isOffline else { return }
        do {
            let c = try await environment.photoViews.counts(photoId: photo.id)
            guard !Task.isCancelled else { return }
            counts = c
            failed = false
        } catch {
            guard !Task.isCancelled else { return }
            if counts == nil { failed = true }
        }
    }
}

/// 閲覧数の内訳のシート（案の頁 版4）。見出しは写真の題、その下に「閲覧数は、あなたにだけ見えます」。
/// 「これまでの閲覧数」の大きな数（開くと 0 から 0.6秒で数え上がる・視差効果を減らす設定では数え上げない）、
/// 真鍮（アプリ）と灰（Web）の帯、印つきの2マスと割合、注記、数え始めた日、真鍮の「リンクを送って見てもらう」。
/// **1回以上のときだけ開く**（0回は写真の詳細の押せない1行だけ・owner 2026-11-23・案の頁 版5）
struct PhotoViewsSheet: View {

    let photo: Photo
    let counts: PhotoViewCounts
    let shareURL: URL?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    /// 写真の大きさ（板 StoryInsights の 48×64）
    static let thumbSize = CGSize(width: 48, height: 64)
    /// 大きな数（案の模型 46px・細い字・等幅の数字）
    static let bigSize: CGFloat = 46

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.m) {
                header
                totals
                splitBar
                cells
                notes
                shareButton
            }
            .padding(.horizontal, JPSpace.l)
            .padding(.top, JPSpace.s)
            .padding(.bottom, JPSpace.xl)
        }
        .scrollContentBackground(.hidden)
        .background(WebTheme.card)
        .task { await countUp() }
        .accessibilityIdentifier("photoViews.sheet")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: JPSpace.s) {
            SheetCloseButton(onContent: true)
            RemoteImage(url: photo.gridImageURL)
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.displayTitle.isEmpty ? PhotoViews.label : photo.displayTitle)
                    .font(JPFont.cardTitle)
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(PhotoViews.onlyYou)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
            .padding(.top, JPSpace.xxs)
            Spacer(minLength: 0)
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            Text(PhotoViews.totalHeading)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(PhotoViews.number(shown))
                    .font(.system(size: Self.bigSize, weight: .light).monospacedDigit())
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = PhotoViews.unit {
                    Text(unit)
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.text2)
                }
            }
        }
        .padding(.top, JPSpace.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(PhotoViews.totalHeading) \(PhotoViews.times(counts.total))")
    }

    /// 割合の帯（真鍮＝アプリ・灰＝Web・高さ 4・角 2）
    private var splitBar: some View {
        GeometryReader { geo in
            let ratio = CGFloat(PhotoViews.appPercent(counts) ?? 0) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.28))
                Capsule().fill(WebTheme.accent).frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var cells: some View {
        let app = PhotoViews.appPercent(counts) ?? 0
        return HStack(spacing: 0) {
            cell(symbol: "iphone", label: PhotoViews.app, value: counts.app, percent: app, tint: WebTheme.accent)
            Rectangle().fill(WebTheme.hairline).frame(width: JPStroke.hairline)
            cell(symbol: "globe", label: PhotoViews.web, value: counts.web, percent: 100 - app, tint: WebTheme.text3)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
    }

    private func cell(symbol: String, label: String, value: Int, percent: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.footnote)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(label)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
            }
            Text(PhotoViews.number(value))
                .font(JPFont.figureLarge)
                .foregroundStyle(WebTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(percent)%")
                .font(JPFont.caption.monospacedDigit())
                .foregroundStyle(WebTheme.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, JPSpace.m)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(PhotoViews.times(value)) \(percent)%")
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: JPSpace.xxs) {
            Text(PhotoViews.note)
            if let since = PhotoViews.sinceLine(counts.since) {
                Text(since)
            }
        }
        .font(JPFont.caption)
        .foregroundStyle(WebTheme.text3)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 真鍮の「リンクを送って見てもらう」（写真の頁の URL だけ・画像は渡さない。CLAUDE.md「他人の写真」と同じくリンクだけ）。
    /// 個別の頁が無い写真（下書き・絞った写真）では出さない
    @ViewBuilder
    private var shareButton: some View {
        if let shareURL {
            ShareLink(item: shareURL) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text(PhotoViews.shareLink)
                }
                .font(JPFont.bodyEmphasis)
                .foregroundStyle(WebTheme.accent)
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("photoViews.share")
        }
    }

    /// 0 から数え上げる（0.6秒・20コマ）。視差効果を減らす設定では最初から数を出す
    private func countUp() async {
        let target = counts.total
        guard !reduceMotion, target > 0 else { shown = target; return }
        let steps = 20
        for i in 1...steps {
            try? await Task.sleep(nanoseconds: UInt64(PhotoViews.countUpSeconds / Double(steps) * 1_000_000_000))
            if Task.isCancelled { shown = target; return }
            let t = Double(i) / Double(steps)
            // 終わりがゆっくりになる形（ease-out）
            shown = Int((Double(target) * (1 - pow(1 - t, 3))).rounded())
        }
        shown = target
    }
}

/// 写真の詳細が1秒以上見えたら閲覧数を1回送る（本人・ログインの確かめ中・圏外・30分以内の同じ写真は送らない）。
/// 画面を離れると `.task` が取り消されるので、1秒より前に離れたら送らない
struct PhotoViewBeacon: ViewModifier {

    let photoId: String
    let isMine: Bool

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var connectivity: Connectivity

    func body(content: Content) -> some View {
        content.task(id: "\(photoId)|\(isMine)|\(auth.isResolving)") {
            guard PhotoViews.mayRecord(isMine: isMine, signInResolving: auth.isResolving,
                                       offline: connectivity.isOffline,
                                       previewSession: PreviewSession.userId != nil) else { return }
            let log = PhotoViewSendLog()
            guard log.shouldSend(photoId, now: Date()) else { return }
            try? await Task.sleep(nanoseconds: PhotoViews.dwellNanoseconds)
            guard !Task.isCancelled, !connectivity.isOffline, log.shouldSend(photoId, now: Date()) else { return }
            if await environment.photoViews.record(photoId: photoId) {
                log.markSent(photoId, now: Date())
            }
        }
    }
}

extension View {
    /// 写真の詳細の閲覧数を送る（`PhotoViewBeacon`）
    func photoViewBeacon(photoId: String, isMine: Bool) -> some View {
        modifier(PhotoViewBeacon(photoId: photoId, isMine: isMine))
    }
}

/// マイページの数字の段の下の1行「（目の印）累計閲覧数 1万2,480回」（押せない数だけ・マイページは本人しか見ない）。
/// 読めない・写真が無い・圏外のときは出さない（分からない数を出さない）
struct MyPageViewsLine: View {

    let photoIds: [String]

    /// 写真が増えた・減った・電波が戻ったときに読み直す
    private struct LoadKey: Equatable { let ids: [String]; let offline: Bool }

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var connectivity: Connectivity
    @State private var total: Int?

    var body: some View {
        Group {
            // 0回は出さない（「0」が並ぶと空っぽに見える・いいねの数と同じ決まり）
            if let total, total > 0 {
                HStack(alignment: .firstTextBaseline, spacing: JPSpace.xs) {
                    Image(systemName: "eye")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .accessibilityHidden(true)
                    Text(PhotoViews.myPageLabel)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                    Text(PhotoViews.times(total))
                        .font(JPFont.body.monospacedDigit())
                        .foregroundStyle(Color.white)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(PhotoViews.myPageLabel) \(PhotoViews.times(total))")
                .accessibilityIdentifier("mypage.views")
            }
        }
        .task(id: LoadKey(ids: photoIds, offline: connectivity.isOffline)) {
            guard !photoIds.isEmpty, !connectivity.isOffline else { return }
            if let sum = try? await environment.photoViews.total(photoIds: photoIds), !Task.isCancelled {
                total = sum
            }
        }
    }
}
