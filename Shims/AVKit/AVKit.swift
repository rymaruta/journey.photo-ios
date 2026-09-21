// AVKit の模型（Linux で型検査を通すためだけのもの）。
//
// 本物は iOS 14 以降の `VideoPlayer`。ここでは「View である」ことと
// 初期化の形だけを写す。
import SwiftUI
import AVFoundation

public struct VideoPlayer<Overlay: View>: View {
    public init(player: AVPlayer?) where Overlay == EmptyView {}
    public init(player: AVPlayer?, @ViewBuilder videoOverlay: () -> Overlay) {}
    public var body: some View { EmptyView() }
}
