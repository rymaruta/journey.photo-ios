import Foundation

/// 写真の編集レシピ（**非破壊**）。元の画素には手を付けず、「どう補正するか」だけを持つ。
/// 描くのは `PhotoRenderer`、Core Image のフィルターの並びに直すのは `PhotoRecipePlan`。
///
/// owner の指示（2026-10-02）: Core Image 中心の写真編集、Phase 1 は「エンジン」だけ。
/// 編集画面・投稿画面への組み込みは次の枝（デザインを owner に見せてから）。
///
/// 項目と幅（**0 が無変更**）:
/// - `exposure`: 露出（EV）。−2…+2
/// - `contrast` / `saturation` / `temperature` / `highlights` / `shadows`: −1…+1 の正規化値。
///   フィルターの引数への直し方は `PhotoRecipePlan` に1か所だけ置く（ここは「つまみの位置」）
/// - `temperature` は＋で暖かく（黄）、−で冷たく（青）。**色かぶり（tint）は入れない**
/// - `preset`: プリセットの id と強さ（0…1）。つまみの値はプリセットの上に**足す**
///
/// **版番号 `v`** を書き出す。版を上げるのは**既存の鍵の意味が変わるとき**だけ
/// （鍵を足すだけなら上げない——古いアプリは知らない鍵を読み飛ばす）。
/// 読めない新しい版は「無編集」として読む（意味の変わった値で、違う見た目に焼かない）。
/// 壊れた値・欠けた鍵・知らない鍵で**落ちない**（`PhotoFraming` と同じ作り）
struct PhotoRecipe: Equatable, Codable {

    /// 今の版。鍵の意味を変えたら上げ、`init(from:)` に読み替えを足す
    static let currentVersion = 1

    var exposure: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var temperature: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var preset: PresetChoice? = nil

    /// 選んだプリセット。`id` は `PhotoPresets` の id（画面の名前ではない・変えない）
    struct PresetChoice: Equatable, Codable {
        var id: String
        var strength: Double = 1

        init(id: String, strength: Double = 1) {
            self.id = id
            self.strength = strength
        }

        private enum CodingKeys: String, CodingKey { case id, strength }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
            strength = (try? c.decodeIfPresent(Double.self, forKey: .strength)) ?? 1
        }
    }

    static let identity = PhotoRecipe()

    /// 露出の幅（EV）。それ以上は白飛び・黒つぶれで写真が壊れる
    static let exposureRange: ClosedRange<Double> = -2...2
    /// 正規化した項目の幅
    static let unitRange: ClosedRange<Double> = -1...1
    /// プリセットの強さの幅
    static let strengthRange: ClosedRange<Double> = 0...1

    init(exposure: Double = 0, contrast: Double = 0, saturation: Double = 0,
         temperature: Double = 0, highlights: Double = 0, shadows: Double = 0,
         preset: PresetChoice? = nil) {
        self.exposure = exposure
        self.contrast = contrast
        self.saturation = saturation
        self.temperature = temperature
        self.highlights = highlights
        self.shadows = shadows
        self.preset = preset
    }

    /// 何も変えないレシピか。**幅に収めてから**見る（NaN や 0 の強さのプリセットも無編集）
    var isIdentity: Bool {
        let s = sanitized
        return s.exposure == 0 && s.contrast == 0 && s.saturation == 0
            && s.temperature == 0 && s.highlights == 0 && s.shadows == 0
            && (s.preset == nil || s.preset?.strength == 0)
    }

    /// 幅に収めたもの。NaN・無限大は 0（無変更）。**知らないプリセットは外す**
    /// （新しい版のアプリで選んだもの・消したもの。id だけ残しても描けない）。
    /// 強さ 0 のプリセットは残す——つまみを 0 まで下げても、どれを選んでいるかは残したい
    var sanitized: PhotoRecipe {
        var next = PhotoRecipe(exposure: Self.clamp(exposure, Self.exposureRange),
                               contrast: Self.clamp(contrast, Self.unitRange),
                               saturation: Self.clamp(saturation, Self.unitRange),
                               temperature: Self.clamp(temperature, Self.unitRange),
                               highlights: Self.clamp(highlights, Self.unitRange),
                               shadows: Self.clamp(shadows, Self.unitRange))
        if let preset, PhotoPresets.preset(id: preset.id) != nil {
            next.preset = PresetChoice(id: preset.id, strength: Self.clamp(preset.strength, Self.strengthRange))
        }
        return next
    }

    /// 幅に収める。NaN・無限大は 0
    static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - 読み書き

    private enum CodingKeys: String, CodingKey {
        case v, exposure, contrast, saturation, temperature, highlights, shadows, preset
    }

    /// **幅に収めてから書く。** NaN のまま渡すと `JSONEncoder` が投げ、下書きごと保存に失敗する
    func encode(to encoder: Encoder) throws {
        let s = sanitized
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .v)
        try c.encode(s.exposure, forKey: .exposure)
        try c.encode(s.contrast, forKey: .contrast)
        try c.encode(s.saturation, forKey: .saturation)
        try c.encode(s.temperature, forKey: .temperature)
        try c.encode(s.highlights, forKey: .highlights)
        try c.encode(s.shadows, forKey: .shadows)
        try c.encodeIfPresent(s.preset, forKey: .preset)
    }

    /// **投げない。** 鍵が無い・型が違う値は 0（無変更）。`v` が無ければ 1 として読む。
    /// 読めない新しい版は無編集にする（上の注記）
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .identity
            return
        }
        let version = (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? 1
        guard version <= Self.currentVersion else {
            self = .identity
            return
        }
        func read(_ key: CodingKeys) -> Double {
            (try? c.decodeIfPresent(Double.self, forKey: key)) ?? 0
        }
        self = PhotoRecipe(exposure: read(.exposure),
                           contrast: read(.contrast),
                           saturation: read(.saturation),
                           temperature: read(.temperature),
                           highlights: read(.highlights),
                           shadows: read(.shadows),
                           preset: (try? c.decodeIfPresent(PresetChoice.self, forKey: .preset)) ?? nil)
            .sanitized
    }
}
