import SwiftUI
import UIKit
#if !os(Linux)
import ImageIO
#endif

/// 旅をストーリーに（資料「画面デザインの案」第9章・1.1.83・2026-11-12 判断）。
///
/// **型を横に払って選ぶ1枚**（搭乗券・切手と消印・フィルムの帯）。比率は 9:16 に決め打ち（ストーリーの口なので）、
/// 型・形・場所・日付は前に選んだものから始まる（`TravelStory.load`）。何も触らずに主ボタンを押せば載せられる。
///
/// **インスタのストーリーへ直接渡す口（`instagram-stories://share`）は作っていない**（2026-11-12 判断）:
/// Meta の決まりで `source_application` に Facebook の App ID が要り（無いと受け取り側で失敗する）、
/// それは Meta の開発者の登録（owner の操作）なので、この枝では作らない。
/// いまは写真に重ねる絵を**標準の共有シート**（今の「SNS に載せる」と同じ渡し方・`ShareSheet`）で渡し、
/// ステッカーは**透明の PNG をクリップボードに置く**（インスタのストーリーの編集で貼り付けるとステッカーになる）。
struct TravelStorySheet: View {

    /// 先頭の写真（搭乗券・切手の絵）。旅の一冊なら最後の1枚
    let leadURL: URL
    /// フィルムの帯に並べる写真（最大3枚・`TravelStory.filmPicks`）。先頭の1枚だけでもよい
    let filmURLs: [URL]
    let facts: TravelStory.Facts

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var toasts: ToastCenter

    @State private var choice: TravelStory.Choice
    @State private var leadData: Data?
    @State private var filmData: [Data]?
    @State private var loadFailed = false
    @State private var loadAttempt = 0
    /// 描いた絵（`Choice.renderKey` ごと）。**置くのは今の選びと両隣の型だけ**（`keep(_:)`）、閉じると捨てる
    @State private var outputs: [String: Rendered] = [:]
    @State private var failedKeys: Set<String> = []
    @State private var renderAttempt = 0
    @State private var drag: CGFloat = 0
    @State private var shareItem: ShareItem?

    /// 描いた絵と、見本に出す縮めた絵（2026-11-12・確かめ役）。払っている間に 1080×1920 の JPEG を
    /// 毎回 `UIImage(data:)` で開かない——描いたときに1度だけ見本の大きさに縮めて持つ
    private struct Rendered {
        let output: TravelStoryRenderer.Output
        let preview: UIImage?
    }

    private struct ShareItem: Identifiable {
        let id = UUID()
        let data: Data
    }

    /// 上に置く部品（「SNS に載せる」の「投稿 | ストーリー」の切り替え・`SocialShareSheet`）
    private let header: AnyView?

    /// `leadData` は呼び手がもう読んだ先頭の写真（写真の詳細の「SNS に載せる」）。あれば読み直さない
    init(leadURL: URL, filmURLs: [URL], facts: TravelStory.Facts, phase: TravelStory.Phase,
         leadData: Data? = nil, header: AnyView? = nil) {
        self.leadURL = leadURL
        self.filmURLs = filmURLs.isEmpty ? [leadURL] : filmURLs
        self.facts = facts
        self.header = header
        _choice = State(initialValue: TravelStory.load(phase: phase))
        _leadData = State(initialValue: leadData)
    }

