import SwiftUI

// **モデルに SwiftUI の型を持ち込まない。** `Photo` は Foundation だけで
// 立っていて、テストもそこに乗っている。寄せ先への読み替えはここで行う。
extension Photo {

    /// 一覧で切り抜くときの寄せ先。`FocalCrop` を SwiftUI の言葉に直すだけ。
    var gridAlignment: Alignment {
        switch gridCrop {
        case .center: return .center
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}
