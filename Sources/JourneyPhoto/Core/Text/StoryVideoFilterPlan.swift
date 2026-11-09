import Foundation

/// 動画にフィルターをかける書き出しの決まり（2026-11-09・段 2b）。**画面と AVFoundation から出しておく**
/// （Linux の `swift test` で確かめるため）。
///
/// ## なぜ「2回に分ける」か（2026-11-09 判断・**確かめていない前提を避けた**）
/// 重ねの焼き込み（`AVVideoCompositionCoreAnimationTool`）と、Core Image でコマごとにフィルターをかける
/// `AVMutableVideoComposition(asset:applyingCIFiltersWithHandler:)` は、**同じ動画の合成に同時には使えない**
/// と思われる（カスタムの合成器と Core Animation の道具の併用）。ただし実機で確かめていない。
/// 重ねを1枚絵にしてハンドラの中で合成する形に寄せると、**重ねの位置・向き（縦動画の歪み）・上下反転**を
/// 作り直すことになり、いまの焼き込み（実機で確かめ済み）を壊す危険のほうが大きい。
///
/// そこで**フィルターをかけるだけの1回目**（切り取り・縮小・フィルター → 中間の動画）を足し、
/// **2回目は今までと同じ道**（向き補正・重ねの焼き込み・50MB の段下げ・位置情報の除去）を、
/// 中間の動画を元に通す。重ねの焼き込みには一切手を入れない。代わりに書き出しの時間は延び、
/// 画は1回余分に符号化される（1回目は最高画質）。**実機で書き出しの時間・メモリを測り、遅ければ
/// 1回に寄せる**（札の「確かめていないこと」）。
///
/// フィルターが「なし」の動画は1回目を通らない（今までと同じ・時間も増えない）。
enum StoryVideoFilterPlan {

    /// 1回目の出力の大きさ。**最上段（長い辺 1920）に収める・偶数**（2回目の段はここから縮める）。
    /// 4K の動画を 4K のまま符号化して中間の動画が数百 MB にならないようにする
    static func passRenderSize(oriented: CGSize) -> CGSize {
        StoryVideoRules.renderSize(for: oriented, step: StoryVideoRules.allSteps[0])
    }

    /// 1コマ（`extent` の大きさ）を `target` に合わせる縦横の倍率
    static func scale(from extent: CGSize, to target: CGSize) -> (x: CGFloat, y: CGFloat) {
        guard extent.width > 0, extent.height > 0, target.width > 0, target.height > 0 else { return (1, 1) }
        return (target.width / extent.width, target.height / extent.height)
    }

    /// 2回目の元になる動画（1回目が書いた中間の動画）。**切り取りは1回目で済んでいる**ので、範囲は全部・
    /// 長さは残した長さ。大きさは1回目の出力の大きさ（向きは直してある）
    static func secondPassClip(from clip: StoryVideoClip, intermediate url: URL, size: CGSize) -> StoryVideoClip {
        StoryVideoClip(url: url, durationSec: clip.outputSeconds, size: size, bytes: 0)
    }

    /// 1回目の出力の向きが、目標と合っているか（縦横の比が 5% 以内）。
    /// **合っていないまま出さない**——ハンドラの1コマの向きが想定と違った（横向きの動画になった）ときの保険で、
    /// 呼ぶ側は合わなければ書き出しを失敗にする（黙って横向きの動画を上げない）。
    /// 正方形に近い動画は縦横の差が出ないので、取り違えても害が無く、合っていると扱う
    static func orientationMatches(expected: CGSize, actual: CGSize) -> Bool {
        guard expected.width > 0, expected.height > 0, actual.width > 0, actual.height > 0 else { return false }
        let ratio = (expected.width / expected.height) / (actual.width / actual.height)
        return ratio > 0.95 && ratio < 1.05
    }
}

extension StoryVideoTrim {

    /// 実際の動画の長さ（`assetDuration`・丸めで保存した長さとわずかに違う）に収めた、元の動画の側の範囲。
    /// 始点は動画の外へ出さず、長さは最短を割らず動画の終わりを越えない
    func sourceRange(assetDuration: Double) -> (start: Double, length: Double) {
        guard assetDuration.isFinite, assetDuration > 0 else { return (start, length) }
        let from = min(start, max(assetDuration - minimumLength, 0))
        let span = min(length, max(assetDuration - from, minimumLength))
        return (from, span)
    }
}
