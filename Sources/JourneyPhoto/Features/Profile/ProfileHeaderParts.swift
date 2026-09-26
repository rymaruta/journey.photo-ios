import SwiftUI

/// 見出しの「@ユーザー名 · (線のピン)居住地」の1行（板 05c・31）。
/// マイページと人のページで同じものを使う——片方だけ直して食い違わないように
struct ProfileHandleLine: View {

    let line: ProfileLine.HandleAndHome

    var body: some View {
        // 居住地は**地図には出さない**（住んでいる場所はピンにしない）。
        // 頭の印は板どおり**線のピン**（11pt）——絵文字の「📍」は赤く出ていた
        HStack(spacing: 4) {
            if let handle = line.handle {
                // 狭いときは居住地の方を先に詰める（名前と「·」を残す）
                Text(handle)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if line.handle != nil && line.home != nil {
                Text("·")
                    .layoutPriority(1)
            }
            if let home = line.home {
                Image(systemName: "mappin")
                    .font(.system(size: 11))
                Text(home)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(WebTheme.faint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spoken)
    }
}

/// ひとことと自己紹介（板: 13px・行間 1.6・白72%）。空は出さず、同じ文は二度出さない
struct ProfileAbout: View {

    let status: String?
    let bio: String?

    var body: some View {
        ForEach(ProfileLine.about(status: status, bio: bio), id: \.self) { text in
            Text(text)
                .font(.footnote)
                .lineSpacing(4)
                .foregroundStyle(WebTheme.muted2)
        }
    }
}
