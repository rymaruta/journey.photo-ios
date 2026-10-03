import Foundation

/// 写真の編集画面の状態（**純**。画面・Core Image に触らない）。
///
/// 履歴は `PhotoEditHistory`（#138 のエンジン）をそのまま持ち、ここは
/// 「どのタブ・どの項目を選んでいるか」「つまみの位置 ↔ レシピの値」「長押しで比べる」だけを足す。
/// 画面（`PhotoEditView`）はこれを `@State` に持ち、描くレシピは `displayed`。
///
/// デザインは Artifact「写真の編集 — 画面の候補」の 1（owner 2026-10-02: 比べ方は長押し・
/// プリセット名は今のまま）。
struct PhotoEditScreen: Equatable {

    enum Tab: Equatable { case film, adjust }

    /// 調整の6項目（並びは画面の順）
    enum Adjustment: String, CaseIterable, Identifiable, Equatable {
        case exposure, contrast, saturation, temperature, highlights, shadows

        var id: String { rawValue }

        var label: String {
            switch self {
            case .exposure: return L("露出", "Exposure")
            case .contrast: return L("コントラスト", "Contrast")
            case .saturation: return L("彩度", "Saturation")
            case .temperature: return L("色温度", "Warmth")
            case .highlights: return L("ハイライト", "Highlights")
            case .shadows: return L("シャドウ", "Shadows")
            }
        }

        /// SF Symbols の名前
        var symbol: String {
            switch self {
            case .exposure: return "sun.max"
            case .contrast: return "circle.lefthalf.filled"
            case .saturation: return "drop"
            case .temperature: return "thermometer.medium"
            case .highlights: return "circle.tophalf.filled"
            case .shadows: return "circle.bottomhalf.filled"
            }
        }

        /// レシピの値（露出は EV・ほかは −1…+1）
        func value(in recipe: PhotoRecipe) -> Double {
            switch self {
            case .exposure: return recipe.exposure
            case .contrast: return recipe.contrast
            case .saturation: return recipe.saturation
            case .temperature: return recipe.temperature
            case .highlights: return recipe.highlights
            case .shadows: return recipe.shadows
            }
        }

        func setting(_ value: Double, in recipe: PhotoRecipe) -> PhotoRecipe {
            var next = recipe
            switch self {
            case .exposure: next.exposure = value
            case .contrast: next.contrast = value
            case .saturation: next.saturation = value
            case .temperature: next.temperature = value
            case .highlights: next.highlights = value
            case .shadows: next.shadows = value
            }
            return next.sanitized
        }

        /// レシピの値の幅の端（つまみの ±100 がここに当たる）
        private var unit: Double {
            self == .exposure ? PhotoRecipe.exposureRange.upperBound : PhotoRecipe.unitRange.upperBound
        }

        /// つまみの位置（−100…+100）
        func sliderValue(in recipe: PhotoRecipe) -> Double {
            PhotoRecipe.clamp(value(in: recipe) / unit * 100, PhotoEditScreen.adjustmentSliderRange)
        }

        /// つまみの位置 → レシピの値。**整数に丸める**（表示する値と描く値をそろえる）
        func recipeValue(slider: Double) -> Double {
            PhotoRecipe.clamp(slider, PhotoEditScreen.adjustmentSliderRange).rounded() / 100 * unit
        }

        /// 変えてあるか（つまみの表示で 0 でない）。真鍮の点とアイコンの色を決める
        func isChanged(in recipe: PhotoRecipe) -> Bool {
            sliderValue(in: recipe).rounded() != 0
        }

        /// 読み上げ（「露出・変えてあります」。ストーリーの道具と同じ言い方）
        func accessibilityLabel(changed: Bool) -> String {
            changed ? L("\(label)・変えてあります", "\(label), adjusted") : label
        }
    }

