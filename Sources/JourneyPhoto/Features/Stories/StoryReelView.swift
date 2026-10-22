import SwiftUI

/// ストーリーを**人から人へ**続けて見る（2026-09-29・owner「インスタ超えたい」）。
///
/// 1人の束は閲覧画面（`StoryViewerView`）がそのまま見せる。束の最後まで見たら
/// 閉じずに**次の人へ立方体のように回る**。横に払えば指に付いて回り、下へ払えば
/// 指に付いて縮み、離すと閉じる。決まりは `StoryReel`。
///
/// 🔴 **隣の面は写真1枚だけ**（`StoryReelFace`）。隣の人の閲覧画面を並べて作ると、
/// そちらの時計・「見た」の知らせ・動画・曲が裏で動き出す（見ていない人に「見た」が
/// 届く）。閲覧画面は常に1つだけ。
///
/// 🔴 **隣の面は画面の外に常に置いておく**（±90度に倒れて見えない）。回すときに
/// 初めて足すと、SwiftUI は行き着く先の位置で足すので回らずに現れた（自動で次の人へ
/// 進むとき・左タップで前の人へ戻るとき。3615504 のレビュー）
struct StoryReelView: View {

    /// 人ごとの束（輪の並びの順）。**開いたときの写し**
    let groups: [StoryReel.Group]
    let viewerId: String?
    let onSeen: ((String) -> Void)?
    let onDeleted: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// 「動きを減らす」。入っていたら立方体に回さず、重ねて濃さを入れ替える
    /// （`StoryReel.faceLook`）。ばねの戻りも短い緩やかな動きにする
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var toasts: ToastCenter

    @State private var group: Int
    /// 指で動かしている間の値。**打ち切られても（通知センター・電話・背面）自動で
    /// 元に戻る**——`@State` に持っていたときは戻らず、閲覧画面が止まったままだった
    @GestureState private var finger = Finger()
    /// 指を離した後の動き（回りきる・戻る・縮みから戻る）
    @State private var settleX: Double = 0
    @State private var settleY: Double = 0
    /// 回りきる動きの最中（二度押しで2人進まない・閲覧画面を止める・触らせない）
    @State private var turning = false
    /// 指を離して元へ戻すばねの最中（閉じずに戻る縮み・回らずに戻る横）。**この間も時計を止める**
    /// ——止めないと、縮んだ写真が戻りきる前に次の1本へ進んでいた（2026-10-16 判断）
    @State private var settling = false
    /// 戻すばねの回（新しい払いで始めた戻しを、古い回の終わりで解かない）
    @State private var settleRun = 0
    @State private var width: Double = 390
    /// 並びから落とした1本（通報・削除）。**人を行き来して閲覧画面が作り直されても戻さない**
    @State private var removed: Set<String> = []
    /// 入れた票（1本ごと）。**閲覧画面は人ごとに作り直されるので、ここで覚える**
    /// ——閲覧画面の中だけに持つと、次の人へ行って戻ると入れる前の数に戻っていた
    @State private var voteStates: [String: StoryVoteState] = [:]
    /// 送った反応（1本ごと・`StoryPlayback.SentReactions`）。票と同じく**ここで覚える**
    /// ——閲覧画面の中だけに持つと、次の人へ回って戻ると ♡ の印が消え、2回目を送れた
    @State private var sentReactions = StoryPlayback.SentReactions()
    /// 閲覧画面が「いまは払えない」（返信欄に入力中・メニュー・送信中）と言っている。
    /// **止めるのは横（人を替える）だけ**——下へ払って閉じるのは止めない（圏外で返事を
    /// 待つ間に閉じられなくなる。`StoryViewerView.leftTap` の注記と同じ）
    @State private var swipeLocked = false
    /// 閲覧画面の返信欄に入力中。**この間の払いは下も横も動かさない**（閲覧画面が
    /// キーボードを閉じるだけ）——下へ払うと閉じて書きかけが消えていた
    @State private var typing = false
    /// 払い始めに決めた向き（`StoryReel.SwipeGate`）。**離したときもこれを使う**（離した瞬間の
    /// 移動量で決め直すと、横に回していたのに指が下へ流れて閉じる、縮めていたのに横へ流れて回る、
    /// が起きた）。`onChanged` で `value` から決める（`@GestureState` の反映の順に頼らない）。
    /// **回っている間に始まった払いは離すまで受けない**
    @State private var swipeGate = StoryReel.SwipeGate()
    /// いま閲覧画面に渡している束。**人が替わるときだけ決め直す**——通報・ブロックの
    /// たびに渡す束を変えると、閲覧画面の中の位置と食い違い、通報した1本や見ていない
    /// 1本に「見た」が飛んだ（7a3894b のレビュー）
    @State private var shown: StoryReel.Group?
    /// 撮影スポットの索引（撮影地 → ガイド）。**並び全体で一度だけ読み、閲覧画面へ渡す**
    @State private var spotIndex: [OfficialSpot] = []

