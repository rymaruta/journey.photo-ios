import SwiftUI

/// 「色から探す」の先（モック9 の「色から探す状態」）。
///
/// 並ぶのは**その色味の代表色を持つ写真だけ**。色を持たない写真は
/// 混ぜない——「分からない」を「その色」として数えない。
struct ColorPhotosView: View {

    let section: ColorFamilies.Section

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("\(section.family.note)・\(section.count)枚",
                       "\(section.family.note) · \(section.count) photos"))
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                    .padding(.horizontal, 16)

                PhotoGrid(photos: section.photos) { photo in
                    PhotoDetailView(photo: photo, context: section.photos)
                }
            }
            .padding(.vertical, 12)
            .padding(.bottom, 24)
        }
        .webScreen()
        .navigationTitle(section.family.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}
