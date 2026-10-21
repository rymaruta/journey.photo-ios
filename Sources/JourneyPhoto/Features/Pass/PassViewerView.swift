import SwiftUI

/// カードの束を開く（板 PassViewer・表と裏）。
///
/// **ストーリーの部品は使わない**（板「10 すれちがい」の題: 進み線・24時間で消える形を使わない）。
/// カードは手でめくる: **押すと裏返る・左右に払って次のカード**。勝手に進まない。
/// 読み上げでは、カードを「裏返す」ボタンとして読み、次・前は読み上げの操作で選べる。
///
/// - 束（`.bundle`）: 上の眉は「今日のカード」、下に「ありがとう」と「帳に入れる」。閉じたら開いた印を付ける
/// - 帳から（`.book`）: 上の眉は「すれちがい帳」、下は「ありがとう」だけ
///
/// 「ありがとう」は**そのカードの写真へのいいね**（2026-10-16 判断: サーバーに新しい口を足さない）。
/// 相手には、ほかのいいねと同じお知らせが届く
struct PassViewerView: View {

    enum Mode { case bundle, book }

    let cards: [PassCardContent]
    let mode: Mode
    var start = 0
    /// 「帳に入れる」を押した（閉じた後に帳を開く）
    var onFile: () -> Void = {}

    @EnvironmentObject private var pass: PassStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var hidden: ModerationStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    /// きっぷの横の回り（ラジアン・0 が表）。**90° を越えたら裏**（`SpinMotion.showsBack`）。
    /// 2026-10-16 判断（owner「このカードも回転できるようにしたい」）: メダルと同じ手触りで指で回す
    @State private var yaw: Double = 0
    /// 指を置いた時の回りと時刻（回すか払うかを決める・`PassSpinGesture`）。自分のカードの見本と同じ手つき
    @State private var spin = PassSpinDrag()
    /// 「視差効果を減らす」・きっぷの外で払っている間の横のずれ
    @State private var drag: CGFloat = 0

    private var showsBack: Bool { SpinMotion.showsBack(yaw) }
    @State private var thanking = false
    @State private var errorMessage: String?
    @State private var didStart = false
    /// この画面で外した・ブロックしたカード（並びから落とす）
    @State private var removed: Set<String> = []
    @State private var reportTarget: PassCardContent?
    /// ひとことを通報する（写真の通報とは分ける）
    @State private var noteReportTarget: PassCardContent?
    /// 全面で見ている写真
    @State private var fullPhoto: Photo?
    @State private var blockTarget: PassCardContent?

    /// 払って次へ進む距離
    nonisolated static let swipeDistance: CGFloat = 90

    /// 字の伸びの上限（送らない画面なので、ボタンが画面の外へ出ない大きさまで）
    nonisolated static let typeLimit: DynamicTypeSize = .xxxLarge

    /// いま見せる並び: 外した・通報した写真・ブロックした人のカードを落とす
    private var shown: [PassCardContent] {
        let hiding = hidden.snapshot
        let live = Dictionary(uniqueKeysWithValues: pass.encounters.map { ($0.id, $0) })
        return cards.compactMap { content in
            guard !removed.contains(content.id), !hiding.reported.contains(content.photo.id),
                  !(content.card.ownerId.map(hiding.blocked.contains) ?? false) else { return nil }
            // ひとことを伏せた等は、置き場の新しい記録で描く
            return live[content.id].map(content.with(card:)) ?? content
        }
    }

