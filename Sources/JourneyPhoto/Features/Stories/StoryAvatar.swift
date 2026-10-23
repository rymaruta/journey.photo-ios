import SwiftUI

/// **顔からストーリーを開く**（2026-10-22・owner「インスタみたいに使いやすく」）。
///
/// 以前は輪がホームの列（`StoriesRow`）にしか無く、人のページ・自分のページ・写真の作者の顔から
/// その人のストーリーへ行けなかった。ストーリーがある人の顔にだけ輪（まだ見ていない＝真鍮・
/// 見た＝白 22%・`StoryRing`）を描き、押すとその人の束から開く（`StoryReelView`）。
///
/// - 輪は**顔の大きさのまま**描き、写真を内側へ縮める（顔の周りの並びを動かさない）
/// - ストーリーが無い人は今までどおり（`plain` をそのまま出す）
/// - 一覧は `GET /stories` を読むだけ（`StoryRingDirectory`・新しい口は作らない）
struct StoryAvatar<Face: View, Plain: View>: View {

    let userId: String?
    /// 読み上げの名前（「〇〇 のストーリー 2本（まだ見ていない）」）
    let name: String
    /// 顔の直径（輪の外径）
    let diameter: CGFloat
    let face: Face
    let plain: Plain

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var seen: SeenStoriesStore
    @ObservedObject private var directory = StoryRingDirectory.shared
    /// 閲覧画面の中から開いた画面（`insideStoryViewer`）。中なら輪を出さない（閲覧画面を二重に重ねない）
    @Environment(\.insideStoryViewer) private var insideStoryViewer
    /// 開いた束（開いた瞬間に写して、閉じるまで変えない・`StoriesRow` と同じ）
    @State private var opened: StoryReel.Group?

    /// - Parameters:
    ///   - face: 顔の写真だけ（枠も丸めもしない）。輪の内側に縮めて置く
    ///   - plain: ストーリーが無いときに出す、今までどおりの顔
    init(userId: String?, name: String, diameter: CGFloat,
         @ViewBuilder face: () -> Face, @ViewBuilder plain: () -> Plain) {
        self.userId = userId
        self.name = name
        self.diameter = diameter
        self.face = face()
        self.plain = plain()
    }

    private var isMine: Bool { userId != nil && userId == auth.userId }

    private var ring: StoryPlayback.PersonRing? {
        guard auth.userId != nil, !insideStoryViewer else { return nil }
        let shown = StoryPlayback.visible(directory.stories(for: auth.userId),
                                          blockedUserIds: hidden.blockedUserIds,
                                          reportedPhotoIds: hidden.reportedPhotoIds)
        return StoryPlayback.personRing(userId: userId, in: shown, isSeen: { seen.contains($0) })
    }

    var body: some View {
        Group {
            if let ring {
                // 自分の輪は**見たかどうかに関係なく真鍮**（ホームの「あなた」の輪と同じ）
                let unseen = isMine || ring.unseen
                Button {
                    opened = ring.group
                } label: {
                    StoryRing(count: ring.count, unseen: unseen, diameter: diameter) { face }
                        // 顔が小さくても押せるのは 44pt（写真の作者の顔は 40）
                        .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMine ? L("あなたのストーリー", "Your story")
                                           : StoriesRow.ringLabel(name: name, count: ring.count, unseen: unseen))
                .accessibilityIdentifier("story.avatar.ring")
            } else {
                plain
            }
        }
        // 古ければ読み直す（1分以内に読んだ一覧は使い回す・`StoryPlayback.needsRingRefresh`）
        .task(id: "\(auth.userId ?? "-")|\(userId ?? "-")") {
            guard auth.userId != nil, userId != nil, !insideStoryViewer else { return }
            await directory.refreshIfStale(environment: environment, auth: auth)
        }
        .fullScreenCover(item: $opened, onDismiss: {
            // 閉じたら読み直す（消した・通報した1本の輪を残さない）
            Task { await directory.refresh(environment: environment, auth: auth) }
        }) { group in
            StoryReelView(groups: [group], startGroup: 0, viewerId: auth.userId,
                          onSeen: { seen.markSeen($0) },
                          onDeleted: { directory.remove(id: $0) })
        }
        // **開いた1本を見たことにする**（ホームの輪と同じ。次へ送ったぶんは閲覧画面が知らせる）
        .onChange(of: opened?.id) { _, id in
            if let id { seen.markSeen(id) }
        }
    }
}

extension StoryReel.Group: Identifiable {
    /// 開いた1本の id（束を `fullScreenCover(item:)` で開くため）
    var id: String {
        stories.indices.contains(start) ? stories[start].id : (stories.first?.id ?? "")
    }
}

