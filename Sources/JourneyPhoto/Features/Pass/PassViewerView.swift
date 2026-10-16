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
    @State private var showsBack = false
    @State private var drag: CGFloat = 0
    @State private var thanking = false
    @State private var errorMessage: String?
    @State private var didStart = false
    /// この画面で外した・ブロックしたカード（並びから落とす）
    @State private var removed: Set<String> = []
    @State private var reportTarget: PassCardContent?
    @State private var blockTarget: PassCardContent?

    /// 払って次へ進む距離
    nonisolated static let swipeDistance: CGFloat = 90

    /// いま見せる並び: 外した・通報した写真・ブロックした人のカードを落とす
    private var shown: [PassCardContent] {
        let hiding = hidden.snapshot
        return cards.filter { content in
            !removed.contains(content.id) && !hiding.reported.contains(content.photo.id)
                && !(content.card.ownerId.map(hiding.blocked.contains) ?? false)
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
            VStack(spacing: 0) {
                header
                if let current {
                    deck(current)
                        .padding(.top, 26)
                    Text(L("押すと裏返る · 左右に払って次のカード", "Tap to flip · Swipe for the next card"))
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
            showsBack = false
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(photoId: target.photo.id, ownerId: target.card.ownerId)
        }
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
            ZStack {
                PassCardFront(photo: content.photo, name: content.name,
                              avatarURL: content.owner?.avatarURL(),
                              from: content.fromPrefecture.map(PassExchange.fromLabel),
                              number: PassExchange.numberLabel(content.card.number))
                    .opacity(showsBack ? 0 : 1)
                PassCardBack(content: content)
                    // 裏は鏡に映らないように先に半回転しておく
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(showsBack ? 1 : 0)
            }
            .rotation3DEffect(.degrees(showsBack ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotationEffect(.degrees(showsBack ? 1 : -1.5))
            .offset(x: drag)
            .rotationEffect(.degrees(Double(drag) / 24))
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: showsBack)
            .contentShape(Rectangle())
            .onTapGesture { showsBack.toggle() }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in drag = value.translation.width }
                    .onEnded { value in settle(value.translation.width) }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(showsBack ? L("押すと表に戻ります", "Tap to see the front")
                                         : L("押すと裏返します", "Tap to flip the card"))
            .accessibilityAction { showsBack.toggle() }
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

    /// 指を離した。払った距離が `swipeDistance` を超えたら次（左へ）・前（右へ）
    private func settle(_ width: CGFloat) {
        let step = PassViewerMotion.step(forDrag: width, distance: Self.swipeDistance)
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            drag = 0
            if step != 0 { move(by: step) }
        }
    }

    private func move(by step: Int) {
        let next = index + step
        guard shown.indices.contains(next) else { return }
        index = next
        showsBack = false
        errorMessage = nil
    }

    // MARK: - 下

    private func actions(_ content: PassCardContent) -> some View {
        let thanked = favorites.contains(content.photo.id)
        return VStack(spacing: JPSpace.xs) {
        HStack(spacing: JPSpace.xs) {
            Button { Task { await thank(content) } } label: {
                HStack(spacing: JPSpace.xs) {
                    // ハートは白（2026-10-16 判断: 板は真鍮だが、「ありがとう」はいいねそのもの。
                    // CLAUDE.md の owner の好み「いいねのハートは白（同じ操作の色を割らない）」を取った）
                    Image(systemName: thanked ? "heart.fill" : "heart")
                        .font(.system(size: 17))
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
            // 「ありがとう」は名前つきのいいね（相手のお知らせにこちらの名前が出る）。押す前に言う
            Text(PassPrivacyText.thanksNotice)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, JPSpace.gutter)
        .padding(.bottom, JPSpace.m)
    }

    private func thank(_ content: PassCardContent) async {
        guard !thanking, !favorites.contains(content.photo.id) else { return }
        thanking = true
        defer { thanking = false }
        errorMessage = nil
        favorites.set(content.photo.id, favorite: true)
        do {
            _ = try await environment.social.like(photoId: content.photo.id)
        } catch {
            // 届かなければ戻す（届いたように見せない）
            favorites.set(content.photo.id, favorite: false)
            errorMessage = L("ありがとうを送れませんでした。電波のあるところでもう一度お試しください。",
                             "Couldn\u{2019}t send your thanks. Please try again with a signal.")
        }
    }
}

/// めくりの決まり（テストで見張る）
enum PassViewerMotion {
    /// 払った距離から、進む数（左へ払うと次 = +1、右へ払うと前 = -1、足りなければ 0）
    static func step(forDrag width: CGFloat, distance: CGFloat) -> Int {
        if width <= -distance { return 1 }
        if width >= distance { return -1 }
        return 0
    }
}
