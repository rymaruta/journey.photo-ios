import SwiftUI

/// 旅のトランク（モック Main.dc.html・2026-10-17 owner 承認）。入口はマイページの旅の記録の札。
///
/// 上から: 眉ラベル（MY TRUNK · 型の名前）→ トランク（押すと手に取って回す）→ 足元の光 →
/// 数え札3つ（貼ったラベル・か国・地域・年から）→ 最近貼ったラベル3枚（すべて見る）→
/// 手持ち・型・受け取りの札。読み込み中・空・失敗・圏外はそれぞれの形で出す（板 v2 の4つの状態）。
struct TrunkView: View {
    /// 名札に刻む名前（寝台列車・飛行艇の型）
    var ownerName: String?

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var connectivity: Connectivity
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = TrunkViewModel()
    @ObservedObject private var tabRouter = TabRouter.shared
    @State private var showSpin = false
    @State private var showPaywall = false

    var body: some View {
        content
            .webScreen()
            .navigationTitle(L("旅のトランク", "Travel trunk"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                model.bind(environment.trunk)
                await model.load(offline: connectivity.isOffline)
                noteAging()
            }
            .refreshable { await model.load(offline: connectivity.isOffline) }
            .fullScreenCover(isPresented: $showSpin) {
                if let state = model.state {
                    TrunkSpinViewer(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck,
                                    ownerName: ownerName)
                }
            }
            .fullScreenCover(isPresented: $showPaywall, onDismiss: {
                // 買えたかもしれない: Pro かどうか・上限・回数を読み直す
                Task { await model.refreshAfterPaywall(offline: connectivity.isOffline) }
            }) { PaywallView() }
            // 知らせは `RootView` の全体の知らせで出る（押して進む画面なので重ねない・2026-10-17 の読み直し）
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ScrollView {
                VStack(spacing: 16) {
                    // 読み込み中も形は同じ（新しいトランクを薄く置き、行は骨格）
                    TrunkFigure(model: .leather, posts: 0, width: 300)
                        .opacity(0.25)
                        .padding(.top, 40)
                    JPLoadingState(kind: .rows).padding(.horizontal, 20)
                }
            }
            .accessibilityIdentifier("trunk.loading")
        case .failed(let message):
            ErrorBanner(title: L("トランクを開けませんでした", "Couldn\u{2019}t open your trunk"), message: message,
                        retry: { Task { await model.load(offline: connectivity.isOffline) } })
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("trunk.failed")
        case .offline:
            ErrorBanner(title: L("電波がありません", "No signal"),
                        message: L("電波のあるところで開くと、トランクを読み込みます。",
                                   "Open this again where you have a signal to load your trunk."),
                        retry: { Task { await model.load(offline: connectivity.isOffline) } })
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("trunk.offline")
        case .loaded:
            if let state = model.state { loaded(state) }
        }
    }

    private func loaded(_ state: TrunkState) -> some View {
        ScrollView {
            VStack(spacing: 0) {
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
                trunkButton(state)
                if model.isEmpty {
                    EmptyState(title: L("まだラベルがありません", "No labels yet"),
                               message: L("写真を投稿すると、お礼に旅のラベルが1枚届きます。届いたラベルをトランクに貼っていきましょう。",
                                          "Each photo you post brings a travel label as thanks. Stick them on your trunk."),
                               actionTitle: L("写真を投稿", "Post a photo"), actionIdentifier: "trunk.emptyPost") {
                        tabRouter.openPost(.photo)
                    }
                    .accessibilityIdentifier("trunk.empty")
                } else {
                    stats(state)
                    recent(state)
                }
                menu(state)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
            }
        }
        .accessibilityIdentifier("trunk.screen")
    }

