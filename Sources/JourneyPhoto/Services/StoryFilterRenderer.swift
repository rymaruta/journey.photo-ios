import Foundation
import UIKit

/// ストーリーのフィルターを写真に当てる（`PhotoRenderer` の Core Image をそのまま使う・段 2a）。
///
/// 描く本体は**写真の編集と同じ**（`PhotoRenderer.shared`: Metal 対応の `CIContext` を1つ使い回す・
/// 拡張リニア Display P3 で作業・元の画素は変えない）。ここは「作る画面の絵」「帯の見本」「焼き込み」の
/// 3つの入口だけで、**どれも主スレッドの外で呼ぶ**（画面の呼び手が `Task.detached` に入れる）。
enum StoryFilterRenderer {

    /// 写真に当てた絵。`recipe` が無編集（なし・強さ 0）なら nil——呼ぶ側は元の絵をそのまま使う。
    /// `maxPixelSize` は長い辺（元より大きくはしない）。読めなければ nil
    static func image(data: Data, recipe: PhotoRecipe, maxPixelSize: Int) -> UIImage? {
        guard !recipe.isIdentity,
              let cgImage = PhotoRenderer.shared.render(data: data, recipe: recipe, maxPixelSize: maxPixelSize)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// 帯の見本（全フィルターと「なし」・id → 絵）。**写真を1回だけ小さく読み**、フィルターごとに当てる。
    /// 読めなければ空
    static func swatches(data: Data, maxPixelSize: Int) -> [String: UIImage] {
        guard let loaded = PhotoRenderer.load(data: data, maxPixelSize: maxPixelSize) else { return [:] }
        var result: [String: UIImage] = [:]
        var entries: [(String, PhotoRecipe)] = [(StoryFilterChoice.noneId, PhotoRecipe.identity)]
        for filter in StoryFilters.all { entries.append((filter.id, filter.recipe)) }
        for (id, recipe) in entries {
            if let cgImage = PhotoRenderer.shared.preview(recipe, loaded: loaded) {
                result[id] = UIImage(cgImage: cgImage)
            }
        }
        return result
    }
}
