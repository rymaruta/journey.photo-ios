import Foundation

/// **ストーリーを見る画面の寸法と濃さ**（v2 の板 StoryViewer・Paused・Menu・Reply・Mine・
/// DeleteConfirm・HighlightPlayer・2026-10-14）。
///
/// 画面（`StoryViewerView`）に 3・0.45・52 と数を直に書いていたものを、板の値の名前で持つ。
/// **数だけで持つ**（SwiftUI に触らない）——Linux のテストで板の値・最小の大きさを見張る
/// （`StoryV2DesignTests`）。色は `WebTheme` のもの（写真の上は白の透過だけ）。
enum StoryViewerMetrics {

    // MARK: 進み線

    /// 進み線の太さ（v1 の 3 → **2.5** に細く）
    static let progressHeight: CGFloat = 2.5
    /// 区切りの間（4 → 3）
    static let progressGap: CGFloat = 3
    /// 進み線の地（白 32%）
    static let progressTrack = 0.32
    /// 止めている間の地と塗り（白 22%・70%）。**止まっていることを線でも見せる**
    static let pausedTrack = 0.22
    static let pausedFill = 0.7

    // MARK: 止めている間

    /// 止めている間は写真を少しだけ縮める（板 `scale(.985)`）
    static let pausedScale = 0.985
    /// 「一時停止中」の札の高さ（ガラス・14pt）
    static let pausedPillHeight: CGFloat = 40
    /// 札の縦の位置。**画面の高さに対する札の中心の割合**（板は 844 のうち上から 360・高さ 40 →
    /// 中心 380）。真ん中より少し上——親指の下に隠れない
    static let pausedPillCenter = (360.0 + 20.0) / 844.0

    // MARK: 字（2026-10-16・板 v2 の 14px）

    /// 見出しの名前・「…」のシートの先頭の名前・一時停止の札・返信の一言の候補・ハイライトの「編集」（板 14）。
    /// 14 は文字の種類の標準の大きさに無いので、`.subheadline` と同じだけ伸び縮みさせる（`jpSystemFont`）
    static let smallTextSize: CGFloat = 14

    // MARK: 上下の暗がり（写真の上の白い字を写真の明るさに負けさせない）

    /// 上（板 170・黒 60%）
    static let topShadeHeight: CGFloat = 170
    static let topShadeOpacity = 0.6
    /// 下（板 260・黒 70%）。ハイライトは 240（板 HighlightPlayer）
    static let bottomShadeHeight: CGFloat = 260
    static let highlightBottomShadeHeight: CGFloat = 240
    static let bottomShadeOpacity = 0.7

    // MARK: ひとこと

    /// ひとことの塊の左右（板 28）
    static let captionInset: CGFloat = 28
    /// 撮影地・曲の行の白（板 `rgba(255,255,255,.88)`）。**写真の上なので白の透過**
    static let metaOpacity = 0.88
    /// ひとことの明朝（板 StoryViewer 30・HighlightPlayer 28）。**作る画面の 30 と揃える**（`StoryComposerView.captionSize`）
    static let captionSize: Double = 30
    static let highlightCaptionSize: Double = 28
    /// ハイライトの日付の行（板 `rgba(255,255,255,.82)`・13 の等幅数字）
    static let highlightDateOpacity = 0.82

    // MARK: 暗幕

    /// 「…」のシート（板 50%）
    static let menuDim = 0.5
    /// 返信を書いている間（板 55%）
    static let replyDim = 0.55
    /// 削除の確認（板 60%）
    static let deleteDim = 0.6

    // MARK: 「…」のシート

    /// 行の高さ（板 56）
    static let menuRowHeight: CGFloat = 56
    /// 札の角（板 20）
    static let menuRadius: CGFloat = 20
    /// 札の左右の内側（板 20）
    static let menuInset: CGFloat = 20
    /// 先頭の「誰のストーリーか」の顔（板 28）
    static let menuAvatar: CGFloat = 28
    /// 行の間の線（板の白 10%）
    static let menuDivider = 0.10

    // MARK: 削除の確認

    /// 幅（板 290）・角（板 22）
    static let confirmWidth: CGFloat = 290
    static let confirmRadius: CGFloat = 22
    /// 中に入れるストーリーの写真（板 56×72・角 8）。何を消すかを取り違えない
    static let confirmThumb = (width: CGFloat(56), height: CGFloat(72))
    /// キャンセル｜削除 の2つ並びの高さ（板 50）
    static let confirmButtonHeight: CGFloat = 50
    /// 地（板 `rgba(40,40,42,.96)`）
    static let confirmFill: UInt32 = BrandPalette.surface6
    static let confirmFillOpacity = 0.96

    // MARK: 足元

    /// 返信欄の高さ（板 44・46 → 44）と縁の白（板 30%）
    static let replyFieldHeight: CGFloat = 44
    static let replyFieldBorder = 0.30
    /// 書いている間の欄の地（板 `rgba(28,28,30,.9)`）と縁（白 20%）
    static let replyFieldFocusedFill: UInt32 = BrandPalette.surface4
    static let replyFieldFocusedFillOpacity = 0.9
    static let replyFieldFocusedBorder = 0.20
    /// 送信の白い丸（板 44）
    static let sendSize: CGFloat = 44
    /// 返信の一言の候補（板 `.qr`: 高さ 36・左右 14・白 14% の地・縁なし）
    static let quickReplyHeight: CGFloat = 36
    static let quickReplyFill = 0.14
    /// ♡（板 26）
    static let heartSize: CGFloat = 26
    /// 自分のストーリーの足元の丸（板 46・地は surface-2・縁は白 12%）
    static let ownCircle: CGFloat = 46
    static let ownCircleBorder = 0.12
    /// 見た人・いいねの数（板 15・SF 600）
    static let ownCountSize: Double = 15

    // MARK: ハイライト

    /// 表紙の丸の縁（板の白 50%）
    static let highlightCoverRing = 0.5
    /// 「編集」の線のボタン（板 40・当たりは 44）
    static let highlightEditHeight: CGFloat = 40
    /// 「編集」の縁（板 `--line` 白 14%・地は透明）
    static let highlightEditBorder = 0.14
}
