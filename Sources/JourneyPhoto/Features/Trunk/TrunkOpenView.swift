import SwiftUI
import UIKit

/// ふたを開ける（板「旅のトランク」の TrunkOpen・InsideHold・InsideEmpty・2026-10-18 owner 承認）。
///
/// **前開き**: 下の辺が蝶番で、ふたは手前へ倒れる（0 → 180°）。指で引き下ろすと開き、離すと近い方へ寄る。
/// 「ふたを開ける／閉じる」のボタンと、開き具合の棒（読み上げで値を言う）でも動かせる。開け始めに錠前の板が
/// 起きて留め金が外れる。開いた姿は胴が上・倒れたふたが下（`TrunkInsideView`）。
///
/// 中身は本物の持ち物: メダル＝持っているバッジ、会員証＝サポーター証（Pro のときだけ）、乗車券＝すれちがい帳。
/// 押すと持ち上がり（板 InsideHold）、出口のボタンで今ある画面へ（メダルを回す・サポーター証・すれちがい帳・
/// 「ほか N」はバッジの棚）。何も入っていなければ空のトランク（板 InsideEmpty）。
struct TrunkOpenView: View {
    let model: TrunkModel
    let posts: Int
    var stuck: [TrunkLabel] = []
    var ownerName: String?
    var parts: TrunkEquipped = .none
    var wrinkles: [String: Double] = [:]

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var pass: PassStore
    @EnvironmentObject private var hidden: ModerationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var tabRouter = TabRouter.shared

    /// 開き具合（0 閉じ・1 開き切る）
    @State private var p: Double = 0
    /// 指で引いている間の、引き始めの開き具合
    @State private var dragStart: Double?
    /// 開き切る動きが終わった（平らなふたを置いて中身を押せる）
    @State private var lidSettled = false
    /// ふたを動かしている間に使い回す絵（ふたの表と裏・胴・持ち手の帯）。中身が替わったら描き直す
    @State private var lidImages: TrunkLidImages?
    @State private var profile: UserProfile?
    @State private var phase: Phase = .loading
    @State private var cardImage: UIImage?
    @State private var held: TrunkHeld?
    @State private var viewingMedal: EarnedBadge?
    @State private var showShelf = false
    @State private var showCard = false
    @State private var showBook = false
    /// 触覚の合図（留め金が外れた・ふたが寄り切った・中身を持ち上げた）
    @State private var claspTicks = 0
    @State private var landings = 0
    @State private var picks = 0

    enum Phase: Equatable { case loading, loaded, failed }

    private var lining: TrunkLining { TrunkInsideLooks.lining(model: model, equipped: parts) }

    private var contents: TrunkInsideContents {
        // 画面写真の「空のトランク」（`-JPPreviewTrunk empty`・Debug のみ。Release では必ず nil）
        if PreviewSession.trunkSample == .empty {
            return TrunkInsideContents(medals: [], showsCard: false, ticketCount: 0)
        }
        return TrunkInsideContents(badges: profile?.earnedBadges ?? BadgeSet(), isPro: profile?.isPro ?? false,
                                   supporter: profile?.supporterInfo, ticketCount: ticketContents.count)
    }

    /// すれちがい帳に綴じた乗車券（届いたもの・見せてよいもの）
    private var ticketContents: [PassCardContent] {
        let book = pass.book(hiding: hidden.snapshot)
        return pass.contents(book, book: book)
    }

