import Foundation

/// 写真の編集画面の状態（**純**。画面・Core Image に触らない）。
///
/// 履歴は `PhotoEditHistory`（#138 のエンジン）をそのまま持ち、ここは
/// 「どのタブ・どの項目を選んでいるか」「つまみの位置 ↔ レシピの値」「長押しで比べる」だけを足す。
/// 画面（`PhotoEditView`）はこれを `@State` に持ち、描くレシピは `history.displayed`。
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

    /// 今見せているレシピ（長押しの間は編集前）
    var displayed: PhotoRecipe { history.displayed }
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

    /// 長押しの出来事。**指が触れただけでは比べない**（押すたびに写真が一瞬入れ替わると、
    /// ただのタップでもちらつく）。長押しと認めたら編集前、指を離したら戻す
    enum Press: Equatable { case recognized, released }

    mutating func press(_ event: Press) {
        switch event {
        case .recognized: history.setComparing(true)
        case .released: history.setComparing(false)
        }
    }

    /// 「編集前」の札を出すか（長押しの間だけ）
    var showsBeforeLabel: Bool { history.isComparing }

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