/// 閲覧画面の中から開いた画面か（2026-10-22）。**中なら顔の輪を出さない**——閲覧画面の中から開いた
/// 人のページ（見出しの名前・見た人の一覧・返信の一覧）で輪を押すと、閲覧画面がもう1枚重なっていた
struct InsideStoryViewerKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var insideStoryViewer: Bool {
        get { self[InsideStoryViewerKey.self] }
        set { self[InsideStoryViewerKey.self] = newValue }
    }
}

/// 顔の輪のための**ストーリーの一覧の控え**（2026-10-22）。
///
/// 人のページ・写真の詳細を開くたびに `GET /stories` を読むと通信が増えるので、1つの控えを
/// 使い回す。ホームの輪の列（`StoriesRow`）が読んだ一覧もここへ渡す（`publish`）。
/// **控えは見ている人ごと**——人が替わったら前の人の一覧を使わない
@MainActor
final class StoryRingDirectory: ObservableObject {

    static let shared = StoryRingDirectory()

    @Published private var list: [Story] = []
    /// 控えの持ち主（この人の鍵で読んだ一覧）
    private(set) var viewerId: String?
    private var fetchedAt: Date?
    /// 読めなかった時刻（その人の分）。**圏外で顔を開くたびに読み直さない**（`StoryPlayback.needsRingRefresh`）
    private var failedAt: Date?
    private var failedFor: String?
    /// 読んでいる途中の回（同じ人の読み込みは1つにまとめる）
    private var loading: (viewer: String?, task: Task<Void, Never>)?
    /// 消した1本（読み直しの答えが削除より古くても戻さない・`StoriesViewModel.remove` と同じ）
    @Published private var deletedIds: Set<String> = []

    init() {}

    /// この人が見ているときの一覧。**控えの持ち主と違う人なら空**
    func stories(for viewer: String?) -> [Story] {
        viewer != nil && viewer == viewerId ? list.filter { !deletedIds.contains($0.id) } : []
    }

    /// 読み終えた一覧を控えに入れる。🔴 **読み始めた人（`loadedFor`）と今の人（`current`）が同じときだけ**
    /// ——読んでいる間にアカウントを切り替えると、前の人の一覧が新しい人の控えに入っていた
    /// （2026-10-22 の確かめ）。入れたら true
    @discardableResult
    func publish(_ stories: [Story], loadedFor: String?, current: String?, now: Date = Date()) -> Bool {
        guard loadedFor != nil, loadedFor == current else { return false }
        list = stories
        viewerId = loadedFor
        fetchedAt = now
        failedAt = nil
        failedFor = nil
        return true
    }

    func remove(id: String) {
        deletedIds.insert(id)
    }

    /// 古いとき（`StoryPlayback.needsRingRefresh`）だけ読む。読んでいる途中なら、その答えを待つ
    func refreshIfStale(viewerId: String?, now: Date = Date(),
                        current: @escaping @MainActor () -> String?,
                        fetch: @escaping () async throws -> [Story]) async {
        guard StoryPlayback.needsRingRefresh(fetchedAt: fetchedAt, sameViewer: viewerId == self.viewerId,
                                             failedAt: failedFor == viewerId ? failedAt : nil,
                                             now: now) else { return }
        await refresh(viewerId: viewerId, current: current, fetch: fetch)
    }

    /// 読む。**同じ人の読み込みが走っていればそれを待つ**（顔が並ぶ画面で同時に何度も読まない）。
    /// 別の人の読み込みが走っていたら待たずに読む（前の人の答えは `publish` が捨てる）
    func refresh(viewerId: String?, current: @escaping @MainActor () -> String?,
                 fetch: @escaping () async throws -> [Story]) async {
        if let loading, loading.viewer == viewerId {
            await loading.task.value
            return
        }
        let task = Task { @MainActor in
            do {
                let fetched = try await fetch()
                self.publish(fetched, loadedFor: viewerId, current: current())
            } catch {
                // 取れなくても顔は今までどおり（輪は添え物）。前の控えは残し、しばらく読み直さない
                self.failedAt = Date()
                self.failedFor = viewerId
            }
        }
        loading = (viewerId, task)
        await task.value
        if loading?.viewer == viewerId { loading = nil }
    }
}

extension StoryRingDirectory {
    /// 画面から読む口（`AppEnvironment` の `GET /stories`・今の人は `AuthStore`）
    func refreshIfStale(environment: AppEnvironment, auth: AuthStore) async {
        let viewer = auth.userId
        await refreshIfStale(viewerId: viewer, current: { [weak auth] in auth?.userId },
                             fetch: { try await environment.stories.list() })
    }

    func refresh(environment: AppEnvironment, auth: AuthStore) async {
        let viewer = auth.userId
        await refresh(viewerId: viewer, current: { [weak auth] in auth?.userId },
                      fetch: { try await environment.stories.list() })
    }
}