    var body: some View {
        let contents = contents
        ZStack {
            Group {
                if phase == .loaded && contents.isEmpty {
                    emptyTrunk(contents)
                } else {
                    openable(contents)
                }
            }
            .blur(radius: held == nil ? 0 : 8)
            .allowsHitTesting(held == nil)
            if let held {
                holdOverlay(held, contents)
                    .transition(reduceMotion ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.45)).combined(with: .offset(y: 120)))
                    .zIndex(1)
            }
        }
        .background { TrunkStyle.stageBackground(centerY: 0.4) }
        .navigationTitle(L("旅のトランク", "Travel trunk"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: claspTicks)
        .sensoryFeedback(.impact(weight: .medium), trigger: landings)
        .sensoryFeedback(.selection, trigger: picks)
        .task { await load() }
        .task(id: snapshotKey) {
            if let images = await TrunkLidImages.make(stage(contents)) { lidImages = images }
        }
        .onAppear {
            // 動きの終わりの合図が来ないまま画面を離れて戻ったときの逃げ道
            if TrunkLid.isOpen(p), dragStart == nil { lidSettled = true }
        }
        .fullScreenCover(item: $viewingMedal) { badge in
            MedalViewerView(badge: badge, ownerName: profile?.name ?? ownerName ?? "")
        }
        .navigationDestination(isPresented: $showShelf) { BadgeShelfView(mode: .mine, preloaded: profile) }
        .navigationDestination(isPresented: $showCard) {
            if let profile { SupporterCardView(profile: profile) }
        }
        .navigationDestination(isPresented: $showBook) { PassBookView() }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（run 464 と同じ）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.open.screen")
    }

    // MARK: 読み込み

    private func load() async {
        if PreviewSession.trunkSample == .empty {
            phase = .loaded
            return
        }
        // 乗車券は端末の中の帳から。届いているのに写真がまだ引けていなければ、帳と同じ口で引く
        if pass.hasDelivered(), ticketContents.isEmpty {
            await pass.resolve(gallery: environment.gallery, profiles: environment.profiles)
        }
        guard profile == nil else { return }
        do {
            let fetched = try await environment.profiles.myProfile()
            profile = fetched
            phase = .loaded
            if TrunkInsideContents.showsCard(isPro: fetched.isPro, supporter: fetched.supporterInfo) {
                cardImage = SupporterCardTextures.front(cardFace(fetched, fetched.supporterInfo))
            }
        } catch {
            phase = .failed
        }
    }

    private func cardFace(_ profile: UserProfile, _ supporter: SupporterInfo?) -> SupporterCardFace {
        SupporterCardFace(name: profile.name, handle: profile.username,
                          number: supporter?.number ?? 0, since: SupporterText.since(supporter?.since))
    }

    // MARK: 開け閉めできる姿（板 TrunkOpen）

    /// ふたの絵を描き直す合図（中身・会員証の絵・内張り・正面の絵〔型・古び・ラベル・部品・よれ・名札〕が替わったとき）。
    /// 乗車券の写真は絵にせず生きたまま描くので、合図に入れない（写真が届くたびに描き直さない）
    private var snapshotKey: LidSnapshotKey {
        LidSnapshotKey(contents: contents, hasCard: cardImage != nil, lining: lining.name, model: model, posts: posts,
                       stuck: stuck, parts: parts, wrinkles: wrinkles, ownerName: ownerName)
    }

    /// 小さい画面・大きい文字でも舞台を下限（`TrunkLid.minScale`）より縮めない（メダルの押す所 44pt を保つ）。
    /// 入らない分は上下に送って見る。ふたを引く指は舞台の上では送りより先に効く（`highPriorityGesture`）
    private func openable(_ contents: TrunkInsideContents) -> some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            let room = Double(geo.size.height) - 28 - TrunkLid.controlsReserve
            let k = TrunkLid.stageScale(width: width, height: room)
            let overflows = TrunkLid.overflows(width: width, height: room)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Text(TrunkText.eyebrow(model))
                        .font(JPFont.eyebrow)
                        .tracking(11 * 0.12)
                        .foregroundStyle(WebTheme.accent)
                        .lineLimit(1)
                        .padding(.top, 4)
                    Color.clear
                        .frame(width: TrunkLid.stageWidth, height: TrunkLid.stageHeight)
                        .modifier(stage(contents))
                        .scaleEffect(k, anchor: .top)
                        .frame(width: width, height: TrunkLid.stageHeight * k, alignment: .top)
                        .contentShape(Rectangle())
                        .modifier(LidDragPriority(overflows: overflows, gesture: drag(scale: k)))
                    controls(contents)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
                .frame(minHeight: Double(geo.size.height), alignment: .top)
            }
        }
    }

    /// 舞台（390×584）。**ふたの角度・表と裏・胴の位置は、動きの途中の値から決める**（`TrunkLidStage` の
    /// `animatableData`）。平らなふた（押せる）への差し替えは開き切る動きが終わってから（`lidSettled`）
    private func stage(_ contents: TrunkInsideContents) -> TrunkLidStage {
        TrunkLidStage(p: p, settled: lidSettled && dragStart == nil, model: model, posts: posts, stuck: stuck,
                      ownerName: ownerName, parts: parts, wrinkles: wrinkles, lining: lining, contents: contents,
                      cardImage: cardImage, cardLabel: cardLabel, ticketPhotos: ticketPhotos, lifted: held,
                      closedLabel: TrunkText.accessibilityLabel(model: model, labels: TrunkPlacement.layout(stuck, stage: 0).count,
                                                                tags: TrunkAging.tagCount(posts: posts), equipped: parts),
                      images: lidImages, onPick: pick, onAdjust: { up in move(to: TrunkLid.stepped(p, up: up)) })
    }

    private var cardLabel: String {
        guard let profile else { return L("サポーター証", "Supporter card") }
        return cardFace(profile, profile.supporterInfo).accessibilityLabel
    }

    private var ticketPhotos: [Photo] { ticketContents.prefix(TrunkInsideContents.ticketStack).map(\.photo) }

    // MARK: 指で引き下ろす

    private func drag(scale k: Double) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard held == nil else { return }
                let start = dragStart ?? p
                if dragStart == nil { dragStart = p }
                lidSettled = false
                let next = TrunkLid.dragged(from: start, dy: Double(value.translation.height) / max(0.1, k))
                if TrunkLid.claspProgress(p) < 1, TrunkLid.claspProgress(next) >= 1 { claspTicks += 1 }
                p = next
            }
            .onEnded { _ in
                dragStart = nil
                settle(to: TrunkLid.settled(p))
            }
    }

    /// 開き切るか閉じ切る（指を離した・ボタン）。寄り切ったら触覚
    private func settle(to target: Double) {
        if target > 0, TrunkLid.claspProgress(p) < 1 {
            claspTicks += 1
            TrunkSound.tick()
        }
        move(to: target)
        landings += 1
    }

    /// 開き具合を動かす（板の 0.55s）。閉じ始めたらすぐ平らなふたを外し、開き切る動きが**終わってから**平らなふたにする
    private func move(to target: Double) {
        // 行き先がいまと同じ（指で 100% まで引いて離した）なら、動きの終わりを待たずにその場で決める
        guard TrunkLid.needsMotion(from: p, to: target) else {
            lidSettled = TrunkLid.isOpen(target)
            return
        }
        lidSettled = false
        if reduceMotion {
            p = target
            lidSettled = TrunkLid.isOpen(target)
            return
        }
        withAnimation(.timingCurve(0.2, 0.75, 0.25, 1, duration: TrunkLid.settleDuration), completionCriteria: .logicallyComplete) {
            p = target
        } completion: {
            // 途中で指が触れた・別の行き先に替わったときは差し替えない
            if p == target, dragStart == nil { lidSettled = TrunkLid.isOpen(target) }
        }
    }

    // MARK: 下の一言・棒・ボタン（板 TrunkOpen）

    private func controls(_ contents: TrunkInsideContents) -> some View {
        VStack(spacing: 10) {
            Text(phase == .failed
                 ? L("メダルと会員証を読み込めませんでした。電波のあるところで開き直すと入ります。",
                     "Couldn\u{2019}t load your medals and card. Open this again where you have a signal.")
                 : TrunkLid.hint(p))
                .font(.footnote)
                .foregroundStyle(phase == .failed ? WebTheme.danger : TrunkStyle.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 20)
                .accessibilityIdentifier("trunk.open.hint")
            HStack(spacing: 12) {
                Text(L("開き具合", "Open"))
                    .font(.caption)
                    .foregroundStyle(TrunkStyle.faint)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { p }, set: { p = $0; lidSettled = TrunkLid.isOpen($0) }), in: 0...1)
                    .tint(Color(trunk: TrunkRGBA(0x2A2A2A)))
                    .accessibilityLabel(L("ふたの開き具合", "How far the lid is open"))
                    .accessibilityValue(TrunkLid.accessibilityValue(p))
                    .accessibilityIdentifier("trunk.open.amount")
                Text(TrunkLid.percentText(p))
                    .font(JPFont.mono(12))
                    .foregroundStyle(WebTheme.text)
                    .frame(width: 40, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: WebTheme.minTapTarget)
            HStack(spacing: 8) {
                Button { settle(to: TrunkLid.toggled(p)) } label: {
                    TrunkButtonFace(title: TrunkLid.toggleTitle(p), kind: .secondary, height: 48, size: 15)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trunk.open.toggle")
                Button { takeFirst(contents) } label: {
                    TrunkButtonFace(title: L("中身を手に取る", "Pick something up"), kind: .secondary, height: 48, size: 15)
                }
                .buttonStyle(.plain)
                .disabled(contents.firstItem == nil)
                .accessibilityIdentifier("trunk.open.take")
            }
        }
    }

    /// 「中身を手に取る」: 開いていなければ開け切り、最初の1つ（メダル → 会員証 → 乗車券）を持ち上げる
    private func takeFirst(_ contents: TrunkInsideContents) {
        guard let first = contents.firstItem else { return }
        if !TrunkLid.isOpen(p) { settle(to: 1) }
        pick(first)
    }

    private func pick(_ item: TrunkHeld) {
        TrunkSound.tick()
        picks += 1
        if reduceMotion {
            held = item
        } else {
            withAnimation(.timingCurve(0.2, 0.75, 0.25, 1, duration: 0.42)) { held = item }
        }
    }

    private func putBack() {
        if reduceMotion {
            held = nil
        } else {
            withAnimation(.easeOut(duration: 0.25)) { held = nil }
        }
    }

    // MARK: 中身を手に取る（板 InsideHold）

    private func holdOverlay(_ item: TrunkHeld, _ contents: TrunkInsideContents) -> some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                heldItem(item, contents)
                Text(contents.title(item))
                    .font(JPFont.display(24, relativeTo: .title2))
                    .foregroundStyle(WebTheme.foreground)
                    .multilineTextAlignment(.center)
                    .padding(.top, 26)
                    .accessibilityAddTraits(.isHeader)
                Text(contents.subtitle(item))
                    .font(.footnote)
                    .foregroundStyle(TrunkStyle.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 24)
                VStack(spacing: 8) {
                    Button { go(item) } label: { TrunkButtonFace(title: contents.actionTitle(item), size: 15) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("trunk.hold.go")
                    Button { putBack() } label: {
                        TrunkButtonFace(title: TrunkInsideContents.putBackTitle, kind: .secondary, height: 48, size: 15)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trunk.hold.putBack")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.hold")
    }

    @ViewBuilder
    private func heldItem(_ item: TrunkHeld, _ contents: TrunkInsideContents) -> some View {
        switch item {
        case .medal(let badge):
            Image(BadgeCatalog.largeImage(badge.key, tier: badge.tier))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 220, height: 220)
                .shadow(color: Color.black.opacity(0.75), radius: 13, x: 0, y: 26)
                .accessibilityLabel(contents.title(item))
        case .more:
            // 扇に3枚（左・真ん中・右。真ん中がいちばん上）
            let fan = contents.fanMedals
            ZStack(alignment: .topLeading) {
                ForEach(Array(fan.enumerated()), id: \.offset) { i, badge in
                    Image(BadgeCatalog.largeImage(badge.key, tier: badge.tier))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 150, height: 150)
                        .rotationEffect(.degrees([-12.0, 0, 12][i]))
                        .shadow(color: Color.black.opacity(0.7), radius: 9, x: 0, y: 18)
                        .offset(x: [0.0, 62, 124][i], y: [18.0, 0, 18][i])
                        .zIndex([1.0, 3, 2][i])
                }
            }
            .frame(width: 274, height: 200, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(contents.title(item))
        case .card:
            GeometryReader { geo in
                let w = min(SupporterCardLayout.width, Double(geo.size.width) - 48)
                Group {
                    if let cardImage {
                        Image(uiImage: cardImage).resizable().interpolation(.high)
                    } else {
                        Image("supporter-card-front").resizable().interpolation(.high)
                    }
                }
                .frame(width: w, height: w / SupporterCardLayout.aspect)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.75), radius: 24, x: 0, y: 24)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 6), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : -8), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(height: SupporterCardLayout.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cardLabel)
        case .tickets:
            let photos = ticketPhotos
            ZStack(alignment: .topLeading) {
                ForEach(0..<min(TrunkInsideContents.ticketStack, max(1, contents.ticketCount)), id: \.self) { i in
                    bigTicket(photos.indices.contains(i) ? photos[i] : nil)
                        .rotationEffect(.degrees([-9.0, 6, -3][i]))
                        .offset(x: [10.0, 34, 58][i], y: 12)
                }
            }
            .frame(width: 210, height: 220, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(contents.ticketLabel)
        }
    }

    private func bigTicket(_ photo: Photo?) -> some View {
        let brass = WebTheme.accent
        return VStack(spacing: 0) {
            Group {
                if let photo {
                    RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                } else {
                    Color(trunk: TrunkRGBA(0x1A1A1A))
                }
            }
            .frame(width: 138, height: 114)
            .clipped()
            brass.opacity(0.55).frame(height: 1)
            Spacer(minLength: 0)
        }
        .frame(width: 138, height: 192)
        .background(Color(trunk: TrunkRGBA(0x0E0D0B)))
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 6) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0.5))
                    p.addLine(to: CGPoint(x: 102, y: 0.5))
                }
                .stroke(brass.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: 102, height: 1)
                Circle().strokeBorder(brass.opacity(0.5), lineWidth: 1).frame(width: 10, height: 10)
            }
            .padding(.leading, 10)
            .padding(.bottom, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(brass.opacity(0.5), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.65), radius: 9, x: 0, y: 16)
    }

    /// 出口: 今ある画面へ
    private func go(_ item: TrunkHeld) {
        switch item {
        case .medal(let badge): viewingMedal = badge
        case .more: showShelf = true
        case .card: if profile != nil { showCard = true }
        case .tickets: showBook = true
        }
        held = nil
    }

    // MARK: 空のトランク（板 InsideEmpty）

    private func emptyTrunk(_ contents: TrunkInsideContents) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Text(TrunkText.eyebrow(model))
                        .font(JPFont.eyebrow)
                        .tracking(11 * 0.12)
                        .foregroundStyle(WebTheme.accent)
                        .lineLimit(1)
                        .padding(.top, 4)
                    TrunkInsideView(model: model, part: .all, lining: lining, contents: contents)
                        .scaleEffect(0.7, anchor: .topLeading)
                        .frame(width: TrunkInsideView.width * 0.7, height: TrunkInsideView.openHeight * 0.7, alignment: .topLeading)
                        .padding(.top, 10)
                    VStack(spacing: 0) {
                        let rows = TrunkInsideEmpty.rows
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                            emptyRow(row)
                            if i < rows.count - 1 { TrunkStyle.line.frame(height: 1) }
                        }
                    }
                    .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
                .padding(.bottom, 16)
            }
            Button { tabRouter.openPost(.photo) } label: {
                TrunkButtonFace(title: TrunkInsideEmpty.actionTitle, size: 15)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .accessibilityIdentifier("trunk.open.emptyPost")
        }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.open.empty")
    }

    private func emptyRow(_ row: TrunkInsideEmpty.Row) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                switch row.shape {
                case .medal:
                    Circle().strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 28, height: 28)
                case .card:
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 28, height: 20)
                        .padding(.vertical, 4)
                case .ticket:
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 20, height: 28)
                        .padding(.horizontal, 4)
                }
            }
            .frame(width: 28)
            .padding(.top, 1)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(TrunkStyle.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// ふたを開ける舞台（390×584・板 TrunkOpen）。**`p`（開き具合）が動きの途中の値で毎コマ描き直される**
/// （`animatableData`）ので、ボタン・離して寄る動きでも、ふたは途中の角度を通って倒れ・起き、90° を越えた
/// コマから裏を描く。床の光・持ち手・胴（中）・ふた・蝶番を重ねる
struct TrunkLidStage: ViewModifier, Animatable {
    var p: Double
    /// 開き切る動きが終わった（平らなふたを置いて押せる）
    let settled: Bool
    let model: TrunkModel
    let posts: Int
    let stuck: [TrunkLabel]
    let ownerName: String?
    let parts: TrunkEquipped
    let wrinkles: [String: Double]
    let lining: TrunkLining
    let contents: TrunkInsideContents
    let cardImage: UIImage?
    let cardLabel: String
    let ticketPhotos: [Photo]
    let lifted: TrunkHeld?
    /// 閉じている・倒れている途中の読み上げ（トランクの名前）
    let closedLabel: String
    /// 1度だけ描いた絵（無ければその場で描く）
    let images: TrunkLidImages?
    let onPick: (TrunkHeld) -> Void
    /// 読み上げの「増やす・減らす」（true で開く方へ1段）
    let onAdjust: (Bool) -> Void

    var animatableData: Double {
        get { p }
        set { p = newValue }
    }

    func body(content: Content) -> some View {
        let pose = TrunkLid.pose(p)
        let flat = TrunkLid.showsFlatLid(p, settled: settled)
        let left = TrunkLid.bodyLeft
        let h = TrunkLid.bodyHeight
        return content.overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                // 床に落ちる真鍮の淡い光（ふたが倒れると下へ）
                EllipticalGradient(colors: [WebTheme.accent.opacity(0.14), Color.clear])
                    .frame(width: 320, height: 26)
                    .offset(x: 35, y: pose.baseTop + h - 8 + h * p)
                    .accessibilityHidden(true)
                // 上の面の持ち手（胴に付いたまま・正面の絵の上 40）
                handleStrip
                    .offset(x: left, y: pose.baseTop - TrunkLooks.bodyTop)
                    .accessibilityHidden(true)
                // 胴の中。閉じている・倒れている途中は読ませない（ふたの名前だけ読む）
                base(flat: flat)
                    .offset(x: left, y: pose.baseTop)
                    .accessibilityHidden(!flat)
                if flat {
                    // 開き切った: ふたの裏は平らに置いて押せるようにする（3D の回転の中では押す場所がずれる）
                    TrunkInsideView(model: model, part: .lid, lining: lining, contents: contents, interactive: true,
                                    lifted: lifted, onPick: onPick)
                        .offset(x: left, y: pose.baseTop + h)
                } else {
                    lid(pose)
                        .rotation3DEffect(.degrees(-pose.angle), axis: (x: 1, y: 0, z: 0), anchor: .bottom,
                                          perspective: TrunkLid.perspective)
                        .offset(x: left, y: pose.baseTop)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if pose.hingesVisible {
                    ForEach([64.0, 268], id: \.self) { x in
                        TrunkPartPaintView(paint: TrunkInsideLooks.look(model).metal)
                            .frame(width: 28, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.45)).frame(height: 1) }
                            .shadow(color: Color.black.opacity(0.6), radius: 1.5, x: 0, y: 2)
                            .offset(x: left + x, y: pose.baseTop + h - 7)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(width: TrunkLid.stageWidth, height: TrunkLid.stageHeight, alignment: .topLeading)
            .modifier(StageAccessibility(open: flat, label: closedLabel, value: TrunkLid.accessibilityValue(p),
                                         onAdjust: onAdjust))
        }
    }

    /// 持ち手の帯（1度だけ描いた絵があればそれ）
    @ViewBuilder
    private var handleStrip: some View {
        if let image = images?.handle {
            TrunkLidImages.place(image, w: TrunkLooks.canvasWidth, h: 40, pad: 0)
        } else {
            TrunkBoxView(model: model, posts: posts, stuck: stuck, ownerName: ownerName, parts: parts, wrinkles: wrinkles)
                .frame(width: TrunkLooks.canvasWidth, height: 40, alignment: .top)
                .clipped()
        }
    }

    /// 胴の中。開き切ったら押せる生の絵、動かしている間は乗車券の下と上を絵にして、写真の乗車券だけ生きたまま挟む
    @ViewBuilder
    private func base(flat: Bool) -> some View {
        if !flat, let below = images?.baseBelow, let above = images?.baseAbove {
            ZStack(alignment: .topLeading) {
                TrunkLidImages.place(below, w: TrunkInsideView.width, h: TrunkInsideView.height)
                TrunkInsideView(model: model, part: .base, lining: lining, contents: contents,
                                ticketPhotos: ticketPhotos, layer: .ticketsOnly)
                TrunkLidImages.place(above, w: TrunkInsideView.width, h: TrunkInsideView.height, pad: 0)
            }
            .frame(width: TrunkInsideView.width, height: TrunkInsideView.height, alignment: .topLeading)
        } else {
            TrunkInsideView(model: model, part: .base, lining: lining, contents: contents, cardImage: cardImage,
                            cardLabel: cardLabel, ticketPhotos: ticketPhotos, interactive: flat, lifted: lifted,
                            onPick: onPick)
        }
    }

    /// 倒れていくふた。90° までは表（正面の絵・錠前の板が起きる）、越えたら裏（上下を返して描き、回すと正しい向き）
    @ViewBuilder
    private func lid(_ pose: TrunkLid.Pose) -> some View {
        if pose.showsInside {
            Group {
                if let image = images?.lidInside {
                    TrunkLidImages.place(image, w: TrunkInsideView.width, h: TrunkInsideView.height)
                } else {
                    TrunkInsideView(model: model, part: .lid, lining: lining, contents: contents)
                }
            }
            .frame(width: TrunkInsideView.width, height: TrunkInsideView.height, alignment: .topLeading)
                .overlay {
                    RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(pose.innerShade))
                }
                .scaleEffect(x: 1, y: -1)
        } else {
            ZStack(alignment: .topLeading) {
                if let image = images?.front {
                    TrunkLidImages.place(image, w: TrunkLooks.bodyWidth, h: TrunkLooks.bodyHeight)
                } else {
                    TrunkBoxView(model: model, posts: posts, stuck: stuck, ownerName: ownerName, bodyOnly: true,
                                 parts: parts, wrinkles: wrinkles)
                }
                if pose.claspProgress > 0 { clasp(pose) }
                RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(pose.lidShade))
            }
            .frame(width: TrunkLooks.bodyWidth, height: TrunkLooks.bodyHeight, alignment: .topLeading)
        }
    }

    /// 錠前の板（開け始めの 10% で手前へ起き、下の受けが見える）
    private func clasp(_ pose: TrunkLid.Pose) -> some View {
        let look = TrunkLooks.look(model, stage: TrunkAging.stage(posts: posts))
        let fittings = TrunkFittings(parts)
        let w = look.lock.width, h = look.lock.height
        let x = 180 - w / 2, y = TrunkLooks.lockTop(look)
        return ZStack(alignment: .topLeading) {
            // 受け（暗い凹みと、掛け金の穴）
            ZStack {
                LinearGradient(colors: [Color(trunk: TrunkRGBA(0x3A2A14)), Color(trunk: TrunkRGBA(0x1A1008))],
                               startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(trunk: TrunkRGBA(0x2A1A0A))).frame(width: 6, height: 6).offset(y: h * 0.2)
            }
            .frame(width: w, height: h)
            .clipShape(TrunkLockShape(round: look.lock.round))
            .offset(x: x, y: y)
            // 起きる板
            ZStack {
                TrunkHardwareFace(look: look, fittings: fittings, w: w, h: h)
                UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 4)
                    .fill(Color.black.opacity(0.65))
                    .frame(width: 7, height: 11)
            }
            .frame(width: w, height: h)
            .clipShape(TrunkLockShape(round: look.lock.round))
            .shadow(color: Color.black.opacity(0.6), radius: 2 + 3 * pose.claspProgress, x: 0, y: 2 + 8 * pose.claspProgress)
            .rotation3DEffect(.degrees(pose.claspAngle), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
            .offset(x: x, y: y)
        }
        .accessibilityHidden(true)
    }
}

