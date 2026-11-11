import SwiftUI

/// 写真から行き先を選ぶ（2026-09-30 owner の依頼「どこに旅行行きたいかを直感で操作できて
/// 旅行プラン作成する機能」）。
///
/// 🔴 **2026-11-10（札 #521）: 旅行プランを作る流れ（`TripCreateView`）の「写真から選ぶ」のタブになった。**
/// 以前は一覧の別の入口から開く全画面の板で、選んだ場所だけで別の下書き（`TripPickerDraftView`）を作っていた。
/// いまは払った場所が、行きたい場所のタブで選んだ場所と**同じ下書き**に入る（作る流れが拾う・`TripCreateModel`）。
///
/// **写真を見て指で選ぶだけ。** 撮影スポットの写真を1枚ずつ大きく出し、
/// 右へ払う＝行きたい・左へ払う＝見送る。下のボタンでも、読み上げの操作
/// （`accessibilityAction`）でも同じことができる。「行きたい」にした場所は
/// その場で「行きたい」にも入る（`WishlistSync`・Web の一覧にも並ぶ）。
/// 札の山は「行きたい」に入っていない撮影スポットだけ（今のまま）。
///
/// 見た目（デザインシステム「黒塗りの真鍮」）:
///  - 写真が主役。**写真の上には白しか置かない**（払っている間の札も白）
///  - 写真を持つ画面なので、主ボタン（行きたい）は白の塗り。1画面に白の塗りは1つ
///  - 真鍮は黒地の上の合図だけ（眉ラベル）
///  - 数は選んだ数だけ（数えた値）。順位・人数は出さない
struct TripPickerView: View {

    /// 札の山と決めごと（作る流れが持つ——タブを替えても、めくった札と選んだ場所を残す）
    @ObservedObject var model: TripPickerModel
    /// 山から除く鍵を足す（撮影スポットを払う画面: 前に払った札・`SpotSwipeProgress.seen`）。
    /// 足した鍵で山が空になったら、「行きたい」だけを除いて作り直す（`TripPickerModel.load` の `fallbackExcluding`）
    var alsoExclude: Set<String> = []
    /// 山の中に挟む札（撮影スポットを払う画面だけ・`SpotSwipe.showsPause`）。nil なら挟まない
    var pause: TripPickerPause?

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 払っている指の横の動き
    @State private var dragX: Double = 0
    /// 札が飛んでいく間（押しを重ねない）
    @State private var flying = false
    /// 開いた時点の種（`TripPicker.deck`）。開き直すと新しい並び
    @State private var seed = UInt64.random(in: .min ... .max)

    /// 払ったと見なす距離（pt）
    private static let swipeThreshold: Double = 110

    var body: some View {
        content
            .task { await loadDeck() }
            // めくる先の札と選んだ場所の詳細（写真・季節の文）。分けた置き場の索引だけの行のときだけ（2026-10-07）
            .task(id: SpotDetailNeeds.key(model.detailNeeds)) {
                await model.applyDetails { await environment.spots.withDetails($0, for: $1) }
            }
    }

    private func loadDeck() async {
        let wished = wishlist.spotIds
        await model.load(fetch: { try await environment.spots.fetchIndex() },
                         excluding: wished.union(alsoExclude), seed: seed,
                         fallbackExcluding: alsoExclude.isEmpty ? nil : wished)
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            failed
        case .loaded:
            VStack(spacing: 0) {
                if model.current != nil, let pause {
                    pauseArea(pause)
                } else if let spot = model.current {
                    // **スクロールの中に置かない。** 縦のスクロールが札を払う指を奪う
                    // （札の上から始めた縦の動きで、払えない・流れない）。札は残りの高さに収める
                    VStack(alignment: .leading, spacing: 12) {
                        intro
                        card(spot)
                            // 大きい文字の小さい端末でも写真を潰さない
                            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
                        caption(spot)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    controls
                } else {
                    finished
                }
            }
        }
    }

    // MARK: - 頭

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 眉ラベル。黒地なので真鍮
            Text("Where to next")
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            Text(L("右へ払うと行きたい、左へ払うと見送る",
                   "Swipe right if you want to go, left to pass."))
                .font(.caption)
                .foregroundStyle(WebTheme.faint)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 札

