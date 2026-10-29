import SwiftUI

/// 全体の再生器の透け方を確かめる見本の地（UI テストだけ・`PreviewSession.miniPlayerBackdrop`）。
///
/// 2026-10-29 判断（#402・owner「背景透過させて、後ろの画像とかが見えるようにしたい」）: 再生器の地を
/// ぼかし無しの薄い黒にしたので、**白い写真（雪・空）・模様の多い写真（色の多い街並み＋白い字）・黒い写真（夜）**の
/// 上で曲名・歌手名・停止ボタンが読めるかを、毎回同じ絵で見る。通信で来る写真は回ごとに変わるので作り物で敷く。
/// 鳴っている間だけ、画面を上から白・模様・黒の3段で覆う（触れない・読み上げない）
struct MiniPlayerBackdrop: View {

    @ObservedObject private var player = MusicPreviewPlayer.shared

    /// 模様の段の色（鮮やかな色と明るい色を混ぜる）
    private static let busyColors: [Color] = [
        Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.20, green: 0.55, blue: 0.85),
        Color(red: 0.98, green: 0.92, blue: 0.70), Color(red: 0.25, green: 0.60, blue: 0.30),
        Color(red: 0.85, green: 0.25, blue: 0.35), Color(red: 0.92, green: 0.92, blue: 0.95),
    ]

    var body: some View {
        if PreviewSession.miniPlayerBackdrop, player.playingSong != nil {
            // 段の高さは画面の 40%・30%・30%。再生器のいちばん上（見出しの下・`MiniPlayerPlacement.topReserved`）が
            // 白の段に、真ん中が模様の段に、最初の置き場所（右下）が黒の段に来る
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    // 白い写真（雪・曇り空）
                    Color(red: 0.96, green: 0.96, blue: 0.94)
                        .frame(height: proxy.size.height * 0.4)
                    // 模様の多い写真（色の格子＋下の説明文のような白い字）
                    busy
                        .frame(height: proxy.size.height * 0.3)
                    // 黒い写真（夜）
                    Color(red: 0.04, green: 0.04, blue: 0.06)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var busy: some View {
        ZStack {
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { col in
                            Self.busyColors[(row * 5 + col * 2) % Self.busyColors.count]
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in
                    Text(verbatim: "いまの季節のスポット。朝の光が斜めに差し、水面に山の影が映る")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
        }
        .clipped()
    }
}