    struct Finger: Equatable {
        var axis: StoryReel.Axis?
        var dx: Double = 0
        var dy: Double = 0
    }

    /// 回りきるのにかける時間
    private static let turnDuration: Double = 0.32
    /// 戻すばねが落ち着くまで（`settleAnimation` のばね 0.3 秒・弾まない形 0.2 秒）。この間は止めておく
    static let settleDuration: Double = 0.3

    init(groups: [StoryReel.Group], startGroup: Int, viewerId: String?,
         onSeen: ((String) -> Void)? = nil, onDeleted: ((String) -> Void)? = nil) {
        self.groups = groups
        self.viewerId = viewerId
        self.onSeen = onSeen
        self.onDeleted = onDeleted
        let start = groups.indices.contains(startGroup) ? startGroup : 0
        _group = State(initialValue: start)
        _shown = State(initialValue: groups.indices.contains(start) ? groups[start] : nil)
    }

    // MARK: - 並び

    /// まだ見せるものがある束（落とした1本・ブロックした人を外す）
    private func liveGroup(_ index: Int) -> StoryReel.Group? {
        guard groups.indices.contains(index) else { return nil }
        return StoryReel.live(groups[index], removed: removed, blocked: hidden.blockedUserIds)
    }

    private func neighbor(_ step: Int) -> Int? {
        StoryReel.neighbor(from: group, step: step, count: groups.count) { liveGroup($0) != nil }
    }

    // MARK: - 動き

    private var dragX: Double {
        settleX + (finger.axis == .horizontal
            ? StoryReel.resisted(dx: finger.dx, hasNext: neighbor(1) != nil, hasPrevious: neighbor(-1) != nil)
            : 0)
    }