    static let adjustmentSliderRange: ClosedRange<Double> = -100...100
    static let strengthSliderRange: ClosedRange<Double> = 0...100
    /// プリセットを選んだときの強さ（見本 1 と同じ 80）。
    /// 2026-10-02 判断: 1（100）だと効きが強すぎる写真があり、見本どおり少し引いた所から始める
    static let defaultPresetStrength = 0.8

    private(set) var history: PhotoEditHistory
    var tab: Tab = .film
    var adjustment: Adjustment = .exposure

    init(original: PhotoRecipe = .identity) {
        history = PhotoEditHistory(original: original)
    }

    /// 今見せているレシピ。長押しの間は**元の写真（無編集）**（`press` の注記）
    var displayed: PhotoRecipe { showsBeforeLabel ? .identity : history.current }
    /// 編集中のレシピ（つまみの途中を含む）
    var current: PhotoRecipe { history.current }

    // MARK: - フィルム

    /// 選んでいるプリセットの id（なしは nil）
    var selectedPresetId: String? { current.preset?.id }

    /// プリセットを選ぶ（nil は「なし」）。**同じものを押し直しても手を増やさない。**
    /// 調整のつまみの値は残す（プリセットの上に足す作り・`PhotoRecipe`）
    mutating func selectPreset(_ id: String?) {
        guard id != selectedPresetId else { return }
        var next = current
        next.preset = id.map { PhotoRecipe.PresetChoice(id: $0, strength: Self.defaultPresetStrength) }
        history.apply(next)
    }

    /// 強さのつまみ（0…100）。プリセットが無ければ nil（つまみを出さない）
    var strengthSlider: Double? {
        current.preset.map { ($0.strength * 100).rounded() }
    }

    /// 強さのつまみを動かしている途中（手は増やさない。離したら `endDrag`）
    mutating func dragStrength(_ slider: Double) {
        guard var preset = current.preset else { return }
        preset.strength = PhotoRecipe.clamp(slider, Self.strengthSliderRange).rounded() / 100
        var next = current
        next.preset = preset
        history.preview(next)
    }

    // MARK: - 調整

    var adjustmentSlider: Double { adjustment.sliderValue(in: current).rounded() }

    mutating func dragAdjustment(_ slider: Double) {
        history.preview(adjustment.setting(adjustment.recipeValue(slider: slider), in: current))
    }

    /// 「0に戻す」（1手として。取り消せる）
    mutating func resetAdjustment() {
        guard adjustment.isChanged(in: current) else { return }
        history.apply(adjustment.setting(0, in: current))
    }

    /// 指を離した。動かした分を1手にする
    mutating func endDrag() {
        history.commit()
    }

    /// つまみの値の文字（+12 / 0 / −5）。負の符号は文字のハイフンではなくマイナス記号
    static func valueText(_ slider: Double) -> String {
        let n = Int(PhotoRecipe.clamp(slider, adjustmentSliderRange).rounded())
        if n > 0 { return "+\(n)" }
        if n < 0 { return "−\(-n)" }
        return "0"
    }

    // MARK: - 取り消し・やり直し

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    mutating func undo() { history.undo() }
    mutating func redo() { history.redo() }

    // MARK: - 長押しで編集前と比べる（owner 2026-10-02: 比べ方は長押し）

    /// 長押しと認めるまでの時間（秒）
    static let holdDelay: TimeInterval = 0.25

    /// 指の出来事。
    ///
    /// - `began(at:)`: 指が触れた（触れている間に何度来ても、最初の1回だけ数える）
    /// - `tick(now:)`: 時計（触れてから `holdDelay` たったら呼ぶ）。**触れてからの時間で決める**——
    ///   離して触れ直したあとに前の時計が届いても、新しい指からはまだ時間がたっていないので比べない
    /// - `ended`: 指を離した。**離すまで編集前を出し続け、離したら必ず戻す**
    ///
    /// **指が触れただけでは比べない**（ただのタップで写真がちらつく）。
    ///
    /// **2026-10-02 判断（owner の Before/After）: 出すのは元の写真（無編集）。** この編集を始めたときの姿
    /// （`PhotoEditHistory.original`）ではない——帯の一言「元の写真は変わりません」と同じ「元」
    enum Press: Equatable {
        case began(at: Date)
        case tick(now: Date)
        case ended
    }