    /// 写真の札。**写真の上には白しか置かない**（払っている間の「行きたい」「見送る」も白）
    private func card(_ spot: OfficialSpot) -> some View {
        ZStack {
            // 次の札を下に重ねる（めくった先があると分かる・先に読み込ませる）
            if let next = model.upcoming, let photo = next.photo {
                photoFrame(photo.url)
                    .scaleEffect(0.95)
                    .opacity(0.5)
                    .accessibilityHidden(true)
            }
            // 詳細がまだの索引だけの行も、読み込み中の札として払える（空白の札で止めない）
            cardFrame(TripPicker.cardFace(spot, detailTried: model.detailTried.contains(spot.spotId)))
                .overlay(alignment: .topLeading) { stamp(L("行きたい", "Want to go"), icon: "heart.fill").opacity(stampOpacity(1)) }
                .overlay(alignment: .topTrailing) { stamp(L("見送る", "Pass"), icon: "xmark").opacity(stampOpacity(-1)) }
                // 回してから動かす（逆だと、動く前の位置を中心に回って札が下へ沈む）
                .rotationEffect(.degrees(dragX / 24))
                .offset(x: dragX)
                .gesture(swipe)
                // 読み上げでは1つの札として読み、操作の一覧から選ばせる
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel(cardLabel(spot))
                .accessibilityHint(L("操作の一覧から「行きたい」か「見送る」を選べます",
                                     "Use actions to choose Want to go or Pass."))
                .accessibilityAction(named: L("行きたい", "Want to go")) { choose(.want) }
                .accessibilityAction(named: L("見送る", "Pass")) { choose(.skip) }
                .accessibilityIdentifier("tripPicker.card")
                // 札が替わったら、払った位置を引き継がない
                .id(spot.spotId)
        }
    }

    /// 札の面。写真が届く前は、写真の読み込み中（`RemoteImage`）と同じ見た目（面の色＋輪）。
    /// 頼み終えても写真が無ければ面の色だけ（輪を回し続けない）
    @ViewBuilder
    private func cardFrame(_ face: TripPicker.CardFace) -> some View {
        switch face {
        case .photo(let url):
            photoFrame(url)
        case .loading:
            plainFrame.overlay(ProgressView())
        case .noPhoto:
            plainFrame
        }
    }

