import SwiftUI
import UIKit

/// 作例・構図を重ねて撮る（Pro・板 ComposeGuide・2026-10-09）。全画面・黒地。
///
/// 入口は2つ（Pro の確かめはどちらも `ComposeGuideLauncher`。この画面は Pro の人だけが開く）:
/// - 撮影スポットの画面の作例の節（`OfficialSpotView.composeEntry`＝1枚目から、
///   帯の作例の写真＝押した1枚から・2026-10-10）
/// - 投稿のシートの「構図を重ねて撮る」（2026-10-10・**作例なし**）。上の札・作例のサムネ・濃さ・
///   出典・切り替えを隠し、構図の線だけで撮る。撮ったら左下の「投稿」で投稿画面へ進める（`onPost`）
///
/// **構図（2026-10-10 owner「有名な構図からマイナーな構図まで」）**: 下の黒い面のいちばん上に「構図」の行
/// （小さな絵＋名前＋▾、向きのある構図だけ右に「向き」）。押すと構図のシート（`CompositionPicker`）。
/// 重ね順は 映像 → 作例 → 構図の線 → 切り出し枠の外の暗がり（`CompositionOverlay`）。
/// 構図の切り替えには払いを付けない（作例の左右の払いと紛れる）。選んだものは端末に覚える
/// （`CompositionPreferences`・サーバーに送らない）。
///
/// **映像の枠は撮れる範囲（3:4）に合わせる**（2026-10-10 owner の決定）。以前は空いた面いっぱいに
/// 映像を切り抜いて敷いていて、左右が約 45pt 切れ、線も作例も写真とずれていた。上下の余りは黒い地
///
/// 板のとおり（390×844）:
/// - 上（板 640pt・端末の高さに合わせて伸び縮み）にカメラの映像、その上に作例を半透明で重ね
///   （既定 0.4・0〜0.8）、構図の線（白・既定 35%・2026-10-10 から選べる。以前は三分割だけ）
/// - 左上に閉じる（44pt の丸・黒 55%・白 12% の縁）、上の札「[撮影地の名前] · 作例 [2] / [6]」
///   （黒 60%・12pt 太字）
/// - 映像の下寄りに案内の札（黒 62%・角 12・13pt）。文は構図ごとの一言（`CompositionKind.tip`）。
///   構図が「なし」なら札を出さない（`ComposeGuide.hint(current:target:tip:)`）
/// - 下（板 204pt）は黒: 「作例の濃さ」のスライダー（白）、下段に左「作例」のサムネ（52pt・角 10）、
///   中央シャッター（72pt・白 4pt の輪）、右「作例を切り替える」（52pt の丸）
///
/// **板と変えたところ（PR で報告）**
/// - 作例は**切り抜かずに**（縦横比のまま・`.fit`）重ねる。板は映像の枠いっぱいに敷いているが、
///   作例は切り抜かない決まり（`OfficialSpotView.samplesSection` の注記・docs/spot-samples-commons.md）
/// - スライダーの下に作例の出典の1行（題 / 写真: 作者 / ライセンス / 出どころ）を足した。
///   **Commons・Flickr の CC BY 系は表示の条件**で、重ねて見せる画面でもたどれるようにする。
///   黒地の上なのでリンクは真鍮（CLAUDE.md の owner の好み）
/// - 左のサムネは押すと作例を隠す・出す（板は押した先が無い）
/// - カメラが使えない（許可が無い・制限・カメラが無い）ときは、映像の枠に理由と
///   「設定を開く」（写真の無い画面の主ボタン＝真鍮の塗りに墨）を出す
/// - 下の黒い面のいちばん上に「構図」の行（2026-10-10・板に無い。板の決まりに合わせた）
struct ComposeGuideView: View {

    /// 撮影地の名前（作例なしの入口は nil）
    let spotName: String?
    let samples: [SpotSample]
    /// 撮った1枚を投稿へ進める（投稿のシートの入口だけ）。nil なら「投稿」を出さない
    let onPost: ((CameraCapture) -> Void)?

    @StateObject private var camera = ComposeCamera()
    @StateObject private var level = LevelMotion()
    @State private var index: Int

    /// 構図（nil は「なし」）・向き・線の濃さ
    @State private var composition: CompositionKind?
    @State private var variant: Int
    @State private var lineOpacity: Double
    @State private var showPicker = false
    /// 最後に撮れた1枚（投稿へ進める用）
    @State private var lastShot: ComposeShot?
    private let preferences = CompositionPreferences()