    /// 指が触れた時刻（離していれば nil）
    private(set) var pressedAt: Date?

    mutating func press(_ event: Press) {
        switch event {
        case .began(let at):
            guard pressedAt == nil else { return }
            pressedAt = at
        case .tick(let now):
            guard let pressedAt, now.timeIntervalSince(pressedAt) >= Self.holdDelay else { return }
            history.setComparing(true)
        case .ended:
            pressedAt = nil
            history.setComparing(false)
        }
    }

    /// 「編集前」の札を出すか（長押しと認めてから、指を離すまで）
    var showsBeforeLabel: Bool { history.isComparing }

    // MARK: - 写真の欄に何を出すか（2026-10-03）

    enum PhotoShown: Equatable {
        /// 編集後の絵（`PhotoEditPreview.edited`）
        case edited
        /// 元の写真（無編集）
        case before
        /// 帯の編集済みサムネを仮に出す（編集後の最初の絵が届くまで）
        case placeholder
        /// 編集後の絵を描けなかった。元の写真を出し、描けなかったことを添える
        case beforeRenderFailed
        case spinner
        case failed
    }

    /// 写真の欄に何を出すか。
    ///
    /// 🔴 **編集済みの写真で開き直したとき、編集後の最初の絵が届くまで元の写真を札なしで出さない。**
    /// 以前は `edited ?? before` で、元の写真（無編集）が「編集前」の札なしで出て、編集が消えたように見えた。
    /// 今のレシピが無編集でないあいだは、帯の編集済みサムネ（あれば・長い辺 360px なので仮）か、スピナー。
    /// 長押しの間は元の写真（`showsBeforeLabel`）。
    ///
    /// `renderFailed`: 編集後の絵を描けなかった（まだ1枚も描けていない）。スピナーを回し続けず、
    /// 元の写真に「描けなかった」を添えて出す（2026-10-03）
    func photoShown(hasEdited: Bool, hasBefore: Bool, hasPlaceholder: Bool, failed: Bool,
                    renderFailed: Bool = false) -> PhotoShown {
        if showsBeforeLabel {
            if hasBefore { return .before }
            return failed ? .failed : .spinner
        }
        if hasEdited { return .edited }
        if failed { return .failed }
        if renderFailed { return hasBefore ? .beforeRenderFailed : .failed }
        if !current.isIdentity { return hasPlaceholder ? .placeholder : .spinner }
        return hasBefore ? .before : .spinner
    }

    // MARK: - 閉じる

    /// 「キャンセル」で確かめるか（編集前から変わっている）
    var asksBeforeDiscard: Bool { history.hasChanges }

    /// 「完了」で返すレシピ。動かしている途中の値も含めて確定したもの
    var finished: PhotoRecipe {
        var copy = history
        copy.commit()
        return copy.current
    }
}

/// 編集画面の見本を出す順番（純・2026-10-03）。描くのは `PhotoEditPreview`。
///
/// 1. **枠の大きさが取れるまで待つ**——最初の `onAppear` で枠が 0 のことがあり、以前は決め打ちの
///    1200px で読んでいた（大きい画面では粗く、小さい画面では無駄に重い）
/// 2. 画面用の写真と編集前の絵を読んで**先に出す**
/// 3. プリセットの見本は**後から**描く（読んだ写真を縮めて・原本を二度デコードしない）。
///    以前は見本9枚を描き終えるまで写真も出なかった
///
/// 画面を閉じたら（`disappeared`）取り消す。開き直しで枠が来たら始め直す（`run` で前の回の結果を捨てる）
struct PhotoEditLoadSteps: Equatable {