    /// 写真の無い札の面（面の色・写真の札と同じ形）
    private var plainFrame: some View {
        Color.clear
            .aspectRatio(4 / 5, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(WebTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private func photoFrame(_ url: URL) -> some View {
        Color.clear
            .aspectRatio(4 / 5, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(RemoteImage(url: url))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 払っている向きの札（写真の上なので白・黒の敷き）
    private func stamp(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WebTheme.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5))
            .padding(14)
            .accessibilityHidden(true)
    }

    /// 払っている向きに合う札だけを濃くする（`direction` は右＝1・左＝-1）
    private func stampOpacity(_ direction: Double) -> Double {
        max(0, min(1, dragX * direction / Self.swipeThreshold))
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !flying else { return }
                dragX = value.translation.width
            }
            .onEnded { value in
                guard !flying else { return }
                // 勢いも見る（短く速く払っても通す）
                let x = value.translation.width
                let predicted = value.predictedEndTranslation.width
                if x > Self.swipeThreshold || predicted > Self.swipeThreshold * 2 {
                    choose(.want)
                } else if x < -Self.swipeThreshold || predicted < -Self.swipeThreshold * 2 {
                    choose(.skip)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragX = 0 }
                }
            }
    }

    private func cardLabel(_ spot: OfficialSpot) -> String {
        var parts = [spot.name]
        if let region = TripPicker.region(of: spot).label ?? spot.regionLabel { parts.append(region) }
        return parts.joined(separator: L("、", ", "))
    }

    // MARK: - 札の下（黒地）

    private func caption(_ spot: OfficialSpot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(spot.name)
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.foreground)
                .lineLimit(2)
            if let region = regionLine(spot) {
                Text(region)
                    .font(.caption)
                    .foregroundStyle(WebTheme.muted2)
            }
            // いまの季節の案内があるときだけ（無ければ作らない）
            if let hint = TripPicker.seasonHint(spot, now: Date()) {
                Text("\(hint.label) · \(hint.text)")
                    .font(.footnote)
                    .foregroundStyle(WebTheme.muted2)
                    .lineLimit(1)
            }
            // **出典は写真と必ず一緒に**（CC BY・CC BY-SA の条件）。押すと出典・ライセンスへ
            if let photo = spot.photo {
                SpotImageCredit(photo: photo)
                    .font(.caption)
                    .foregroundStyle(WebTheme.muted2)
                    .lineLimit(2)
                    .accessibilityIdentifier("tripPicker.photoCredit")
            }
        }
        .padding(.horizontal, 4)
        // 札より先に縮めない（名前と出典は必ず出す）
        .layoutPriority(1)
    }

    /// 「フランス · パリ」「京都府 · 京都市」。どれも無ければ nil
    private func regionLine(_ spot: OfficialSpot) -> String? {
        let parts = [spot.region?.country, spot.region?.prefecture, spot.region?.city]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - 押す（払うのと同じ）

    private var controls: some View {
        HStack(spacing: 12) {
            // 見送る（枠だけ）
            Button { choose(.skip) } label: {
                Label(L("見送る", "Pass"), systemImage: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(Capsule().strokeBorder(WebTheme.outline, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tripPicker.pass")

            // ひとつ戻す（押した順に戻る）
            Button { undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: 52, height: 52)
                    .overlay(Circle().strokeBorder(WebTheme.outline, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.decisions.isEmpty || flying)
            .opacity(model.decisions.isEmpty ? 0.4 : 1)
            .accessibilityLabel(L("ひとつ戻す", "Undo"))

            // 行きたい（写真のある画面の主ボタン＝白の塗り＋墨）
            Button { choose(.want) } label: {
                Label(L("行きたい", "Want to go"), systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(WebTheme.accentBackground, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.isFull)
            .opacity(model.isFull ? 0.5 : 1)
            .accessibilityIdentifier("tripPicker.want")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// 払う・押す・読み上げの操作の3つが、ここに来る
    private func choose(_ choice: TripPickerModel.Choice) {
        guard !flying, model.current != nil else { return }
        if choice == .want && model.isFull {
            toasts.show(L("選べるのは \(TripPicker.pickMax) か所までです",
                          "You can pick up to \(TripPicker.pickMax) places."), kind: .failure)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragX = 0 }
            return
        }
        guard reduceMotion == false else {
            commit(choice)
            return
        }
        flying = true
        withAnimation(.easeOut(duration: 0.2)) { dragX = choice == .want ? 600 : -600 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            commit(choice)
            flying = false
        }
    }

    private func commit(_ choice: TripPickerModel.Choice) {
        dragX = 0
        guard let current = model.current else { return }
        let key = SavedSpotKey.official(current.slug)
        let wasWanted = model.wasWantedBefore(current.spotId, inWishlist: wishlist.contains(key))
        guard model.decide(choice, alreadyWanted: wasWanted) != nil, choice == .want, !wasWanted else { return }
        model.markAdded(current.spotId)
        let store = wishlist
        let service = environment.savedSpots
        model.enqueueWish {
            let outcome = await WishlistSync.set(key, wanted: true, store: store, service: service)
            // 成功は札が進むので言わない。**届かなかったときだけ**言う（選んだ場所は下書きに残る）
            if case .failed = outcome, let notice = WishlistSync.notice(for: outcome) {
                toasts.show(notice.text, kind: notice.kind)
            }
        }
    }

    private func undo() {
        // 前から「行きたい」に入っていた場所は外さない（`Decision.wasWanted`）
        guard !flying, let last = model.undo(), last.choice == .want, !last.wasWanted else { return }
        let key = SavedSpotKey.official(last.spot.slug)
        let store = wishlist
        let service = environment.savedSpots
        let generation = model.addedGeneration(last.spot.spotId)
        model.enqueueWish {
            let outcome = await WishlistSync.set(key, wanted: false, store: store, service: service)
            switch outcome {
            case .synced(false), .local(false): model.unmarkAdded(last.spot.spotId, generation: generation)
            default: break
            }
            if let notice = WishlistSync.removalNotice(for: outcome) {
                toasts.show(notice.text, kind: notice.kind)
            }
        }
    }

    // MARK: - 挟む札（撮影スポットを払う画面・2026-11-11）

    /// 山の中に1枚だけ挟む札。**窓で止めない**——左右どちらへ払っても、「続けて払う」でも次の写真へ。
    /// 写真の無い札なので、主ボタンは真鍮の塗りに墨（写真の無い画面の主ボタン）、眉ラベルは黒地の真鍮
    private func pauseArea(_ pause: TripPickerPause) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                intro
                pauseCard(pause)
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            VStack(spacing: 8) {
                Button(action: pause.action) {
                    Text(pause.actionTitle)
                        .jpPillButton(.main(onPhoto: false))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tripPicker.pause.action")
                Button { continueFromPause(pause) } label: {
                    Text(L("続けて払う", "Keep swiping"))
                        .jpPillButton(.outline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tripPicker.pause.continue")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func pauseCard(_ pause: TripPickerPause) -> some View {
        VStack(alignment: .leading, spacing: JPSpace.s) {
            Spacer(minLength: 0)
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(WebTheme.accent)
                .accessibilityHidden(true)
            Text(pause.title)
                .font(JPFont.cardTitle)
                .foregroundStyle(WebTheme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(pause.line)
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(JPSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .jpCardFace()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .rotationEffect(.degrees(dragX / 24))
        .offset(x: dragX)
        .gesture(pauseSwipe(pause))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: L("続けて払う", "Keep swiping")) { continueFromPause(pause) }
        .accessibilityIdentifier("tripPicker.pause")
    }

    /// 挟む札はどちらへ払っても続ける（「行きたい」「見送る」は写真の札だけ）
    private func pauseSwipe(_ pause: TripPickerPause) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !flying else { return }
                dragX = value.translation.width
            }
            .onEnded { value in
                guard !flying else { return }
                let x = value.translation.width
                let predicted = value.predictedEndTranslation.width
                if abs(x) > Self.swipeThreshold || abs(predicted) > Self.swipeThreshold * 2 {
                    continueFromPause(pause, toward: x < 0 ? -1 : 1)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragX = 0 }
                }
            }
    }

    private func continueFromPause(_ pause: TripPickerPause, toward direction: Double = -1) {
        guard !flying else { return }
        guard reduceMotion == false else {
            dragX = 0
            pause.onContinue()
            return
        }
        flying = true
        withAnimation(.easeOut(duration: 0.2)) { dragX = 600 * direction }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            dragX = 0
            pause.onContinue()
            flying = false
        }
    }

    // MARK: - 札が無いとき

    /// めくり終えた・はじめから見せる札が無い
    private var finished: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Text(model.deck.isEmpty
                 ? L("選べる撮影スポットがありません", "No places left to pick")
                 : L("ここまでで全部です", "That's all for now"))
                .font(JPFont.rowTitle)
                .foregroundStyle(WebTheme.foreground)
            Text(model.deck.isEmpty
                 ? L("「行きたい」に入れた場所は、ここには出しません。",
                     "Places already on your wishlist aren't shown.")
                 : L("選んだ場所は、下の「次へ」で旅行プランの下書きになります。", "Tap Next below to turn the places you picked into a trip."))
                .font(.footnote)
                .foregroundStyle(WebTheme.muted2)
                .multilineTextAlignment(.center)
            if !model.decisions.isEmpty {
                Button { undo() } label: {
                    Label(L("ひとつ戻す", "Undo"), systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                        .foregroundStyle(WebTheme.foreground)
                        .padding(.horizontal, 20)
                        .frame(minHeight: WebTheme.minTapTarget)
                        .overlay(Capsule().strokeBorder(WebTheme.outline, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failed: some View {
        VStack(spacing: 12) {
            Text(L("撮影スポットを読み込めませんでした。", "Couldn't load photo spots."))
                .font(.callout)
                .foregroundStyle(WebTheme.muted2)
            // 大きさと当たりの形は **label の中に**（外に付けると押せるのが文字の上だけになる）
            Button {
                Task { await loadDeck() }
            } label: {
                Text(L("再試行", "Retry"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .webTappable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 払う山の中に挟む札（`TripPickerView.pause`・撮影スポットを払う画面だけ）
struct TripPickerPause {
    let title: String
    let line: String
    /// 主な操作の名前（「ログインして見る」「旅行プランにする」）
    let actionTitle: String
    let action: () -> Void
    /// 払った・「続けて払う」を押した（呼び手が次に挟むまでの数を数え直す）
    let onContinue: () -> Void
}