/// 舞台の読み上げ。開き切ったら中の押せるものを1つずつ、閉じている・途中は1つの要素（名前・開き具合・
/// 「増やす／減らす」で1段ずつ開け閉め）
private struct StageAccessibility: ViewModifier {
    let open: Bool
    let label: String
    let value: String
    let onAdjust: (Bool) -> Void

    func body(content: Content) -> some View {
        if open {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("trunk.open.stage")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(value)
                .accessibilityHint(L("上下に払うと、ふたを開け閉めします", "Swipe up or down to open or close the lid"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: onAdjust(true)
                    case .decrement: onAdjust(false)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("trunk.open.closed")
        }
    }
}

/// ふたの絵を描き直す合図
private struct LidSnapshotKey: Equatable {
    let contents: TrunkInsideContents
    let hasCard: Bool
    let lining: String
    // 倒れるふたの表・持ち手の帯（正面の絵）に効くもの
    let model: TrunkModel
    let posts: Int
    let stuck: [TrunkLabel]
    let parts: TrunkEquipped
    let wrinkles: [String: Double]
    let ownerName: String?
}

/// ふたを動かしている間に使い回す絵（2026-10-18 見直し）。動きの途中のコマごとに正面の絵（ラベル・部品）や
/// 胴の中を作り直さないよう、開いたとき・中身が替わったときに1度だけ描く。影が切れないよう周りに余白を付けて描く
struct TrunkLidImages {
    /// 正面（倒れていくふたの表）
    let front: UIImage?
    /// 上の面の持ち手の帯（正面の絵の上 40）
    let handle: UIImage?
    /// ふたの裏
    let lidInside: UIImage?
    /// 胴の、乗車券の下の層と上の層（乗車券は写真が後から届くので生きたまま挟む）
    let baseBelow: UIImage?
    let baseAbove: UIImage?

    /// 影のための余白（影のある絵だけ。胴の上の層と持ち手の帯は影が無いので余白なし＝絵を小さく持つ）
    static let pad: Double = 48

    /// 1コマ待ってから描く（画面が押し出される途中で止まらないように）。待つ間に取り消されたら描かずに nil
    @MainActor
    static func make(_ stage: TrunkLidStage) async -> TrunkLidImages? {
        do { try await Task.sleep(for: .milliseconds(16)) } catch { return nil }
        guard !Task.isCancelled else { return nil }
        return TrunkLidImages(
            front: render(TrunkBoxView(model: stage.model, posts: stage.posts, stuck: stage.stuck, ownerName: stage.ownerName,
                                       bodyOnly: true, parts: stage.parts, wrinkles: stage.wrinkles),
                          w: TrunkLooks.bodyWidth, h: TrunkLooks.bodyHeight),
            handle: render(TrunkBoxView(model: stage.model, posts: stage.posts, stuck: stage.stuck, ownerName: stage.ownerName,
                                        parts: stage.parts, wrinkles: stage.wrinkles)
                            .frame(width: TrunkLooks.canvasWidth, height: 40, alignment: .top)
                            .clipped(),
                           w: TrunkLooks.canvasWidth, h: 40, pad: 0),
            lidInside: render(TrunkInsideView(model: stage.model, part: .lid, lining: stage.lining, contents: stage.contents),
                              w: TrunkInsideView.width, h: TrunkInsideView.height),
            baseBelow: render(TrunkInsideView(model: stage.model, part: .base, lining: stage.lining, contents: stage.contents,
                                              cardImage: stage.cardImage, layer: .belowTickets),
                              w: TrunkInsideView.width, h: TrunkInsideView.height),
            baseAbove: render(TrunkInsideView(model: stage.model, part: .base, lining: stage.lining, contents: stage.contents,
                                              layer: .aboveTickets),
                              w: TrunkInsideView.width, h: TrunkInsideView.height, pad: 0))
    }

    @MainActor
    private static func render<V: View>(_ view: V, w: Double, h: Double, pad: Double = pad) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: w, height: h, alignment: .topLeading).padding(pad))
        renderer.scale = 3
        return renderer.uiImage
    }

    /// 余白ごと描いた絵を、元の枠（`w`×`h`）の位置に置く
    @MainActor
    static func place(_ image: UIImage, w: Double, h: Double, pad: Double = pad) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: w + pad * 2, height: h + pad * 2)
            .offset(x: -pad, y: -pad)
            .frame(width: w, height: h, alignment: .topLeading)
            .allowsHitTesting(false)
    }
}

/// ふたを引く指と、画面の送りの取り合い（2026-10-18 見直し）。
/// 画面に収まるときは引く指を先に効かせる（送りは無い）。収まらず送りがあるときは、引く指と送りを両方効かせる
/// （舞台が画面の大半を占めるので、舞台の上で送れないと下のボタンへ届かない）。
/// **枝分けで View を替えない**——どちらでも同じ形のまま、効かせない方を `GestureMask` で止める
/// （if/else で包むと切り替わるたびに舞台がまるごと作り直され、中の状態・写真の読み込みが消える）
private struct LidDragPriority<G: Gesture>: ViewModifier {
    let overflows: Bool
    let gesture: G

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(gesture, including: Self.highPriorityMask(overflows: overflows))
            .simultaneousGesture(gesture, including: Self.simultaneousMask(overflows: overflows))
    }

    /// 収まるときだけ、引く指を先に（止めるときも中のボタンの指は通す）
    static func highPriorityMask(overflows: Bool) -> GestureMask { overflows ? .subviews : .all }
    /// 送りがあるときだけ、引く指と送りを両方
    static func simultaneousMask(overflows: Bool) -> GestureMask { overflows ? .all : .subviews }
}

