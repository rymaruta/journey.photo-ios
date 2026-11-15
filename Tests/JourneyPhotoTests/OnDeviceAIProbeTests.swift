#if os(iOS)
import UIKit
import XCTest
@testable import JourneyPhoto

/// 端末の AI（投稿の候補・札 #622）の**日本語の出来と、Mac のシミュレーターで動くか**を数で取る（2026-11-15）。
///
/// 作り込む前の試し（owner の指示「例の写真と撮影地10組で、端末の AI が出す題とタグを数で見る」）。
/// 例の写真はアプリに入っている構図の見本の写真（`Assets.xcassets` の `composition-ai-*`）。撮影地は写真に合いそうな
/// 日本の場所を人が当てた（写真の本当の撮影地ではない）。
///
/// 書き出す行（Mac の `xcodebuild-full.log`）:
/// - `measured [onDeviceAI] status=…` 端末の AI が使えるか（使えない理由）
/// - `measured [postSuggest] case=… labels=… ms=… raw.titles=… raw.caption=… raw.tags=… shown.titles=… …`
/// - `measured [postSuggest] summary …` 10組の数（候補が出た組・題の数・タグの数・落とした題の数・失敗）
///
/// **端末の AI が使えない環境（Apple Intelligence の無い Mac のシミュレーター）では、理由を書いて抜ける。**
/// 失敗にはしない——使えないことが答え（「確かめられない」と報告する）
final class OnDeviceAIProbeTests: XCTestCase {

    private struct Case {
        let asset: String
        let input: PostSuggest.Input
    }

    private static let cases: [Case] = [
        Case(asset: "composition-ai-tunnel", input: .init(place: "伏見稲荷大社（京都府京都市）", spotName: "伏見稲荷大社",
                                                          spotSeasons: ["autumn"], spotTimes: ["morning"],
                                                          takenOn: "2026-06-14", takenHour: 8)),
        Case(asset: "composition-ai-sCurve", input: .init(place: "いろは坂（栃木県日光市）", spotName: "いろは坂",
                                                          spotSeasons: ["autumn"], spotTimes: ["morning"],
                                                          takenOn: "2026-10-25", takenHour: 10)),
        Case(asset: "composition-ai-triangle", input: .init(place: "大山（鳥取県）", takenOn: "2026-11-08", takenHour: 9)),
        Case(asset: "composition-ai-symmetry", input: .init(place: "琵琶湖（滋賀県）", spotName: "琵琶湖",
                                                            spotSeasons: ["summer"], spotTimes: ["dawn"],
                                                            takenOn: "2026-03-02", takenHour: 6)),
        Case(asset: "composition-ai-radial", input: .init(place: "大井川（静岡県）", takenOn: "2026-05-20", takenHour: 7)),
        Case(asset: "composition-ai-hinomaru", input: .init(place: "嘉瀬川（佐賀県佐賀市）", takenOn: "2026-11-01", takenHour: 8)),
        Case(asset: "composition-ai-frameWithin", input: .init(place: "江の島（神奈川県藤沢市）", spotName: "江の島",
                                                               spotSeasons: ["summer"], spotTimes: ["goldenHour"],
                                                               takenOn: "2026-08-12", takenHour: 15)),
        Case(asset: "composition-ai-negativeSpace", input: .init(place: "犬吠埼灯台（千葉県銚子市）", spotName: "犬吠埼灯台",
                                                                 spotSeasons: ["winter"], spotTimes: ["dawn"],
                                                                 takenOn: "2026-02-11", takenHour: 7)),
        Case(asset: "composition-ai-horizon", input: .init(place: "鳥取砂丘（鳥取県鳥取市）", spotName: "鳥取砂丘",
                                                           spotSeasons: ["winter"], spotTimes: ["goldenHour"],
                                                           takenOn: "2026-01-20", takenHour: 15)),
        // 撮影地が無い写真（位置情報の無い写真）。日時と写真の中身だけ
        Case(asset: "composition-ai-goldenSpiral", input: .init(takenOn: "2026-09-14", takenHour: 17)),
    ]

    func testJapaneseQualityOfOnDeviceSuggestions() async {
        let status = OnDeviceAI.systemStatus
        print("measured [onDeviceAI] status=\(status)")

        var labelled = 0
        var shown = 0, titles = 0, tags = 0, captions = 0, dropped = 0, failures = 0, mentions = 0
        var badWords = 0
        var times: [Int] = []
        for (index, item) in Self.cases.enumerated() {
            guard let image = UIImage(named: item.asset), let data = image.jpegData(compressionQuality: 0.8) else {
                print("measured [postSuggest] case=\(index + 1) asset=\(item.asset) image=missing")
                continue
            }
            var input = item.input
            let started = Date()
            input.labels = await PostSuggester.labels(for: data)
            let visionMs = Int(Date().timeIntervalSince(started) * 1000)
            if !input.labels.isEmpty { labelled += 1 }
            guard status.isAvailable else {
                print("measured [postSuggest] case=\(index + 1) asset=\(item.asset) visionMs=\(visionMs) labels=\(input.labels)")
                continue
            }
            let asked = Date()
            let answer = await PostSuggester.ask(input)
            let ms = Int(Date().timeIntervalSince(asked) * 1000)
            times.append(ms)
            let result = PostSuggest.result(titles: answer.titles, caption: answer.caption, tags: answer.tags)
            if answer.error != nil { failures += 1 }
            if !result.isEmpty { shown += 1 }
            titles += result.titles.count
            tags += result.tags.count
            if result.caption != nil { captions += 1 }
            dropped += max(0, min(answer.titles.count, PostSuggest.titleCount) - result.titles.count)
            // 撮影地・観光スポットの名前（かっこの前）が題か説明に入ったか
            let name = (input.spotName ?? input.place).components(separatedBy: "（").first ?? ""
            if !name.isEmpty, (result.titles + [result.caption ?? ""]).contains(where: { $0.contains(name) }) { mentions += 1 }
            let raw = answer.titles + [answer.caption ?? ""]
            if raw.contains(where: { text in ["・", "·", "撮りどき", "捨て", "撮影スポット"].contains { text.contains($0) } }) {
                badWords += 1
            }
            print("measured [postSuggest] case=\(index + 1) asset=\(item.asset) visionMs=\(visionMs) ms=\(ms)"
                  + " labels=\(input.labels) raw.titles=\(answer.titles) raw.caption=\(answer.caption ?? "-")"
                  + " raw.tags=\(answer.tags) error=\(answer.error ?? "-")"
                  + " shown.titles=\(result.titles) shown.caption=\(result.caption ?? "-") shown.tags=\(result.tags)")
            // 縛り: 出したタグは決まった選択肢の語だけ
            XCTAssertTrue(result.tags.allSatisfy(TagChoices.all.contains), "選択肢に無いタグ \(result.tags)")
        }
        let sorted = times.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        print("measured [postSuggest] summary status=\(status) cases=\(Self.cases.count) visionLabelled=\(labelled)"
              + " shown=\(shown) titles=\(titles) captions=\(captions) tags=\(tags) droppedTitles=\(dropped)"
              + " rawBadWords=\(badWords) placeMentioned=\(mentions) failures=\(failures) medianMs=\(median) maxMs=\(sorted.last ?? 0)")
    }
}
#endif
