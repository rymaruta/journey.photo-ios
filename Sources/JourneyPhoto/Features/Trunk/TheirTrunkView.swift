import SwiftUI

/// 人のトランクを開ける画面に渡す中身（`TrunkOpenView` の `theirs`）。**読むだけ**
struct TheirTrunkInside {
    let userId: String
    /// 画面に出す名前（`UserProfileViewModel.shownName`）
    let name: String?
    let handle: String?
    /// 乗車券の「発」に出す居住地（公開プロフィールの `homeLocation`）
    let homeLocation: String?
    let trunk: TheirTrunk
    /// 「ほか N」でその人のバッジの棚を開くときに渡す
    let profile: UserProfile?
    /// その人の公開写真（乗車券の写真を引く）
    let photos: [Photo]
    /// 画面写真の見本で動いているか
    var preview = false

    var ticketPhoto: Photo? { TheirTrunkText.ticketPhoto(trunk.ticket, in: photos, preview: preview) }

    /// 会員証の表（**番号と始めた年月は刷らない**・板 TheirInside）
    var cardFace: SupporterCardFace {
        SupporterCardFace(name: name ?? "", handle: handle, number: 0, since: nil, showsNumber: false)
    }
}

/// 人のトランクの読み込み（プロフィールの段と人のトランクの画面が同じものを見る）。
///
/// - 見せていない（404）は `.hidden`。**理由は区別しない**（段ごと出さない・画面は「いまは見られません」）
/// - 一度読めた中身は、読み直しの失敗で消さない（`TrunkViewModel` と同じ判断）
/// - 画面写真の見本（`-JPPreviewTheirTrunk`）ではサーバーに何も送らず、見本のトランクを出す
@MainActor
final class TheirTrunkModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        /// 見せていない（404・理由は区別しない）・ログインしていない
        case hidden
        case failed(String)
        case offline
    }

    @Published private(set) var trunk: TheirTrunk?
    @Published private(set) var phase: Phase = .idle

    let isPreview: Bool
    private var userId: String?
    /// 読み込みの回（後から始まった回があれば、前の回は何も書かない）
    private var seq = 0

    private let entry: TrunkEntryStore

    init(preview: Bool = PreviewSession.theirTrunkSample, entry: TrunkEntryStore? = nil) {
        isPreview = preview
        self.entry = entry ?? .shared
    }

    /// プロフィールに段を出すか（読めて、中身があるときだけ。読み込み中・失敗・404・ブロックの関係では空の枠も出さない）
    func showsOnProfile(blocked: Bool) -> Bool { !blocked && phase == .loaded && trunk != nil }

    /// - Parameter isSelf: 自分のプロフィールを人の画面で開いた。人の口は自分には見せない設定でも中身を返すので、
    ///   **自分の設定（`GET /user/trunk` の `showTrunk`）がオフなら見せない**（人には出ていない段を出さない）
    func load(userId: String, service: TrunkService, signedIn: Bool, offline: Bool, isSelf: Bool = false) async {
        if self.userId != userId {
            self.userId = userId
            trunk = nil
            phase = .idle
        }
        // どの枝でも回を進める（前に始まった回の答えが、あとの「見せない」「見本」を上書きしない）
        seq += 1
        let mine = seq
        // 人の口はログインした人だけ
        guard signedIn else {
            trunk = nil
            phase = .hidden
            return
        }
        if isPreview {
            trunk = TheirTrunkSample.trunk(userId: userId)
            phase = .loaded
            return
        }
        // サーバーが人のトランクに対応していないと分かっている間（いまの本番）は、人の口を読まない（道が無く必ず 404）。
        // 分からない間（自分のトランクをまだ読んでいない）は今までどおり読む
        if entry.knownSupportsSharing == false {
            trunk = nil
            phase = .hidden
            return
        }
        if trunk == nil { phase = .loading }
        do {
            if isSelf {
                // 自分の見せる設定は入口の店（`TrunkEntryStore`）が読めている中身を使い、**無いときだけ読む**
                // （読むのも同じ店を通す＝`GET /user/trunk` を1本にまとめる）。端末には書かない
                // サーバーが対応していない（`showTrunk` の欄が無い）応答なら、人には出ていないので段を出さない
                var shows = entry.state(for: userId)?.sharedWithOthers
                if shows == nil {
                    let own = try await entry.read(userId: userId, service: service)
                    guard mine == seq, self.userId == userId else { return }
                    shows = own.sharedWithOthers
                }
                guard shows == true else {
                    trunk = nil
                    phase = .hidden
                    return
                }
            }
            let fresh = try await service.theirs(userId)
            guard mine == seq, self.userId == userId else { return }
            if let fresh {
                trunk = fresh
                phase = .loaded
            } else {
                trunk = nil
                phase = .hidden
            }
        } catch {
            // 取り消された回（画面を離れた）は書かない。一度読めた中身は残す
            guard mine == seq, self.userId == userId, !Task.isCancelled, !(error is CancellationError) else { return }
            if trunk != nil { return }
            phase = TrunkViewModel.isUnreachable(error) && offline ? .offline : .failed(TrunkViewModel.message(error))
        }
    }
}