    private var kinds: [TravelStory.Kind] { TravelStory.Kind.allCases }
    private var index: Int { kinds.firstIndex(of: choice.kind) ?? 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let header { header }
                stage
                    .frame(maxHeight: .infinity)
                nameRow
                dots
                options
                    .padding(.horizontal, JPSpace.m)
                    .padding(.top, JPSpace.s)
                primaryButton
                    .padding(.horizontal, JPSpace.m)
                    .padding(.top, JPSpace.m)
                    .padding(.bottom, JPSpace.m)
            }
            .background(Color.black)
            .foregroundStyle(WebTheme.text)
            // シートの上ではアプリの下の知らせ（`RootView`）が隠れるので、ここにも置く（`NameSideBadgeView` と同じ）。
            // 主ボタン（44＋余白）に重ねない
            .overlay(alignment: .bottom) { ToastOverlay().padding(.bottom, 84) }
            .navigationTitle(L("ストーリーに", "To your story"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("閉じる", "Close")) { dismiss() }
                        .accessibilityIdentifier("travelStory.close")
                }
            }
            .task(id: loadAttempt) { await loadPhotos() }
            // 今の型を先に、両隣を後から描く（払ったときに待たせない）
            .task(id: "\(choice.renderKey)#\(leadData?.count ?? 0)#\(filmData?.count ?? 0)#\(renderAttempt)") {
                await renderVisible()
            }
            .onChange(of: choice) { _, newValue in TravelStory.save(newValue) }
            .sheet(item: $shareItem) { item in
                // 文は渡さない（ストーリーは文を受け取らない・クリップボードを上書きしない）
                ShareSheet(images: [item.data], text: "")
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - 払って選ぶ

    /// 横に払うと型が替わる。両隣は 45%・0.92 倍で覗かせる（章の模型の `.pk-slide`）
    private var stage: some View {
        GeometryReader { geo in
            let gap: CGFloat = 12
            let byHeight: CGFloat = (geo.size.height - JPSpace.s) * 9.0 / 16.0
            let width: CGFloat = max(80, min(geo.size.width * 0.74, byHeight))
            let step = width + gap
            let offset = (geo.size.width - width) / 2 - CGFloat(index) * step + drag
            HStack(spacing: gap) {
                ForEach(kinds) { kind in
                    let on = kind == choice.kind
                    slide(kind)
                        .frame(width: width, height: width * 16.0 / 9.0)
                        .opacity(on ? 1 : 0.45)
                        .scaleEffect(on ? 1 : 0.92)
                        .accessibilityHidden(!on)
                }
            }
            .offset(x: offset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        let atEdge = (index == 0 && value.translation.width > 0)
                            || (index == kinds.count - 1 && value.translation.width < 0)
                        drag = atEdge ? value.translation.width * 0.3 : value.translation.width
                    }
                    .onEnded { value in
                        let moved = value.translation.width
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                            drag = 0
                            if abs(moved) > width * 0.16 { go(index + (moved < 0 ? 1 : -1)) }
                        }
                    }
            )
            .clipped()
        }
        .padding(.vertical, JPSpace.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("型。左右に払って替える", "Style. Swipe left or right to change"))
        .accessibilityValue("\(choice.kind.name)（\(index + 1)/\(kinds.count)）")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: go(index + 1)
            case .decrement: go(index - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("travelStory.stage")
    }

    @ViewBuilder
    private func slide(_ kind: TravelStory.Kind) -> some View {
        let key = choice.with(kind: kind).renderKey
        let sticker = choice.with(kind: kind).effectiveMode == .sticker
        ZStack {
            if sticker { StickerChecker() } else { WebTheme.sheet }
            if let image = outputs[key]?.preview {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(sticker ? 12 : 0)
                    .accessibilityLabel(L("\(kind.name)の見本", "\(kind.name) preview"))
            } else if loadFailed || failedKeys.contains(key) {
                failure
            } else {
                ProgressView()
                    .tint(WebTheme.text2)
                    .accessibilityLabel(L("絵を作っています", "Making the image"))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: JPRadius.field))
        .overlay(RoundedRectangle(cornerRadius: JPRadius.field).strokeBorder(WebTheme.line.opacity(0.6), lineWidth: 1))
    }

    /// 写真を読めない・描けないとき（圏外を含む）。もう一度
    private var failure: some View {
        VStack(spacing: JPSpace.xs) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title3)
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
            Text(loadFailed ? L("写真を読み込めませんでした", "Couldn't load the photo")
                            : L("絵を作れませんでした", "Couldn't make the image"))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .multilineTextAlignment(.center)
            Button {
                if loadFailed {
                    loadFailed = false
                    loadAttempt += 1
                } else {
                    failedKeys.removeAll()
                    renderAttempt += 1
                }
            } label: {
                Text(L("もう一度", "Try again"))
                    .jpOutlineButton(.inline)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("travelStory.retry")
        }
        .padding(JPSpace.s)
    }

    private func go(_ next: Int) {
        guard kinds.indices.contains(next) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
            choice = choice.with(kind: kinds[next])
        }
    }

    /// ‹ 名前（2/3） ›（押しても替えられる・払うのが分からない人のため）
    private var nameRow: some View {
        HStack(spacing: JPSpace.xxs) {
            arrow("chevron.left", L("前の型", "Previous style"), id: "travelStory.prev", enabled: index > 0) { go(index - 1) }
            Text("\(choice.kind.name)（\(index + 1)/\(kinds.count)）")
                .font(JPFont.rowTitle)
                .foregroundStyle(WebTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 180)
                .accessibilityIdentifier("travelStory.name")
            arrow("chevron.right", L("次の型", "Next style"), id: "travelStory.next",
                  enabled: index < kinds.count - 1) { go(index + 1) }
        }
        .frame(maxWidth: .infinity)
    }

    private func arrow(_ symbol: String, _ label: String, id: String, enabled: Bool,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(WebTheme.text2)
                .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    /// 点の列。今の型は真鍮の長い点（黒地の上・owner の好み「選んでいる所は真鍮」）
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(kinds) { kind in
                let on = kind == choice.kind
                Capsule()
                    .fill(on ? WebTheme.accent : Color.white.opacity(0.28))
                    .frame(width: on ? 16 : 6, height: 6)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    // MARK: - 形・場面・場所・日付

    private var options: some View {
        VStack(spacing: JPSpace.xs) {
            TravelStorySegment(items: TravelStory.Mode.allCases, selection: choice.effectiveMode,
                               label: \.label, groupLabel: L("形", "Form"), idPrefix: "travelStory.mode",
                               isEnabled: { $0 == .photo || choice.kind.supportsSticker }) { choice.mode = $0 }
            if choice.kind.usesPhase {
                TravelStorySegment(items: TravelStory.Phase.allCases, selection: choice.phase,
                                   label: \.label, groupLabel: L("旅のどこ", "Trip moment"),
                                   idPrefix: "travelStory.phase") { choice.phase = $0 }
            }
            row(L("場所", "Place")) {
                TravelStorySegment(items: TravelStory.PlaceLevel.allCases, selection: choice.placeLevel,
                                   label: \.label, groupLabel: L("場所の細かさ", "Place detail"),
                                   idPrefix: "travelStory.place") { choice.placeLevel = $0 }
            }
            row(L("日付", "Date")) {
                TravelStorySegment(items: TravelStory.DateLevel.allCases, selection: choice.dateLevel,
                                   label: \.label, groupLabel: L("日付", "Date"),
                                   idPrefix: "travelStory.date") { choice.dateLevel = $0 }
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: JPSpace.xs) {
            Text(title)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .frame(width: 40, alignment: .leading)
                .accessibilityHidden(true)
            content()
        }
    }

    // MARK: - 渡す

    private var currentOutput: TravelStoryRenderer.Output? { outputs[choice.renderKey]?.output }

    /// 写真に重ねる絵は共有シートへ、ステッカーはクリップボードへ（理由は型の注記）
    private var primaryButton: some View {
        Button {
            guard let output = currentOutput else { return }
            if output.isSticker {
                UIPasteboard.general.setItems([["public.png": output.data]],
                                              options: [.localOnly: true,
                                                        .expirationDate: Date().addingTimeInterval(600)])
                // 知らせはアプリの共通の部品（`ToastOverlay`）で。読み上げにも伝える
                let note = L("コピーしました。インスタのストーリーで貼り付けられます",
                             "Copied. Paste it into your Instagram story")
                toasts.show(note)
                UIAccessibility.post(notification: .announcement, argument: note)
            } else {
                shareItem = ShareItem(data: output.data)
            }
        } label: {
            Label(choice.effectiveMode == .sticker ? L("ステッカーをコピー", "Copy sticker")
                                                    : L("ストーリーに共有", "Share to your story"),
                  systemImage: choice.effectiveMode == .sticker ? "doc.on.doc" : "square.and.arrow.up")
                .jpPillButton(.main(onPhoto: true))
        }
        .buttonStyle(.plain)
        .disabled(currentOutput == nil)
        .opacity(currentOutput == nil ? 0.5 : 1)
        .accessibilityIdentifier("travelStory.share")
    }

    // MARK: - 読む・描く

    private func loadPhotos() async {
        if leadData == nil {
            guard let data = await TripBookCardRenderer.coverData(leadURL) else {
                if !Task.isCancelled { loadFailed = true }
                return
            }
            leadData = data
        }
        guard filmData == nil else { return }
        // フィルムの帯の残り（先頭と同じ URL は読み直さない）。読めない1枚は落とす
        var films: [Data] = []
        for url in filmURLs {
            if url == leadURL, let leadData { films.append(leadData); continue }
            if let data = await TripBookCardRenderer.coverData(url) { films.append(data) }
            if Task.isCancelled { return }
        }
        filmData = films.isEmpty ? leadData.map { [$0] } : films
    }

    /// 今の型を先に、両隣を後から描く（払ったときに待たせない）。**今の選びと両隣でない絵は捨てる**
    /// （場所・日付を替えるたびに増えていかない・`TravelStory.nearby`）。
    /// 選びが替わって task が取り消されたら、まだ始めていない描画は始めず、走っている描画（detached）にも取り消しを伝える
    private func renderVisible() async {
        let wanted = TravelStory.nearby(choice.kind).map { choice.with(kind: $0) }
        let keys = Set(wanted.map(\.renderKey))
        outputs = outputs.filter { keys.contains($0.key) }
        guard let leadData else { return }
        for each in wanted {
            guard !Task.isCancelled else { return }
            let key = each.renderKey
            guard outputs[key] == nil, !failedKeys.contains(key) else { continue }
            let photos: [Data]
            if each.kind == .film {
                guard let filmData else { continue }   // 読み終えたら描き直しの task が来る
                photos = filmData
            } else {
                photos = [leadData]
            }
            let facts = facts
            let job = Task.detached(priority: .userInitiated) { () -> Rendered? in
                guard !Task.isCancelled,
                      let output = TravelStoryRenderer.render(photos, facts: facts, choice: each) else { return nil }
                guard !Task.isCancelled else { return nil }
                return Rendered(output: output, preview: Self.preview(output.data))
            }
            let rendered = await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
            guard !Task.isCancelled else { return }
            if let rendered { outputs[key] = rendered } else { failedKeys.insert(key) }
        }
    }

    /// 見本の大きさ（長い辺 1600px）。見本の幅は画面の 74%（6.9 インチで約 320pt・3倍で約 960px）までなので、
    /// 9:16 の長い辺 1600px（幅 900px）で足りる
    nonisolated static let previewMaxPixel: CGFloat = 1600

    nonisolated static func preview(_ data: Data) -> UIImage? {
        #if os(Linux)
        return UIImage(data: data)
        #else
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: previewMaxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
        #endif
    }
}

/// つながった切り替え（板の「表示の切替」・章の模型の `.seg`）。溝は surface-2、選んだ側は surface-8 に白の字 600。
/// 見た目 38＋溝の 3＋3 で当たりは 44（`PassSegment` と同じ作り）
struct TravelStorySegment<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let selection: Item
    let label: KeyPath<Item, String>
    let groupLabel: String
    let idPrefix: String
    var isEnabled: (Item) -> Bool = { _ in true }
    let select: (Item) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let on = item == selection
                let enabled = isEnabled(item)
                Button { select(item) } label: {
                    Text(item[keyPath: label])
                        .font(on ? JPFont.footnote.weight(.semibold) : JPFont.footnote)
                        .foregroundStyle(on ? WebTheme.text : WebTheme.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(WebTheme.minimumScale(forTextSize: 13))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(on ? WebTheme.surface8 : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.3)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("\(idPrefix).\(item.id)")
            }
        }
        .padding(.horizontal, 3)
        .background(WebTheme.sheet, in: RoundedRectangle(cornerRadius: JPRadius.field))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(groupLabel)
    }
}

/// ステッカーの見本の地（透明を表す市松・章の模型の `.cd.st`）
private struct StickerChecker: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = max(8, size.width * 0.06)
            context.fill(Path { $0.addRect(CGRect(origin: .zero, size: size)) }, with: .color(Color(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255)))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
                while x < size.width {
                    context.fill(Path { $0.addRect(CGRect(x: x, y: y, width: cell, height: cell)) },
                                 with: .color(Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2D / 255)))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}
