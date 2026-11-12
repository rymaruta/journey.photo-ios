import SwiftUI
// Linux では URLSession が別モジュールに居る（iOS では何も起きない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ホームで手に取っている写真（2026-11-12・札 #543・資料第6章 段1・決まりは `PhotoLift`）。
///
/// 札（`HomeFeedTile`）が指の位置を書き、ホーム（`GalleryView`）の上に重ねた `PhotoLiftOverlay` が
/// 行き先と指に付いた写真を描く。**手に取っている間はホームの縦の送りと横の払いを止める**
/// （`GalleryView` の `scrollDisabled`・`ProfileTabPager` の払いの始まり）
@MainActor
final class PhotoLiftCenter: ObservableObject {

    static let shared = PhotoLiftCenter()

    /// 手に取っている写真（無ければ nil）
    @Published private(set) var photo: Photo?
    /// 指の位置（画面の座標）
    @Published private(set) var point: CGPoint = .zero
    /// 下へ弾いて開いたままの送る人の列（写真は指から離れ、顔を押して送る）
    @Published var facesOpenFor: Photo?
    /// 落とした後の取り消し（3秒）
    let undo = CountdownUndo()

    /// 指の跡（弾く判定・`PhotoLift.flick`）
    private var samples: [(t: Double, x: Double, y: Double)] = []

    /// 手に取っている・送る人の列が開いている（ホームの送りと払いを止める）
    var isHolding: Bool { photo != nil || facesOpenFor != nil }

    /// 縦の送りの払いを止める印（UIKit の払いの始まりが読む・`ProfileTabPager`）
    nonisolated(unsafe) static var holding = false

    /// 手に取る。`fingerKnown` が偽（指の位置がまだ届いていない・札の真ん中で代える）なら、指の跡は最初の
    /// `move` から始める（札の真ん中を動き始めの点にしない——動かした距離を見誤る）
    func lift(_ photo: Photo, at point: CGPoint, fingerKnown: Bool = true) {
        self.photo = photo
        self.point = point
        samples = fingerKnown ? [(Date().timeIntervalSinceReferenceDate, Double(point.x), Double(point.y))] : []
        Self.holding = true
    }

    func move(to point: CGPoint) {
        guard photo != nil else { return }
        self.point = point
        samples.append((Date().timeIntervalSinceReferenceDate, Double(point.x), Double(point.y)))
        if samples.count > 40 { samples.removeFirst(samples.count - 40) }
    }

    /// 指を離した1回（重ねた `PhotoLiftOverlay` が行き先を決めて実行する——顔の段と画面の大きさはあちらが持つ）
    struct Drop: Equatable {
        let id = UUID()
        let photo: Photo
        let point: CGPoint
        let samples: [Sample]
        /// 行き先を直に選んだ（読み上げの操作）。nil なら指の位置と弾きで決める
        var chosen: PhotoLift.Target? = nil

        static func == (a: Drop, b: Drop) -> Bool { a.id == b.id }
    }

    struct Sample: Equatable {
        let t: Double
        let x: Double
        let y: Double
    }

    /// 最後に離した1回
    @Published private(set) var drop: Drop?

    /// 指を離した（札が呼ぶ）。写真を指から離し、重ねた画面に知らせる
    func end() {
        guard let photo else { return }
        drop = Drop(photo: photo, point: point, samples: samples.map { Sample(t: $0.t, x: $0.x, y: $0.y) })
        self.photo = nil
        Self.holding = facesOpenFor != nil
    }

    /// 読み上げの操作で行き先を直に選んだ（指を使わない道）
    func choose(_ photo: Photo, target: PhotoLift.Target) {
        drop = Drop(photo: photo, point: .zero, samples: [], chosen: target)
    }

    /// 下へ弾いた: 送る人の列を開いたままにする
    func openFaces(for photo: Photo) {
        facesOpenFor = photo
        Self.holding = true
    }

    func closeFaces() {
        facesOpenFor = nil
        Self.holding = photo != nil
    }

