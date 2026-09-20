import Foundation

/// 一覧で切り抜くときに、写真のどこを残すか。
///
/// owner が Web で掴んで動かした位置（`Photo.focalPoint`・0〜1 の割合。
/// `app/components/CropFramePicker.tsx`）を、SwiftUI が寄せられる9方向に
/// 丸めたもの。
///
/// **SwiftUI の型を混ぜない。** `Alignment` に直すのは画面側
/// （`PhotoFocal.swift`）の仕事で、ここは数だけを見る——そうしないと
/// Linux 上のテストで確かめられない（模型の `Alignment` は中身が無く、
/// 何と比べても等しくなるので**何も検証しないテスト**になる）。
enum FocalCrop: String, Equatable {
    case center, top, bottom, leading, trailing
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    /// **3等分していちばん近い方向へ。** 連続的に寄せるには画像の縦横比が
    /// 要るが、`AsyncImage` は教えてくれない。中央固定よりは指定に近い。
    static func bucket(x: Double, y: Double) -> FocalCrop {
        switch (x, y) {
        case (..<0.34, ..<0.34): return .topLeading
        case (..<0.34, 0.67...): return .bottomLeading
        case (..<0.34, _): return .leading
        case (0.67..., ..<0.34): return .topTrailing
        case (0.67..., 0.67...): return .bottomTrailing
        case (0.67..., _): return .trailing
        case (_, ..<0.34): return .top
        case (_, 0.67...): return .bottom
        default: return .center
        }
    }
}
