import SwiftUI

/// 旅のトランク（モック Main.dc.html・2026-10-17 owner 承認）。入口はマイページの旅の記録の札。
///
/// **2026-11-23 判断（札 #711・案「トランクを見やすく」版3・owner 承認）**: 同じ形の行が9本並び、毎日使う
/// 「ラベルを貼る」とたまにしか使わない「トランクの型」の見分けがつかなかった。上から:
/// 眉ラベル（MY TRUNK 型の名前）→ トランク（押すと回す・右下に「回して見る」）→ 数え札3つ（「貼ったラベル ›」で一覧）→
/// **状態で替わる大きいボタン1つ**（真鍮の塗りに墨・`TrunkHome.primary`）→ **4つのカード**（カプセル・部品箱・手荷物タグ・
/// ふた。大きいボタンと同じことは出さない）→ 手持ちのラベル・トランクの型・受け取りの札。
/// 最近貼ったラベル3枚の段はなくした（トランクの絵に貼ってあるものと同じだった）。
/// 状態は6つ（ラベルあり・ラベル0で硬貨あり・どちらも0・初めて開いた・読み込み中・圏外。`TrunkHome.screen`）。
/// 受け取りの設定は「手持ちのラベル」の画面へ移す案だが、ステッカーの札 #706 のあとに作るので今は最後の札に残す
struct TrunkView: View {
    /// 名札に刻む名前（寝台列車・飛行艇の型）
    var ownerName: String?

    /// 文字の大きさの設定（アクセシビリティの大きさでは数え札・カードの字を折り返す・2026-10-21）
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = TrunkViewModel()
    @ObservedObject private var tabRouter = TabRouter.shared
    @State private var showSpin = false
    @State private var showPaywall = false
    @State private var showStick = false
    /// 大きいボタンとカードから開く画面
    @State private var route: TrunkHomeTile?
    /// 初めて開いたときの揺れ（トランクを左右に少し回す角度）と「回して見る」の光
    @State private var wiggle = 0.0
    @State private var chipGlow = false

