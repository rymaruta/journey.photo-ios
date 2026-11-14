import SwiftUI

/// **①「フィルムを現像するみたいに」の画面**（2026-11-12・札 #543・資料第6章 段2 ①）。
///
/// ホームの「現像前の旅」の札から全画面で開く（②「1年前」の「投稿にする」からも同じ画面）。
/// 端末が選んだコマ（最大10・`DevelopTrips.frames`）を色を抜いた札で1枚ずつ出し、
/// **右へ払う＝載せる（色が戻る）・左へ払う＝外す**。下の丸（✕・↶・✓）でも、読み上げの操作でも同じ。
/// 払い終えたら一冊の表紙で「投稿する」（5秒は取り消せる・`DevelopPostCenter` が送る）。
///
/// 寸法（章）: 写真の面 390×640・角は下だけ 24。上の丸 44（ガラス）。フィルムの帯 56（地 surface-1・穴の列）。
/// 下の丸 56・44・56、間 28。外したコマは帯で 25%、載せたコマは色つき、今のコマは白 2pt の枠。
/// 払っている札の字は写真の上なので白（黒 60% の影）。
///
/// 払った結果は**端末の中だけ**に残す（`DevelopProgressStore`）——途中で閉じても、次は続きのコマから
struct DevelopView: View {

