import Foundation

/// 写真に写った物を、端末の画像分類（Vision の `VNClassifyImageRequest`）の名前から決める。
///
/// 🔴 **確かめていない**（板の付箋「集める」: 画像分類で森・川・雪をどこまで正しく分けられるか）。
/// 分類の名前は英語の小文字と _ の語（`forest`・`snow`・`beach`…）。語の一致で拾い、信頼度 0.3 未満は捨てる
enum CampSubjectRule {

    static let minimumConfidence: Float = 0.3

    /// 写った物 → 拾う分類の語
    static let keywords: [CampSubject: [String]] = [
        .forest: ["forest", "woodland", "jungle", "conifer", "evergreen", "tree", "trees"],
        .mountain: ["mountain", "mountains", "hill", "cliff", "volcano", "alps", "peak", "summit"],
        .starrySky: ["star", "stars", "night_sky", "milky_way", "galaxy", "astronomy"],
        .campfire: ["campfire", "bonfire", "fire", "fireplace", "flame"],
        .seaside: ["beach", "shore", "ocean", "sea", "coast", "seashore", "seaside"],
        .bamboo: ["bamboo"],
        .park: ["park", "garden", "playground"],
        .river: ["river", "stream", "creek", "rapids"],
        .waterside: ["waterfront", "pond", "waterside", "riverbank", "lakeside", "pier", "dock"],
        .lake: ["lake", "pond", "reservoir"],
        .wetland: ["wetland", "marsh", "swamp", "bog"],
        .pasture: ["pasture", "farm", "ranch", "meadow", "grassland", "cattle", "cow", "sheep", "horse"],
        .springWater: ["hot_spring", "fountain", "well", "geyser"],
        .firewood: ["firewood", "woodpile", "lumber", "log", "logs"],
        .snow: ["snow", "snowy", "glacier", "frost", "ski", "snowman", "ice"],
    ]

    /// 人を表す分類の語（人の写った写真は数えない・切り絵にしない）
    static let peopleKeywords: Set<String> = ["people", "person", "adult", "child", "baby", "crowd", "portrait", "selfie"]

    static func subjects(labels: [(String, Float)]) -> [CampSubject] {
        var found: Set<CampSubject> = []
        for (raw, confidence) in labels where confidence >= minimumConfidence {
            let id = raw.lowercased()
            let tokens = Set(id.split(separator: "_").map(String.init) + [id])
            for (subject, words) in keywords where words.contains(where: { tokens.contains($0) }) {
                found.insert(subject)
            }
        }
        return CampSubject.allCases.filter { found.contains($0) }
    }

    static func showsPeople(labels: [(String, Float)]) -> Bool {
        labels.contains { $0.1 >= 0.5 && peopleKeywords.contains($0.0.lowercased()) }
    }

    /// 切り絵の題（写った物から 1 つ）。板の見本は「霧の針葉樹林」
    static func title(_ subjects: [CampSubject], season: CampSeason) -> String {
        let order: [CampSubject] = [.starrySky, .campfire, .snow, .bamboo, .waterside, .lake, .river, .seaside, .wetland,
                                    .pasture, .springWater, .firewood, .park, .mountain, .forest]
        guard let s = order.first(where: subjects.contains) else { return L("撮った景色", "Your view") }
        switch s {
        case .forest:
            if subjects.contains(.mountain) { return L("山の針葉樹林", "Mountain conifers") }
            return season == .autumn ? L("秋の森", "Autumn forest") : L("針葉樹の森", "Conifer forest")
        case .mountain: return L("山の稜線", "Mountain ridge")
        case .starrySky: return L("星空", "Starry sky")
        case .campfire: return L("焚き火", "Campfire")
        case .seaside: return L("海辺", "Seaside")
        case .bamboo: return L("竹林", "Bamboo grove")
        case .park: return L("公園の木立", "Park trees")
        case .river: return L("川辺", "Riverside")
        case .waterside: return L("水辺", "Waterside")
        case .lake: return L("湖のほとり", "Lakeside")
        case .wetland: return L("湿原", "Wetland")
        case .pasture: return L("牧場", "Pasture")
        case .springWater: return L("湧き水", "Spring water")
        case .firewood: return L("薪", "Firewood")
        case .snow: return L("雪の林", "Snowy woods")
        }
    }
}