    var body: some View {
        content
            .webScreen()
            .navigationTitle(L("旅のトランク", "Travel trunk"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                model.bind(environment.trunk, userId: auth.userId)
                await model.load(offline: connectivity.isOffline, saved: savedState)
                noteAging()
                await playIntroIfNeeded()
            }
            .refreshable { await model.load(offline: connectivity.isOffline, saved: savedState) }
            // 測る起動（`-JPPreviewTrunkDiag rastercost`・Debug のみ）のときだけ: 回す箱の絵を塗る時間の内訳（2026-11-11・測るだけ）
            .task(id: model.state != nil) {
                guard let state = model.state else { return }
                if PreviewSession.trunkDiag.contains("boldcheck") {
                    TrunkBoldProbe.run(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck, ownerName: ownerName,
                                       parts: state.equipped, wrinkles: TrunkWrinkles(userId: auth.userId).strengths,
                                       tagPicks: state.tagPicks)
                }
                guard PreviewSession.trunkDiag.contains("rastercost") else { return }
                try? await Task.sleep(for: .seconds(1))
                await TrunkRasterProbe.run(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck, ownerName: ownerName,
                                           parts: state.equipped, wrinkles: TrunkWrinkles(userId: auth.userId).strengths,
                                           tagPicks: state.tagPicks)
            }
            // 2026-11-11 判断: 回す画面の絵はトランクの画面では先に作らない。先に作ると開くのは速いが、塗るときの作業用の
            // メモリが戻らず、トランクの画面にいる間が +80MB・閉じた後も +30MB だった（run 1014 / 1019・owner の「重い」と逆向き）。
            // 回す画面を開いたときに描き、2 回目は使い回す（`TrunkTextures.kept`）。画面から戻ったら手放す
            // （回す画面などを上に出している間は持っておく）
            .onDisappear {
                if !showSpin, !showStick, !showPaywall { TrunkTextures.forget() }
            }
            .fullScreenCover(isPresented: $showSpin) {
                if let state = model.state {
                    TrunkSpinViewer(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck,
                                    ownerName: ownerName, parts: state.equipped,
                                    wrinkles: TrunkWrinkles(userId: auth.userId).strengths, tagPicks: state.tagPicks)
                }
            }
            .fullScreenCover(isPresented: $showPaywall, onDismiss: {
                // 買えたかもしれない: Pro かどうか・上限・回数を読み直す
                Task { await model.refreshAfterPaywall(offline: connectivity.isOffline) }
            }) { PaywallView(origin: .trunk) }
            .fullScreenCover(isPresented: $showStick) { TrunkStickView(model: model, ownerName: ownerName) }
            .navigationDestination(item: $route) { tile in destination(tile) }
            // 電波が戻ったら読み直す（圏外で前に読んだトランク・「電波がありません」を出している間だけ。
            // 2026-11-23 確かめ役の指摘: 「もう一度」を押すまで薄いままだった。見張りは他の画面と同じ `Connectivity`）
            .onChange(of: connectivity.isOffline) { _, offline in
                guard TrunkHome.reloadsWhenBack(offline: offline, showingSaved: model.showingSaved,
                                                phaseOffline: model.phase == .offline) else { return }
                Task { await model.load(offline: connectivity.isOffline, saved: savedState) }
            }
            // タグに載せていたラベルをはがして、その枠がおまかせに戻った（一度だけ知らせる・2026-11-08）
            .onChange(of: model.tagPickReset) { _, reset in
                guard reset else { return }
                model.tagPickReset = false
                toasts.show(TrunkTagText.pickResetNotice, kind: .info)
            }
            // 知らせは `RootView` の全体の知らせで出る（押して進む画面なので重ねない・2026-10-17 の読み直し）
    }

    /// 前に読んだその人のトランク（入口の数のために `TrunkEntryStore` がこの起動の間だけメモリに持つ写し・端末には書かない）。
    /// 圏外で読めないときだけ使う（2026-11-23 判断・札 #711: 写しがあるかをコードで確かめた——ディスクの控えは無く、
    /// メモリの写しはマイページ・メニューの入口を一度読んだ起動の間だけある）
    private var savedState: TrunkState? {
        auth.userId.flatMap { TrunkEntryStore.shared.state(for: $0) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            loadingSkeleton
        case .failed(let message):
            ErrorBanner(title: L("トランクを開けませんでした", "Couldn\u{2019}t open your trunk"), message: message,
                        retry: { Task { await model.load(offline: connectivity.isOffline, saved: savedState) } })
                .frame(maxHeight: .infinity)
                // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（2026-10-17・run 464）
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("trunk.failed")
        case .offline:
            // 前に読んだトランクが手元に無い（この起動でまだ一度も読めていない）ときだけ。あれば `loaded` で薄く出す
            ErrorBanner(title: L("電波がありません", "No signal"),
                        message: L("電波のあるところで開くと、トランクを読み込みます。",
                                   "Open this again where you have a signal to load your trunk."),
                        retry: { Task { await model.load(offline: connectivity.isOffline, saved: savedState) } })
                .frame(maxHeight: .infinity)
                // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（2026-10-17・run 464）
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("trunk.offline")
        case .loaded:
            if let state = model.state { loaded(state) }
        }
    }

    /// 読み込み中（案の模型: 形は同じで灰。眉ラベル・薄いトランク・数え札・大きいボタン・4つのカード）
    private var loadingSkeleton: some View {
        ScrollView {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4).fill(WebTheme.surface4)
                    .frame(width: 120, height: 12)
                    .padding(.top, 6)
                TrunkFigure(model: .leather, posts: 0, width: 300)
                    .opacity(0.22)
                    .padding(.top, 30)
                RoundedRectangle(cornerRadius: 10).fill(WebTheme.surface4)
                    .frame(height: 48)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                Capsule().fill(WebTheme.surface4)
                    .frame(height: JPHeight.primaryButton)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                LazyVGrid(columns: tileColumns, spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 14).fill(WebTheme.surface4).frame(height: 84)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            // 読み上げは「読み込み中」1つ（骨格の一つずつを読ませない）
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("読み込み中", "Loading"))
        }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（2026-10-17・run 464）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.loading")
    }

    private func loaded(_ state: TrunkState) -> some View {
        let saved = model.showingSaved
        return ScrollView {
            VStack(spacing: 0) {
                if saved {
                    offlineSavedBanner
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }
                if let error = model.actionError {
                    Text(error)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
                Text(TrunkText.eyebrow(state.effectiveModel))
                    .font(JPFont.eyebrow)
                    .tracking(11 * 0.12)
                    .foregroundStyle(WebTheme.accent)
                    .lineLimit(1)
                    .padding(.top, 4)
                trunkStage(state)
                    .opacity(saved ? 0.55 : 1)
                if model.isEmpty {
                    Text(TrunkHome.firstNote)
                        .font(.subheadline)
                        .foregroundStyle(TrunkStyle.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（2026-10-17・run 464）
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("trunk.empty")
                } else {
                    stats(state)
                }
                primaryButton(state, disabled: saved)
                    .padding(.top, 14)
                tiles(state, disabled: saved)
                    .padding(.top, 10)
                menu(state, disabled: saved)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
        }
        // 子の目印（押せるもの）を消さないよう、入れ物の要素にしてから名前を付ける（2026-10-17・run 464）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.screen")
    }

    /// 圏外で前に読んだトランクを出しているときの上のお知らせ（板 OfflineTrip の帯の形に「もう一度」を足す）
    private var offlineSavedBanner: some View {
        HStack(alignment: .center, spacing: JPSpace.s) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WebTheme.accent)
                .accessibilityHidden(true)
            Text(TrunkHome.offlineSavedNote)
                .font(JPFont.footnote.weight(.semibold))
                .foregroundStyle(WebTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                Task {
                    await model.load(offline: connectivity.isOffline, saved: savedState)
                    if model.showingSaved { toasts.show(TrunkHome.stillOffline, kind: .info) }
                }
            } label: {
                Text(TrunkHome.offlineRetry)
                    .jpCapsuleFace(font: JPFont.footnote, text: WebTheme.foreground, fill: Color.clear, border: WebTheme.line,
                                   fullWidth: false, minHeight: PillChip.height, textInset: 12)
                    .padding(.vertical, PillChip.tapSlack)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.offlineSaved.retry")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(WebTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trunk.offlineSaved")
    }

    /// トランク（モック: 378×318 の押せる枠・少し傾けて置く・足元に真鍮の淡い光）と、右下の「回して見る」。
    /// 「押すと手に取って回せます」の文はやめ、押せることをボタンの形で見せる（2026-11-23・札 #711）
    private func trunkStage(_ state: TrunkState) -> some View {
        VStack(spacing: 0) {
            Button { showSpin = true } label: {
                // モック: 360×300 を 1.05 倍・少し傾けて（rotateX 5°・rotateY -7°・rotate -1°）378×318 の枠に。
                // 幅の狭い画面では枠ごと縮める（左右に 6 ずつ）。初めて開いたときだけ rotateY を少し揺らす（`wiggle`）
                TrunkFigureFit(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck,
                               ownerName: ownerName, parts: state.equipped,
                               wrinkles: TrunkWrinkles(userId: auth.userId).strengths, maxWidth: 360,
                               tagPicks: state.tagPicks)
                    .scaleEffect(1.05)
                    .rotation3DEffect(.degrees(5), axis: (x: 1, y: 0, z: 0), perspective: 0.36)
                    .rotation3DEffect(.degrees(-7 + wiggle), axis: (x: 0, y: 1, z: 0), perspective: 0.36)
                    .rotationEffect(.degrees(-1))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 378)
                    // 押せる範囲は枠いっぱい（絵の透けた所・縁の余白でも開く。絵の層の押し分けに頼らない）
                    .contentShape(Rectangle())
            }
            .buttonStyle(TrunkPressStyle())
            .accessibilityLabel(L("トランクを手に取って回す", "Pick up and turn your trunk"))
            .accessibilityIdentifier("trunk.spin")
            .padding(.top, 18)
            .overlay(alignment: .bottomTrailing) { spinChip.padding(.trailing, 22) }
            EllipticalGradient(colors: [WebTheme.accent.opacity(0.16), Color.clear])
                .frame(width: 320, height: 18)
                .padding(.top, -4)
                .accessibilityHidden(true)
        }
    }

    /// 「回して見る」（見た目 32・当たり 44。黒の半透明の丸に白の字。初めて開いたときだけ真鍮の光が3回）
    private var spinChip: some View {
        Button { showSpin = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .accessibilityHidden(true)
                Text(TrunkHome.spinTitle)
                    .font(JPFont.caption)
            }
            // 丸いボタンの面（`jpCapsuleFace`）を通す。地はトランクの絵に重なるので黒の半透明
            .jpCapsuleFace(font: JPFont.caption, text: WebTheme.text, fill: WebTheme.card.opacity(0.82), border: WebTheme.line,
                           fullWidth: false, minHeight: 32, textInset: 11)
            .shadow(color: WebTheme.accent.opacity(chipGlow ? 0.55 : 0), radius: chipGlow ? 8 : 0)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TrunkHome.spinLabel)
        .accessibilityIdentifier("trunk.spin.chip")
    }

    /// 初めて開いたときだけ（端末に1回・`TrunkHome.takeIntro`）、トランクを少し揺らして「回して見る」を光らせる。
    /// 見本の「初めて開いた」（`-JPPreviewTrunkHome first`）は毎回。動きを減らす設定では揺らさず、光だけ
    private func playIntroIfNeeded() async {
        guard model.phase == .loaded, !model.showingSaved else { return }
        let forced = PreviewSession.trunkHome == "first"
        guard forced || TrunkHome.takeIntro() else { return }
        try? await Task.sleep(for: .milliseconds(250))
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 0.36)) { wiggle = -15 }
            try? await Task.sleep(for: .milliseconds(360))
            withAnimation(.easeInOut(duration: 0.42)) { wiggle = 9 }
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { wiggle = 0 }
        }
        for _ in 0..<3 {
            withAnimation(.easeInOut(duration: 0.7)) { chipGlow = true }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeInOut(duration: 0.7)) { chipGlow = false }
            try? await Task.sleep(for: .milliseconds(700))
        }
    }

    /// 数え札（モック: 22pt の数字・12pt の説明・上下に線）。「貼ったラベル ›」は真鍮で、押すと貼ったラベルの一覧
    /// （前の「最近貼ったラベル」の「すべて見る」と同じ1回）
    private func stats(_ state: TrunkState) -> some View {
        let s = TrunkText.stats(state)
        return HStack(spacing: 8) {
            NavigationLink {
                TrunkStuckLabelsView(labels: state.stuck)
            } label: {
                statCell(String(s.stuck), TrunkHome.stuckCaption, link: true)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.allLabels")
            statCell(String(s.countries), L("の国と地域", "Countries & regions"))
            statCell(s.sinceYear.map(String.init) ?? "—", L("年から", "Since"))
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { TrunkStyle.line.frame(height: 1) }
        .overlay(alignment: .bottom) { TrunkStyle.line.frame(height: 1) }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func statCell(_ value: String, _ caption: String, link: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(JPFont.number(22, weight: .semibold, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
            HStack(spacing: 2) {
                Text(caption)
                if link {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .font(.caption)
            .foregroundStyle(link ? WebTheme.accent : TrunkStyle.muted)
            // アクセシビリティの大きさでは折り返す（1行では「貼ったラ…」と切れた・2026-10-21 Mac run 628）
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: 大きいボタンと4つのカード

    /// 状態で替わる大きいボタン（写真の無い画面なので真鍮の塗りに墨・50 の丸。2行目は何があるから押すのか）
    private func primaryButton(_ state: TrunkState, disabled: Bool) -> some View {
        let action = TrunkHome.primary(state)
        return Button { perform(action) } label: {
            VStack(spacing: 1) {
                Text(TrunkHome.title(action))
                    .font(.callout.weight(.bold))
                Text(TrunkHome.subtitle(action, pocket: state.pocket.count, coins: state.coins))
                    .font(JPFont.caption)
                    .opacity(0.8)
            }
            .foregroundStyle(WebTheme.accentText)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: JPHeight.primaryButton)
            .background(WebTheme.accentFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(TrunkPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(TrunkHome.identifier(action))
        .padding(.horizontal, 20)
    }

    private let tileColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    /// 2つずつの段（`TrunkHome.tileRows`）。3枚のとき（手荷物タグに対応していないサーバー）は3枚目が横いっぱい
    private func tiles(_ state: TrunkState, disabled: Bool) -> some View {
        let rows = TrunkHome.tileRows(TrunkHome.tiles(for: TrunkHome.primary(state), showsTags: state.supportsTagPicks))
        return VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { tile in
                        Button { open(tile) } label: { tileFace(tile, state: state) }
                            .buttonStyle(JPRowButtonStyle())
                            .disabled(disabled)
                            .opacity(disabled ? 0.4 : 1)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier(TrunkHome.identifier(tile))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    /// カード（模型: 札の地・角 14・高さ 84 以上。上に真鍮の印、下に名前 15 と数 12）
    private func tileFace(_ tile: TrunkHomeTile, state: TrunkState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 部品箱のカードに、かけらの切符と数（札 #713・見るまでの押す回数 1 → 0）。5つで真鍮の「交換できます」。
            // 既定の大きさは印の右、アクセシビリティの大きさは名前の行の下
            let placement = tile == .parts
                ? TrunkFragmentText.tilePlacement(fragments: state.fragments, accessibilitySize: typeSize.isAccessibilitySize) : nil
            HStack(spacing: 4) {
                tileIcon(tile)
                Spacer(minLength: 4)
                if placement == .beside {
                    // 狭い幅（375 など）では切符を外して字だけ
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) {
                            TrunkFragmentTicketView(filled: state.fragments, width: 30)
                            fragmentCaption(state.fragments)
                        }
                        fragmentCaption(state.fragments)
                    }
                }
            }
            .frame(height: 22)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(TrunkHome.tileTitle(tile))
                    .font(JPFont.bodyEmphasis)
                    .foregroundStyle(WebTheme.text)
                Text(TrunkHome.tileValue(tile, state: state))
                    .font(JPFont.meta)
                    .foregroundStyle(TrunkStyle.muted)
                if placement == .below {
                    HStack(spacing: 6) {
                        TrunkFragmentTicketView(filled: state.fragments, width: 30)
                        fragmentCaption(state.fragments)
                    }
                    .padding(.top, 4)
                }
            }
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .trunkCard(radius: 14)
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    /// かけらの数（「3 / 5」、5つで真鍮の「交換できます」）。13pt を狭いときだけ 12pt まで縮める
    private func fragmentCaption(_ fragments: Int) -> some View {
        let ready = TrunkPartsBoxText.canExchange(fragments: fragments)
        return Text(TrunkFragmentText.tileCaption(fragments))
            .jpSystemFont(TrunkFragmentText.tileFontSize, weight: ready ? .semibold : .regular, relativeTo: .footnote)
            .foregroundStyle(ready ? WebTheme.accent : TrunkStyle.muted)
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(TrunkFragmentText.tileMinimumScale)
            .accessibilityLabel(TrunkPartsBoxText.fragmentsLabel(fragments))
            .accessibilityIdentifier("trunk.partsBox.fragments")
    }

    @ViewBuilder
    private func tileIcon(_ tile: TrunkHomeTile) -> some View {
        if tile == .gacha {
            TrunkCoinMark(size: 20)
        } else {
            Image(systemName: TrunkHome.symbol(tile))
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(WebTheme.accent)
                .accessibilityHidden(true)
        }
    }

    private func perform(_ action: TrunkHomeAction) {
        switch action {
        case .stick: showStick = true
        case .gacha: route = .gacha
        case .post: tabRouter.openPost(.photo)
        }
    }

    private func open(_ tile: TrunkHomeTile) {
        if tile == .stick { showStick = true } else { route = tile }
    }

    @ViewBuilder
    private func destination(_ tile: TrunkHomeTile) -> some View {
        switch tile {
        case .gacha:
            TrunkGachaView(model: model)
        case .parts:
            TrunkPartsBoxView(model: model, ownerName: ownerName)
        case .tags:
            TrunkTagsView(model: model, onStick: { showStick = true })
        case .open:
            // ふたを開ける（2026-10-18 次の版・板 TrunkOpen）: 中にメダル・会員証・乗車券
            if let state = model.state {
                TrunkOpenView(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck,
                              ownerName: ownerName, parts: state.equipped,
                              wrinkles: TrunkWrinkles(userId: auth.userId).strengths, tagPicks: state.tagPicks)
            }
        case .stick:
            EmptyView()
        }
    }

    // MARK: 下の札

    /// 手持ち・型・受け取り（モック: 札・行 52・区切り）。受け取りは #706 のあとに「手持ちのラベル」の画面へ移す。
    ///
    /// `disabled`: 圏外で前に読んだトランクを出している間（2026-11-23 判断・確かめ役の指摘: 大きいボタンとカードは
    /// 押せないのに、この2行だけ押せて、開いた先で書き込みが失敗していた）。カードと同じ薄さにし、`.disabled` で
    /// 読み上げでも「淡色表示」（押せない）と伝わる。電波が戻れば `TrunkHome.reloadsWhenBack` で読み直して押せるようになる
    private func menu(_ state: TrunkState, disabled: Bool) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                TrunkPocketView(model: model)
            } label: {
                TrunkMenuRow(title: L("手持ちのラベル", "Label pocket"),
                             value: TrunkText.pocketCounter(count: state.pocket.count, limit: state.limit))
            }
            .buttonStyle(JPRowButtonStyle())
            .disabled(disabled)
            .opacity(disabled ? 0.4 : 1)
            .accessibilityIdentifier("trunk.pocket")
            TrunkStyle.line.frame(height: 1)
            NavigationLink {
                TrunkModelsView(model: model, ownerName: ownerName)
            } label: {
                TrunkMenuRow(title: L("トランクの型", "Trunk style"), value: TrunkText.info(state.effectiveModel).name)
            }
            .buttonStyle(JPRowButtonStyle())
            .disabled(disabled)
            .opacity(disabled ? 0.4 : 1)
            .accessibilityIdentifier("trunk.models")
            TrunkStyle.line.frame(height: 1)
            receiveRow(state)
        }
        .trunkCard(radius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    /// ラベルを受け取るか（オフの間は投稿してもラベルは届かない。戻してもさかのぼらない）
    private func receiveRow(_ state: TrunkState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { model.state?.receiveLabels ?? true },
                                 set: { on in Task { await model.setReceiveLabels(on) } })) {
                Text(L("投稿のお礼にラベルを受け取る", "Receive a label when you post"))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
            }
            .tint(WebTheme.accent)
            .disabled(model.busy || model.showingSaved)
            .accessibilityIdentifier("trunk.receive")
            if !state.receiveLabels {
                Text(L("止めている間に投稿した写真には、あとから受け取りに戻しても届きません。",
                       "Photos you post while this is off won\u{2019}t bring labels later, even if you turn it back on."))
                    .font(.caption)
                    .foregroundStyle(TrunkStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
    }

    /// 区切りの投稿を越えたら「変わったところ」を短く知らせる（モック Aging の注記）。人ごと・区切りごとに1回
    private func noteAging() {
        guard let posts = model.state?.posts, let milestone = TrunkAging.latestMilestone(posts: posts),
              let uid = auth.userId else { return }
        let key = TrunkAgingNotice.key(uid)
        let seen = UserDefaults.standard.integer(forKey: key)
        guard milestone.posts > seen else { return }
        UserDefaults.standard.set(milestone.posts, forKey: key)
        // はじめて開いた人には、いまの姿の言葉だけを出す（過ぎた区切りを全部は言わない）
        toasts.show(L("投稿 \(milestone.posts)\u{2002}\(milestone.ja)", "Post \(milestone.posts)\u{2002}\(milestone.en)"), kind: .info)
    }
}

/// トランクを押さえたときの手ざわり（少し沈む）
struct TrunkPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 貼ったラベルをすべて（「すべて見る」）。新しい順の格子
struct TrunkStuckLabelsView: View {
    let labels: [TrunkLabel]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView {
            if labels.isEmpty {
                EmptyState(title: L("まだ貼っていません", "Nothing stuck yet"),
                           message: L("手持ちのラベルを選んで「貼る」を押すと、トランクに貼れます。",
                                      "Choose a label in your pocket and tap Stick to put it on your trunk."))
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(labels) { label in
                        VStack(spacing: 6) {
                            TrunkLabelThumb(label: label, maxWidth: 92, maxHeight: 76)
                                .frame(height: 104)
                                .frame(maxWidth: .infinity)
                                .trunkCard(radius: 14)
                            Text(TrunkLabelDesign.caption(label))
                                .font(.caption)
                                .foregroundStyle(TrunkStyle.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(TrunkLabelDesign.accessibilityLabel(label))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .webScreen()
        .navigationTitle(L("貼ったラベル", "Stuck labels"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