    let trip: LibraryTrip
    /// 端末の一冊の地名（引けていなければ nil・題は期間）
    let name: String?
    /// 「題・公開範囲を変える」: 選んだ写真（表紙が先頭）を渡す。**呼び手は画面が閉じきってから**今の投稿の画面を開く
    let onEdit: ([String], Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var connectivity: Connectivity
    @StateObject private var undo = CountdownUndo()
    /// 送っている最中を見張る（送り終えるまで「投稿する」を押させない・2026-11-12 確かめ役）
    @ObservedObject private var postCenter = DevelopPostCenter.shared
    /// 公開範囲。**既定は非公開**（`DevelopTrips.startsPublic`）。表紙の行を1回押すと替わる
    @State private var published = DevelopTrips.startsPublic
    /// 一部の写真だけ許可か（追加の口を出す）・選び足している最中か
    @ObservedObject private var deviceTrips = DeviceTripShelfStore.shared

    @State private var decisions: [String: DevelopTrips.Decision] = [:]
    @State private var cover: String?
    /// 払っている指の横の動き（pt）
    @State private var dragX: Double = 0
    /// 札が飛んでいく間（押しを重ねない）
    @State private var flying = false
    /// 端末の控えから続きを戻した（一度だけ）
    @State private var restored = false
    /// 読めなかったコマ（飛ばした）。一言を出す
    @State private var unreadable: Set<String> = []
    /// 決めた順（↶ で1枚ずつ戻す）
    @State private var history: [String] = []
    /// 読めないコマを飛ばした直後の札（写真の上のガラス・`DevelopTrips.unreadableNoticeSeconds` で消える）
    @State private var unreadableNotice = false
    /// UI テストのときだけ: 払う画面の上端（画面の座標）と、そこで読める安全な範囲の上の幅（`develop.safeTop` の値）
    @State private var safeTop: CGFloat = 0
    /// UI テストのときだけ: 払う画面の × の**見た目の**上端（画面の座標・`develop.close.visual` の値）。
    /// × の読み上げの枠は当たりの形の大きさになるので（`CornerTapArea`）、状態バーと比べるのは見た目の枠にする
    @State private var closeVisualMinY: CGFloat = -1
    @State private var safeInset: CGFloat = 0

    private let store = DevelopProgressStore()
    private let frames: [String]

    init(trip: LibraryTrip, name: String?, onEdit: @escaping ([String], Bool) -> Void) {
        self.trip = trip
        self.name = name
        self.onEdit = onEdit
        self.frames = DevelopTrips.frames(of: trip)
    }

    private var index: Int { DevelopTrips.nextIndex(frames, decisions: decisions) }
    private var kept: [String] { DevelopTrips.kept(frames, decisions: decisions) }
    private var title: String { DeviceTrips.title(of: trip, name: name) }
    /// 圏外（払うのは端末の中だけで最後までできる。投稿だけ通信できる所で）
    private var offline: Bool { connectivity.isOffline || PreviewSession.developOffline }
    /// 一部の写真だけ許可（見つかった分で払う。追加の許可は今の「写真を選び直す」と同じ口）
    private var limited: Bool { deviceTrips.status == .limited || PreviewSession.developLimited }

    var body: some View {
        ZStack {
            WebTheme.background.ignoresSafeArea()
            if index < frames.count {
                deckScreen
            } else if LibraryTrips.canAddToTrips(count: kept.count) {
                coverScreen
            } else {
                tooFewScreen
            }
        }
        .overlay(alignment: .bottom) {
            if let message = undo.message {
                CountdownUndoBar(message: message, seconds: DevelopTrips.undoSeconds,
                                 onUndo: { undo.undo() }, identifier: "develop.undo")
                    .id(undo.token)
                    .padding(.bottom, JPSpace.l)
                    .transition(.opacity)
            }
        }
        .onAppear(perform: restore)
        // 閉じたら待っている投稿はいま送り出す（取り消しの札は画面と一緒に消えるため。積んだまま捨てない）
        // 閉じたら、取り消しを待っている投稿は**取り消す**（閉じた合図で送り出さない・`closingCancelsPendingPost`）
        .onDisappear {
            if DevelopTrips.closingCancelsPendingPost { undo.undo() } else { undo.finishNow() }
        }
        // 入れ物の目印は中の部品の目印を上書きする（Mac run 1106 の画面の木で、中のボタン「develop.keep」まで
        // 全部「develop.screen」になっていた）。中を含む入れ物にしてから目印を付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("develop.screen")
    }

    // MARK: - 払う画面

    private var deckScreen: some View {
        VStack(spacing: 0) {
            ZStack {
                if index + 1 < frames.count {
                    frameCard(frames[index + 1], isTop: false)
                        .scaleEffect(0.96)
                        .brightness(-0.3)
                        .accessibilityHidden(true)
                }
                frameCard(frames[index], isTop: true)
                    .offset(x: dragX)
                    .rotationEffect(.degrees(dragX / 22))
                    .gesture(swipe)
                    .id(frames[index])
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { if unreadableNotice { unreadableCard } }
            // 上に広げるのは写真の札だけ。上の札と × は**広げた後に**重ね、状態バー（島）の下に置く
            // （2026-11-13 デザインの点検: 先に重ねてから広げていたので、上の札まで状態バーの中に入っていた。
            // 画面写真で札が時計と同じ高さ。`DesignAudit1113Tests`・ScreenshotTests の 120b）
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) { topBar }
            strip
                .padding(.top, JPSpace.xs)
            if unreadable.isEmpty {
                Text(L("右へ払うと載せる、左で外す", "Swipe right to keep, left to skip"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .padding(.top, JPSpace.xs)
            } else {
                Text(L("読み込めなかった写真は飛ばしました", "Skipped photos that couldn't be loaded"))
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text3)
                    .padding(.top, JPSpace.xs)
                    .accessibilityIdentifier("develop.unreadable")
            }
            if limited {
                addMoreButton
            }
            controls
                .padding(.top, JPSpace.m)
                .padding(.bottom, JPSpace.l)
        }
        // UI テストのときだけ: 安全な範囲の上端（画面の座標）を値で出す。上の札と × がその下にあるかを
        // 機種の状態バーの高さに頼らず比べる（2026-11-13 確かめ役: `minY ≥ 44` では島の機種で重なっても通る）。
        // 払う画面の並び（`VStack`）は安全な範囲の中に置かれるので、その上端が安全な範囲の上端。
        // Mac run 1213 では「上端＋読める安全な範囲の上の幅」を出して 124.0 になり、× の上端 65.5 より下だった
        // （上端の中で安全な範囲の幅も読めて二重に足していた）。上端と幅を分けて出し、試験は上端と比べる
        .background {
            if PreviewSession.layoutProbe {
                GeometryReader { g in
                    let top = g.frame(in: .global).minY
                    let inset = g.safeAreaInsets.top
                    Color.clear
                        .onAppear { safeTop = top; safeInset = inset }
                        .onChange(of: top) { _, value in safeTop = value }
                        .onChange(of: inset) { _, value in safeInset = value }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            LayoutProbe(identifier: "develop.safeTop", value: String(format: "top=%.1f inset=%.1f", safeTop, safeInset))
        }
        .overlay(alignment: .bottomTrailing) {
            LayoutProbe(identifier: "develop.close.visual", value: String(format: "minY=%.1f", closeVisualMinY))
        }
    }

    /// 上の丸（閉じる・ガラス）と、真ん中の札「4 / 10  DAY 1  金沢市」
    private var topBar: some View {
        ZStack {
            Text(DevelopTrips.counter(index: index, total: frames.count,
                                      day: DevelopTrips.day(of: frames[min(index, frames.count - 1)], in: trip),
                                      place: name))
                .font(JPFont.mono(12, medium: true))
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, JPSpace.s)
                .padding(.vertical, 6)
                .jpGlass(in: Capsule())
                .accessibilityIdentifier("develop.counter")
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                        .jpGlass(in: Circle())
                        .background {
                            if PreviewSession.layoutProbe {
                                GeometryReader { g in
                                    let top = g.frame(in: .global).minY
                                    Color.clear
                                        .onAppear { closeVisualMinY = top }
                                        .onChange(of: top) { _, value in closeVisualMinY = value }
                                }
                            }
                        }
                        // 角の物は当たりを角の側へ 60pt 四方まで広げる（見た目はそのまま・`CornerTapArea`・2026-11-14）
                        .cornerTapArea(.topLeading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Labels.Common.close)
                .accessibilityIdentifier("develop.close")
                Spacer()
            }
        }
        .padding(.horizontal, JPSpace.s)
        // 状態バーの下は重ねる側（安全な範囲の中）で決まる。`.safeAreaPadding(.top)` は安全な範囲に既定の余白を
        // **足す**もので、状態バーの高さを足すものではない（広げた中では 0 に足すだけだった）ので外した
        .padding(.top, JPSpace.xxs)
    }

    /// 1コマの札（写真の面・下だけ丸い）。払っている札だけ色が戻り、白の判子が出る
    private func frameCard(_ id: String, isTop: Bool) -> some View {
        let amount = isTop ? DevelopTrips.colorAmount(dx: dragX) : 0
        let shot = trip.shots.first { $0.id == id }
        return LibraryShotImage(id: id, side: 420, onFailed: { if isTop { skipUnreadable(id) } })
            // 色を抜いたコマ（セピアに寄せて暗く）→ 払った量だけ色が戻る（0 → 120pt で 0 → 100%）
            .saturation(0.35 + 0.65 * amount)
            .brightness(-0.22 * (1 - amount))
            .colorMultiply(Self.sepia(amount))
            .overlay(alignment: .bottomLeading) {
                if isTop, let shot { caption(shot) }
            }
            .overlay(alignment: .topLeading) {
                if isTop { stamp(L("載せる", "Keep"), opacity: dragX / 90) }
            }
            .overlay(alignment: .topTrailing) {
                if isTop { stamp(L("外す", "Skip"), opacity: -dragX / 90) }
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: JPRadius.xl, bottomTrailingRadius: JPRadius.xl))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shot.map { Self.spokenShot($0, place: name) } ?? L("写真", "Photo"))
            .accessibilityAction(named: L("載せる", "Keep")) { decide(.keep) }
            .accessibilityAction(named: L("外す", "Skip")) { decide(.skip) }
    }

