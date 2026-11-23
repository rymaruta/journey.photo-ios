import SwiftUI

// 写真の色に、日本の色の名前（札 #710 の案10・`JapaneseColors`）の画面の部品。
// 写真の詳細（と、同じ部品を使う投稿の前のプレビューの「詳細」）の1行と、「この色の写真」の画面

/// 名前の色の丸（色だけで伝えない: 横に必ず名前を出す。縁は白 20%）
private struct JapaneseColorSwatch: View {
    let color: JapaneseColors.Color
    let side: CGFloat

    var body: some View {
        Circle()
            .fill(SwiftUI.Color(red: Double((color.hex >> 16) & 0xFF) / 255,
                                green: Double((color.hex >> 8) & 0xFF) / 255,
                                blue: Double(color.hex & 0xFF) / 255))
            .frame(width: side, height: side)
            .overlay(Circle().strokeBorder(SwiftUI.Color.white.opacity(0.2), lineWidth: JPStroke.hairline))
            .accessibilityHidden(true)
    }
}

/// 写真の詳細の1行「● 紅緋　べにひ　　この色の写真 ›」と由来の1行。**名前を出せない写真では何も出さない**
struct JapaneseColorLine: View {
    let photo: Photo

    var body: some View {
        if let color = JapaneseColors.name(forHex: photo.dominantColor) {
            VStack(alignment: .leading, spacing: 2) {
                NavigationLink {
                    JapaneseColorPhotosView(color: color)
                } label: {
                    HStack(spacing: 10) {
                        JapaneseColorSwatch(color: color, side: 22)
                        Text(color.shownName)
                            .font(JPFont.rowTitle)
                            .foregroundStyle(WebTheme.foreground)
                        if let reading = color.shownReading {
                            Text(reading)
                                .font(JPFont.caption)
                                .foregroundStyle(WebTheme.text3)
                        }
                        Spacer(minLength: 8)
                        // 黒地の上の手がかりなので真鍮（owner の好み）
                        Text(L("この色の写真 ›", "Photos in this color ›"))
                            .font(.footnote)
                            .foregroundStyle(WebTheme.accent)
                    }
                    .frame(minHeight: WebTheme.minTapTarget)
                    .overlay(alignment: .top) { Rectangle().fill(WebTheme.hairline).frame(height: JPStroke.hairline) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("写真の色は\(color.name)、\(color.reading)", "Photo color: \(color.romaji)"))
                .accessibilityHint(L("この色の写真を開きます", "Opens photos in this color"))
                .accessibilityIdentifier("photo.japaneseColor")
                Text(color.shownOrigin)
                    .font(JPFont.caption)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 「この色の写真」（札 #710 の案10）。名前の色を見出しに、近い色へ横に移れるチップ。並ぶのは公開の一覧の代表色から、
/// 同じ名前になる写真（少ない色は近い色の写真も混ぜる・`JapaneseColors.photos`）。端末で集める
struct JapaneseColorPhotosView: View {
    @State var color: JapaneseColors.Color

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var hidden: ModerationStore
    @State private var all: [Photo]?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JPSpace.s) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        JapaneseColorSwatch(color: color, side: 36)
                        Text(color.shownName)
                            .font(JPFont.screenTitle)
                            .foregroundStyle(WebTheme.foreground)
                            .accessibilityAddTraits(.isHeader)
                        if let reading = color.shownReading {
                            Text(reading)
                                .font(.footnote)
                                .foregroundStyle(WebTheme.text3)
                        }
                    }
                    Text(color.shownOrigin)
                        .font(.footnote)
                        .foregroundStyle(WebTheme.text2)
                }
                .padding(.horizontal, JPSpace.gutter)
                // 近い色へ移る（選んでいる色は白の塗り＋チェック・板の絞り込みのチップ）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: JPSpace.xs) {
                        ForEach([color] + JapaneseColors.neighbors(of: color)) { other in
                            Button { color = other } label: {
                                HStack(spacing: 6) {
                                    if other == color {
                                        Image(systemName: "checkmark").font(.caption2.weight(.bold))
                                    } else {
                                        JapaneseColorSwatch(color: other, side: 12)
                                    }
                                    Text(other.shownName).font(.footnote.weight(other == color ? .semibold : .regular))
                                }
                                .foregroundStyle(other == color ? WebTheme.accentText : WebTheme.chipText)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(other == color ? WebTheme.accentBackground : SwiftUI.Color.white.opacity(0.07),
                                            in: Capsule())
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(other == color ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, JPSpace.gutter)
                }
                if let all {
                    let shown = hidden.visible(JapaneseColors.photos(for: color, in: all))
                    if shown.isEmpty {
                        EmptyState(icon: nil, title: L("まだ写真がありません", "No photos yet"),
                                   message: L("この色の写真が投稿されると、ここに並びます", "Photos in this color will appear here."))
                    } else {
                        PhotoGrid(photos: shown) { photo in
                            PhotoDetailView(photo: photo, context: shown)
                        }
                    }
                } else if failed {
                    ErrorBanner(message: L("写真を読み込めませんでした", "Couldn't load photos"), isBusy: false, look: .classic) {
                        Task { await load() }
                    }
                } else {
                    JPLoadingState(kind: .rows)
                }
            }
            .padding(.vertical, JPSpace.s)
        }
        .background(SwiftUI.Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("japaneseColor.photos")
        .task { if all == nil { await load() } }
    }

    private func load() async {
        failed = false
        let photos = try? await environment.gallery.fetchPhotos()
        if let photos { all = photos } else { failed = true }
    }
}