/// 人のプロフィールのトランクの段（板 ProfileTrunk）。押すと人のトランクの画面
struct TheirTrunkCard: View {
    let trunk: TheirTrunk
    let ownerName: String?

    var body: some View {
        HStack(spacing: 10) {
            // 板: 360×300 を 0.389 倍（140×117）・少し横を向ける（rotateY -6°）
            TrunkFigure(model: trunk.model, posts: trunk.agingPosts, stuck: trunk.stuck, ownerName: ownerName,
                        parts: trunk.equipped, width: 140)
                .rotation3DEffect(.degrees(-6), axis: (x: 0, y: 1, z: 0), perspective: 0.36)
                .frame(width: 140, height: 117, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 5) {
                Text(TheirTrunkText.cardEyebrow)
                    .font(JPFont.eyebrow)
                    .tracking(11 * 0.12)
                    .foregroundStyle(WebTheme.accent)
                Text(TrunkText.info(trunk.model).name)
                    .font(JPFont.display(18, relativeTo: .headline))
                    .foregroundStyle(WebTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(TheirTrunkText.cardDetail(hasLabels: !trunk.stuck.isEmpty))
                    .font(.caption)
                    .foregroundStyle(TrunkStyle.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(minHeight: 136)
        // 札の地（板: 白 6%・白 8% の縁・角 16）は共通の部品で
        .jpCardFace(fill: Color.white.opacity(0.06))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TheirTrunkText.cardAccessibility(owner: ownerName, model: trunk.model))
        .accessibilityAddTraits(.isButton)
    }
}

/// 人のトランク（板 TheirTrunk・2026-10-18）。上から: 型の名前（真鍮の眉）→ トランク（ラベルを押して選ぶ・
/// 選んだラベルに真鍮の点線）→「手に取って回す」「ふたを開ける」→ 下のシート（選んだラベル・その土地で撮った写真3枚・注記）。
///
/// **読むだけ**: 貼る・はがす・回す機械・部品箱は出さない。地名の無いラベルは地名なしの形（`TrunkLabelDesign.isSealed`）で
/// 描き、写真は出さない（伏せたかどうかは言わない）。読み込み中・失敗（もう一度）・圏外・見られない、をそれぞれの形で出す
struct TheirTrunkView: View {
    let userId: String
    let ownerName: String?
    var handle: String?
    var homeLocation: String?
    var profile: UserProfile?
    /// その人の公開写真（プロフィールで読んだもの・見せない設定の写真は落としてある）
    let photos: [Photo]
    /// 写真の一覧を読み終えたか（読み込み中は格子の骨格）
    var photosReady = true
    @ObservedObject var model: TheirTrunkModel

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedId: String?
    @State private var showSpin = false

    var body: some View {
        content
            .background { TrunkStyle.stageBackground(centerY: 0.28) }
            .navigationTitle(TheirTrunkText.title(ownerName))
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: selectedId)
            .task { await reload() }
            .onChange(of: model.trunk) { _, trunk in
                // ラベルの id は返答の中だけの番号。中身が替わったら選び直す
                guard let trunk else { selectedId = nil; return }
                selectedId = TheirTrunkText.defaultSelection(trunk, drawn: drawn(trunk).map(\.label))
            }
            .fullScreenCover(isPresented: $showSpin) {
                if let trunk = model.trunk {
                    TrunkSpinViewer(model: trunk.model, posts: trunk.agingPosts, stuck: trunk.stuck, ownerName: ownerName,
                                    parts: trunk.equipped)
                }
            }
    }

    private func reload() async {
        await model.load(userId: userId, service: environment.trunk, signedIn: auth.userId != nil,
                         offline: connectivity.isOffline, isSelf: userId == auth.userId)
        if selectedId == nil, let trunk = model.trunk {
            selectedId = TheirTrunkText.defaultSelection(trunk, drawn: drawn(trunk).map(\.label))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let trunk = model.trunk {
            loaded(trunk)
        } else {
            switch model.phase {
            case .idle, .loading, .loaded:
                ScrollView {
                    VStack(spacing: 16) {
                        // 読み込み中も形は同じ（新しいトランクを薄く置き、行は骨格）
                        TrunkFigure(model: .leather, posts: 0, width: 300)
                            .opacity(0.25)
                            .padding(.top, 40)
                        JPLoadingState(kind: .rows).padding(.horizontal, 20)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("trunk.their.loading")
            case .failed(let message):
                ErrorBanner(title: TheirTrunkText.failedTitle, message: message, retry: { Task { await reload() } })
                    .frame(maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("trunk.their.failed")
            case .offline:
                ErrorBanner(title: L("電波がありません", "No signal"), message: TheirTrunkText.offlineMessage,
                            retry: { Task { await reload() } })
                    .frame(maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("trunk.their.offline")
            case .hidden:
                EmptyState(title: TheirTrunkText.hiddenTitle,
                           message: L("プロフィールに戻ると、この人の写真を見られます。",
                                      "Go back to the profile to see this person\u{2019}s photos."))
                    .frame(maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("trunk.their.hidden")
            }
        }
    }

    /// トランクに描くラベル（`TrunkBoxView` と同じ並び・同じ古び方）
    private func drawn(_ trunk: TheirTrunk) -> [TrunkSlots.Placed] {
        TrunkPlacement.layout(trunk.stuck, stage: TrunkAging.stage(posts: trunk.agingPosts))
    }

    private func loaded(_ trunk: TheirTrunk) -> some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Text(TrunkText.info(trunk.model).name)
                        .font(JPFont.eyebrow)
                        .tracking(11 * 0.12)
                        .foregroundStyle(WebTheme.accent)
                        .lineLimit(1)
                        .padding(.top, 4)
                    stage(trunk, width: Double(geo.size.width))
                        .padding(.top, 14)
                    buttons(trunk)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    sheet(trunk)
                        .padding(.top, 24)
                }
                .frame(minHeight: Double(geo.size.height), alignment: .top)
            }
            .refreshable { await reload() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.their.screen")
    }

    // MARK: トランク（板: 360×300・ラベルの押せる所・選んだ印）

    private func stage(_ trunk: TheirTrunk, width: Double) -> some View {
        let k = min(1, max(0.5, (width - 30) / TrunkLooks.canvasWidth))
        let placed = drawn(trunk)
        let selected = placed.first { $0.label.id == selectedId }
        return ZStack(alignment: .topLeading) {
            TrunkBoxView(model: trunk.model, posts: trunk.agingPosts, stuck: trunk.stuck, ownerName: ownerName,
                         parts: trunk.equipped)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TrunkText.accessibilityLabel(model: trunk.model, labels: placed.count,
                                                                 tags: TrunkLooks.tags(stuck: trunk.stuck, posts: trunk.agingPosts).count,
                                                                 equipped: trunk.equipped))
                .accessibilityAddTraits(.isImage)
            // ラベルの id で見分ける（押せる所と読み上げが、読み直しで別のラベルに入れ替わらない・`TrunkSlots.Placed.id`）
            ForEach(placed) { p in
                let f = TheirTrunkText.hitFrame(p, scale: k)
                let on = p.label.id == selectedId
                Button { select(p.label.id) } label: {
                    Color.clear
                        .frame(width: f.w, height: f.h)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .offset(x: f.x, y: f.y)
                .zIndex(on ? 15 : 10)
                .accessibilityLabel(TheirTrunkText.labelAccessibility(p.label, place: trunk.place(of: p.label)))
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("trunk.their.label")
            }
            if let selected {
                let r = TheirTrunkText.ringFrame(selected)
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(WebTheme.accent.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: r.w, height: r.h)
                    .rotationEffect(.degrees(r.rot))
                    .offset(x: r.x, y: r.y)
                    .zIndex(20)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: TrunkLooks.canvasWidth, height: TrunkLooks.canvasHeight, alignment: .topLeading)
        .scaleEffect(k, anchor: .topLeading)
        .frame(width: TrunkLooks.canvasWidth * k, height: TrunkLooks.canvasHeight * k, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func select(_ id: String) {
        guard id != selectedId else { return }
        TrunkSound.tick()
        if reduceMotion {
            selectedId = id
        } else {
            withAnimation(.timingCurve(0.2, 0.75, 0.25, 1, duration: 0.32)) { selectedId = id }
        }
    }

    // MARK: 回す・開ける

    private func buttons(_ trunk: TheirTrunk) -> some View {
        HStack(spacing: 8) {
            Button { showSpin = true } label: {
                TrunkButtonFace(title: L("手に取って回す", "Pick up and turn"), kind: .secondary, height: 44, size: 15)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.their.spin")
            NavigationLink {
                TrunkOpenView(model: trunk.model, posts: trunk.agingPosts, stuck: trunk.stuck, ownerName: ownerName,
                              parts: trunk.equipped,
                              theirs: TheirTrunkInside(userId: userId, name: ownerName, handle: handle,
                                                       homeLocation: homeLocation, trunk: trunk, profile: profile,
                                                       photos: photos, preview: model.isPreview))
            } label: {
                TrunkButtonFace(title: L("ふたを開ける", "Open the lid"), kind: .secondary, height: 44, size: 15)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.their.open")
        }
    }

    // MARK: 下のシート（選んだラベルと、その土地で撮った写真）

    private func sheet(_ trunk: TheirTrunk) -> some View {
        let label = trunk.stuck.first { $0.id == selectedId }
        let place = label.flatMap { trunk.place(of: $0) }
        let matched = place.map { TheirTrunkText.photos(at: $0, in: photos) } ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color(trunk: TrunkRGBA(0x3A3A3A)))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            Group {
                if let label {
                    selection(label, place: place, matched: matched)
                } else {
                    Text(TheirTrunkText.noLabels)
                        .font(.subheadline)
                        .foregroundStyle(TrunkStyle.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .id(selectedId ?? "")
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 24)))
            Text(TheirTrunkText.sheetNote)
                .font(.caption)
                .foregroundStyle(TrunkStyle.faint)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(TrunkStyle.cell)
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.their.sheet")
    }

    @ViewBuilder
    private func selection(_ label: TrunkLabel, place: String?, matched: [Photo]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                TrunkLabelThumb(label: label, maxWidth: 72, maxHeight: 56, rot: 0)
                    .frame(width: 76, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(TheirTrunkText.sheetTitle(label))
                        .font(JPFont.display(20, relativeTo: .title3))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    Text(TheirTrunkText.sheetSubtitle(place: place, owner: ownerName,
                                                      count: place != nil && photosReady ? matched.count : nil))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(TrunkStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let place {
                photoGrid(place: place, matched: matched)
            }
        }
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    @ViewBuilder
    private func photoGrid(place: String, matched: [Photo]) -> some View {
        if !photosReady {
            // 読み込み中は3枚ぶんの骨格（「無い」と言わない）
            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6).fill(TrunkStyle.line).frame(height: 112)
                }
            }
            .accessibilityHidden(true)
        } else if matched.isEmpty {
            Text(TheirTrunkText.noPhotos)
                .font(.footnote)
                .foregroundStyle(TrunkStyle.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(Array(matched.prefix(3).enumerated()), id: \.element.id) { i, photo in
                    NavigationLink { PhotoDetailView(photo: photo, context: matched) } label: {
                        Color.clear
                            .frame(height: 112)
                            .overlay { RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment) }
                            .background(TrunkStyle.line)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(TheirTrunkText.photoAccessibility(place: place, index: i, title: photo.displayTitle))
                    .accessibilityIdentifier("trunk.their.photo")
                }
            }
        }
    }
}

/// 人の「わたしの乗車券」を回して見る（すれちがいの乗車券と同じ回る部品 `PassSpinCard`・番号は出さない）
struct TrunkTheirTicketView: View {
    let theirs: TheirTrunkInside

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let ticket = theirs.trunk.ticket {
                    let faces = Self.faces(ticket, theirs: theirs)
                    PassSpinCard(front: faces.front, back: faces.back,
                                 spokenName: L("\(TheirTrunkText.owner(theirs.name))さんの乗車券",
                                               "\(TheirTrunkText.owner(theirs.name))\u{2019}s ticket"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    Text(L("指で回すと、裏のひとことが見られます", "Turn it with your finger to read the note on the back"))
                        .font(.caption)
                        .foregroundStyle(TrunkStyle.faint)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background { TrunkStyle.stageBackground(centerY: 0.4) }
        .navigationTitle(L("わたしの乗車券", "Their ticket"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.their.ticket")
    }

    /// 表と裏（自分の乗車券の見本と同じ組み方・会ってから決まる欄は「—」）
    static func faces(_ ticket: TrunkTicket, theirs: TheirTrunkInside) -> (front: PassTicketFace, back: PassTicketBackFace) {
        let name = TheirTrunkText.owner(theirs.name)
        // 連絡先の形は券に出さない（`TheirTrunkText.ticketRoute`）
        let route = TheirTrunkText.ticketRoute(ticket)
        let choice = route.choice
        let prefecture = PassExchange.homePrefecture(theirs.homeLocation)
        let photo = theirs.ticketPhoto
        let front = PassTicketFace(photo: photo, kind: .plain, number: nil,
                                   origin: PassTicket.previewOrigin(choice, text: route.origin, homePrefecture: prefecture),
                                   destination: PassTicket.previewDestination(custom: !route.destination.isEmpty,
                                                                              text: route.destination),
                                   name: name, distance: nil, date: nil,
                                   count: PassTicket.countLabel(.plain, meetingCount: nil),
                                   via: PassTicket.via(L("旅先", "their trip")),
                                   style: PassTicketFaceStyle.fromWire(ticket.face == 0 ? nil : UInt8(ticket.face)))
        let back = PassTicketBackFace.preview(photoTitle: photo?.displayTitle, note: route.note, name: name,
                                              origin: choice, homePrefecture: prefecture, style: front.style)
        return (front, back)
    }
}