    enum Phase: Equatable {
        case waitingForSize
        case loadingPhoto(pixels: Int)
        case drawingThumbs
        case done
        case failed
        case cancelled
    }

    private(set) var phase: Phase = .waitingForSize
    /// 何回目に始めたか。描き終えた結果はこれが同じときだけ入れる
    private(set) var run = 0

    /// 見本を描く順（「なし」→ プリセットの並び）
    static var thumbOrder: [String] { [PhotoEditPreview.noneKey] + PhotoPresets.all.map(\.id) }

    /// 枠の大きさが来た。**読み始めてよければ**写真を読む長い辺の画素数を返す
    /// （大きさが 0・壊れた値なら nil のまま待つ。始めるのは待っている間・取り消した後だけ）
    mutating func sized(box: CGSize, scale: Double) -> Int? {
        switch phase {
        case .waitingForSize, .cancelled: break
        default: return nil
        }
        guard let pixels = PhotoRenderer.previewPixelSize(box: box, scale: scale) else { return nil }
        run += 1
        phase = .loadingPhoto(pixels: pixels)
        return pixels
    }

    /// 写真を読み終えた（`ok`: 読めた）。見本を描き始めてよいか
    mutating func photoLoaded(_ ok: Bool, run: Int) -> Bool {
        guard run == self.run, case .loadingPhoto = phase else { return false }
        phase = ok ? .drawingThumbs : .failed
        return ok
    }

    /// 見本を1枚描き終えた。入れてよいか（取り消した・始め直した回のものは捨てる）
    func acceptsThumb(run: Int) -> Bool {
        run == self.run && phase == .drawingThumbs
    }

    mutating func thumbsDrawn(run: Int) {
        guard acceptsThumb(run: run) else { return }
        phase = .done
    }

    /// 画面を閉じた。描き終えていなければ取り消す
    mutating func disappeared() {
        switch phase {
        case .done, .failed: return
        default: phase = .cancelled
        }
    }
}

/// 投稿画面の帯のサムネに付ける札（見本 3）。プリセットを選んでいればその名前、
/// 調整だけなら「調整」、無編集なら付けない。
///
/// 2026-10-02 判断: 強さ 0 のプリセットは「選んでいるが効いていない」ので名前を出さない
/// （調整も無ければ無編集＝札なし）
enum PhotoEditBadge {
    static func text(for recipe: PhotoRecipe) -> String? {
        let r = recipe.sanitized
        guard !r.isIdentity else { return nil }
        if let choice = r.preset, choice.strength > 0, let preset = PhotoPresets.preset(id: choice.id) {
            return preset.name
        }
        return L("調整", "Adjusted")
    }
}

/// 投稿画面と編集の決まり（純）。
enum UploadEditRules {

    /// 送るときに書き出すか。**無編集なら書き出さない**——整えた `prepared` をそのまま送る
    /// （書き出すと JPEG をもう一度焼くぶん画質が落ち、時間もかかる）
    static func needsExport(_ recipe: PhotoRecipe) -> Bool {
        !recipe.isIdentity
    }

    /// 編集画面を開いてよいか。
    ///
    /// 🔴 **2026-10-02 判断: 再試行の鍵（staged）を控えている写真は編集させない。**
    /// 本体は置けたが保存が通ったか分からない写真で、前の保存が実は通っていた場合、
    /// 編集し直して新しい画像（新しい鍵）で送ると**同じ写真が2枚**になる（#136 の二重投稿の守り）。
    /// 公開範囲の錠（`UploadViewModel.visibilityLocked`）と同じ考え: まず「投稿する」を押し直して
    /// 前の送信の結末を確かめてもらう（届いていれば投稿済みとして外れる）。
    /// 送っている間も開かせない（送信は1枚ごとにその時点の写真を読む）
    static func canEdit(isStaged: Bool, isWorking: Bool) -> Bool {
        !isStaged && !isWorking
    }

