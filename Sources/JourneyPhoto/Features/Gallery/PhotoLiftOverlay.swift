import SwiftUI
// Linux では URLSession が別モジュールに居る（iOS では何も起きない）
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// ホームの写真の読み上げの操作「保存・送る・ストーリーで紹介」の行き先（2026-11-12・札 #543・決まりは `PhotoLift`）。
///
/// 札（`HomeFeedTile`）の読み上げの操作が行き先を選び、ホーム（`GalleryView`）の上に重ねた `PhotoLiftOverlay` が
/// 実行する（送るは顔の段を開く）。**顔の段が開いている間はホームの縦の送りと横の払いを止める**
/// （`GalleryView` の `scrollDisabled`・`ProfileTabPager` の払いの始まり）。
///
/// 2026-11-25 判断（札 #733）: 指で写真を手に取って運ぶ身振りは 1.1.84 から止めていた（`PhotoLift.homeGestureEnabled`・
/// ホームの払いを奪っていた）。止めたまま使っていなかったので、身振り・上の帯と右の半円・弾く判定・はじめての案内を消した。
/// 戻すときは札 #733 の片づけの PR の前の版（`HomeMosaic.swift`・この頁・`PhotoLift.swift`）から持ってくる
@MainActor
final class PhotoLiftCenter: ObservableObject {

    static let shared = PhotoLiftCenter()

    /// 開いたままの送る人の列（顔を押して送る）
    @Published var facesOpenFor: Photo?
    /// 選んだ後の取り消し（3秒）
    let undo = CountdownUndo()

    /// 送る人の列が開いている（ホームの送りと払いを止める）
    var isHolding: Bool { facesOpenFor != nil }

    /// 縦の送りの払いを止める印（UIKit の払いの始まりが読む・`ProfileTabPager`）
    nonisolated(unsafe) static var holding = false

    /// 選んだ1回（重ねた `PhotoLiftOverlay` が実行する——顔の段はあちらが持つ）
    struct Drop: Equatable {
        let id = UUID()
        let photo: Photo
        let chosen: PhotoLift.Target

        static func == (a: Drop, b: Drop) -> Bool { a.id == b.id }
    }

    /// 最後に選んだ1回
    @Published private(set) var drop: Drop?

    /// 読み上げの操作で行き先を選んだ
    func choose(_ photo: Photo, target: PhotoLift.Target) {
        drop = Drop(photo: photo, chosen: target)
    }

    /// 送る: 送る人の列を開いたままにする
    func openFaces(for photo: Photo) {
        facesOpenFor = photo
        Self.holding = true
    }

    func closeFaces() {
        facesOpenFor = nil
        Self.holding = false
    }

    /// 前面でなくなった（裏に回る・通知センター）。開いた送る人の列を戻す
    func sceneChanged(active: Bool) {
        guard !active else { return }
        closeFaces()
    }

    /// 暗い幕を押した: 送る人の列を戻す（幕で閉じ込めない）
    func backdropTapped() {
        closeFaces()
    }
}

/// 送る人の顔の段と、選んだ後の取り消しの札。**画面いっぱい（見出しと下の札の上）に重ねる**（`RootView`）
struct PhotoLiftOverlay: View {

    @ObservedObject var center: PhotoLiftCenter

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var savedPhotos: SavedPhotosStore
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var hidden: ModerationStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var undo: CountdownUndo

    /// 顔の段（フォロー中・今の DM の顔の列と同じ人）
    @State private var faces: [FollowUser] = []
    @State private var facesLoadedFor: String?
    /// 「ストーリーで紹介」: 作る画面に入れる写真（読み終えたら開く）
    @State private var storySeed: StoryComposerSeed?
    @State private var showComposer = false

    init(center: PhotoLiftCenter) {
        self.center = center
        self._undo = ObservedObject(wrappedValue: center.undo)
    }

    /// 写真をストーリーで紹介できるか（自分の写真だけ・`PhotoLift.allowsStory`）
    private func allowsStory(_ photo: Photo?) -> Bool {
        guard let photo else { return false }
        return PhotoLift.allowsStory(ownerId: PhotoOwnership.ownerId(of: photo), me: auth.userId)
    }

    /// 顔の段に出す人数
    nonisolated static let faceCount = 4

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if center.isHolding {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        // 幕を押したら戻す（幕で閉じ込めない）
                        .onTapGesture { center.backdropTapped() }
                        .accessibilityHidden(true)
                    facesRow
                }
            }
            .frame(width: size.width, height: size.height)
            .onChange(of: center.drop) { _, drop in if let drop { handle(drop) } }
            // 裏に回る・通知センターを下ろした: 開いた送る人の列を戻す
            .onChange(of: scenePhase) { _, phase in center.sceneChanged(active: phase == .active) }
            // 送る人の列を開いたら顔を読む（2026-11-25 札 #733: 前は指で手に取ったときに読んでいた。
            // 身振りを消したので、列を開いたときに読む）
            .onChange(of: center.facesOpenFor?.id) { _, id in
                guard id != nil else { return }
                Task { await loadFaces() }
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

    // MARK: - 顔の段

    /// 下の顔の段「この人へ送る」
    private var facesRow: some View {
        VStack(spacing: JPSpace.xs) {
            Spacer()
            Text(L("この人へ送る", "Send to"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.muted2)
            HStack(spacing: 0) {
                ForEach(faces.prefix(Self.faceCount), id: \.id) { user in
                    Button {
                        if let photo = center.facesOpenFor { send(photo, to: user) }
                    } label: {
                        VStack(spacing: JPSpace.xxs) {
                            FaceImage(url: UserProfile.profileAssetURL(userId: user.id, suffix: nil, cacheBust: nil))
                                .frame(width: 52, height: 52)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
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

    // MARK: - 動き

    /// 選んだ1回を実行する
    private func handle(_ drop: PhotoLiftCenter.Drop) {
        switch drop.chosen {
        case .save: save(drop.photo)
        case .story: if allowsStory(drop.photo) { openStory(drop.photo) }
        case .face: center.openFaces(for: drop.photo)
        }
    }

    /// ストーリーで紹介: 写真の本体を読んで作る画面を開く（ストーリーは作る画面で確かめてから出すので、取り消しの札は出さない）
    private func openStory(_ photo: Photo) {
        // 読み上げの操作は自分の写真にしか付けないが、ここでも確かめる（人の写真を載せない・2026-11-23）
        guard PhotoOwnership.isMine(photo: photo, me: auth.userId), let url = photo.detailImageURL else { return }
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

/// 送る人の列が開いている間は縦の送りを止める（ホームの `ScrollView` に付ける）
struct PhotoLiftScrollLock: ViewModifier {
    @ObservedObject var center: PhotoLiftCenter

    func body(content: Content) -> some View {
        content.scrollDisabled(center.isHolding)
    }
}
