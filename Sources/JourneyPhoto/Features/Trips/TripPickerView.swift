import SwiftUI

/// 写真から行き先を選ぶ（2026-09-30 owner の依頼「どこに旅行行きたいかを直感で操作できて
/// 旅行プラン作成する機能」）。入口は旅行プランの一覧（`TripPlansView`）。
///
/// **写真を見て指で選ぶだけ。** 撮影スポットの写真を1枚ずつ大きく出し、
/// 右へ払う＝行きたい・左へ払う＝見送る。下のボタンでも、読み上げの操作
/// （`accessibilityAction`）でも同じことができる。「行きたい」にした場所は
/// その場で「行きたい」にも入る（`WishlistSync`・Web の一覧にも並ぶ）。
/// 選んだら「旅行プランにする」→ 地域で束ねて近い順に日へ割った下書き
/// （`TripPickerDraftView`）→ 保存。
///
/// 見た目（デザインシステム「黒塗りの真鍮」）:
///  - 写真が主役。**写真の上には白しか置かない**（払っている間の札も白）
///  - 写真を持つ画面なので、主ボタン（行きたい）は白の塗り。1画面に白の塗りは1つ
///  - 真鍮は黒地の上の合図だけ（眉ラベル・「旅行プランにする」の文字の合図）
///  - 数は選んだ数だけ（数えた値）。順位・人数は出さない
///
/// 全画面の板なので、閉じるのは右上の「閉じる」（板の決まり）。
struct TripPickerView: View {

    /// 旅行プランの一覧と書き込み（一覧の画面と共有する——作ったプランがすぐ一覧に並ぶ）
    @ObservedObject var plans: TripPlansModel
    /// 保存できた。作ったプランの ID を渡す（一覧の画面が閉じてそのプランを開く）
    let onSaved: (String) -> Void

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var wishlist: WishlistStore
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var model = TripPickerModel()
    /// 払っている指の横の動き
    @State private var dragX: Double = 0
    /// 札が飛んでいく間（押しを重ねない）
    @State private var flying = false
    @State private var showDraft = false
    /// 開いた時点の種（`TripPicker.deck`）。開き直すと新しい並び
    @State private var seed = UInt64.random(in: .min ... .max)

    /// 払ったと見なす距離（pt）
    private static let swipeThreshold: Double = 110

    var body: some View {
        NavigationStack {
            content
                .webScreen()
                .navigationTitle(L("写真から選ぶ", "Pick by photo"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
                }
                .navigationDestination(isPresented: $showDraft) {
                    TripPickerDraftView(picker: model, plans: plans, onSaved: onSaved)
                }
        }
        // 全画面の板の上では、アプリの下の知らせ（`RootView`）が隠れるので、ここにも置く
        .overlay(alignment: .bottom) {
            // 足元の「旅行プランにする」・下書きの「保存」（56pt 前後）に重ねない
            ToastOverlay().padding(.bottom, 84)
        }
        .task {
            await model.load(fetch: { try await environment.spots.fetchIndex() },
                             excluding: wishlist.spotIds, seed: seed)
        }
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
                if let spot = model.current {
                    // **スクロールの中に置かない。** 縦のスクロールが札を払う指を奪う
                    // （札の上から始めた縦の動きで、払えない・流れない）。札は残りの高さに収める
                    VStack(alignment: .leading, spacing: 12) {
                        intro
                        card(spot)
                            // 大きい文字の小さい端末でも写真を潰さない
                            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                        caption(spot)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    controls
                } else {
                    finished
                }
                footer
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
            if let photo = spot.photo {
                photoFrame(photo.url)
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
                    .font(.system(size: 12))
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
                    .font(.caption2)
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
        let key = model.current.map { SavedSpotKey.official($0.slug) } ?? ""
        let wasWanted = !key.isEmpty && wishlist.contains(key)
        guard let spot = model.decide(choice, alreadyWanted: wasWanted), choice == .want,
              !wasWanted, key == SavedSpotKey.official(spot.slug) else { return }
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
        model.enqueueWish {
            let outcome = await WishlistSync.set(key, wanted: false, store: store, service: service)
            if let notice = WishlistSync.removalNotice(for: outcome) {
                toasts.show(notice.text, kind: notice.kind)
            }
        }
    }

    // MARK: - 足元（選んだ数と、下書きへ）

    private var footer: some View {
        let count = model.picked.count
        return Button { showDraft = true } label: {
            HStack(spacing: 8) {
                Text(L("行きたい", "Picked"))
                    .font(.footnote)
                    .foregroundStyle(WebTheme.muted2)
                Text(TripPlanText.placeCount(count))
                    .font(JPFont.mono(13, medium: true))
                    .foregroundStyle(WebTheme.foreground)
                Spacer(minLength: 8)
                // ヘッダーの文字の合図と同じ真鍮（黒地）
                Text(L("旅行プランにする", "Make a trip"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WebTheme.accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.5 : 1)
        .overlay(alignment: .top) {
            Rectangle().fill(WebTheme.border).frame(height: 1)
        }
        .accessibilityLabel(L("選んだ \(count) か所で旅行プランにする",
                              "Make a trip with \(count) picked places"))
        .accessibilityIdentifier("tripPicker.makeTrip")
    }

    // MARK: - 札が無いとき

    /// めくり終えた・はじめから見せる札が無い
    private var finished: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Text(model.deck.isEmpty
                 ? L("新しく見せられる写真がありません", "No new photos to show")
                 : L("ここまでで全部です", "That's all for now"))
                .font(JPFont.rowTitle)
                .foregroundStyle(WebTheme.foreground)
            Text(model.deck.isEmpty
                 ? L("写真のある撮影スポットは、もう「行きたい」に入っています。",
                     "Every photo spot with a photo is already on your wishlist.")
                 : L("選んだ場所で旅行プランを作れます。", "Make a trip with the places you picked."))
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
            Button(L("再試行", "Retry")) {
                Task {
                    await model.load(fetch: { try await environment.spots.fetchIndex() },
                                     excluding: wishlist.spotIds, seed: seed)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WebTheme.foreground)
            .webTappable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
