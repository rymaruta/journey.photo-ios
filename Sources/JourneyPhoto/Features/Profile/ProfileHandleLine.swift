import SwiftUI

/// 「@ユーザー名 · 居住地」の1行（`ProfileLine.handleAndHome`）。マイページと人のページで使う。
///
/// 居住地は**地図には出さない**（住んでいる場所はピンにしない）。
/// 頭の印はマイページの板（05c）どおり**線のピン**（11pt）——絵文字の「📍」は赤く出ていた。
/// 人のページの板（31）はピンを描いていないので `showsPin: false`
struct ProfileHandleLine: View {

    let line: ProfileLine.HandleAndHome
    let showsPin: Bool

    var body: some View {
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
                if showsPin {
                    Image(systemName: "mappin")
                        .font(.system(size: 11))
                }
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