    func cancel() {
        photo = nil
        facesOpenFor = nil
        Self.holding = false
        samples = []
    }

    /// 札の身振りが終わった（`@GestureState` が戻った）。**離した（`end`）が来ないまま終わった**——着信・通知センター・
    /// 裏に回った・一覧の読み直しで身振りが取り消された——なら、手に取ったままにせず元へ戻す。
    /// 2026-11-12 確かめ役: 取り消されると `onEnded` が来ず `photo` が残り、幕がかかって全体が押せなくなっていた
    func gestureReset(photoId: String) {
        guard photo?.id == photoId else { return }
        cancel()
    }

    /// 前面でなくなった（裏に回る・通知センター）。手に取ったもの・開いた送る人の列を戻す
    func sceneChanged(active: Bool) {
        guard !active else { return }
        cancel()
    }

    /// 暗い幕を押した: 手に取ったもの・送る人の列を戻す（幕で閉じ込めない）
    func backdropTapped() {
        cancel()
    }
}

extension PhotoLift {
    /// 離した1回の行き先（運んだ先、無ければ弾いた向き）。`openFaces` は下へ弾いた（送る人の列を開いたまま）
    static func resolve(point: CGPoint, samples: [PhotoLiftCenter.Sample], size: CGSize,
                        faces: Int, allowsStory: Bool) -> (target: Target?, openFaces: Bool) {
        let w = Double(size.width), h = Double(size.height)
        // 動かさずに離したら元へ戻るだけ（手に取った所が行き先の上でも）
        // （指の跡が無い＝指の位置が分からないまま一度も動いていない、も同じ）
        guard let start = samples.first,
              hypot(Double(point.x) - start.x, Double(point.y) - start.y) >= carryDistance else {
            return (nil, false)
        }
        if let target = target(x: Double(point.x), y: Double(point.y), width: w, height: h, faces: faces,
                               allowsStory: allowsStory) {
            return (target, false)
        }
        switch flick(samples: samples.map { (t: $0.t, x: $0.x, y: $0.y) }) {
        case .save: return (.save, false)
        case .story: return allowsStory ? (.story, false) : (nil, false)
        case .faces: return (nil, true)
        case nil: return (nil, false)
        }
    }
}

/// 手に取った写真と3つの行き先（上の帯・右の半円・下の顔の段）。
/// **画面いっぱい（見出しと下の札の上）に重ねる**（`RootView`）——指の位置は画面の座標で届く
struct PhotoLiftOverlay: View {

    @ObservedObject var center: PhotoLiftCenter

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var savedPhotos: SavedPhotosStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var hidden: ModerationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var undo: CountdownUndo

    /// 顔の段（フォロー中・今の DM の顔の列と同じ人）
    @State private var faces: [FollowUser] = []
    @State private var facesLoadedFor: String?
    /// はじめての1回だけの矢印
    @State private var showHint = false
    /// 重ねた画面の大きさ（行き先の当たりを決める）
    @State private var size: CGSize = .zero
    /// 「ストーリーで紹介」: 作る画面に入れる写真（読み終えたら開く）
    @State private var storySeed: StoryComposerSeed?
    @State private var showComposer = false

    init(center: PhotoLiftCenter) {
        self.center = center
        self._undo = ObservedObject(wrappedValue: center.undo)
    }

    /// 写真をストーリーの行き先へ運べるか（自分の写真だけ・`PhotoLift.allowsStory`）
    private func allowsStory(_ photo: Photo?) -> Bool {
        guard let photo else { return false }
        return PhotoLift.allowsStory(ownerId: photo.userId ?? photo.uploadedBy, me: auth.userId)
    }