    /// トランク（モック: 378×318 の押せる枠・少し傾けて置く・足元に真鍮の淡い光）
    private func trunkButton(_ state: TrunkState) -> some View {
        VStack(spacing: 0) {
            Button { showSpin = true } label: {
                // モック: 360×300 を 1.05 倍・少し傾けて（rotateX 5°・rotateY -7°・rotate -1°）378×318 の枠に。
                // 幅の狭い画面では枠ごと縮める（左右に 6 ずつ）
                TrunkFigureFit(model: state.effectiveModel, posts: state.posts ?? 0, stuck: state.stuck,
                               ownerName: ownerName, maxWidth: 360)
                    .scaleEffect(1.05)
                    .rotation3DEffect(.degrees(5), axis: (x: 1, y: 0, z: 0), perspective: 0.36)
                    .rotation3DEffect(.degrees(-7), axis: (x: 0, y: 1, z: 0), perspective: 0.36)
                    .rotationEffect(.degrees(-1))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 378)
            }
            .buttonStyle(TrunkPressStyle())
            .accessibilityLabel(L("トランクを手に取って回す", "Pick up and turn your trunk"))
            .accessibilityIdentifier("trunk.spin")
            .padding(.top, 18)
            EllipticalGradient(colors: [WebTheme.accent.opacity(0.16), Color.clear])
                .frame(width: 320, height: 18)
                .padding(.top, -4)
                .accessibilityHidden(true)
            Text(L("押すと手に取って回せます", "Tap to pick it up and turn it"))
                .font(.caption)
                .foregroundStyle(TrunkStyle.faint)
                .padding(.top, 2)
        }
    }

    /// 数え札（モック: 22pt の数字・12pt の説明・上下に #1A1A1A の線）
    private func stats(_ state: TrunkState) -> some View {
        let s = TrunkText.stats(state)
        return HStack(spacing: 8) {
            statCell(String(s.stuck), L("貼ったラベル", "Labels stuck"))
            statCell(String(s.countries), L("か国・地域", "Countries & regions"))
            statCell(s.sinceYear.map(String.init) ?? "—", L("年から", "Since"))
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { TrunkStyle.line.frame(height: 1) }
        .overlay(alignment: .bottom) { TrunkStyle.line.frame(height: 1) }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func statCell(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(JPFont.number(22, weight: .semibold, relativeTo: .title2))
                .foregroundStyle(WebTheme.text)
            Text(caption)
                .font(.caption)
                .foregroundStyle(TrunkStyle.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// 最近貼ったラベル（3枚・すべて見る）
    @ViewBuilder
    private func recent(_ state: TrunkState) -> some View {
        HStack {
            Text(L("最近貼ったラベル", "Recently stuck"))
                .jpEyebrow()
                .foregroundStyle(WebTheme.accent)
            Spacer()
            NavigationLink {
                TrunkStuckLabelsView(labels: state.stuck)
            } label: {
                Text(L("すべて見る", "See all"))
                    .font(.subheadline)
                    .underline()
                    .foregroundStyle(WebTheme.accent)
                    .frame(minHeight: WebTheme.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trunk.allLabels")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        if state.stuck.isEmpty {
            Text(L("手持ちのラベルを貼ると、ここに並びます。", "Labels you stick will appear here."))
                .font(JPFont.footnote)
                .foregroundStyle(TrunkStyle.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(state.stuck.prefix(3))) { label in
                    VStack(spacing: 6) {
                        TrunkLabelThumb(label: label, maxWidth: 100, maxHeight: 72)
                        Text(TrunkLabelDesign.caption(label))
                            .font(.caption)
                            .foregroundStyle(TrunkStyle.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(TrunkLabelDesign.accessibilityLabel(label))
                }
                // 3枚に満たないときも、1枚の幅は3つに割ったまま
                ForEach(0..<max(0, 3 - min(3, state.stuck.count)), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// 手持ち・型・受け取り（モック: #121212 の札・行 52・#1A1A1A の区切り）
    private func menu(_ state: TrunkState) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                TrunkPocketView(model: model)
            } label: {
                TrunkMenuRow(title: L("手持ちのラベル", "Label pocket"),
                             value: TrunkText.pocketCounter(count: state.pocket.count, limit: state.limit))
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("trunk.pocket")
            TrunkStyle.line.frame(height: 1)
            NavigationLink {
                TrunkModelsView(model: model, ownerName: ownerName)
            } label: {
                TrunkMenuRow(title: L("トランクの型", "Trunk style"), value: TrunkText.info(state.effectiveModel).name)
            }
            .buttonStyle(JPRowButtonStyle())
            .accessibilityIdentifier("trunk.models")
            TrunkStyle.line.frame(height: 1)
            receiveRow(state)
        }
        .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
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
            .disabled(model.busy)
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
        let key = "trunk.agingSeen.\(uid)"
        let seen = UserDefaults.standard.integer(forKey: key)
        guard milestone.posts > seen else { return }
        UserDefaults.standard.set(milestone.posts, forKey: key)
        // はじめて開いた人には、いまの姿の言葉だけを出す（過ぎた区切りを全部は言わない）
        toasts.show(L("投稿 \(milestone.posts) · \(milestone.ja)", "Post \(milestone.posts) · \(milestone.en)"), kind: .info)
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
                                .background(TrunkStyle.cell, in: RoundedRectangle(cornerRadius: 14))
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
