import SwiftUI
import PhotosUI
import UIKit
import ImageIO

/// 作例・構図を重ねて撮る（板 ComposeGuide・2026-10-09）。全画面・黒地。
///
/// 2026-10-17 判断（owner）: **全員無料。** 誰でも開ける（ログインしていなくても・圏外でも）。
/// ログインが要るのは「投稿」で投稿画面へ進んだ先だけ（`UploadView` がログインを求める）。
///
/// 入口は2つ（開く流れはどちらも `ComposeGuideLauncher`）:
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
///
/// **2026-10-16（owner「回転がないのしんどい」「UI を隠さないと全体が見れない」「標準のカメラ App と遜色なく」）**
/// - 上の帯（閉じる・札・小さな丸の「向き」「右に90度回す」「隠す」）は**映像の外の黒い帯**へ。構図の一言も
///   映像の上から下の帯へ移した（線と重ねない）。板は映像の上に重ねている——板と変えたところ
/// - 回す: 90° ずつのボタンと2本指のひねり（0/90/180/270 に吸い付く）。線も参考写真も同じ角度。
///   順と 90°/270° の描き方は `CompositionGuide.screenMarks` の注記
/// - 隠す: 上下の帯ごと消し、撮れる範囲（3:4）を画面いっぱいに出して縁を細い白で示す。映像を1回タップで戻す。
///   シャッターは枠の下の余りに置けるときだけ残し、いつでも音量ボタン（`CaptureButtonInteraction`）と
///   読み上げの「撮影」（2本指のダブルタップ）で撮れる
/// - 拡大の段（0.5×/1×/2×/望遠・端末のレンズに応じて）とピンチ、タップでピントと明るさ・長押しで固定・
///   上下にずらして明るさ、シャッターの振動と暗転、撮った直後の左下の見本。指の割り当ては「指」の節の注記
struct ComposeGuideView: View {

    /// 撮影地の名前（作例なしの入口は nil）
    let spotName: String?
    let samples: [SpotSample]
    /// 撮った1枚を投稿へ進める（投稿のシートの入口・撮影スポットの作例の入口）。nil なら「投稿」を出さない
    let onPost: ((CameraCapture) -> Void)?

    @StateObject private var camera = ComposeCamera()
    /// 傾き（水準器・持った向き）。🔴 **`@State` で持つだけで見張らない**——見張ると角度が変わるたびに
    /// この画面全体が描き直される。角度は線の子の View（`CompositionLines`）だけが見る（2026-10-10）
    @State private var level = LevelMotion()
    /// 持った向き（0〜3）。横持ちなら構図の線を写真の向きに回す。変わったときだけ `LevelMotion` が知らせる
    @State private var quarterTurns = 0
    @State private var index: Int
    @State private var reference = ReferenceOverlayState()
    @State private var librarySelection: PhotosPickerItem?
    @State private var libraryImage: UIImage?
    @State private var loadingLibrary = false
    /// ライブラリから読めた回数（選び直したら参考写真が替わった合図・`referenceIdentity`）
    @State private var libraryLoads = 0
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinchFactor = 1.0