    /// セピアの色（色を抜いた量に合わせて白へ戻す）
    private static func sepia(_ amount: Double) -> Color {
        let a = max(0, min(1, amount))
        return Color(red: 1, green: 0.90 + 0.10 * a, blue: 0.74 + 0.26 * a)
    }

    /// 札の下の字（写真の上なので白・影）「金沢市 · 9.12」「17:48」
    private func caption(_ shot: LibraryShot) -> some View {
        let day = DevelopTrips.day(of: shot.id, in: trip)
        let date = day.map { "\($0.month).\($0.day)" } ?? ""
        let head = [name, date].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: JPSpace.xxs) {
            Text(head)
                .font(JPFont.display(20, relativeTo: .title3))
                .foregroundStyle(WebTheme.foreground)
            Text(Self.clock(of: shot, zone: trip.timeZone))
                .font(JPFont.mono(12))
                .foregroundStyle(WebTheme.muted2)
        }
        .jpPhotoTextShadow()
        .padding(JPSpace.m)
        .accessibilityHidden(true)
    }

    /// 撮った時刻「17:48」（時と分だけ・旅の時間帯）
    private static func clock(of shot: LibraryShot, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.hour, .minute], from: shot.date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func spokenShot(_ shot: LibraryShot, place: String?) -> String {
        let time = clock(of: shot, zone: .current)
        if let place, !place.isEmpty { return L("\(place)の写真、\(time)", "Photo in \(place), \(time)") }
        return L("写真、\(time)", "Photo, \(time)")
    }

    /// 払っている向きの判子（写真の上なので白の字と縁）
    private func stamp(_ text: String, opacity: Double) -> some View {
        Text(text)
            .font(JPFont.display(22, relativeTo: .title2))
            .foregroundStyle(WebTheme.foreground)
            .padding(.horizontal, JPSpace.s)
            .padding(.vertical, JPSpace.xxs)
            .overlay(RoundedRectangle(cornerRadius: JPRadius.xs).strokeBorder(Color.white, lineWidth: 2))
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: JPRadius.xs))
            .rotationEffect(.degrees(-8))
            .padding(.top, 96)
            .padding(.horizontal, JPSpace.xl)
            .opacity(max(0, min(1, opacity)))
            .accessibilityHidden(true)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !flying else { return }
                dragX = value.translation.width
            }
            .onEnded { value in
                guard !flying else { return }
                if let decision = DevelopTrips.decide(dx: value.translation.width, velocity: value.velocity.width) {
                    decide(decision)
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6)) { dragX = 0 }
                }
            }
    }

    /// 読めないコマを飛ばした札（章「読めない写真があった」）。写真の上なのでガラスに白
    private var unreadableCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DevelopTrips.unreadableTitle)
                .font(JPFont.bodyEmphasis)
                .foregroundStyle(WebTheme.foreground)
            Text(DevelopTrips.unreadableDetail)
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.muted2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(JPSpace.m)
        .jpGlass(in: RoundedRectangle(cornerRadius: JPRadius.l))
        .padding(.horizontal, JPSpace.l)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("develop.unreadableCard")
        .transition(.opacity)
    }

    /// 一部の写真だけ許可した人の追加の口（黒地の上の文字ボタンなので真鍮・44pt）
    private var addMoreButton: some View {
        Button {
            Task { await deviceTrips.addMorePhotos() }
        } label: {
            Text(DevelopTrips.addMoreLabel)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.accent)
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(deviceTrips.isPickingMore)
        .accessibilityIdentifier("develop.addMore")
    }

    // MARK: - フィルムの帯

    private var strip: some View {
        VStack(spacing: 3) {
            holes
            HStack(spacing: JPSpace.xxs) {
                ForEach(Array(frames.enumerated()), id: \.element) { offset, id in
                    let decision = decisions[id]
                    LibraryShotImage(id: id, side: 60)
                        .saturation(decision == .keep ? 1 : 0.35)
                        .brightness(decision == .keep ? 0 : -0.22)
                        .colorMultiply(decision == .keep ? .white : Self.sepia(0))
                        .opacity(decision == .skip ? 0.25 : 1)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .overlay {
                            if offset == index {
                                RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white, lineWidth: 2)
                            }
                        }
                }
            }
            .frame(height: 32)
            holes
        }
        .padding(.horizontal, 10)
        .frame(height: Self.stripHeight)
        .background(WebTheme.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(frames.count)コマ中 載せる\(kept.count)枚",
                              "\(kept.count) of \(frames.count) kept"))
        .accessibilityIdentifier("develop.strip")
    }

    /// 帯の穴の列（飾り）
    private var holes: some View {
        HStack(spacing: 6) {
            ForEach(0..<24, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.12)).frame(width: 6, height: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }

    nonisolated static let stripHeight: CGFloat = 56

    // MARK: - 下の丸（✕・↶・✓）

    private var controls: some View {
        HStack(spacing: 28) {
            Button { decide(.skip) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: 56, height: 56)
                    .overlay(Circle().strokeBorder(WebTheme.line, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("外す", "Skip"))
            .accessibilityIdentifier("develop.skip")
            Button(action: stepBack) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(history.isEmpty ? WebTheme.text3 : WebTheme.foreground)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .overlay(Circle().strokeBorder(WebTheme.line, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(history.isEmpty)
            .accessibilityLabel(L("1枚戻す", "Back one"))
            .accessibilityIdentifier("develop.back")
            Button { decide(.keep) } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(width: 56, height: 56)
                    .background(WebTheme.accentBackground, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("載せる", "Keep"))
            .accessibilityIdentifier("develop.keep")
        }
    }

    // MARK: - 表紙（払い終えた）

    private var coverScreen: some View {
        let order = DevelopTrips.uploadOrder(kept: kept, cover: cover ?? kept.first)
        let chosen = order.first
        return VStack(alignment: .leading, spacing: JPSpace.s) {
            closeRow
            JPSectionHeading(eyebrow: DevelopTrips.coverEyebrow(trip), spoken: LibraryTrips.periodText(trip), title: title)
            Text(L("\(kept.count)枚、押した写真が表紙になります",
                   kept.count == 1 ? "1 photo. Tap one to make it the cover" : "\(kept.count) photos. Tap one to make it the cover"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text2)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: JPSpace.xxs), count: 3),
                          spacing: JPSpace.xxs) {
                    ForEach(kept, id: \.self) { id in coverCell(id, isCover: id == chosen) }
                }
                .padding(JPSpace.xxs)
            }
            if let notice = DevelopTrips.coverNotice(offline: offline) {
                // 圏外（章「圏外」）: 地名が引けないと期間の題。投稿は通信できる所で
                Text(notice)
                    .font(JPFont.footnote)
                    .foregroundStyle(WebTheme.text2)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("develop.offline")
            } else {
                audienceRow
            }
            VStack(spacing: JPSpace.xxs) {
                Button { post(order) } label: {
                    Text(L("投稿する", "Post")).jpPillButton(.main(onPhoto: true))
                }
                .buttonStyle(.plain)
                .disabled(!DevelopTrips.canPost(offline: offline, undoShown: undo.message != nil,
                                                posting: postCenter.isPosting))
                // 押せないときは薄く（章の圏外の絵: 50%）
                .opacity(offline ? 0.5 : 1)
                .accessibilityIdentifier("develop.post")
                Button {
                    undo.undo()
                    onEdit(order, published)
                    dismiss()
                } label: {
                    Text(L("題を変える", "Change title"))
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("develop.edit")
            }
            // 取り消しの札が出ている間は、ボタンの上に札が重ならないよう下を空ける
            .padding(.bottom, undo.message == nil ? 0 : CountdownUndoBar.height + JPSpace.l)
        }
        .padding(.horizontal, JPSpace.gutter)
        .padding(.bottom, JPSpace.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("develop.cover")
    }

    /// 公開範囲の行（押すと 非公開 ⇄ 公開。1回で替わる）。下に撮影地と日付の出どころ
    private var audienceRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                published.toggle()
            } label: {
                HStack(spacing: JPSpace.xs) {
                    Image(systemName: published ? "globe" : "lock.fill")
                        .font(.callout)
                        .foregroundStyle(WebTheme.text2)
                        .accessibilityHidden(true)
                    Text(DevelopTrips.audienceLabel(published: published))
                        .font(JPFont.bodyEmphasis)
                        .foregroundStyle(WebTheme.text)
                    Spacer(minLength: JPSpace.xs)
                    Text(L("変える", "Change"))
                        .font(JPFont.body)
                        .foregroundStyle(WebTheme.accent)
                }
                .frame(minHeight: WebTheme.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(undo.message != nil)
            .accessibilityLabel(L("公開範囲", "Audience"))
            .accessibilityValue(DevelopTrips.audienceLabel(published: published))
            .accessibilityHint(L("押すと替わります", "Tap to change"))
            .accessibilityIdentifier("develop.audience")
            Text(L("撮影地と日付は写真の情報から入れます", "Place and date come from the photos"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
        }
    }

    private func coverCell(_ id: String, isCover: Bool) -> some View {
        Button {
            cover = id
            persist()
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { LibraryShotImage(id: id, side: 130) }
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs))
                .overlay(alignment: .bottomLeading) {
                    if isCover {
                        Text(L("表紙", "Cover"))
                            .font(JPFont.caption.weight(.semibold))
                            .foregroundStyle(WebTheme.accentText)
                            .padding(.horizontal, JPSpace.xxs)
                            .background(WebTheme.accentBackground, in: RoundedRectangle(cornerRadius: 4))
                            .padding(JPSpace.xxs)
                    }
                }
                .padding(2)
                .overlay {
                    if isCover {
                        RoundedRectangle(cornerRadius: JPRadius.xs + 2).strokeBorder(Color.white, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCover ? L("表紙の写真", "Cover photo") : L("表紙にする", "Make cover"))
        .accessibilityAddTraits(isCover ? .isSelected : [])
    }

    /// 閉じる（表紙・少なすぎるの画面は黒地。左上の丸）
    private var closeRow: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                    .cornerTapArea(.topLeading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Labels.Common.close)
            .accessibilityIdentifier("develop.close")
            Spacer()
        }
        .padding(.leading, -JPSpace.s)
    }

    // MARK: - 載せるが1枚以下

    private var tooFewScreen: some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            closeRow
            JPEyebrowLine(DevelopTrips.coverEyebrow(trip), spoken: LibraryTrips.periodText(trip))
            Text(L("2枚から一冊にできます", "A trip needs 2 or more photos"))
                .font(JPFont.stateTitle)
                .foregroundStyle(WebTheme.text)
                .accessibilityAddTraits(.isHeader)
            Text(L("外した写真から、もう一度選べます", "You can pick again from the photos you skipped"))
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text2)
            Spacer()
            // 写真の無い画面の主ボタンは真鍮の塗り（CLAUDE.md）
            Button {
                decisions = decisions.filter { unreadable.contains($0.key) }
                history = []
                cover = nil
                persist()
            } label: {
                Text(L("もう一度払う", "Swipe again")).jpPillButton(.main(onPhoto: false))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("develop.again")
            Button {
                store.close(trip.id, for: auth.userId)
                dismiss()
            } label: {
                Text(L("この旅は出さない", "Don't show this trip"))
                    .font(JPFont.body)
                    .foregroundStyle(WebTheme.text2)
                    .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("develop.closeTrip")
        }
        .padding(.horizontal, JPSpace.gutter)
        .padding(.bottom, JPSpace.l)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("develop.tooFew")
    }

    // MARK: - 動き

    private func decide(_ decision: DevelopTrips.Decision) {
        guard !flying, index < frames.count else { return }
        let id = frames[index]
        flying = true
        let target: Double = decision == .keep ? 460 : -460
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { dragX = target }
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(nanoseconds: 300_000_000) }
            decisions[id] = decision
            history.append(id)
            dragX = 0
            flying = false
            persist()
        }
    }

    /// ↶ 1枚ずつ戻す
    private func stepBack() {
        guard !flying, let last = history.popLast() else { return }
        decisions[last] = nil
        if cover == last { cover = nil }
        persist()
    }

    /// 読めなかったコマは外して次へ（章: 今の「読み込めなかった枚数」の知らせと同じ扱い）
    private func skipUnreadable(_ id: String) {
        guard decisions[id] == nil else { return }
        unreadable.insert(id)
        decisions[id] = .skip
        persist()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { unreadableNotice = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(DevelopTrips.unreadableNoticeSeconds * 1_000_000_000))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { unreadableNotice = false }
        }
    }

    private func restore() {
        guard !restored else { return }
        restored = true
        guard let saved = store.progress(trip.id, for: auth.userId) else { return }
        // 今のコマにある分だけ戻す（読み直しでコマが替わっていたら、その分は払い直す）
        decisions = saved.decisions.filter { frames.contains($0.key) }
        history = frames.filter { decisions[$0] != nil }
        cover = saved.cover.flatMap { frames.contains($0) ? $0 : nil }
    }

    private func persist() {
        var progress = store.progress(trip.id, for: auth.userId) ?? DevelopProgress(updatedAt: Date())
        progress.decisions = decisions
        progress.cover = cover
        store.save(progress, trip: trip.id, for: auth.userId)
    }

    /// 「投稿する」: 5秒の取り消しの間は何も送らない。たってから送り出し、画面を閉じる
    private func post(_ order: [String]) {
        guard let userId = auth.userId else { return }
        let trip = trip
        let environment = environment
        let toasts = toasts
        let store = store
        let published = published
        undo.schedule(DevelopTrips.postingNotice(count: order.count), seconds: DevelopTrips.undoSeconds) {
            // 札は先に閉じる（送っている間にホームへ戻っても同じ旅の札が出ない）
            store.close(trip.id, for: userId)
            DevelopPostCenter.shared.post(trip: trip, ids: order, published: published, userId: userId,
                                          environment: environment, toasts: toasts) { _ in }
            dismiss()
        }
    }
}
