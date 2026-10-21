import SwiftUI

/// 時計（とバー）の裏に敷く黒のぼかし。マイページ・人のページ・写真の詳細で使う。
///
/// どれも上のバーの地を出さない（マイページは隠す・人のページと写真の詳細は透かす）ので、
/// 流した写真が時計・電池の字や戻る・「…」の真下を通って読めなくなる
/// （マイページで一度踏んだ）。`topInset` は置いた場所の安全域の高さ——
/// GeometryReader の原点は安全域の下なので、その分だけ上へずらして画面の上端から敷く。
/// 押す操作は下へ通す
///
/// **`solid`（2026-10-21 判断・run 609 の 15・33）**: マイページ・人のページは、時計の帯の下を**黒で塗る**。
/// 0.7 のぼかしでは、送った格子や札の中身が時計の真下に透けて「潜って」見えた。帯の下だけ黒 100%、
/// その下 `fade` の分で消える。写真の詳細は写真が主役なので、これまでどおりのぼかし
struct TopBarScrim: View {

    let topInset: CGFloat
    var solid = false

    /// 黒の帯の下で消えていく長さ
    static let fade: CGFloat = 16

    /// 塗りの段（上端からの割合と黒の濃さ）。`solid` は時計の帯の下端まで黒 100%
    static func stops(topInset: CGFloat, solid: Bool) -> [(location: CGFloat, opacity: Double)] {
        guard solid else { return [(0, 0.7), (1, 0)] }
        let height = topInset + fade
        let bandEnd = height > 0 ? topInset / height : 0
        return [(0, 1), (bandEnd, 1), (1, 0)]
    }

    var body: some View {
        LinearGradient(stops: Self.stops(topInset: topInset, solid: solid).map {
                           Gradient.Stop(color: Color.black.opacity($0.opacity), location: $0.location)
                       },
                       startPoint: .top, endPoint: .bottom)
            .frame(height: topInset + Self.fade)
            .offset(y: -topInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
