import SwiftUI

/// 時計（とバー）の裏に敷く黒のぼかし。マイページと人のページで使う。
///
/// どちらも上のバーの地を出さない（マイページは隠す・人のページは透かす）ので、
/// 流した写真が時計・電池の字や戻る・「…」の真下を通って読めなくなる
/// （マイページで一度踏んだ）。`topInset` は置いた場所の安全域の高さ——
/// GeometryReader の原点は安全域の下なので、その分だけ上へずらして画面の上端から敷く。
/// 押す操作は下へ通す
struct TopBarScrim: View {

    let topInset: CGFloat

    var body: some View {
        LinearGradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: topInset + 16)
            .offset(y: -topInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