    static let editLockMessage = L("前の送信が届いている可能性があるため、この写真は編集できません。まず「投稿する」をもう一度押してください",
                                   "Your last attempt may have gone through, so this photo can't be edited. Tap Post again first.")

    /// 編集した写真を書き出せなかったときの知らせ。**抜け道を添える**——書き出しが毎回落ちる写真でも、
    /// 編集を「なし」に戻せば整えた元の写真で送れる
    static func exportFailureMessage(_ reason: String?) -> String {
        let head = reason ?? L("編集した写真を書き出せませんでした", "Couldn't export the edited photo")
        return head + L("。編集を「なし」に戻すと元の写真で送れます",
                        ". Set the edit back to None to post the original photo.")
    }

    /// 送り始める前に編集した写真を書き出している進み（2026-10-03）。`index` は 1 から
    struct ExportProgress: Equatable {
        let index: Int
        let total: Int

        /// 投稿ボタンに出す短い文（送信中の「3/5」と同じ書き方）
        var label: String { L("書き出し中 \(index)/\(total)", "Exporting \(index)/\(total)") }
        /// 読み上げ
        var accessibilityLabel: String {
            L("編集した写真を書き出し中 \(index) / \(total) 枚目", "Exporting edited photo \(index) of \(total)")
        }
    }

    /// 共有から外した写真があれば、そのことを知らせに足す（編集前の絵を黙って SNS に渡さない）
    static func withShareSkipped(_ summary: String?, skipped: Int) -> String? {
        guard skipped > 0 else { return summary }
        // 外した写真があると共有の画面そのものを開かない（`UploadViewModel` の `shareSkipped == 0`）ので、
        // 「その枚数だけ外した」ではなく「共有を開かなかった」と言う（残りが共有されたと読ませない）
        let note = L("編集した写真 \(skipped) 枚を共有用に用意できなかったため、SNS への共有は開いていません（投稿は済んでいます）",
                     "\(skipped) edited photo(s) couldn't be prepared for sharing, so sharing to social media was not opened (the post itself went through).")
        guard let summary else { return note }
        return summary + L("　", " ") + note
    }

    /// 控えている鍵（`staged`）をやり直しに使ってよいか。**置いたときと同じ見た目のときだけ。**
    ///
    /// 編集の錠（`canEdit`）があるので、ふつうは同じになる。それでも違ったら（錠をすり抜けた）、
    /// 前の鍵の画像は今の編集と違う絵なので使わない——置き直す（古い鍵は片付けに回す）
    static func reusesStaged(stagedWith: PhotoRecipe?, current: PhotoRecipe) -> Bool {
        let before = stagedWith ?? .identity
        if before.isIdentity && current.isIdentity { return true }
        return before.sanitized == current.sanitized
    }
}

/// 描画を「最新だけ」にする順番待ち（純）。
///
/// つまみを動かすと、描き終わる前に次の値が来る。全部を順に描くと遅れが積もるので、
/// **描いている間に来た値は最後の1つだけ残し、途中の値は描かずに捨てる。**
/// 描き終えた絵は出してよい（表示中の絵より必ず新しい）
struct LatestOnlyQueue<Job: Equatable>: Equatable {
    private(set) var running: Job?
    private(set) var pending: Job?

    init() {}

    /// 新しい仕事。空いていれば今すぐ始めるものを返す。描いている最中なら待たせ（前の待ちは捨てる）、nil
    mutating func submit(_ job: Job) -> Job? {
        guard running != nil else {
            running = job
            return job
        }
        pending = job
        return nil
    }

    /// 描き終えた。次に始めるもの（待っていた最新）を返す
    mutating func finish() -> Job? {
        running = nil
        guard let next = pending else { return nil }
        pending = nil
        running = next
        return next
    }
}
