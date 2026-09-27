import SwiftUI

/// 「色から探す」の先（モック9 の「色から探す状態」・形は板 12）。
///
/// 並ぶのは**その色味の代表色を持つ写真だけ**。色を持たない写真は
/// 混ぜない——「分からない」を「その色」として数えない。
struct ColorPhotosView: View {

    let section: ColorFamilies.Section

    var body: some View {
        CollectionPhotosScreen(title: section.family.note, note: section.family.label,
                               photos: section.photos)
    }
}
