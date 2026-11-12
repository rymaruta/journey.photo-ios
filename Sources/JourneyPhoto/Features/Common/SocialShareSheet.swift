import SwiftUI

/// 写真の詳細の ⋯ →「SNS に載せる」の画面（2026-11-12 秘書室の判断・1.1.83 第9章）。
///
/// **⋯ の行は「SNS に載せる」1つのまま**（行を増やさない）。開いた画面の上で「投稿 | ストーリー」を切り替える:
/// - 投稿 → 今までの写真1枚のカード（`SignatureShareCardSheet`・型と比率を選ぶ画面をそのまま出す）
/// - ストーリー → 旅をストーリーに（`TravelStorySheet`・型を払って選ぶ1枚）
///
/// はじめは投稿（今までと同じ）。**前に選んだ側から始まる**（ストーリーを使う人は次から1回で届く）
struct SocialShareSheet: View {

    enum Mode: String, CaseIterable, Identifiable {
        case post
        case story

        var id: String { rawValue }

        var label: String {
            switch self {
            // 比率の字は付けない（投稿の側に 4:5／9:16／1:1 の切り替えがあり、重なる・2026-11-12 確かめ役）
            case .post: return L("投稿", "Post")
            case .story: return L("ストーリー", "Story")
            }
        }

        static let defaultsKey = "socialShare.mode"

        static func load(_ defaults: UserDefaults = .standard) -> Mode {
            defaults.string(forKey: defaultsKey).flatMap(Mode.init(rawValue:)) ?? .post
        }

        static func save(_ mode: Mode, _ defaults: UserDefaults = .standard) {
            defaults.set(mode.rawValue, forKey: defaultsKey)
        }
    }

    // 投稿（写真1枚のカード）
    let photoData: Data
    let credit: SignatureShareCardRenderer.Credit
    let shareText: String
    let avatarURL: URL?
    // ストーリー
    let leadURL: URL
    let filmURLs: [URL]
    let facts: TravelStory.Facts

    @State private var mode: Mode = Mode.load()

    var body: some View {
        switch mode {
        case .post:
            SignatureShareCardSheet(photoData: photoData, credit: credit, shareText: shareText,
                                    avatarURL: avatarURL, header: AnyView(picker))
        case .story:
            // 先頭の写真はもう読んである（`photoData`）。読み直さない
            TravelStorySheet(leadURL: leadURL, filmURLs: filmURLs, facts: facts, phase: .now,
                             leadData: photoData, header: AnyView(picker.padding(.bottom, JPSpace.xs)))
        }
    }

    private var picker: some View {
        TravelStorySegment(items: Mode.allCases, selection: mode, label: \.label,
                           groupLabel: L("載せる先", "Where to post"), idPrefix: "socialShare.mode") { next in
            mode = next
            Mode.save(next)
        }
        .padding(.horizontal, JPSpace.m)
        .padding(.top, JPSpace.xs)
    }
}