    /// 顔の段に出す人数
    nonisolated static let faceCount = 4
    nonisolated static let hintKey = "photoLift.hintShown"

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if center.isHolding {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        // 幕を押したら戻す（手に取ったまま残った写真も・幕で閉じ込めない）
                        .onTapGesture { center.backdropTapped() }
                        .accessibilityHidden(true)
                    if center.photo != nil {
                        if allowsStory(center.photo) { topBand(size) }
                        saveHalfCircle(size)
                    }
                    facesRow(size)
                    if let photo = center.photo { lifted(photo, size: size) }
                    if showHint, center.photo != nil { hintArrows(size) }
                }
            }
            .frame(width: size.width, height: size.height)
            .onAppear { self.size = size }
            .onChange(of: size) { _, new in self.size = new }
            .onChange(of: center.drop) { _, drop in if let drop { handle(drop) } }
            // 裏に回る・通知センターを下ろした: 手に取ったものを戻す
            .onChange(of: scenePhase) { _, phase in center.sceneChanged(active: phase == .active) }
            .onChange(of: center.photo?.id) { _, id in
                guard id != nil else { return }
                Task { await loadFaces() }
                if !UserDefaults.standard.bool(forKey: Self.hintKey) {
                    UserDefaults.standard.set(true, forKey: Self.hintKey)
                    showHint = true
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(PhotoLift.hintSeconds * 1_000_000_000))
                        showHint = false
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = undo.message {
                CountdownUndoBar(message: message, seconds: PhotoLift.undoSeconds,
                                 onUndo: { undo.undo() }, identifier: "lift.undo")
                    .id(undo.token)
                    .padding(.bottom, JPSpace.s)
            }
        }
        .allowsHitTesting(center.isHolding || undo.message != nil)
        // ストーリーで紹介: 作る画面（端末の画面いっぱい・ホームの「＋」と同じ出し方）
        .fullScreenCover(isPresented: $showComposer, onDismiss: { storySeed = nil }) {
            NavigationStack { StoryComposerView(seed: storySeed) }
        }
    }

    // MARK: - 行き先

    private func hot(_ target: PhotoLift.Target, size: CGSize) -> Bool {
        PhotoLift.near(x: Double(center.point.x), y: Double(center.point.y), width: Double(size.width),
                       height: Double(size.height), faces: faces.count,
                       allowsStory: allowsStory(center.photo)).map { near in
            if case .face = near, case .face = target { return true }
            return near == target
        } ?? false
    }

    /// 上の帯「みんなへ ストーリーで紹介」
    private func topBand(_ size: CGSize) -> some View {
        let on = hot(.story, size: size)
        return VStack {
            HStack(spacing: JPSpace.xs) {
                Image(systemName: "plus.circle").accessibilityHidden(true)
                Text(L("みんなへ", "Everyone")).font(JPFont.caption).foregroundStyle(WebTheme.muted2)
                Text(L("ストーリーで紹介", "Share to story")).font(JPFont.bodyEmphasis)
            }
            .foregroundStyle(WebTheme.foreground)
            .frame(maxWidth: .infinity, minHeight: PhotoLift.topBand - 20)
            .background(Color.white.opacity(on ? 0.22 : 0.10))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(on ? 0.6 : 0.2)).frame(height: 1) }
            .scaleEffect(on ? 1.03 : 1)
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityHidden(true)
    }

    /// 右の半円「とっておく」（親指の届く右の中ほど）
    private func saveHalfCircle(_ size: CGSize) -> some View {
        let on = hot(.save, size: size)
        let c = PhotoLift.saveCenter(width: Double(size.width), height: Double(size.height))
        let r = PhotoLift.saveRadius
        return ZStack {
            Circle()
                .fill(Color.white.opacity(on ? 0.24 : 0.12))
                .overlay(Circle().strokeBorder(Color.white.opacity(on ? 0.7 : 0.25), lineWidth: 1))
                .frame(width: r * 2, height: r * 2)
            VStack(spacing: JPSpace.xxs) {
                Image(systemName: on ? "bookmark.fill" : "bookmark").font(.title3)
                Text(L("保存", "Save")).font(JPFont.bodyEmphasis)
            }
            .foregroundStyle(WebTheme.foreground)
            .offset(x: -r / 2)
        }
        .scaleEffect(on ? 1.06 : 1)
        .position(x: c.x, y: c.y)
        .accessibilityHidden(true)
    }

    /// 下の顔の段「この人へ送る」
    private func facesRow(_ size: CGSize) -> some View {
        VStack(spacing: JPSpace.xs) {
            Spacer()
            Text(L("この人へ送る", "Send to"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.muted2)
            HStack(spacing: 0) {
                ForEach(Array(faces.prefix(Self.faceCount).enumerated()), id: \.element.id) { offset, user in
                    let on = center.photo != nil && PhotoLift.target(
                        x: Double(center.point.x), y: Double(center.point.y), width: Double(size.width),
                        height: Double(size.height), faces: min(faces.count, Self.faceCount),
                        allowsStory: allowsStory(center.photo)) == .face(offset)
                    Button {
                        if let photo = center.facesOpenFor { send(photo, to: user) }
                    } label: {
                        VStack(spacing: JPSpace.xxs) {
                            RemoteImage(url: UserProfile.profileAssetURL(userId: user.id, suffix: nil, cacheBust: nil),
                                        placeholderSymbol: "person.crop.circle.fill")
                                .frame(width: 52, height: 52)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(on ? 1 : 0.3), lineWidth: on ? 2 : 1))
                                .scaleEffect(on ? 1.15 : 1)
                            Text(user.displayName)
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.foreground)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(center.facesOpenFor == nil)
                    .accessibilityLabel(L("\(user.displayName) さんへ送る", "Send to \(user.displayName)"))
                }
                if faces.isEmpty {
                    Text(L("フォロー中の人がいません", "You're not following anyone yet"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.muted2)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
            }
            .padding(.vertical, JPSpace.xs)
            .frame(minHeight: PhotoLift.bottomBand - 30)
            .background(Color.black.opacity(0.6))
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lift.faces")
    }

    /// 指に付いた写真と、離すと何が起きるかの札
    private func lifted(_ photo: Photo, size: CGSize) -> some View {
        let target = PhotoLift.target(x: Double(center.point.x), y: Double(center.point.y), width: Double(size.width),
                                      height: Double(size.height), faces: min(faces.count, Self.faceCount),
                                      allowsStory: allowsStory(photo))
        let faceName: String? = {
            if case .face(let i)? = target, faces.indices.contains(i) { return faces[i].displayName }
            return nil
        }()
        return VStack(spacing: JPSpace.xs) {
            Text(PhotoLift.releaseLabel(target, faceName: faceName))
                .font(JPFont.bodyEmphasis)
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, JPSpace.s)
                .padding(.vertical, 6)
                .jpGlass(in: Capsule())
            RemoteImage(url: photo.gridImageURL, alignment: photo.gridAlignment)
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.m))
                .overlay(RoundedRectangle(cornerRadius: JPRadius.m).strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
                .rotationEffect(.degrees(-4))
                .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
                .scaleEffect(target == nil ? 1 : 0.8)
        }
        .position(x: center.point.x, y: center.point.y - 60)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// はじめての1回だけ: 3つの向きの矢印（2.2秒）
    private func hintArrows(_ size: CGSize) -> some View {
        ZStack {
            if allowsStory(center.photo) {
                Image(systemName: "arrow.up").position(x: center.point.x, y: center.point.y - 150)
            }
            Image(systemName: "arrow.right").position(x: min(size.width - 30, center.point.x + 110), y: center.point.y)
            Image(systemName: "arrow.down").position(x: center.point.x, y: center.point.y + 110)
        }
        .font(.title2.weight(.semibold))
        .foregroundStyle(WebTheme.foreground)
        .jpPhotoTextShadow()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - 動き

    /// 指を離した1回を実行する（運んだ先・弾いた向き。外でゆっくり離したら何もしない＝元へ戻る）
    private func handle(_ drop: PhotoLiftCenter.Drop) {
        if let chosen = drop.chosen {
            switch chosen {
            case .save: save(drop.photo)
            case .story: if allowsStory(drop.photo) { openStory(drop.photo) }
            case .face: center.openFaces(for: drop.photo)
            }
            return
        }
        let decided = PhotoLift.resolve(point: drop.point, samples: drop.samples, size: size,
                                        faces: min(faces.count, Self.faceCount),
                                        allowsStory: allowsStory(drop.photo))
        if decided.openFaces {
            center.openFaces(for: drop.photo)
            return
        }
        switch decided.target {
        case .save?: save(drop.photo)
        case .story?: openStory(drop.photo)
        case .face(let i)? where faces.indices.contains(i): send(drop.photo, to: faces[i])
        default: break
        }
    }

    /// ストーリーで紹介: 写真の本体を読んで作る画面を開く（ストーリーは作る画面で確かめてから出すので、取り消しの札は出さない）
    private func openStory(_ photo: Photo) {
        guard auth.userId != nil, let url = photo.detailImageURL else { return }
        let toasts = toasts
        Task {
            let data = try? await URLSession.shared.data(from: url).0
            guard let data, !data.isEmpty else {
                toasts.show(L("写真を読み込めませんでした", "Couldn't load the photo"), kind: .failure)
                return
            }
            storySeed = StoryComposerSeed(photo: data, text: "")
            showComposer = true
        }
    }

    private func loadFaces() async {
        guard let me = auth.userId, facesLoadedFor != me else { return }
        let fetched = try? await environment.social.following(userId: me)
        guard let users = fetched?.users, auth.userId == me else { return }
        faces = DMStart.candidates(users, me: me, blocked: hidden.blockedUserIds)
        facesLoadedFor = me
    }

    /// とっておく（しおり）。3秒たってから送る（取り消せる間は送らない）。もうとってある写真はそのまま
    private func save(_ photo: Photo) {
        guard auth.userId != nil else { return }
        let id = photo.id
        guard !savedPhotos.contains(id) else {
            toasts.show(L("もうとってあります", "Already saved"), kind: .info)
            return
        }
        let saves = environment.saves
        let store = savedPhotos
        let toasts = toasts
        undo.schedule(PhotoLift.doneMessage(.save, faceName: nil), seconds: PhotoLift.undoSeconds) {
            let owner = store.owner
            store.set(id, saved: true)
            Task {
                do {
                    try await saves.save(photoId: id)
                } catch {
                    store.set(id, saved: false, for: owner)
                    toasts.show((error as? LocalizedError)?.errorDescription ?? L("保存できませんでした", "Couldn't save"),
                                kind: .failure)
                }
            }
        }
    }

    /// この人へ送る（写真のページのリンクをメッセージで）。3秒たってから送り出す
    private func send(_ photo: Photo, to user: FollowUser) {
        center.closeFaces()
        guard let conversation = DMStart.conversationId(me: auth.userId, peer: user.id),
              let url = PhotoLink.url(photoId: photo.id, isPublished: photo.published != false) else { return }
        let dm = environment.dm
        let toasts = toasts
        let text = PhotoLift.shareText(title: photo.displayTitle, url: url.absoluteString)
        undo.schedule(PhotoLift.doneMessage(.face(0), faceName: user.displayName), seconds: PhotoLift.undoSeconds) {
            Task {
                do {
                    _ = try await dm.send(conversation, text: text, clientId: UUID().uuidString)
                    toasts.show(L("\(user.displayName) さんへ送りました", "Sent to \(user.displayName)"))
                } catch {
                    toasts.show((error as? LocalizedError)?.errorDescription ?? L("送れませんでした", "Couldn't send"),
                                kind: .failure)
                }
            }
        }
    }
}

/// 手に取っている間は縦の送りを止める（ホームの `ScrollView` に付ける）。指が動くたびに描き直るのはこの修飾だけ
struct PhotoLiftScrollLock: ViewModifier {
    @ObservedObject var center: PhotoLiftCenter

    func body(content: Content) -> some View {
        content.scrollDisabled(center.isHolding)
    }
}