    private var dragY: Double {
        settleY + (finger.axis == .vertical ? max(0, finger.dy) : 0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                // 隣の面（画面の外に倒して置いておく）
                if let previous = neighbor(-1) {
                    face(StoryReelFace(story: representative(of: previous, back: true)), minX: -width + dragX)
                }
                if let next = neighbor(1) {
                    face(StoryReelFace(story: representative(of: next, back: false)), minX: width + dragX)
                }
                if let current = shown {
                    face(viewer(current), minX: dragX)
                        // **人が替わったら閲覧画面を作り直す**（前の人の時計・返信欄を持ち越さない）
                        .id(group)
                        // 回っている間は触らせない（古い束で次の1本へ進み、見ていない1本を既読にした）
                        .allowsHitTesting(!turning)
                }
            }
            // 全画面の上では、アプリの下の知らせ（`RootView`）が隠れるので、ここにも置く
            // （`TripPickerView` と同じ）。ブロックして次の人へ回ると、閲覧画面は作り直されて
            // 自分の知らせを持ち越せない。足元の返信欄（60pt 前後）に重ねない
            .overlay(alignment: .bottom) {
                ToastOverlay().padding(.bottom, 84)
            }
            .scaleEffect(StoryReel.dragScale(dy: dragY))
            .offset(y: max(0, dragY))
            .onAppear { width = max(1, geo.size.width) }
            .onChange(of: geo.size.width) { _, w in width = max(1, w) }
            // 撮影スポットの索引は並び全体で**一度だけ**（取れなければ撮影地を結ばないだけ）
            .task {
                guard spotIndex.isEmpty else { return }
                let fetched = try? await environment.spots.fetchIndex()
                guard !Task.isCancelled, let fetched else { return }
                spotIndex = fetched
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: StoryReel.axisThreshold)
                .updating($finger) { value, state, _ in
                    // 回っている間・回っている間に始まった払いは指に付けない（`SwipeGate`）
                    guard swipeGate.accepts(start: value.startLocation, turning: turning) else { return }
                    let dx = value.translation.width, dy = value.translation.height
                    if state.axis == nil {
                        state.axis = StoryReel.axis(dx: dx, dy: dy, swipeLocked: swipeLocked, typing: typing)
                    }
                    state.dx = dx
                    state.dy = dy
                }
                .onChanged { value in
                    swipeGate.change(start: value.startLocation,
                                     dx: value.translation.width, dy: value.translation.height,
                                     turning: turning, swipeLocked: swipeLocked, typing: typing)
                }
                .onEnded { value in
                    let axis = swipeGate.end(start: value.startLocation)
                    guard !turning else { return }
                    let dx = value.translation.width, dy = value.translation.height
                    switch axis {
                    case .horizontal:
                        // 指の位置を引き継いでから回す（`finger` はここで 0 に戻る）
                        let hasNext = neighbor(1) != nil, hasPrevious = neighbor(-1) != nil
                        settleX = StoryReel.resisted(dx: dx, hasNext: hasNext, hasPrevious: hasPrevious)
                        turn(StoryReel.release(dx: dx, predictedDX: value.predictedEndTranslation.width,
                                               width: width, hasNext: hasNext, hasPrevious: hasPrevious))
                    case .vertical:
                        // 上へ戻して離した（下へ引いていない）なら戻す動きは要らない。戻すばねの間は時計を
                        // 止めるので、要らない `settle` を走らせると上への払い（返信欄）のたびに止まっていた
                        guard StoryReel.needsSettle(dy: dy) else { break }
                        settleY = max(0, dy)
                        if StoryReel.closes(dy: dy, predictedDY: value.predictedEndTranslation.height) {
                            dismiss()
                        } else {
                            settle { settleY = 0 }
                        }
                    case nil:
                        break
                    }
                }
        )
    }

    /// 指を離した後に戻す動き。**「動きを減らす」ならばねで弾ませない**
    private var settleAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.85)
    }

    /// 指を離した後に元へ戻す。**戻りきるまで閲覧画面の時計を止める**（`holds` の `settling`）
    private func settle(_ change: () -> Void) {
        settleRun += 1
        let run = settleRun
        settling = true
        withAnimation(settleAnimation, change)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(Self.settleDuration * 1000)))
            if run == settleRun { settling = false }
        }
    }

    /// 立方体の1面。`minX` は面の左端の位置。
    /// 「動きを減らす」なら回さず重ねて濃さを入れ替える（`StoryReel.faceLook`）
    private func face<V: View>(_ content: V, minX: Double) -> some View {
        let hinge = StoryReel.hinge(minX: minX)
        let look = StoryReel.faceLook(minX: minX, width: width, reduceMotion: reduceMotion)
        return content
            .rotation3DEffect(.degrees(look.angle),
                              axis: (x: 0, y: 1, z: 0),
                              anchor: hinge == .leading ? .leading : .trailing,
                              perspective: 0.5)
            .offset(x: look.offsetX)
            .opacity(look.opacity)
    }

    private func viewer(_ g: StoryReel.Group) -> some View {
        StoryViewerView(
            stories: g.stories, startIndex: g.start, viewerId: viewerId,
            // **指で動かしている間・回りきる間・縮みから戻る間は止める**（長押しの判定は
            // 指が動くと外れ、時計が進み続けていた）
            holds: finger.axis != nil || turning || settling,
            onGroupEnd: { turn(.forward) },
            onGroupBack: neighbor(-1) != nil ? { turn(.back) } : nil,
            swipesHandledOutside: true,
            onDropped: { removed.insert($0) },
            onSwipeLockChange: { swipeLocked = $0 },
            onTypingChange: { typing = $0 },
            spotIndex: spotIndex,
            voteStates: voteStates,
            onVoted: { voteStates[$0] = $1 },
            sentReactions: sentReactions,
            // 2026-10-22: 閲覧画面は**送る前に**知らせ（先に塗る）、送れなかったら取り消す
            onReacted: { sentReactions.record($1, on: $0) },
            // 失敗の知らせは**並びが出す**（閲覧画面は人を回すと作り直され、知らせを出す先が無い）
            onReactionFailed: { storyId, emoji in
                sentReactions.rollback(emoji, on: storyId)
                toasts.show(StoryPlayback.reactionFailedMessage(emoji), kind: .failure)
            },
            onSeen: onSeen,
            onDeleted: onDeleted)
    }

    /// 隣の面に出す1本（回って入ったときに開く1本・`StoryReel.entering`）
    private func representative(of index: Int, back: Bool) -> Story? {
        guard let g = liveGroup(index).map({ StoryReel.entering($0, back: back) }) else { return nil }
        return g.stories.indices.contains(g.start) ? g.stories[g.start] : g.stories.first
    }

    /// 回りきる／戻す。**次の人がいなければ閉じる**（最後の人の先・今までと同じ）
    private func turn(_ release: StoryReel.Release) {
        guard !turning else { return }
        let target: Int
        switch release {
        case .forward:
            guard let next = neighbor(1) else { dismiss(); return }
            target = next
        case .back:
            guard let previous = neighbor(-1) else {
                settle { settleX = 0 }
                return
            }
            target = previous
        case .stay:
            settle { settleX = 0 }
            return
        }
        turning = true
        withAnimation(.easeInOut(duration: Self.turnDuration)) {
            settleX = target > group ? -width : width
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(Self.turnDuration * 1000)))
            // 回りきった面（写真1枚）を本物の閲覧画面に差し替える。**動きは付けない**
            let back = target < group
            group = target
            shown = liveGroup(target).map { StoryReel.entering($0, back: back) }
            settleX = 0
            turning = false
            // 回っている間にその人の束が空になった（削除の完了・ブロックの同期）。
            // 閲覧画面の無い黒い画面を残さず閉じる（下へ払えば閉じられたが、気づきにくい）
            if shown == nil { dismiss() }
        }
    }
}