    /// 構図（nil は「なし」）・向き・線の濃さ
    @State private var composition: CompositionKind?
    @State private var variant: Int
    @State private var lineOpacity: Double
    /// 構図の線と参考写真を回した角度（時計回りの度・2026-10-16）。その構図を選び直すまで保つ。
    /// 2026-10-18: 横長の参考写真は開いたときから 90° 回しておく（`ComposeControls.autoRotation`）
    @State private var rotation: Double
    /// 人が回すボタン・ひねりで回したか（2026-10-18）。true の間は持った向きが変わっても自動で回し直さない。
    /// 参考写真・構図が替わったら false（自動に戻す・`ComposeControls.decidedRotation`）
    @State private var rotationManual = false
    /// 2本指でひねっている間の角度（指のそのままの値。効かせるかは `twistState`）
    @GestureState private var twist = 0.0
    /// ひねりを効かせたか・拡大の指とみなしたか（2026-10-16 確かめ役の指摘「つまむたびに回る」・
    /// `ComposeControls.nextTwist`）。指を離す・取り消されたら戻す
    @State private var twistState = ComposeControls.Twist()
    /// いまつまんでいる量（1 が無し）。ひねりと拡大の読み分けに使う
    @State private var pinchMagnification = 1.0
    /// 2本指でつまんでいる間だけ true（取り消されても自動で戻る）
    @GestureState private var pinchActive = false
    /// 1本指が触れている間だけ true（取り消されても自動で戻る・後始末の合図）
    @GestureState private var touchActive = false
    /// つまんで寄り始めたときのカメラの倍率
    @State private var zoomStart: Double?
    /// 最後に2本指（ひねる・つまむ）を使った時刻。直後の1本指のタップ・払いを読まない
    @State private var lastMultiTouch: Date?
    /// UI（上下の帯・ボタン・札）を隠して、撮れる範囲の全体を見る（2026-10-16 owner の声）
    @State private var uiHidden = false
    /// ピントの枠（映像の枠の上の点・pt）。タップ・長押しで出す
    @State private var focusPoint: CGPoint?
    @State private var focusHideTask: Task<Void, Never>?
    /// 明るさの補正（EV）。ピントの枠の横を上下にずらして変える
    @State private var exposureBias = 0.0
    /// いまの指（1本）の始まり。長押しの判定と明るさの始まりの値を持つ
    @State private var touch: TouchTrack?
    @State private var pressTask: Task<Void, Never>?
    /// 撮った回数（シャッターの振動の合図）と、押した瞬間の暗転
    @State private var shotCount = 0
    @State private var shutterFlash = false
    @State private var showPicker = false
    /// 最後に撮れた1枚（投稿へ進める用）
    @State private var lastShot: ComposeShot?
    /// 最後に撮れた1枚の小さな絵（「投稿」のカプセルに入れる・v2）。撮ったときに一度だけ縮めて作る
    @State private var lastShotThumb: UIImage?
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
        // 2026-10-18 判断: 作例を重ねて開くときは、作例の縦横で初めの向きを決める（横長なら 90°）。
        // 作例なしの入口は今まで通り覚えた角度（`ComposeControls.decidedRotation` の注記）
        let first = samples.isEmpty ? nil : samples[ComposeGuide.normalized(startIndex, count: samples.count)]
        let auto = first.map {
            ComposeControls.autoRotation(referenceWidth: $0.width, referenceHeight: $0.height,
                                         frameAspect: ComposeGuide.frameAspect, heldQuarterTurns: 0)
        }
        _rotation = State(initialValue: ComposeControls.decidedRotation(
            .opened, current: 0, manual: false, auto: auto, remembered: prefs.rotation(for: kind)) ?? 0)
    }

    /// 1本の指の始まり（映像の枠の上）
    struct TouchTrack {
        let start: Date
        let location: CGPoint
        var adjustedExposure = false
        var locked = false
        var exposureStart = 0.0
    }
    @State private var opacity = ComposeGuide.defaultOpacity
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
    private var hasReference: Bool {
        reference.source == .samples ? sample != nil : libraryImage != nil
    }
    /// 参考写真を重ねて見せているか
    private var referenceShown: Bool { hasReference && !reference.hidden }
    /// ライブラリの写真を重ねている（ピンチはその写真の大きさに効かせる・以前のまま）
    private var libraryShown: Bool { reference.source == .library && libraryImage != nil && !reference.hidden }
    /// 回せるか。構図の線（水準器は除く——傾きは重さの向きが基準なので回さない）か、参考写真があるとき
    private var canRotate: Bool {
        (composition != nil && composition != .level) || referenceShown
    }
    /// いま重ねている参考写真の縦横から決めた、自動の向き（参考写真が無ければ nil・2026-10-18）
    private var autoReferenceRotation: Double? {
        let size: (width: Double, height: Double)?
        if reference.source == .samples, let sample {
            size = (sample.width, sample.height)
        } else if reference.source == .library, let libraryImage {
            size = (Double(libraryImage.size.width), Double(libraryImage.size.height))
        } else {
            size = nil
        }
        guard let size else { return nil }
        return ComposeControls.autoRotation(referenceWidth: size.width, referenceHeight: size.height,
                                            frameAspect: ComposeGuide.frameAspect,
                                            heldQuarterTurns: quarterTurns, mirrored: reference.mirrored)
    }
    /// 重ねている参考写真の見分け（替わったら向きを決め直す）。隠しても替わらない
    private var referenceIdentity: String? {
        if reference.source == .samples, let sample { return "sample:" + sample.sourceUrl.absoluteString }
        if reference.source == .library, libraryImage != nil { return "library:\(libraryLoads)" }
        return nil
    }
    /// 描くときの角度（累積・ひねっている間も 0/90/180/270 の近くでは吸い付く）。
    /// 2026-10-16（確かめ役の指摘）: 角度は 0〜360 に丸めず累積で持つ。270° から右へ回すと 360° になり、
    /// 参考写真は逆回りせずに右へ 90° 回る（線・読み上げ・覚える値は 0〜360 に戻して使う）
    private var shownRotation: Double {
        ComposeControls.snappedCumulative(rotation + ComposeControls.effectiveTwist(rotation: twist, state: twistState))
    }
    private var canShoot: Bool {
        ComposeControls.canShoot(ready: camera.state == .ready, capturing: camera.isCapturing, sheetOpen: showPicker)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 2026-10-16 判断（owner「標準のカメラ App と遜色なく」）: 上の帯は映像の外の黒い帯に置き、
            // 構図の線と重ねない。隠している間は上下の帯ごと消し、撮れる範囲を画面いっぱいに見せる
            if !uiHidden { topBar }
            viewfinder
            if !uiHidden { controls }
        }
        .background { Color.black.ignoresSafeArea() }
        // 音量ボタンで撮る（隠している間も・標準のカメラ App と同じ）
        .background {
            CaptureButtonInteraction(enabled: canShoot) { Task { await shootIfReady() } }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        // シャッターの押し心地（軽い振動）・0/90/180/270 に吸い付いたときの軽い合図
        .sensoryFeedback(.impact(weight: .light), trigger: shotCount)
        // 吸い付いたときだけ鳴らす（-1 に戻るときは鳴らさない）
        .sensoryFeedback(.selection, trigger: snapTrigger) { old, new in
            ComposeControls.snapFeedbackFires(old: old, new: new)
        }
        // 読み上げ: 2本指のダブルタップで撮る・こすって隠すのをやめる（隠している間はボタンが無い）
        .accessibilityAction(.magicTap) { Task { await shootIfReady() } }
        .accessibilityAction(.escape) {
            if uiHidden { setHidden(false) } else { dismiss() }
        }
        .preferredColorScheme(.dark)
        .task { await camera.start() }
        .onAppear { updateLevel() }
        .onChange(of: composition) { _, _ in updateLevel() }
        // 2026-10-18: 参考写真が替わったら、その縦横で向きを決め直す。持った向きが変わったら、
        // 人が回していなければ写真が立つ側へ（`ComposeControls.decidedRotation`）
        .onChange(of: referenceIdentity) { _, _ in applyAutoRotation(.referenceChanged) }
        .onChange(of: quarterTurns) { _, _ in applyAutoRotation(.heldTurned) }
        .onDisappear {
            camera.stop()
            // 写っているものの見張りを外す（確かめ役の指摘・開き直したら `ComposeCamera.run` が付け直す）
            camera.stopObservingSubjectArea()
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
        .onChange(of: camera.focusResetCount) { _, _ in focusPoint = nil }
        // 指が取り消されたときの後始末（`touchActivityChanged`・`multiTouchChanged`）
        .onChange(of: touchActive) { _, active in touchActivityChanged(active) }
        .onChange(of: twist) { _, _ in multiTouchChanged() }
        .onChange(of: pinchActive) { _, _ in multiTouchChanged() }
        .onChange(of: librarySelection) { _, item in
            if let item { Task { await loadLibraryImage(item) } }
        }
        // 裏に回ったら止め、戻ったら流し直す（撮影の場は OS も止めるが、こちらからも止めて電池を守る）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await camera.start() }
                updateLevel()
            } else if phase == .background {
                camera.stop()
                // 傾きの見張りも止める（裏で 30 回/秒 動かし続けない・確かめ役の指摘）
                level.stop()
            }
        }
    }

    // MARK: - 映像の枠（板: 上 640pt）

    private var viewfinder: some View {
        // 撮れる範囲（3:4）の枠を、空いた面の真ん中にいちばん大きく置く。余りは黒い地（2026-10-10）。
        // 2026-10-16 判断: 上下の帯は黒のまま（標準のカメラ App の「帯を半透明にして外の映像を透かす」は、
        // 撮れる写真が 4:3 で**枠の外に映像が無い**ので、透かしても見えるものが無い）
        GeometryReader { geo in
            let size = ComposeGuide.viewfinderSize(width: Double(geo.size.width), height: Double(geo.size.height))
            let frame = CGSize(width: size.width, height: size.height)
            ZStack {
                cameraLayers
                    .frame(width: size.width, height: size.height)
                    // 押した瞬間の暗転（シャッターの手応え・標準のカメラ App と同じ）
                    .overlay { Color.black.opacity(shutterFlash ? 1 : 0).allowsHitTesting(false) }
                    .overlay { focusOverlay(frame: frame) }
                    .overlay(alignment: .top) { lockBadge }
                    .overlay(alignment: .bottom) {
                        if let notice { noticeView(notice).padding(.horizontal, 16).padding(.bottom, 16) }
                    }
                    // 隠している間は、撮れる範囲（保存される 3:4）の縁を細い白で示す（暗い景色でも枠が分かる）
                    .overlay {
                        if uiHidden {
                            Rectangle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(touchGesture(frame: frame))
                    // つまんで寄る。ライブラリの写真を重ねている間は、その写真の大きさに効かせる（以前のまま）
                    .simultaneousGesture(zoomGesture, including: libraryShown && !uiHidden ? .subviews : .all)
                    .simultaneousGesture(twistGesture)
                    .accessibilityIdentifier("composeGuide.viewfinder")
                    .position(x: Double(geo.size.width) / 2, y: Double(geo.size.height) / 2)
                // 隠している間のシャッター: 枠の下の黒い余りに置けるときだけ（枠に重ねない）。
                // 置けなければ音量ボタン・読み上げの「撮影」（2本指のダブルタップ）で撮る
                if uiHidden, ComposeControls.hiddenShutterFits(containerHeight: Double(geo.size.height),
                                                               frameHeight: size.height, shutter: Self.shutterSize) {
                    shutter
                        .position(x: Double(geo.size.width) / 2,
                                  y: Double(geo.size.height) - (Double(geo.size.height) - size.height) / 4)
                }
                // 隠している間、読み上げでは UI を戻すボタンとして読む（指のタップの代わり）
                if uiHidden {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(L("操作を表示", "Show controls"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { setHidden(false) }
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("composeGuide.showUI")
                }
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    // MARK: - 指（2026-10-16・標準のカメラ App にそろえる）
    //
    // 2026-10-16 判断（指の割り当て。ぶつからないように1つの指の流れで読み分ける・`ComposeControls.touchEnd`）:
    // - 1本指のタップ＝その場所にピントと明るさ。**UI を隠している間は、タップは UI を戻すだけ**（ピントは動かさない）
    // - 長押し（0.6 秒）＝ピントと明るさを固定（AE/AF ロック）。タップで合わせ直すと外れる
    // - ピントの枠が出ている間に上下へずらす＝明るさ（上で明るく）
    // - 左右に払う＝作例を替える（以前のまま・作例を重ねているときだけ）
    // - 2本指でつまむ＝寄る・引く、2本指でひねる＝構図の線と参考写真を回す。2本指の直後の
    //   1本指の動きはタップ・払いとみなさない（ひねった指を離したときに作例が替わらない）
    // - ライブラリの写真を重ねている間は、その写真を動かす指（ドラッグ・つまむ）が先（以前のまま）。
    //   その間は上下にずらしても明るさは変えない（写真を動かす指と紛れる）
    // それまで、この画面にピント合わせのタップは**無かった**（確かめた）。ぶつかる相手は払いと写真の指だけ

    private func touchGesture(frame: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touchActive) { _, state, _ in state = true }
            .onChanged { value in touchChanged(value, frame: frame) }
            .onEnded { value in touchEnded(value, frame: frame) }
    }

    /// 指が取り消された（`onEnded` が来ない）ときの後始末。2026-10-16（確かめ役の指摘）: 以前は `touch` が
    /// 残り、長押しの処理が勝手に AE/AF ロックをかけた。ふつうに離したときは `onEnded` が先に片づけるので、
    /// ここは一拍おいて、同じ指がまだ残っていたら消す
    private func touchActivityChanged(_ active: Bool) {
        guard !active else { return }
        let started = touch?.start
        Task { @MainActor in
            guard let started, touch?.start == started, !touchActive else { return }
            pressTask?.cancel()
            touch = nil
        }
    }

    /// 2本指が取り消されたときの後始末（ひねり・つまむの状態を戻す）。離したときは `onEnded` の後に来る
    private func multiTouchChanged() {
        Task { @MainActor in
            if twist == 0 { twistState = ComposeControls.Twist() }
            if !pinchActive {
                pinchMagnification = 1
                zoomStart = nil
            }
        }
    }

    private func touchChanged(_ value: DragGesture.Value, frame: CGSize) {
        if touch == nil {
            touch = TouchTrack(start: Date(), location: value.startLocation, exposureStart: exposureBias)
            pressTask?.cancel()
            guard !uiHidden else { return }
            let location = value.startLocation
            pressTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(ComposeControls.longPressSeconds * 1_000_000_000))
                guard !Task.isCancelled, touchActive, var t = touch, !t.adjustedExposure,
                      !ComposeControls.isAfterMultiTouch(last: lastMultiTouch, now: Date()) else { return }
                t.locked = true
                touch = t
                focus(at: location, frame: frame, lock: true)
            }
        }
        let dx = Double(value.translation.width), dy = Double(value.translation.height)
        if abs(dx) > ComposeControls.tapSlop || abs(dy) > ComposeControls.tapSlop { pressTask?.cancel() }
        guard !uiHidden, !libraryShown, var t = touch,
              ComposeControls.isExposureDrag(dx: dx, dy: dy, focusShown: focusPoint != nil,
                                             afterMultiTouch: ComposeControls.isAfterMultiTouch(last: lastMultiTouch,
                                                                                               now: Date())) else { return }
        t.adjustedExposure = true
        touch = t
        exposureBias = ComposeControls.exposureBias(start: t.exposureStart, dy: dy,
                                                    min: camera.exposureRange.lowerBound,
                                                    max: camera.exposureRange.upperBound)
        camera.setExposureBias(exposureBias)
        keepFocusShown()
    }

    private func touchEnded(_ value: DragGesture.Value, frame: CGSize) {
        pressTask?.cancel()
        let t = touch
        touch = nil
        let outcome = ComposeControls.touchEnd(
            dx: Double(value.translation.width), dy: Double(value.translation.height),
            seconds: Date().timeIntervalSince(t?.start ?? Date()),
            adjustedExposure: t?.adjustedExposure ?? false, locked: t?.locked ?? false,
            afterMultiTouch: ComposeControls.isAfterMultiTouch(last: lastMultiTouch, now: Date()))
        switch outcome {
        case .tap:
            if uiHidden {
                setHidden(false)
            } else {
                focus(at: value.startLocation, frame: frame, lock: false)
            }
        case .swipe(let dx):
            // 左右に払って作例を切り替える（短い払いは切り替えない・`ComposeGuide.swiped`）
            guard !uiHidden, reference.source == .samples else { return }
            switchTo(ComposeGuide.swiped(index: current, count: samples.count, translationWidth: dx))
        case .none:
            break
        }
    }

    /// つまんで寄る（標準のカメラ App と同じく滑らかに）
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchActive) { _, state, _ in state = true }
            .onChanged { value in
                lastMultiTouch = Date()
                pressTask?.cancel()
                pinchMagnification = Double(value.magnification)
                // ひねりとして効いている間は寄らない（回すつもりの指で拡大が動かない）
                guard !twistState.engaged else { return }
                let start = zoomStart ?? camera.zoomFactor
                if zoomStart == nil { zoomStart = start }
                camera.setZoom(factor: ComposeControls.pinchedFactor(start: start,
                                                                     magnification: Double(value.magnification),
                                                                     levels: camera.zoomLevels), animated: false)
            }
            .onEnded { _ in
                lastMultiTouch = Date()
                zoomStart = nil
                pinchMagnification = 1
            }
    }

    /// 2本指でひねって回す（0/90/180/270 の近くでは吸い付く・`CompositionGuide.snappedRotation`）
    private var twistGesture: some Gesture {
        RotateGesture()
            .updating($twist) { value, state, _ in
                state = value.rotation.degrees
            }
            .onChanged { value in
                lastMultiTouch = Date()
                pressTask?.cancel()
                // つまむ量が先に大きければ拡大の指、ひねりが 15° を越えたら回す指（`ComposeControls.nextTwist`）
                twistState = ComposeControls.nextTwist(twistState, rotation: value.rotation.degrees,
                                                       magnification: pinchMagnification)
            }
            .onEnded { value in
                lastMultiTouch = Date()
                let state = twistState
                twistState = ComposeControls.Twist()
                guard canRotate, state.engaged else { return }
                setRotation(ComposeControls.snappedCumulative(
                    rotation + ComposeControls.effectiveTwist(rotation: value.rotation.degrees, state: state)))
            }
    }

    /// 吸い付いたときの合図（ひねりが効いていて 0/90/180/270 に乗ったら 0〜3、ほかは -1）
    private var snapTrigger: Int {
        ComposeControls.snapSignal(shownRotation: shownRotation, baseRotation: rotation,
                                   twisting: twistState.engaged && canRotate)
    }

    /// その点にピントと明るさを合わせ、枠を出す
    private func focus(at location: CGPoint, frame: CGSize, lock: Bool) {
        guard camera.state == .ready else { return }
        let p = ComposeControls.devicePoint(x: Double(location.x), y: Double(location.y),
                                            width: Double(frame.width), height: Double(frame.height))
        exposureBias = 0
        camera.focus(at: p, lock: lock)
        focusPoint = location
        if lock {
            focusHideTask?.cancel()
            announce(L("ピントと明るさを固定しました", "Focus and exposure locked"))
        } else {
            keepFocusShown()
        }
    }

    /// ピントの枠を少しの間出しておく（固定しているときは出したまま）
    private func keepFocusShown() {
        focusHideTask?.cancel()
        guard !camera.focusLocked else { return }
        focusHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, !camera.focusLocked else { return }
            withAnimation(.easeOut(duration: 0.2)) { focusPoint = nil }
        }
    }

    /// ピントの枠（写真の上なので白・板の決まり）と、右に明るさの印（太陽）。上下にずらすと動く
    @ViewBuilder
    private func focusOverlay(frame: CGSize) -> some View {
        if let p = focusPoint, !uiHidden {
            let box = 72.0
            ZStack {
                Rectangle()
                    .strokeBorder(WebTheme.foreground, lineWidth: 1.5)
                    .frame(width: box, height: box)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WebTheme.foreground)
                    .shadow(color: .black.opacity(0.4), radius: 1)
                    .offset(x: box / 2 + 14,
                            y: -exposureBias / max(camera.exposureRange.upperBound, 0.1) * box / 2)
            }
            .position(x: min(max(Double(p.x), box / 2), Double(frame.width) - box / 2),
                      y: min(max(Double(p.y), box / 2), Double(frame.height) - box / 2))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// AE/AF ロックの札（写真の上なので黒 60% に白の字・上の札と同じ形）
    @ViewBuilder
    private var lockBadge: some View {
        if camera.focusLocked, !uiHidden {
            Text(L("AE/AF ロック", "AE/AF LOCK"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(WebTheme.foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6), in: Capsule())
                .padding(.top, 10)
                .allowsHitTesting(false)
                .accessibilityIdentifier("composeGuide.focusLock")
        }
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
            // 画面写真の試験の鍵があるときだけ（Debug のみ・2026-10-18）: カメラの無いシミュレータでも
            // 作例の重なり（横長の作例を 90° 回して収めた向き）を絵に残す
            if camera.state != .ready, ComposeGuideAccess.previewUnlocked {
                overlay
            }
            // 重ね順: 映像 → 作例 → 構図の線 → 切り出し枠の外の暗がり（`CompositionOverlay`）
            if showsLines, let composition {
                CompositionLines(kind: composition, variant: variant, lineOpacity: lineOpacity,
                                 // 参考写真を重ねている間は、線も作例と同じ向き（2026-10-18・`linesQuarterTurns`）
                                 quarterTurns: ComposeControls.linesQuarterTurns(
                                    held: quarterTurns, kind: composition, referenceShown: referenceShown),
                                 rotationDegrees: shownRotation, level: level)
            }
        }
        .clipped()
    }

    /// 参考写真を回す（構図の線と同じ角度・2026-10-16）。90°/270° のときは**縦横を入れ替えた枠に収めてから**
    /// 回す——線と同じく、回した後の写真が撮れる範囲にちょうど収まる（引き伸ばさない・切り抜かない）。
    /// 順は線と同じ「反転（ライブラリの左右反転）→ 回転 → 指で動かした位置」
    private func rotatedReference<Content: View>(_ content: Content) -> some View {
        GeometryReader { geo in
            // 縦横の入れ替えは決まった角度で（ひねりの途中 45° で写真の大きさが跳ねない・確かめ役の指摘）
            let swap = ComposeControls.referenceSwapsAxes(committedRotation: rotation)
            content
                .frame(width: swap ? geo.size.height : geo.size.width, height: swap ? geo.size.width : geo.size.height)
                .rotationEffect(.degrees(shownRotation))
                .position(x: Double(geo.size.width) / 2, y: Double(geo.size.height) / 2)
        }
    }

    /// 作例を半透明で重ねる（縦横比のまま・切り抜かない）。読み込み中・失敗は何も重ねない
    @ViewBuilder
    private var overlay: some View {
        if !reference.hidden {
            if reference.source == .samples, let sample {
                rotatedReference(
                    AsyncImage(url: sample.src) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit)
                        default:
                            Color.clear
                        }
                    }
                )
                .opacity(ComposeGuide.clampedOpacity(opacity))
                .id(sample.sourceUrl)
                .transition(.opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else if reference.source == .library, let libraryImage {
                // 写真は画面上だけの層。ComposeCamera.capture/save に渡すのはカメラの出力だけ。
                rotatedReference(
                    Image(uiImage: libraryImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(x: (reference.mirrored ? -1 : 1) * reference.scale * pinchFactor,
                                     y: reference.scale * pinchFactor)
                )
                    .offset(x: reference.offsetX + Double(dragTranslation.width),
                            y: reference.offsetY + Double(dragTranslation.height))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    // 2026-10-16: 動かし始めの幅を 0 → 4pt に。タップ（ピント）を外の指に通す
                    .gesture(DragGesture(minimumDistance: 4)
                        .updating($dragTranslation) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            reference.moveBy(x: Double(value.translation.width), y: Double(value.translation.height))
                        })
                    .simultaneousGesture(MagnificationGesture()
                        .updating($pinchFactor) { value, state, _ in state = value }
                        .onEnded { value in reference.setScale(reference.scale * value) })
                    // 隠している間は写真を動かさない（タップは UI を戻すだけ）
                    .allowsHitTesting(!uiHidden)
                    .opacity(ComposeGuide.clampedOpacity(opacity))
                    .accessibilityLabel(L("写真ライブラリの参考写真", "Reference photo from your library"))
            }
        }
    }

    // MARK: - 上の帯（閉じる・作例の番号・向き・回す・隠す）

    /// 映像の外の黒い帯（2026-10-16）。左に閉じる、札、右に標準のカメラ App の上の帯のような小さな丸
    /// （向き・回す・隠す）。黒い地の上なので、回している合図だけ真鍮（CLAUDE.md の owner の好み）
    private var topBar: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                roundIcon("xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Labels.Common.close)
            .accessibilityIdentifier("composeGuide.close")
            // 作例なしの入口では札を出さない（数える作例が無い）
            if reference.source == .samples, !samples.isEmpty, let spotName {
                Text(ComposeGuide.counter(spotName: spotName, index: current, count: samples.count))
                    // 12pt 太字・数字は等幅（送っても札の幅が揺れない）
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(WebTheme.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(ComposeGuide.counterAccessibility(spotName: spotName, index: current,
                                                                          count: samples.count))
                    .accessibilityIdentifier("composeGuide.counter")
            }
            Spacer(minLength: 4)
            if let composition, composition.hasVariants { variantButton(composition) }
            if canRotate { rotateButton }
            hideButton
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    /// 上の帯の小さな丸の見た目（当たりは 44）
    static let roundVisual: CGFloat = 34

    /// 上の帯の小さな丸（白 12% の丸に白の印。`tinted` なら印を真鍮＝いま効いている合図）
    private func roundIcon(_ systemName: String, tinted: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tinted ? WebTheme.accent : WebTheme.foreground)
            .frame(width: Self.roundVisual, height: Self.roundVisual)
            .background(Color.white.opacity(0.12), in: Circle())
            .frame(width: WebTheme.minTapTarget, height: WebTheme.minTapTarget)
            .contentShape(Rectangle())
    }

    /// 向き（反転）。2026-10-16: 下の「構図」の行から上の帯の小さな丸へ移した（回す・隠すと並べる）
    private func variantButton(_ composition: CompositionKind) -> some View {
        Button { cycleVariant(of: composition) } label: {
            roundIcon("arrow.left.and.right.righttriangle.left.righttriangle.right")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CompositionGuide.variantAccessibilityLabel(composition, variant: variant))
        .accessibilityHint(L("次の向きに替えます", "Switches to the next orientation"))
        .accessibilityIdentifier("composeGuide.variant")
    }

    /// 右に 90° 回す（反転の隣・2026-10-16）。回している間は印が真鍮
    private var rotateButton: some View {
        Button { rotateRight() } label: {
            roundIcon("rotate.right", tinted: CompositionGuide.normalizedRotation(rotation) != 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("構図を右に90度回す", "Rotate the guide 90° right"))
        .accessibilityValue(CompositionGuide.rotationAccessibilityValue(rotation))
        .accessibilityHint(L("2本指でひねっても回せます", "You can also twist with two fingers"))
        .accessibilityAction(named: L("回転を戻す", "Reset rotation")) { setRotation(ComposeControls.straightened(rotation)) }
        .accessibilityIdentifier("composeGuide.rotate")
    }

    /// UI を隠して撮れる範囲の全体を見る（2026-10-16 owner の声）。戻すのは映像を1回タップ
    private var hideButton: some View {
        Button { setHidden(true) } label: {
            roundIcon("arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("操作を隠して撮れる範囲を見る", "Hide controls to see the whole frame"))
        .accessibilityIdentifier("composeGuide.hideUI")
    }

    // MARK: - 案内の札

    /// 案内の札の文。構図ごとの一言（2026-10-10）。水準器で傾きが読めない端末ではそう言う
    private var hintText: String? {
        if composition == .level, !level.available {
            return L("この端末では傾きを読めません", "This device can't read its tilt")
        }
        return ComposeGuide.hint(current: nil, target: nil, tip: composition?.tip)
    }

    /// 構図の一言（板の案内の札の文）。2026-10-16 判断: 板は映像の下寄りに黒 62% の札で重ねるが、
    /// owner「標準のカメラ App と遜色なく」を受けて**映像の外の黒い帯**へ移した（構図の線と重ねない）。
    /// 距離が出せるときだけ上向きの矢印、それ以外は格子の記号
    private func hintLine(_ text: String) -> some View {
        let move = ComposeGuide.movement(current: nil, target: nil)
        return HStack(spacing: 8) {
            Image(systemName: move == nil ? "rectangle.split.3x3" : "arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
            Text(text)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
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
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(WebTheme.foreground)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(JPFont.body)
                .foregroundStyle(WebTheme.text2)
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
            // 2026-10-16: 構図の一言は映像の上（線と重なる）から、映像の外のこの帯へ移した
            if showsLines || camera.state == .ready, let text = hintText { hintLine(text) }
            sourceRow
            if hasReference {
                opacityRow
                if reference.source == .samples, let sample { credit(sample) }
                if reference.source == .library { libraryAdjustments }
            }
            // v2: 左・シャッター・右の3つ割り（板の `grid-template-columns: 1fr auto 1fr`）。
            // 左右を同じ幅の枠にするので、「投稿」のカプセルが出てもシャッターは真ん中のまま
            HStack(spacing: 0) {
                HStack(spacing: JPSpace.s) {
                    if onPost == nil {
                        // 投稿へ進めない入口でも、撮った直後に左下へ小さな見本（標準のカメラ App と同じ・2026-10-16）
                        if !withoutSamples { thumbButton }
                        lastShotPreview
                    } else if withoutSamples {
                        postButton
                    } else if onPost != nil {
                        // 撮影スポットの作例から開いたとき（2026-10-14）: 作例のサムネの隣に「投稿」。
                        // 撮った1枚をそのスポットの投稿へ進める（`OfficialSpotView` が `onPost` を渡す）
                        thumbButton
                        postButton
                    } else {
                        thumbButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                shutter
                Group {
                    if !withoutSamples { switchButton }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
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
                    CompositionThumbnail(kind: composition, variant: variant, cornerRadius: 3,
                                         rotationDegrees: composition == .level ? 0 : rotation)
                        .frame(width: 24, height: 32)
                    Text(composition?.name ?? CompositionGuide.noneName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WebTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WebTheme.text3)
                        .accessibilityHidden(true)
                }
                // v2: 札の面（surface-1）・角 12・白 8% の縁の 44 の札（押すと構図のシート）
                .padding(.horizontal, JPSpace.s)
                .frame(minHeight: WebTheme.minTapTarget)
                .background(WebTheme.card, in: RoundedRectangle(cornerRadius: JPRadius.field))
                .overlay(RoundedRectangle(cornerRadius: JPRadius.field).strokeBorder(WebTheme.hairline, lineWidth: JPStroke.hairline))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(CompositionGuide.accessibilityLabel(composition))
            .accessibilityHint(L("構図を選びます", "Choose a composition"))
            .accessibilityIdentifier("composeGuide.composition")
            // 拡大の段（端末のレンズに応じて 0.5×/1×/2×/望遠・2026-10-16）。向きは上の帯の小さな丸へ移した
            zoomPills
        }
    }

    /// 参考写真は作例・写真ライブラリから選ぶ。選択キャンセルでは元の状態を変えない。
    private var sourceRow: some View {
        HStack(spacing: 8) {
            Text(L("参考写真", "Reference"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
            Spacer(minLength: 0)
            // v2: **つながったセグメント**（白 7% の地・選んだ側は白 14% の面に白の太字）。v1 は離れた2つの線のカプセル
            HStack(spacing: 0) {
            Button {
                reference.useSamples()
            } label: {
                Text(L("作例", "Examples"))
                    .font(JPFont.footnote.weight(.semibold))
                    .foregroundStyle(reference.source == .samples ? WebTheme.foreground : WebTheme.text2)
                    .padding(.horizontal, 12)
                    .frame(minHeight: Self.segmentInner)
                    .background(reference.source == .samples ? Color.white.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(samples.isEmpty)
            .opacity(samples.isEmpty ? 0.4 : 1)
            .accessibilityLabel(L("Journey Photoの作例", "Journey Photo examples"))
            .accessibilityValue(reference.source == .samples && !samples.isEmpty ? L("選択中", "Selected") : "")
            .accessibilityIdentifier("composeGuide.sourceSamples")

            PhotosPicker(selection: $librarySelection, matching: .images) {
                HStack(spacing: 5) {
                    if loadingLibrary { ProgressView().tint(WebTheme.foreground) }
                    Text(L("写真ライブラリ", "Photo library"))
                        .font(JPFont.footnote.weight(.semibold))
                }
                .foregroundStyle(reference.source == .library ? WebTheme.foreground : WebTheme.text2)
                .padding(.horizontal, 12)
                .frame(minHeight: Self.segmentInner)
                .background(reference.source == .library ? Color.white.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(loadingLibrary)
            .accessibilityValue(reference.source == .library ? L("選択中", "Selected") : "")
            .accessibilityIdentifier("composeGuide.sourceLibrary")
            }
            .padding(3)
            .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: JPRadius.field))
        }
    }

    /// セグメントの内側の高さ（外の 3 の余白と合わせて 44＝押せるものの最小）
    static let segmentInner: CGFloat = WebTheme.minTapTarget - 6

    /// ライブラリ画像だけ位置と反転を調整。非表示は1タップで戻せる。
    private var libraryAdjustments: some View {
        HStack(spacing: 8) {
            Button {
                reference.mirrored.toggle()
            } label: {
                Label(L("左右反転", "Mirror"), systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("composeGuide.mirror")
            Button {
                reference.resetPosition()
            } label: {
                Label(L("位置リセット", "Reset"), systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("composeGuide.reset")
            Button {
                reference.hidden.toggle()
            } label: {
                Label(reference.hidden ? L("表示", "Show") : L("非表示", "Hide"),
                      systemImage: reference.hidden ? "eye" : "eye.slash")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("composeGuide.visibility")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(WebTheme.foreground)
        .buttonStyle(.plain)
    }

    /// 参考写真の濃さを0〜100%で変更。数値も表示する。
    private var opacityRow: some View {
        HStack(spacing: 12) {
            Text(L("濃さ", "Opacity"))
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
                .accessibilityHidden(true)
            Slider(value: $opacity, in: ComposeGuide.opacityRange)
                .tint(WebTheme.foreground)
                .accessibilityLabel(L("参考写真の濃さ", "Reference opacity"))
                .accessibilityValue(ComposeGuide.opacityPercent(opacity))
                .accessibilityIdentifier("composeGuide.opacity")
            Text(ComposeGuide.opacityPercent(opacity))
                .font(JPFont.mono(13, relativeTo: .footnote))
                .foregroundStyle(WebTheme.foreground)
        }
        .disabled(reference.hidden)
    }

    /// 作例の出典の1行（`OfficialSpotView.sampleCreditLink` と同じ書き方・当たりは 44pt 以上）
    private func credit(_ sample: SpotSample) -> some View {
        CreditLinksMenu(links: sample.creditLinks, accessibilityLabel: sample.credit) {
            Text(sample.linkedCredit)
                .tint(WebTheme.accent)
                .font(JPFont.caption)
                .foregroundStyle(WebTheme.text3)
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
            reference.hidden.toggle()
            announce(reference.hidden ? L("参考写真を隠しました", "Overlay hidden")
                                      : L("参考写真を表示しました", "Overlay shown"))
        } label: {
            ZStack {
                if reference.source == .library, let libraryImage {
                    Image(uiImage: libraryImage).resizable().scaledToFill()
                } else if let sample {
                    RemoteImage(url: sample.thumbnail(maxWidth: 250), contentMode: .fill)
                } else {
                    WebTheme.surface
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            // 隠している間は薄く（色だけでなく読み上げの値でも伝える）
            .opacity(reference.hidden ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!hasReference)
        .accessibilityLabel(L("参考写真", "Reference photo"))
        .accessibilityValue(reference.hidden ? L("隠しています", "Hidden") : L("重ねています", "Shown"))
        .accessibilityHint(reference.hidden ? L("作例を重ねます", "Shows the example overlay")
                                         : L("作例を隠します", "Hides the example overlay"))
        .accessibilityIdentifier("composeGuide.thumb")
    }

    /// 左（作例なしの入口・撮影スポットの作例から開いたときはサムネの隣）: 撮った1枚を投稿へ進める
    /// （52pt・角 10）。撮るまでは空き。
    /// 写真の無い黒い面の上の押せるものなので、印は真鍮（CLAUDE.md の owner の好み）
    @ViewBuilder
    private var postButton: some View {
        if let onPost, let shot = lastShot {
            Button {
                onPost(shot.cameraCapture)
                dismiss()
            } label: {
                // v2 ComposeGuide「撮った後（投稿）」: **真鍮の縁と字のカプセル（44）に、撮った1枚の小さな写真**
                // （黒い面の上の押せるもの・CLAUDE.md の owner の好み）
                HStack(spacing: JPSpace.xs) {
                    Group {
                        if let thumb = lastShotThumb {
                            Image(uiImage: thumb).resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo").font(JPFont.caption)
                        }
                    }
                    .frame(width: Self.postThumb, height: Self.postThumb)
                    .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs))
                    .accessibilityHidden(true)
                    Text(L("投稿", "Post"))
                        .font(JPFont.bodyEmphasis)
                }
                .foregroundStyle(WebTheme.accent)
                .padding(.leading, JPSpace.xs)
                .padding(.trailing, JPSpace.m)
                .frame(minHeight: WebTheme.minTapTarget)
                .overlay(Capsule().strokeBorder(WebTheme.accent, lineWidth: 1.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("撮った写真を投稿する", "Post the photo you took"))
            .accessibilityIdentifier("composeGuide.post")
        }
    }

    /// 「投稿」の中の撮った1枚（板 26）
    static let postThumb: CGFloat = 26

    /// 撮った1枚を小さく読む（長い辺 120 画素・向きは焼く）。読めなければ nil（印で代える）
    private static func thumbnail(of data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = ImagePreparer.downsampledImage(source: source, maxPixelSize: 120) else { return nil }
        return UIImage(cgImage: image)
    }

    /// 拡大の段の丸（標準のカメラ App と同じ形: 黒い地に小さな丸、選んでいる段はいまの倍率と「×」）。
    /// 黒い帯の上なので、選んでいる段の字は真鍮（CLAUDE.md の owner の好み「選んでいるもの」）。
    /// 段が1つ（1× だけ）の端末では出さない
    @ViewBuilder
    private var zoomPills: some View {
        let levels = camera.zoomLevels
        if levels.presets.count > 1 {
            let display = levels.display(factor: camera.zoomFactor)
            let active = ComposeControls.activePreset(display: display, presets: levels.presets)
            HStack(spacing: 0) {
                ForEach(levels.presets, id: \.self) { preset in
                    let on = preset == active
                    Button { camera.setZoom(display: preset, animated: !reduceMotion) } label: {
                        // 2026-10-16（確かめ役の指摘）: 字は既存の数字の字（`JPFont.mono`・文字サイズの設定に
                        // ついていく）、丸は字に合わせて広がる。当たりは 44×44
                        Text(ComposeControls.zoomLabel(on ? display : preset, active: on))
                            .font(JPFont.mono(12, medium: true, relativeTo: .caption))
                            .foregroundStyle(on ? WebTheme.accent : WebTheme.foreground)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .frame(minWidth: on ? 36 : 30, minHeight: on ? 36 : 30)
                            .background(Color.white.opacity(on ? 0.16 : 0.08), in: Capsule())
                            .frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ComposeControls.zoomAccessibility(preset))
                    .accessibilityValue(on ? L("選択中", "Selected") : "")
                    .accessibilityIdentifier(ComposeControls.zoomIdentifier(preset))
                }
            }
        }
    }

    /// 撮った直後の小さな見本（投稿へ進めない入口の左下・押す先は無い）
    @ViewBuilder
    private var lastShotPreview: some View {
        if let thumb = lastShotThumb {
            Image(uiImage: thumb)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: JPRadius.xs))
                .overlay(RoundedRectangle(cornerRadius: JPRadius.xs).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(L("撮った写真（写真に保存しました）", "Photo you just took (saved to Photos)"))
                .accessibilityIdentifier("composeGuide.lastShot")
        }
    }

    /// 中央: シャッター（v2 の 76pt・白 4pt の輪・内側に白の丸）
    private var shutter: some View {
        Button { Task { await shootIfReady() } } label: {
            Circle()
                .fill(WebTheme.foreground)
                .padding(8)
                .frame(width: Self.shutterSize, height: Self.shutterSize)
                .overlay(Circle().strokeBorder(WebTheme.foreground, lineWidth: 4))
        }
        .buttonStyle(.plain)
        .disabled(!canShoot)
        .opacity(camera.state == .ready ? 1 : 0.4)
        .accessibilityLabel(L("撮影", "Take photo"))
        .accessibilityHint(L("撮った写真は端末の写真に保存されます", "The photo is saved to your Photos"))
        .accessibilityIdentifier("composeGuide.shutter")
    }

    /// シャッター（v2 の板 76。v1 は 72）
    static let shutterSize: CGFloat = 76

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
        .disabled(reference.source != .samples || samples.count < 2)
        .opacity(reference.source == .samples && samples.count >= 2 ? 1 : 0.4)
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

    /// シャッター・音量ボタン・読み上げの「撮影」の入口。撮れるときだけ（`ComposeControls.canShoot`）、
    /// 押した瞬間に軽い振動と暗転（標準のカメラ App の手応え）
    private func shootIfReady() async {
        guard canShoot else { return }
        shotCount += 1
        // 2026-10-16（確かめ役の指摘）: 以前は同じ処理で false に戻していて、黒が一度も描かれなかった。
        // 黒を描かせてから（`shutterFlashHold`）戻す
        shutterFlash = true
        let fade = reduceMotion ? 0.05 : 0.18
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(ComposeControls.shutterFlashHold * 1_000_000_000))
            withAnimation(.easeOut(duration: fade)) { shutterFlash = false }
        }
        await shoot()
    }

    /// 撮って保存し、結果を知らせる。作例なしの入口では、撮れた1枚を「投稿」へ進められるようにする
    /// （写真への保存を断られても、撮れた1枚は投稿できる）
    private func shoot() async {
        guard let shot = await camera.capture() else {
            show(ComposeGuide.message(for: .failed), isError: true)
            return
        }
        lastShot = shot
        lastShotThumb = Self.thumbnail(of: shot.data)
        let outcome = await ComposeCamera.save(shot.data)
        show(ComposeGuide.message(for: outcome), isError: outcome != .saved)
    }

    /// Picker の戻る・キャンセルでは選択が変わらない。読めたときだけ画像と出典を切り替える。
    private func loadLibraryImage(_ item: PhotosPickerItem) async {
        guard !loadingLibrary else { return }
        loadingLibrary = true
        defer {
            loadingLibrary = false
            librarySelection = nil // 同じ画像を選び直せるようにする
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                show(L("写真を読み込めませんでした", "Couldn't load the photo"), isError: true)
                return
            }
            let thumbnail = try await Task.detached(priority: .userInitiated) {
                try ReferencePhotoLoader.previewJPEG(from: data)
            }.value
            guard let image = UIImage(data: thumbnail) else {
                show(L("写真を表示できませんでした", "Couldn't display the photo"), isError: true)
                return
            }
            libraryImage = image
            libraryLoads += 1
            reference.useLibrary()
        } catch {
            show(L("写真を読み込めませんでした。別の写真をお試しください",
                   "Couldn't load the photo. Try another one."), isError: true)
        }
    }

    // MARK: - 構図

    /// 構図を選んだ（シートから）。覚えて、読み上げで伝える
    private func choose(_ picked: CompositionKind?) {
        composition = picked
        variant = picked.map { preferences.variant(for: $0) } ?? 0
        // 選び直したら回転は初めの向きに戻す（`CompositionPreferences.select` が覚えた角度は 0 にする）。
        // 2026-10-18: 初めの向きは、横長の参考写真を重ねていれば 90°、それ以外は真っ直ぐ（0°）。
        // 累積の角度はいちばん短く回る値へ（逆回りに大きく回らない）
        applyAutoRotation(.compositionChosen, animated: false)
        preferences.select(picked)
        announce(CompositionGuide.accessibilityLabel(picked))
    }

    /// 次の向きへ（払いは付けない・作例の払いと紛れる）
    private func cycleVariant(of kind: CompositionKind) {
        variant = kind.nextVariant(after: variant)
        preferences.setVariant(variant, for: kind)
        announce(CompositionGuide.variantAccessibilityLabel(kind, variant: variant))
    }

    /// 右に 90° 回す（次の 90° の倍数へ・`CompositionGuide.rotatedRight`）
    private func rotateRight() {
        setRotation(ComposeControls.rotatedRightCumulative(rotation))
    }

    /// 回した角度を決めて覚え、読み上げで伝える
    /// 状態は累積のまま持ち（絵がいちばん短い向きに回る）、覚える値と読み上げは 0〜360 に戻す
    private func setRotation(_ degrees: Double) {
        guard degrees.isFinite else { return }
        // 人が選んだ向き（2026-10-18）。参考写真・構図が替わるまで自動で回し直さない
        rotationManual = true
        if reduceMotion {
            rotation = degrees
        } else {
            withAnimation(.easeOut(duration: 0.2)) { rotation = degrees }
        }
        let normalized = CompositionGuide.normalizedRotation(degrees)
        preferences.setRotation(normalized, for: composition)
        announce(CompositionGuide.rotationAccessibilityValue(normalized))
    }

    /// 自動の向きに決め直す（2026-10-18・`ComposeControls.decidedRotation`）。自動の向きは覚えない
    /// （覚えるのは人が回した角度だけ）。ひねっている最中は持った向きで回し直さない
    private func applyAutoRotation(_ trigger: ComposeControls.RotationTrigger, animated: Bool = true) {
        if trigger == .heldTurned, twistState.engaged { return }
        guard let next = ComposeControls.decidedRotation(
            trigger, current: rotation, manual: rotationManual, auto: autoReferenceRotation,
            remembered: preferences.rotation(for: composition)) else { return }
        if trigger != .heldTurned { rotationManual = false }
        guard next != rotation else { return }
        if reduceMotion || !animated {
            rotation = next
        } else {
            withAnimation(.easeOut(duration: 0.2)) { rotation = next }
        }
    }

    /// UI を隠す・戻す。隠すときはピントの枠も消し、戻し方を読み上げで伝える
    private func setHidden(_ hidden: Bool) {
        guard hidden != uiHidden else { return }
        if hidden { focusPoint = nil }
        if reduceMotion {
            uiHidden = hidden
        } else {
            withAnimation(.easeOut(duration: 0.2)) { uiHidden = hidden }
        }
        if hidden {
            announce(L("操作を隠しました。画面をタップすると戻ります。音量ボタンで撮れます",
                       "Controls hidden. Tap the screen to show them. Press a volume button to take a photo."))
        }
    }

    /// 傾きの見張りを始める・速さを合わせる。水準器を選んでいる間だけ角度を 30 回/秒で読み、
    /// ほかは持った向き（縦・横）だけを 10 回/秒で見る
    private func updateLevel() {
        level.onQuarterChange = { quarterTurns = $0 }
        level.start(level: composition == .level)
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