    private var current: PassCardContent? {
        let list = shown
        return list.indices.contains(index) ? list[index] : nil
    }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 21 / 255, green: 18 / 255, blue: 12 / 255), Color.black],
                           center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
                // きっぷの外で払う → 次／前のカード（きっぷの上は回す・2026-10-16 判断）
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            spin.begin(yaw: yaw)
                            drag = value.translation.width
                        }
                        .onEnded { value in
                            endDrag(translation: Double(value.translation.width),
                                    predicted: Double(value.predictedEndTranslation.width), onCard: false)
                        }
                )
            VStack(spacing: 0) {
                header
                if let current {
                    deck(current)
                        .padding(.top, 26)
                    Text(reduceMotion
                         ? L("写真を押すと全面 · 下を押すと裏返る · 左右に払って次のカード",
                             "Tap the photo to view it · Tap below to flip · Swipe for the next card")
                         : L("写真を押すと全面 · 指を置いて回す · 素早く払うと次のカード",
                             "Tap the photo to view it · Hold and turn · Flick for the next card"))
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.text3)
                        .multilineTextAlignment(.center)
                        .padding(.top, 18)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                if let errorMessage {
                    Text(errorMessage)
                        .font(JPFont.caption)
                        .foregroundStyle(WebTheme.danger)
                        .padding(.horizontal, JPSpace.gutter)
                        .padding(.bottom, JPSpace.xs)
                }
                if let current { actions(current) }
            }
        }
        .preferredColorScheme(.dark)
        // 2026-10-21 判断: この画面は送らない（きっぷは決まった大きさ・`PassCardStyle` の字組の注記）。文字を
        // アクセシビリティの大きさにすると、見出し・手がかり・下のボタンが画面の外へ押し出されて押せなくなるので、
        // 字の伸びを xxxLarge で止める（ストーリーの飾りの `StoryViewerView.chromeTypeLimit` と同じ考え）
        .dynamicTypeSize(...Self.typeLimit)
        .onAppear {
            guard !didStart else { return }
            didStart = true
            index = min(max(0, start), max(0, cards.count - 1))
        }
        .onDisappear {
            if mode == .bundle { pass.markOpened(cards.map(\.id)) }
        }
        // 並びが減った（外した・ブロックした・通報した）: 位置を詰め、空になったら閉じる
        .onChange(of: shown.count) { _, count in
            if count == 0 { dismiss(); return }
            if index >= count { index = count - 1 }
            yaw = 0
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(photoId: target.photo.id, ownerId: target.card.ownerId,
                        carriedPassNote: target.card.noteReported == true ? target.card.writtenText : nil)
        }
        .sheet(item: $noteReportTarget) { target in
            ReportSheet(photoId: target.photo.id, ownerId: nil, passNote: target.card.writtenText,
                        onReported: { pass.markNoteReported(target.id) })
        }
        .fullScreenCover(item: $fullPhoto) { photo in PassPhotoFullView(photo: photo) }
        // **この画面の上にもトーストを重ねる**（全面の上には根のトーストが出ず、ブロックの失敗・通報の受付が
        // 見えなかった・`PhotoViewerView` と同じ形）
        .overlay(alignment: .top) { ToastOverlay() }
        .blockConfirmation(presenting: $blockTarget) { target in
            Task {
                if await PassCardModeration.block(target, hidden: hidden, environment: environment, toasts: toasts) {
                    removed.insert(target.id)
                }
            }
        }
    }

    // MARK: - 上

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(mode == .bundle ? L("今日のカード", "Today\u{2019}s cards") : L("すれちがい帳", "Pass book"))
                    .jpEyebrow()
                    .foregroundStyle(WebTheme.accent)
                Text(L("\(index + 1) / \(shown.count) 枚", "\(index + 1) of \(shown.count)"))
                    .font(JPFont.number(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(WebTheme.text)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            // 表でも裏でも同じ所に出る「…」（通報・ブロック・帳から外す）
            if let current {
                PassCardMenu(content: current,
                             report: { reportTarget = current },
                             reportNote: { noteReportTarget = current },
                             toggleNote: { pass.setNoteHidden(current.id, current.card.noteHidden != true) },
                             toggleLabels: { pass.setLabelsHidden(current.id, current.card.labelsHidden != true) },
                             block: { blockTarget = current },
                             remove: {
                                 pass.remove(current.id)
                                 removed.insert(current.id)
                             })
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WebTheme.foreground)
                    .webTappable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Labels.Common.close)
            .accessibilityIdentifier("pass.viewer.close")
        }
        .padding(.leading, JPSpace.gutter)
        .padding(.trailing, JPSpace.xs)
        .padding(.top, JPSpace.xs)
    }

    // MARK: - 束

    private func deck(_ content: PassCardContent) -> some View {
        ZStack {
            // 後ろに重なる2枚（残りがあるときだけ・板の傾き 4°・2°）
            if index + 2 < shown.count { backing(inset: 14, opacity: 0.25, tilt: 4, fill: 0x12) }
            if index + 1 < shown.count { backing(inset: 8, opacity: 0.3, tilt: 2, fill: 0x16) }
            // 全面の写真が上に出ている間は、表の光を止める（`active`・2026-10-17）
            PassSpinTicket(yaw: yaw, front: content.face(), back: content.backFace(), reduceMotion: reduceMotion,
                           active: fullPhoto == nil) {
                fullPhoto = content.photo
            }
            .offset(x: drag)
            .rotationEffect(.degrees(Double(drag) / 24))
            .contentShape(Rectangle())
            .onTapGesture { flip() }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        spin.begin(yaw: yaw)
                        if reduceMotion {
                            drag = value.translation.width
                        } else {
                            // 置いてすぐは回りを弱める（払いなら裏を見せない・`PassSpinGesture.liveYaw`）
                            yaw = spin.liveYaw(current: yaw, dx: Double(value.translation.width),
                                               width: Double(PassCardStyle.deckSize.width))
                        }
                    }
                    .onEnded { value in
                        endDrag(translation: Double(value.translation.width),
                                predicted: Double(value.predictedEndTranslation.width), onCard: true)
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityValue(PassSpinTicket.spokenSide(yaw))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(showsBack ? L("押すと表に戻ります", "Tap to see the front")
                                         : L("押すと裏返します", "Tap to flip the card"))
            .accessibilityAction { flip() }
            .accessibilityAction(named: L("写真を全面で見る", "View photo full screen")) { fullPhoto = content.photo }
            .accessibilityAction(named: L("次のカード", "Next card")) { move(by: 1) }
            .accessibilityAction(named: L("前のカード", "Previous card")) { move(by: -1) }
            .accessibilityIdentifier("pass.viewer.card")
        }
        .frame(width: PassCardStyle.deckSize.width, height: PassCardStyle.deckSize.height)
    }

    private func backing(inset: CGFloat, opacity: Double, tilt: Double, fill: Int) -> some View {
        let gray = Double(fill) / 255
        return RoundedRectangle(cornerRadius: PassCardStyle.deckCorner)
            .fill(Color(red: gray, green: gray, blue: gray))
            .overlay(RoundedRectangle(cornerRadius: PassCardStyle.deckCorner)
                .strokeBorder(WebTheme.accent.opacity(opacity), lineWidth: JPStroke.hairline))
            .frame(width: PassCardStyle.deckSize.width, height: PassCardStyle.deckSize.height)
            .rotationEffect(.degrees(tilt))
            .offset(x: inset * 0.3, y: inset)
            .accessibilityHidden(true)
    }

    /// 押して裏返す（読み上げの「裏返す」も）。半周先の面へ（「視差効果を減らす」では動かさずに替える）
    private func flip() {
        let target = SpinMotion.flipTarget(from: yaw)
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82)) { yaw = target }
    }

    /// 指を離した。回す（近い面に吸い付く）か、次／前のカードか（`PassSpinGesture.classify`）
    private func endDrag(translation: Double, predicted: Double, onCard: Bool) {
        let (duration, base) = spin.end()
        let outcome = PassSpinGesture.classify(translation: translation, predicted: predicted, duration: duration,
                                               onCard: onCard, reduceMotion: reduceMotion,
                                               swipeDistance: Double(Self.swipeDistance))
        // 指の速さのおよそ（勢いの見込みは、離してから約 0.25 秒ぶん）
        let velocity = SpinMotion.releaseVelocity(vx: (predicted - translation) / 0.25,
                                                  width: Double(PassCardStyle.deckSize.width), reduceMotion: reduceMotion)
        // 払いと決まったら、回りを見せずに（動かさずに）指を置いた時の面へ戻してから次へ替える
        if outcome == .next || outcome == .previous, let base { yaw = SpinMotion.nearestFace(base) }
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82)) {
            drag = 0
            switch outcome {
            case .rotate:
                yaw = SpinMotion.snapTarget(yaw: yaw, velocity: velocity)
            case .next:
                move(by: 1)
            case .previous:
                move(by: -1)
            case .none:
                yaw = SpinMotion.nearestFace(yaw)
            }
        }
    }

    private func move(by step: Int) {
        let next = index + step
        guard shown.indices.contains(next) else { return }
        index = next
        yaw = 0
        errorMessage = nil
    }

    // MARK: - 下

    private func actions(_ content: PassCardContent) -> some View {
        let thanked = favorites.contains(content.photo.id)
        return VStack(spacing: JPSpace.xs) {
            // 横に入らない大きさ（文字の大きさの設定）では2つのボタンを縦に積む（2026-10-21・線のボタンの字は1行なので、
            // 横 2 つのままでは「ありがとうを返しました」が切れる）
            ViewThatFits(in: .horizontal) {
                HStack(spacing: JPSpace.xs) { actionButtons(content, thanked: thanked) }
                VStack(spacing: JPSpace.xs) { actionButtons(content, thanked: thanked) }
            }
            // 「ありがとう」は名前つきのいいね（相手のお知らせにこちらの名前が出る）。押す前に言う
            Text(PassPrivacyText.thanksNotice)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, JPSpace.gutter)
        .padding(.bottom, JPSpace.m)
    }

    @ViewBuilder
    private func actionButtons(_ content: PassCardContent, thanked: Bool) -> some View {
        Button { Task { await thank(content) } } label: {
            HStack(spacing: JPSpace.xs) {
                // ハートは白（2026-10-16 判断: 板は真鍮だが、「ありがとう」はいいねそのもの。
                // CLAUDE.md の owner の好み「いいねのハートは白（同じ操作の色を割らない）」を取った）
                Image(systemName: thanked ? "heart.fill" : "heart")
                    .font(.body)
                    .foregroundStyle(WebTheme.foreground)
                    .accessibilityHidden(true)
                Text(thanked ? L("ありがとうを返しました", "Thanks sent") : L("ありがとう", "Thank you"))
            }
            .jpOutlineButton(fullWidth: true)
        }
        .buttonStyle(.plain)
        .disabled(thanked || thanking)
        .accessibilityHint(L("この写真にいいねを送ります", "Sends a like to this photo"))
        .accessibilityIdentifier("pass.viewer.thanks")
        if mode == .bundle {
            Button {
                pass.markOpened(cards.map(\.id))
                onFile()
                dismiss()
            } label: {
                Text(L("帳に入れる", "Add to the book")).jpOutlineButton(fullWidth: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pass.viewer.file")
        }
    }

    private func thank(_ content: PassCardContent) async {
        guard !thanking, !favorites.contains(content.photo.id) else { return }
        thanking = true
        defer { thanking = false }
        errorMessage = nil
        // 押した人。失敗の戻しは、この人の控えにだけ書く
        let owner = favorites.owner
        favorites.set(content.photo.id, favorite: true)
        // 見本の束（`-JPPreviewPass`・Debug のみ）はサーバーに送らない。押した後の形（「ありがとうを返しました」）を
        // 画面写真で見るため、端末の中だけで済ませる（2026-10-21）
        if PreviewSession.passSample { return }
        do {
            _ = try await environment.social.like(photoId: content.photo.id)
        } catch {
            // 届かなければ戻す（届いたように見せない）。
            // 人が替わっていたら書かない——前の人の戻しが、次の人のいいねを消し、
            // 同期のあとにも残る印になる（`FavoritesStore.set(_:favorite:for:)`）
            favorites.set(content.photo.id, favorite: false, for: owner)
            guard Self.keepsThanks(owner: owner, viewer: favorites.owner) else { return }
            errorMessage = L("ありがとうを送れませんでした。電波のあるところでもう一度お試しください。",
                             "Couldn\u{2019}t send your thanks. Please try again with a signal.")
        }
    }

    /// ありがとうの失敗を、押した人の画面に書くか
    nonisolated static func keepsThanks(owner: String?, viewer: String?) -> Bool {
        owner != nil && owner == viewer
    }
}
