import SwiftUI

/// ストーリーを**人から人へ**続けて見る（2026-09-29・owner「インスタ超えたい」）。
///
/// 1人の束は閲覧画面（`StoryViewerView`）がそのまま見せる。束の最後まで見たら
/// 閉じずに**次の人へ立方体のように回る**。横に払えば指に付いて回り、下へ払えば
/// 指に付いて縮み、離すと閉じる。決まりは `StoryReel`。
///
/// 🔴 **回っている途中に見える隣の面は写真1枚だけ**（`StoryReelFace`）。
/// 隣の人の閲覧画面を並べて作ると、そちらの時計・「見た」の知らせ・動画・曲が
/// 裏で動き出す（見ていない人に「見た」が届く）。閲覧画面は常に1つだけ
struct StoryReelView: View {

    /// 人ごとの束（輪の並びの順）
    let groups: [StoryReel.Group]
    let viewerId: String?
    let onSeen: ((String) -> Void)?
    let onDeleted: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var group: Int
    /// 横の指の移動（回っている量）。左が負
    @State private var dragX: Double = 0
    /// 下への指の移動（縮む量）
    @State private var dragY: Double = 0
    /// 払い始めに決めた向き。**離すまで変えない**
    @State private var axis: StoryReel.Axis?
    /// 回りきる動きの最中（二度押しで2人進まない・閲覧画面を止める）
    @State private var turning = false
    @State private var width: Double = 390

    /// 回りきるのにかける時間
    private static let turnDuration: Double = 0.32

    init(groups: [StoryReel.Group], startGroup: Int, viewerId: String?,
         onSeen: ((String) -> Void)? = nil, onDeleted: ((String) -> Void)? = nil) {
        self.groups = groups
        self.viewerId = viewerId
        self.onSeen = onSeen
        self.onDeleted = onDeleted
        _group = State(initialValue: groups.indices.contains(startGroup) ? startGroup : 0)
    }

    private var hasNext: Bool { group + 1 < groups.count }
    private var hasPrevious: Bool { group > 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                // 隣の面（回っている間だけ）
                if dragX < 0, hasNext {
                    face(StoryReelFace(story: representative(of: group + 1)), minX: width + dragX)
                } else if dragX > 0, hasPrevious {
                    face(StoryReelFace(story: representative(of: group - 1)), minX: -width + dragX)
                }
                if groups.indices.contains(group) {
                    face(viewer(for: group), minX: dragX)
                        // **人が替わったら閲覧画面を作り直す**（前の人の時計・返信欄を持ち越さない）
                        .id(group)
                }
            }
            .scaleEffect(StoryReel.dragScale(dy: dragY))
            .offset(y: max(0, dragY))
            .onAppear { width = max(1, geo.size.width) }
            .onChange(of: geo.size.width) { _, w in width = max(1, w) }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: StoryReel.axisThreshold)
                .onChanged { value in
                    guard !turning else { return }
                    let dx = value.translation.width, dy = value.translation.height
                    if axis == nil { axis = StoryReel.axis(dx: dx, dy: dy) }
                    switch axis {
                    case .horizontal:
                        dragX = StoryReel.resisted(dx: dx, hasNext: hasNext, hasPrevious: hasPrevious)
                    case .vertical:
                        dragY = max(0, dy)
                    case nil:
                        break
                    }
                }
                .onEnded { value in
                    defer { axis = nil }
                    guard !turning else { return }
                    switch axis {
                    case .horizontal:
                        turn(StoryReel.release(dx: value.translation.width,
                                               predictedDX: value.predictedEndTranslation.width,
                                               width: width, hasNext: hasNext, hasPrevious: hasPrevious))
                    case .vertical:
                        if StoryReel.closes(dy: value.translation.height,
                                            predictedDY: value.predictedEndTranslation.height) {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragY = 0 }
                        }
                    case nil:
                        break
                    }
                }
        )
    }

    /// 立方体の1面。`minX` は面の左端の位置
    private func face<V: View>(_ content: V, minX: Double) -> some View {
        let hinge = StoryReel.hinge(minX: minX)
        return content
            .rotation3DEffect(.degrees(StoryReel.cubeAngle(minX: minX, width: width)),
                              axis: (x: 0, y: 1, z: 0),
                              anchor: hinge == .leading ? .leading : .trailing,
                              perspective: 0.5)
            .offset(x: minX)
    }

    private func viewer(for index: Int) -> some View {
        let g = groups[index]
        return StoryViewerView(
            stories: g.stories, startIndex: g.start, viewerId: viewerId,
            // **指で回している間・回りきる間は止める**（長押しの判定は指が動くと外れ、
            // 時計が進み続けていた）
            holds: axis != nil || turning,
            onGroupEnd: { turn(.forward) },
            onGroupBack: index > 0 ? { turn(.back) } : nil,
            swipesHandledOutside: true,
            onSeen: onSeen,
            onDeleted: onDeleted)
    }

    /// 隣の面に出す1本（その人の束で最初に開く1本）
    private func representative(of index: Int) -> Story? {
        guard groups.indices.contains(index) else { return nil }
        let g = groups[index]
        return g.stories.indices.contains(g.start) ? g.stories[g.start] : g.stories.first
    }

    /// 回りきる／戻す。**最後の人の先は閉じる**（今までと同じ）
    private func turn(_ release: StoryReel.Release) {
        guard !turning else { return }
        let step: Int
        switch release {
        case .forward:
            guard hasNext else { dismiss(); return }
            step = 1
        case .back:
            guard hasPrevious else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragX = 0 }
                return
            }
            step = -1
        case .stay:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragX = 0 }
            return
        }
        turning = true
        withAnimation(.easeInOut(duration: Self.turnDuration)) {
            dragX = step > 0 ? -width : width
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(Self.turnDuration * 1000)))
            // 回りきった面（写真1枚）を本物の閲覧画面に差し替える。**動きは付けない**
            group += step
            dragX = 0
            turning = false
        }
    }
}

/// 回っている途中に見える隣の人の面。**写真1枚と名前だけ**（動画は記号）
private struct StoryReelFace: View {
    let story: Story?

    var body: some View {
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
        .clipped()
        .ignoresSafeArea()
    }
}
