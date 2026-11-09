import Foundation

/// ストーリーのフィルター（2026-11-09 owner「ストーリーをインスタと遜色なく」の第1弾・段 2a は写真）。
///
/// **新しい描き方は作らない。** 写真の編集（`PhotoRecipe`・`PhotoRecipePlan`・`PhotoRenderer`）の
/// **自作のプリセット**（LUT なし・他社の名前も数値も写していない・`PhotoPresets` の注記）を使い回し、
/// ストーリーだけの3つ（鮮やか・しっとり・白黒）を、つまみの値（`PhotoRecipe` の項目）の組で足す。
/// 強さ（0…1）は無変更との線形補間（`PhotoRecipe` のつまみ・プリセットの強さの両方をかける）。
///
/// **`PhotoPresets.all` は変えない**（写真の編集画面が 6〜8 個を前提にしている・テスト）。
/// 画面（`StoryFilterPanel`）・書き出し（`TextOverlayRenderer.burn`）・下書きは、ここの1か所から決める。
struct StoryFilter: Identifiable, Equatable {

    /// 保存する id（下書きに残る）。**名前を変えても id は変えない**
    let id: String
    let nameJa: String
    let nameEn: String
    /// 強さ 1 のレシピ
    let recipe: PhotoRecipe

    var name: String { L(nameJa, nameEn) }

    /// 強さ `strength`（0…1）のレシピ。つまみの値もプリセットの強さも、同じ割合で薄める
    func recipe(strength: Double) -> PhotoRecipe {
        let s = PhotoRecipe.clamp(strength, PhotoRecipe.strengthRange)
        return PhotoRecipe(exposure: recipe.exposure * s, contrast: recipe.contrast * s,
                           saturation: recipe.saturation * s, temperature: recipe.temperature * s,
                           highlights: recipe.highlights * s, shadows: recipe.shadows * s,
                           preset: recipe.preset.map {
                               PhotoRecipe.PresetChoice(id: $0.id, strength: $0.strength * s)
                           })
    }
}

/// 選んだフィルターと強さ。**写真ごと**に持つ（文字・合わせ方と同じ）。下書きに残す形でもある
/// （`Codable`）。**無いとき・壊れたとき・知らない id は「なし」**（古い下書きを壊さない）
struct StoryFilterChoice: Equatable, Codable {

    /// 「なし」の id（フィルターの列の先頭）
    static let noneId = "none"

    var id: String
    /// 0…1。既定は 1（全部かける）
    var strength: Double

    /// 「なし」。**名前を `none` にしない**（`Optional.none` と取り違える——`filter ?? .none` が型検査を通ってしまう）
    static let off = StoryFilterChoice(id: noneId, strength: 1)

    init(id: String, strength: Double = 1) {
        self.id = id
        self.strength = strength
    }

    private enum CodingKeys: String, CodingKey { case id, strength }

    /// **投げない。** 鍵が無い・型が違う値は「なし」・強さ 1 にする
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .off
            return
        }
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? Self.noneId
        strength = (try? c.decodeIfPresent(Double.self, forKey: .strength)) ?? 1
        self = self.sanitized
    }

    /// 幅に収めたもの。知らない id は「なし」・NaN の強さは 1
    var sanitized: StoryFilterChoice {
        guard StoryFilters.filter(id: id) != nil else { return .off }
        let s = strength.isFinite ? PhotoRecipe.clamp(strength, PhotoRecipe.strengthRange) : 1
        return StoryFilterChoice(id: id, strength: s)
    }

    /// 描くレシピ。「なし」・強さ 0・知らない id は無編集
    var recipe: PhotoRecipe {
        let s = sanitized
        guard let filter = StoryFilters.filter(id: s.id) else { return .identity }
        return filter.recipe(strength: s.strength)
    }

    /// 何も変えない選びか（焼き込み・書き出しを飛ばしてよい）
    var isNone: Bool { recipe.isIdentity }

    /// フィルターを選び直す。**強さは 1 に戻す**（前のフィルターの強さを引き継がない）
    func selecting(_ id: String) -> StoryFilterChoice {
        StoryFilterChoice(id: id, strength: 1).sanitized
    }

    /// 強さの刻み（0.05）に丸める。つまみを動かすたびに描き直す回数を減らす
    func withStrength(_ value: Double) -> StoryFilterChoice {
        guard value.isFinite else { return self }
        let stepped = (PhotoRecipe.clamp(value, PhotoRecipe.strengthRange) * 20).rounded() / 20
        return StoryFilterChoice(id: id, strength: stepped).sanitized
    }
}

/// フィルターの一覧（画面に出す順）。**約10種**。
enum StoryFilters {

    /// 写真の編集のプリセット（`PhotoPresets`）から1つ
    private static func preset(_ id: String, ja: String? = nil, en: String? = nil) -> StoryFilter {
        let source = PhotoPresets.preset(id: id)
        return StoryFilter(id: id, nameJa: ja ?? source?.nameJa ?? id, nameEn: en ?? source?.nameEn ?? id,
                           recipe: PhotoRecipe(preset: PhotoRecipe.PresetChoice(id: id, strength: 1)))
    }

    /// ストーリーだけの3つ（つまみの値の組・LUT なし）
    private static let vivid = StoryFilter(
        id: "story-vivid", nameJa: "鮮やか", nameEn: "Vivid",
        recipe: PhotoRecipe(contrast: 0.2, saturation: 0.45))
    private static let matte = StoryFilter(
        id: "story-matte", nameJa: "しっとり", nameEn: "Matte",
        recipe: PhotoRecipe(contrast: -0.05, saturation: -0.15, highlights: -0.15, shadows: 0.3))
    private static let mono = StoryFilter(
        id: "story-mono", nameJa: "白黒", nameEn: "Mono",
        recipe: PhotoRecipe(contrast: 0.15, saturation: -1))

    /// 「なし」を除く全部。並びは画面の順（色の強いもの → 空気感 → 白黒）
    static let all: [StoryFilter] = [
        vivid,
        preset("dusk"),
        preset("summer"),
        preset("harbor"),
        preset("morning"),
        preset("haze"),
        preset("postcard"),
        matte,
        mono,
        preset("sumi"),
        preset("silver"),
    ]

    static func filter(id: String) -> StoryFilter? {
        all.first { $0.id == id }
    }
}