/// 回っている途中に見える隣の人の面。**写真1枚と名前だけ**（動画は記号）。
///
/// **形は本物の閲覧画面と同じ**——写真は上端から伸びて下の角だけ丸く（`StoryViewerMetrics.photoRadius`）、
/// その下に足元の黒い帯（`StoryViewerMetrics.footerHeight`）を空ける。四角い写真を画面いっぱいに
/// 敷いていたときは、回りきって閲覧画面に差し替わった瞬間に角と帯が現れて跳ねた（2026-10-16 判断）
private struct StoryReelFace: View {
    let story: Story?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.black
                if let story {
                    // 枠いっぱいに敷く四角いサムネ（動画は記号。1コマ目を出さない）
                    StoryPoster(story: story)
                }
                if let story {
                    Text(story.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.top, 64)
                        .padding(.leading, 16)
                }
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: StoryViewerMetrics.photoRadius,
                                              bottomTrailingRadius: StoryViewerMetrics.photoRadius))
            .ignoresSafeArea(edges: .top)
            // 足元の黒い帯（閲覧画面の返信欄・自分の足元が乗る高さ）
            Color.black.frame(height: StoryViewerMetrics.footerHeight)
        }
        // 色の地は安全域の外（上の時計・下のホームの印の下）まで敷かれる（`ignoresSafeAreaEdges` の既定）
        .background(Color.black)
        // 画面の外に倒して置いてある面。**読み上げない**（前後の人の名前が読まれていた）
        .accessibilityHidden(true)
    }
}
