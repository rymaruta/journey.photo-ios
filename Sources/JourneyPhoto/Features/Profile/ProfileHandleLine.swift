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
                    // 名前と居住地は区切りの記号を置かず余白で分ける（2026-11-12 owner・間 8）
                    .padding(.trailing, line.home != nil ? 4 : 0)
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
        // v2（板 MyPage・UserProfile: 13px・text-3）。黒地の上だけなので不透明の灰
        .font(JPFont.footnote)
        .foregroundStyle(WebTheme.text3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spoken)
    }
}
