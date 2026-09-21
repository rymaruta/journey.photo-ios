import SwiftUI

/// 今日のテーマ（モック1 の「今日のミッション」）。
///
/// **通信をしない。** テーマは日付から決まり（`DailyTheme`）、参加したか
/// どうかは自分の写真を見て決める。サーバーにテーマを配る口も、参加を
/// 数える口も無いので、**参加人数のような数は出さない**。
struct DailyThemeCard: View {

    /// 背景に使う写真。**そのテーマのタグが付いた公開写真**から1枚
    /// （無ければ背景なしで出す——別のテーマの写真を当てない）
    let photos: [Photo]
    /// 自分の写真（参加したかの判定に使う）
    let myPhotos: [Photo]

    private var theme: DailyTheme.Theme { DailyTheme.today() }
    private var joined: Bool { DailyTheme.hasJoined(theme, myPhotos: myPhotos) }

    private var backdrop: Photo? {
        let key = TagChoices.key(theme.tag)
        let matched = photos.filter { photo in
            (photo.tags ?? []).contains { TagChoices.key($0) == key }
        }
        return GallerySort.popular.apply(matched).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text(L("今日のテーマ", "Today's theme"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("#\(theme.tag)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(WebTheme.surface, in: Capsule())
            }
            .foregroundStyle(WebTheme.muted)

            Text(theme.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(WebTheme.foreground)

            Text(theme.prompt)
                .font(.subheadline)
                .foregroundStyle(WebTheme.muted2)
                .fixedSize(horizontal: false, vertical: true)

            if joined {
                // **参加済みは「押せない印」にする。** 同じ日に何度も
                // 促さない（写真は自分の写真から確かめたもの）
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(L("参加済み", "Joined"))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(WebTheme.foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Button {
                    MissionRouter.shared.join(tag: theme.tag)
                } label: {
                    HStack(spacing: 6) {
                        Text(L("参加する", "Join"))
                            .font(.subheadline.weight(.bold))
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(WebTheme.foreground, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(WebTheme.accentText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(alignment: .trailing) {
            if let backdrop {
                // **写真は脇役。** 文字が読めなくならないよう、右側だけに薄く
                RemoteImage(url: backdrop.gridImageURL, alignment: backdrop.gridAlignment)
                    .frame(width: 160)
                    .opacity(0.35)
                    .mask {
                        LinearGradient(colors: [Color.black.opacity(0), Color.black],
                                       startPoint: .leading, endPoint: .trailing)
                    }
            }
        }
        .background(WebTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }
}
