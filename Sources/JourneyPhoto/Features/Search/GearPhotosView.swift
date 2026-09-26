import SwiftUI

/// 「機材から探す」の先（モック9 の「機材から探す状態」・形は板 12）。
///
/// **その焦点距離で撮られた写真**を並べる。分け方は題の下の小さい字に、
/// 一言（`group.note`）は一覧の上に出す
/// ——なぜこの写真が並んでいるのかを隠さない。
struct GearPhotosView: View {

    let section: GearGroups.Section

    var body: some View {
        CollectionPhotosScreen(title: section.group.label,
                               note: L("焦点距離 \(section.group.range)", "\(section.group.range)"),
                               photos: section.photos,
                               lede: section.group.note)
    }
}