    /// - Parameters:
    ///   - startIndex: 始める作例（作例の帯で押した1枚・2026-10-10）。入口のボタンは 0＝1枚目。
    ///     範囲の外は内側へ戻す（`ComposeGuide.normalized`）
    ///   - initialComposition: 始める構図。nil なら前回の構図（初めてなら三分割）
    init(spotName: String?, samples: [SpotSample], startIndex: Int = 0,
         initialComposition: CompositionKind? = nil, onPost: ((CameraCapture) -> Void)? = nil) {
        self.spotName = spotName
        self.samples = samples
        self.onPost = onPost
        _index = State(initialValue: ComposeGuide.normalized(startIndex, count: samples.count))
        let prefs = CompositionPreferences()
        let kind = initialComposition ?? prefs.lastKind
        _composition = State(initialValue: kind)
        _variant = State(initialValue: kind.map { prefs.variant(for: $0) } ?? 0)
        _lineOpacity = State(initialValue: prefs.lineOpacity)
    }
    @State private var opacity = ComposeGuide.defaultOpacity
    /// 作例を隠している（左のサムネを押した）
    @State private var overlayHidden = false
    /// 撮ったあとの知らせ（数秒で消す）
    @State private var notice: String?
    @State private var noticeIsError = false
    @State private var noticeTask: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: Int { ComposeGuide.normalized(index, count: samples.count) }
    private var sample: SpotSample? { samples.isEmpty ? nil : samples[current] }
    /// 作例なし（投稿のシートの入口）
    private var withoutSamples: Bool { samples.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            viewfinder
            controls
        }
        .background { Color.black.ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .task { await camera.start() }
        .onAppear { updateLevel() }
        .onChange(of: composition) { _, _ in updateLevel() }
        .onDisappear {
            camera.stop()
            level.stop()
            noticeTask?.cancel()
        }
        .sheet(isPresented: $showPicker) {
            CompositionPicker(selected: composition, recents: preferences.recents,
                              variant: { preferences.variant(for: $0) },
                              lineOpacity: $lineOpacity) { picked in
                choose(picked)
            }
        }
        .onChange(of: lineOpacity) { _, value in preferences.setLineOpacity(value) }
        // 裏に回ったら止め、戻ったら流し直す（撮影の場は OS も止めるが、こちらからも止めて電池を守る）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await camera.start() }
            } else if phase == .background {
                camera.stop()
            }
        }
    }

    // MARK: - 映像の枠（板: 上 640pt）

    private var viewfinder: some View {
        // 撮れる範囲（3:4）の枠を、空いた面の真ん中にいちばん大きく置く。余りは黒い地（2026-10-10）
        GeometryReader { geo in
            let size = ComposeGuide.viewfinderSize(width: Double(geo.size.width), height: Double(geo.size.height))
            cameraLayers
                .frame(width: size.width, height: size.height)
                .position(x: Double(geo.size.width) / 2, y: Double(geo.size.height) / 2)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    if let notice { noticeView(notice) }
                    if showsLines || camera.state == .ready, let text = hintText { hintCard(text) }
                }
                // 板: 案内の札は枠の下端から約 40pt 上
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .contentShape(Rectangle())
            // 左右に払って作例を切り替える（短い払いは切り替えない・`ComposeGuide.swiped`）
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        switchTo(ComposeGuide.swiped(index: current, count: samples.count,
                                                     translationWidth: value.translation.width))
                    }
            )
    }

    /// 構図の線を出すか。映像が出ているときだけ（画面写真の試験の鍵があれば、カメラの無い
    /// シミュレータでも線の見た目を撮れるように出す・Debug のみ）
    private var showsLines: Bool {
        composition != nil && (camera.state == .ready || ComposeGuideAccess.previewUnlocked)
    }

    /// 映像の枠の中身（地・映像・作例・構図の線、または使えない理由）
    private var cameraLayers: some View {
        ZStack {
            // 板のカメラの映像の地（#2a3440）。映像が出るまでの間だけ見える
            Color(red: 0x2A / 255, green: 0x34 / 255, blue: 0x40 / 255)
            if camera.state == .ready {
                CameraPreview(session: camera.session)
                    // 2026-10-10 判断: 映像（UIKit の部品）に指を取らせない。枠の左右の払い（作例の切り替え）が
                    // 映像の上で効くように、当たりは外の `contentShape` に任せる（`CameraPreview` の注記）
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                overlay
            } else if let blocked = ComposeGuide.blockedText(camera.state) {
                blockedPanel(title: blocked.title, detail: blocked.detail)
            } else {
                ProgressView()
                    .tint(WebTheme.foreground)
                    .accessibilityLabel(L("カメラを準備しています", "Preparing the camera"))
            }
            // 重ね順: 映像 → 作例 → 構図の線 → 切り出し枠の外の暗がり（`CompositionOverlay`）
            if showsLines, let composition {
                CompositionOverlay(kind: composition, variant: variant, lineOpacity: lineOpacity,
                                   levelDegrees: level.degrees)
            }
        }
        .clipped()
    }

    /// 作例を半透明で重ねる（縦横比のまま・切り抜かない）。読み込み中・失敗は何も重ねない
    @ViewBuilder
    private var overlay: some View {
        if let sample, !overlayHidden {
            AsyncImage(url: sample.src) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                default:
                    Color.clear
                }
            }
            .opacity(ComposeGuide.clampedOpacity(opacity))
            .id(sample.sourceUrl)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - 上（閉じる・作例の番号）

    /// 板: 左に閉じる（44pt の丸）、右へ寄せて札（`justify-content: space-between`）。上は時刻の帯の 5pt 下
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Labels.Common.close)
            .accessibilityIdentifier("composeGuide.close")
            Spacer(minLength: 0)
            // 作例なしの入口では札を出さない（数える作例が無い）
            if !samples.isEmpty, let spotName {
                Text(ComposeGuide.counter(spotName: spotName, index: current, count: samples.count))
                    // 12pt 太字・数字は等幅（送っても札の幅が揺れない）
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(WebTheme.foreground)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .accessibilityLabel(ComposeGuide.counterAccessibility(spotName: spotName, index: current,
                                                                          count: samples.count))
                    .accessibilityIdentifier("composeGuide.counter")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 5)
    }

    // MARK: - 案内の札

    /// 案内の札の文。構図ごとの一言（2026-10-10）。水準器で傾きが読めない端末ではそう言う
    private var hintText: String? {
        if composition == .level, !level.available {
            return L("この端末では傾きを読めません", "This device can't read its tilt")
        }
        return ComposeGuide.hint(current: nil, target: nil, tip: composition?.tip)
    }

    /// 板: 黒 62%・角 12・左に矢印・13pt。いまは作例に撮った位置が無いので、構図の一言だけ
    /// （`ComposeGuide.hint`）。距離が出せるときだけ上向きの矢印、それ以外は格子の記号
    private func hintCard(_ text: String) -> some View {
        let move = ComposeGuide.movement(current: nil, target: nil)
        return HStack(spacing: 10) {
            Image(systemName: move == nil ? "rectangle.split.3x3" : "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WebTheme.foreground)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(WebTheme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("composeGuide.hint")
    }

    /// 撮ったあとの知らせ（写真の上なので白の字・黒の札。成功の記号だけ success の色）
    private func noticeView(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: noticeIsError ? "exclamationmark.circle" : "checkmark.circle.fill")
                .foregroundStyle(noticeIsError ? WebTheme.danger : WebTheme.success)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WebTheme.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.75), in: Capsule())
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .accessibilityIdentifier("composeGuide.notice")
    }

    // MARK: - カメラが使えないとき

    /// 理由と、許可を断ったときだけ「設定を開く」（写真の無い面の主ボタン＝真鍮の塗りに墨）
    private func blockedPanel(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 30))
                .foregroundStyle(WebTheme.faint)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(WebTheme.foreground)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if ComposeGuide.offersSettings(camera.state) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text(L("設定を開く", "Open Settings"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.accentText)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 44)
                        .background(WebTheme.accentFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityIdentifier("composeGuide.openSettings")
            }
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composeGuide.blocked")
    }

    // MARK: - 下（板: 204pt・黒）

    private var controls: some View {
        VStack(spacing: 14) {
            compositionRow
            // 作例なしの入口では、作例の濃さ・出典・サムネ・切り替えを出さない
            if !withoutSamples {
                opacityRow
                if let sample { credit(sample) }
            }
            HStack {
                if withoutSamples { postButton } else { thumbButton }
                Spacer()
                shutter
                Spacer()
                if withoutSamples {
                    // シャッターを真ん中に保つための空き（右の切り替えと同じ幅）
                    Color.clear.frame(width: 52, height: 52).accessibilityHidden(true)
                } else {
                    switchButton
                }
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    // MARK: - 構図の行（2026-10-10）

    /// 下の黒い面のいちばん上: 小さな絵＋名前＋▾（押すと構図のシート）、向きのある構図だけ右に「向き」（44×44）
    private var compositionRow: some View {
        HStack(spacing: 8) {
            Button { showPicker = true } label: {
                HStack(spacing: 10) {
                    CompositionThumbnail(kind: composition, variant: variant, cornerRadius: 3)
                        .frame(width: 24, height: 32)
                    Text(composition?.name ?? CompositionGuide.noneName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WebTheme.muted2)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(CompositionGuide.accessibilityLabel(composition))
            .accessibilityHint(L("構図を選びます", "Choose a composition"))
            .accessibilityIdentifier("composeGuide.composition")
            if let composition, composition.hasVariants {
                Button { cycleVariant(of: composition) } label: {
                    Text(L("向き", "Flip"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WebTheme.foreground)
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CompositionGuide.variantAccessibilityLabel(composition, variant: variant))
                .accessibilityHint(L("次の向きに替えます", "Switches to the next orientation"))
                .accessibilityIdentifier("composeGuide.variant")
            }
        }
    }

    /// 「作例の濃さ」（12pt・白 70%）と白いスライダー（0〜0.8）
    private var opacityRow: some View {
        HStack(spacing: 12) {
            Text(L("作例の濃さ", "Overlay"))
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.7))
                .accessibilityHidden(true)
            Slider(value: $opacity, in: ComposeGuide.opacityRange)
                .tint(WebTheme.foreground)
                .accessibilityLabel(L("作例の濃さ", "Overlay opacity"))
                .accessibilityValue(ComposeGuide.opacityPercent(opacity))
                .accessibilityIdentifier("composeGuide.opacity")
        }
        .disabled(overlayHidden || samples.isEmpty)
    }

    /// 作例の出典の1行（`OfficialSpotView.sampleCreditLink` と同じ書き方・当たりは 44pt 以上）
    private func credit(_ sample: SpotSample) -> some View {
        CreditLinksMenu(links: sample.creditLinks, accessibilityLabel: sample.credit) {
            Text(sample.linkedCredit)
                .tint(WebTheme.accent)
                .font(.caption)
                .foregroundStyle(WebTheme.muted2)
                // **切り詰めない**（題・作者・ライセンス・出どころを必ず全部出す・`SpotSample` の注記）
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("composeGuide.credit")
    }

    /// 左: 作例のサムネ（52pt・角 10・白 30% の縁）。押すと作例を隠す・出す
    private var thumbButton: some View {
        Button {
            overlayHidden.toggle()
            announce(overlayHidden ? L("作例を隠しました", "Overlay hidden") : L("作例を表示しました", "Overlay shown"))
        } label: {
            ZStack {
                if let sample {
                    RemoteImage(url: sample.thumbnail(maxWidth: 250), contentMode: .fill)
                } else {
                    WebTheme.surface
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            // 隠している間は薄く（色だけでなく読み上げの値でも伝える）
            .opacity(overlayHidden ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(samples.isEmpty)
        .accessibilityLabel(L("作例", "Example"))
        .accessibilityValue(overlayHidden ? L("隠しています", "Hidden") : L("重ねています", "Shown"))
        .accessibilityHint(overlayHidden ? L("作例を重ねます", "Shows the example overlay")
                                         : L("作例を隠します", "Hides the example overlay"))
        .accessibilityIdentifier("composeGuide.thumb")
    }

    /// 左（作例なしの入口）: 撮った1枚を投稿へ進める（52pt・角 10）。撮るまでは空き。
    /// 写真の無い黒い面の上の押せるものなので、印は真鍮（CLAUDE.md の owner の好み）
    @ViewBuilder
    private var postButton: some View {
        if let onPost, let shot = lastShot {
            Button {
                onPost(shot.cameraCapture)
                dismiss()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                    Text(L("投稿", "Post"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(WebTheme.accent)
                .frame(width: 52, height: 52)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WebTheme.accent, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("撮った写真を投稿する", "Post the photo you took"))
            .accessibilityIdentifier("composeGuide.post")
        } else {
            Color.clear.frame(width: 52, height: 52).accessibilityHidden(true)
        }
    }

    /// 中央: シャッター（72pt・白 4pt の輪・内側に白の丸）
    private var shutter: some View {
        Button { Task { await shoot() } } label: {
            Circle()
                .fill(WebTheme.foreground)
                .padding(8)
                .frame(width: 72, height: 72)
                .overlay(Circle().strokeBorder(WebTheme.foreground, lineWidth: 4))
        }
        .buttonStyle(.plain)
        .disabled(camera.state != .ready || camera.isCapturing)
        .opacity(camera.state == .ready ? 1 : 0.4)
        .accessibilityLabel(L("撮影", "Take photo"))
        .accessibilityHint(L("撮った写真は端末の写真に保存されます", "The photo is saved to your Photos"))
        .accessibilityIdentifier("composeGuide.shutter")
    }

    /// 右: 作例を切り替える（52pt の丸・白 30% の縁）。1枚しか無ければ押せない
    private var switchButton: some View {
        Button { switchTo(ComposeGuide.next(after: current, count: samples.count)) } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(WebTheme.foreground)
                .frame(width: 52, height: 52)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(samples.count < 2)
        .opacity(samples.count < 2 ? 0.4 : 1)
        .accessibilityLabel(L("作例を切り替える", "Switch example"))
        .accessibilityValue(ComposeGuide.counterAccessibility(spotName: spotName ?? "", index: current, count: samples.count))
        // 読み上げでは払えないので、前へ戻す操作もここに置く。**枠（映像の上の重ね）には付けない**——
        // 中の閉じるボタンまで1つの要素にまとまり、押せなくなる（画面写真の試験で閉じられなかった）
        .accessibilityAction(named: L("前の作例", "Previous example")) {
            switchTo(ComposeGuide.previous(before: current, count: samples.count))
        }
        .accessibilityIdentifier("composeGuide.switch")
    }

    // MARK: - 動き

    /// 作例を替える。「視差効果を減らす」のときは動きを付けずに替える
    private func switchTo(_ next: Int) {
        guard next != current else { return }
        if reduceMotion {
            index = next
        } else {
            withAnimation(.easeOut(duration: 0.2)) { index = next }
        }
        announce(ComposeGuide.counterAccessibility(spotName: spotName ?? "", index: next, count: samples.count))
    }

    /// 撮って保存し、結果を知らせる。作例なしの入口では、撮れた1枚を「投稿」へ進められるようにする
    /// （写真への保存を断られても、撮れた1枚は投稿できる）
    private func shoot() async {
        guard let shot = await camera.capture() else {
            show(ComposeGuide.message(for: .failed), isError: true)
            return
        }
        lastShot = shot
        let outcome = await ComposeCamera.save(shot.data)
        show(ComposeGuide.message(for: outcome), isError: outcome != .saved)
    }

    // MARK: - 構図

    /// 構図を選んだ（シートから）。覚えて、読み上げで伝える
    private func choose(_ picked: CompositionKind?) {
        composition = picked
        variant = picked.map { preferences.variant(for: $0) } ?? 0
        preferences.select(picked)
        announce(CompositionGuide.accessibilityLabel(picked))
    }

    /// 次の向きへ（払いは付けない・作例の払いと紛れる）
    private func cycleVariant(of kind: CompositionKind) {
        variant = kind.nextVariant(after: variant)
        preferences.setVariant(variant, for: kind)
        announce(CompositionGuide.variantAccessibilityLabel(kind, variant: variant))
    }

    /// 水準器を選んでいる間だけ傾きを読む（電池を守る）
    private func updateLevel() {
        if composition == .level { level.start() } else { level.stop() }
    }

    /// 知らせを出して数秒で消す。読み上げにも伝える
    private func show(_ text: String, isError: Bool) {
        noticeTask?.cancel()
        noticeIsError = isError
        if reduceMotion {
            notice = text
        } else {
            withAnimation(.easeOut(duration: 0.2)) { notice = text }
        }
        announce(text)
        noticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: isError ? 4_000_000_000 : 2_000_000_000)
            guard !Task.isCancelled else { return }
            if reduceMotion {
                notice = nil
            } else {
                withAnimation(.easeOut(duration: 0.2)) { notice = nil }
            }
        }
    }

    /// 読み上げ（焦点を動かさずに伝える・`SavedSpotsMapView.announce` と同じ）
    private func announce(_ text: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }
}
