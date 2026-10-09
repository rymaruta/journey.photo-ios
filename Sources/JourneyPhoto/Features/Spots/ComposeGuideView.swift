import SwiftUI
import UIKit

/// 作例を重ねて撮る（Pro・板 ComposeGuide・2026-10-09）。全画面・黒地。
///
/// 入口は撮影スポットの画面の作例の節（`OfficialSpotView.composeEntry`）。Pro でなければそこで
/// Pro の案内を出すので、この画面は Pro の人だけが開く。
///
/// 板のとおり（390×844）:
/// - 上（板 640pt・端末の高さに合わせて伸び縮み）にカメラの映像、その上に作例を半透明で重ね
///   （既定 0.4・0〜0.8）、三分割の線（白 35%）
/// - 左上に閉じる（44pt の丸・黒 55%・白 12% の縁）、上の札「[撮影地の名前] · 作例 [2] / [6]」
///   （黒 60%・12pt 太字）
/// - 映像の下寄りに案内の札（黒 62%・角 12・13pt）。距離が出せないときは「地平線を下の線に合わせる」だけ
///   （`ComposeGuide.hint` の注記）
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
struct ComposeGuideView: View {

    let spotName: String
    let samples: [SpotSample]

    @StateObject private var camera = ComposeCamera()
    @State private var index = 0
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

    var body: some View {
        VStack(spacing: 0) {
            viewfinder
            controls
        }
        .background { Color.black.ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .task { await camera.start() }
        .onDisappear {
            camera.stop()
            noticeTask?.cancel()
        }
        // 裏に回ったら止め、戻ったら流し直す（撮影の場は OS も止めるが、こちらからも止めて電池を守る）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await camera.start() }
            } else if phase == .background {
                camera.stop()
            }
        }
        .accessibilityIdentifier("composeGuide")
    }

    // MARK: - 映像の枠（板: 上 640pt）

    private var viewfinder: some View {
        // 映像・作例・線は時刻の帯の裏まで敷く（板の上 0〜640）。上の札と案内は安全な範囲に置く
        cameraLayers
            .ignoresSafeArea(edges: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    if let notice { noticeView(notice) }
                    if camera.state == .ready { hintCard }
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
            // 読み上げでは払えないので、切り替えを操作として置く
            .accessibilityAction(named: L("次の作例", "Next example")) {
                switchTo(ComposeGuide.next(after: current, count: samples.count))
            }
            .accessibilityAction(named: L("前の作例", "Previous example")) {
                switchTo(ComposeGuide.previous(before: current, count: samples.count))
            }
    }

    /// 映像の枠の中身（地・映像・作例・三分割の線、または使えない理由）
    private var cameraLayers: some View {
        ZStack {
            // 板のカメラの映像の地（#2a3440）。映像が出るまでの間だけ見える
            Color(red: 0x2A / 255, green: 0x34 / 255, blue: 0x40 / 255)
            if camera.state == .ready {
                CameraPreview(session: camera.session)
                    .accessibilityHidden(true)
                overlay
                thirds
            } else if let blocked = ComposeGuide.blockedText(camera.state) {
                blockedPanel(title: blocked.title, detail: blocked.detail)
            } else {
                ProgressView()
                    .tint(WebTheme.foreground)
                    .accessibilityLabel(L("カメラを準備しています", "Preparing the camera"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// 三分割の線（白 35%・1pt）
    private var thirds: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                for i in 1...2 {
                    let x = w * Double(i) / 3, y = h * Double(i) / 3
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: h))
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
            if !samples.isEmpty {
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

    /// 板: 黒 62%・角 12・左に矢印・13pt。いまは作例に撮った位置が無いので、構図の一言だけ
    /// （`ComposeGuide.hint`）。距離が出せるときだけ上向きの矢印、それ以外は三分割の記号
    private var hintCard: some View {
        let move = ComposeGuide.movement(current: nil, target: nil)
        return HStack(spacing: 10) {
            Image(systemName: move == nil ? "rectangle.split.3x3" : "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WebTheme.foreground)
                .accessibilityHidden(true)
            Text(ComposeGuide.hint(current: nil, target: nil))
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
            opacityRow
            if let sample { credit(sample) }
            HStack {
                thumbButton
                Spacer()
                shutter
                Spacer()
                switchButton
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black)
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
                .lineLimit(2)
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
        .accessibilityValue(ComposeGuide.counterAccessibility(spotName: spotName, index: current, count: samples.count))
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
        announce(ComposeGuide.counterAccessibility(spotName: spotName, index: next, count: samples.count))
    }

    /// 撮って保存し、結果を知らせる
    private func shoot() async {
        guard let data = await camera.capture() else {
            show(ComposeGuide.message(for: .failed), isError: true)
            return
        }
        let outcome = await ComposeCamera.save(data)
        show(ComposeGuide.message(for: outcome), isError: outcome != .saved)
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
