import SwiftUI

/// 写真を出す。読み込み中と失敗をはっきり分ける。
///
/// **失敗を「ただの空白」にしない。** Web 側は水和のあとサムネイルが消える
/// 不具合を踏んでいて（CLAUDE.md の `24f9df2c`）、無言で消えると
/// 「そういう写真」に見えてしまい原因に気づけない。
struct RemoteImage: View {

    let url: URL?
    var contentMode: ContentMode = .fill
    /// 枠からはみ出したぶんを、どちら側に残すか。
    ///
    /// **切り抜きの中心は写真ごとに違う**（`Photo.focalPoint`。owner が
    /// Web で掴んで動かせる）。既定の中央のままだと、動かした写真が
    /// アプリでだけ別の切り抜きで出る。
    var alignment: Alignment = .center
    /// 読み込みが片付いたときに呼ぶ（出た＝true・出せないと分かった＝false）。
    /// ストーリーが「絵が出る前から秒数を減らす」のを防ぐためのもの。
    /// 既定は何もしない（他の呼び出しは変わらない）
    var onSettled: ((Bool) -> Void)? = nil
    /// 絵が敷かれた大きさ（縦横比のまま `contentMode` で敷いたもの）。**絵の縦横比を知る口**
    /// ——ストーリーの上にデータで置いた文字は絵の矩形に対する割合で置く（`StoryTextLayer`）。
    /// 既定は何もしない
    var onLayout: ((CGSize) -> Void)? = nil
    /// 出せないときに置く記号。
    ///
    /// **人のアイコンに「壊れた写真」の記号を出さない。** アバターを
    /// 設定していない人は珍しくないのに、丸の中に写真の記号が出て
    /// 「読み込みに失敗した」ように見えていた（実機の絵・run 40）。
    /// 人を指す場所では人型を置く。
    var placeholderSymbol: String = "photo"
    /// 自動の1回のあと、**押して読み直せる**記号を出すか。**既定は出さない。**
    ///
    /// 🔴 ボタンは周りの操作を奪う——ストーリーでは左右送りの押下を、一覧・旅の本では
    /// `NavigationLink` を取ってしまう（2026-10-02 のレビュー）。周りに押す操作が無い所だけで
    /// 呼ぶ側が true にする
    var allowsManualRetry = false

    /// 読み直した回数。**`AsyncImage` の `.id` に使う**——替えると作り直されて、もう一度読む
    @State private var attempt = 0
    /// 自動で読み直した回数・押して読み直した回数（上限は `RemoteImageRetry`）
    @State private var automaticRetries = 0
    @State private var manualRetries = 0

    var body: some View {
        ZStack {
            WebTheme.surface
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.15))) { phase in
                    switch phase {
                    case .success(let image):
                        // **寄せるのは写真だけ。** `ZStack` ごと寄せると、
                        // 読み込み中の輪と失敗の記号まで隅に寄って、
                        // 44〜56pt の枠では切れて見えなくなる
                        image.resizable().aspectRatio(contentMode: contentMode)
                            .background {
                                if let onLayout {
                                    GeometryReader { g in
                                        Color.clear
                                            .onAppear { onLayout(g.size) }
                                            .onChange(of: g.size) { _, size in onLayout(size) }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                            .onAppear { onSettled?(true) }
                    case .failure:
                        failure(RemoteImageRetry.step(automaticDone: automaticRetries, manualDone: manualRetries,
                                              allowsManualRetry: allowsManualRetry))
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
                .id(attempt)
            } else {
                placeholder
            }
        }
        .clipped()
        // 別の写真に替わったら数え直す（前の写真の失敗で、次の写真の読み直しを使い切らない）
        .onChange(of: url) { _, _ in
            attempt = 0
            automaticRetries = 0
            manualRetries = 0
        }
    }

    /// 読めなかったときの段。**一度だけ自動で読み直し、それでも駄目なら押して読み直せる**
    /// （2026-10-02）。圏外の一瞬・スクロールで取り消された読み込みで、記号のまま残っていた
    @ViewBuilder
    private func failure(_ step: RemoteImageRetry.Step) -> some View {
        switch step {
        case .retryAutomatically(let seconds):
            // まだ諦めていない。**読み込み中に見せる**（`onSettled` もまだ呼ばない——
            // ストーリーは読み直しの結果を待つ）
            ProgressView()
                .task {
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    automaticRetries += 1
                    attempt += 1
                }
        case .offerTap:
            Button {
                manualRetries += 1
                attempt += 1
            } label: {
                placeholder
                    // 今の記号の中に小さく「読み直す」の印
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .offset(x: 7, y: 4)
                            .accessibilityHidden(true)
                    }
                    // 押せる幅は 44pt まで（小さな丸では枠に収める——隣を奪わない）
                    .frame(maxWidth: 44, maxHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("画像を読み込めませんでした。読み直す", "Image failed to load. Reload"))
            .accessibilityAddTraits(.isButton)
            .onAppear { onSettled?(false) }
        case .giveUp:
            placeholder
                .onAppear { onSettled?(false) }
        }
    }

    private var placeholder: some View {
        Image(systemName: placeholderSymbol)
            .font(.title2)
            .foregroundStyle(.tertiary)
            // 飾り。読み上げの邪魔をしない
            .accessibilityHidden(true)
    }
}

/// 読めなかった写真を**何回まで読み直すか**（画面を持たない計算）。
///
/// **通信を増やしすぎない。** 一覧の格子で圏外になると、全部のマスが一斉に失敗する。
/// 自動の読み直しは1枚につき1回だけ（少し待ってから）、その先は人が押したときだけ・
/// 押せるのも `manualLimit` 回まで。数えるのは写真（URL）ごと——替われば数え直す
enum RemoteImageRetry {
    /// 自動で読み直す回数
    static let automaticLimit = 1
    /// 自動で読み直す前に待つ秒数（圏外の一瞬・取り消された読み込みが戻るのを待つ）
    static let automaticDelay: Double = 1.2
    /// 押して読み直せる回数。使い切ったら記号だけを置く
    static let manualLimit = 3

    enum Step: Equatable {
        /// 少し待って自動で読み直す
        case retryAutomatically(afterSeconds: Double)
        /// 押すと読み直せる記号を置く
        case offerTap
        /// 読み直さない（記号だけ）
        case giveUp
    }

    /// 失敗したときに次にすること。`automaticDone`・`manualDone` はその写真で読み直した回数。
    /// `allowsManualRetry` が false（既定）なら、自動の1回のあとは記号だけ
    static func step(automaticDone: Int, manualDone: Int, allowsManualRetry: Bool = false) -> Step {
        if automaticDone < automaticLimit { return .retryAutomatically(afterSeconds: automaticDelay) }
        if allowsManualRetry, manualDone < manualLimit { return .offerTap }
        return .giveUp
    }

    /// 1枚の写真を読みに行く回数の上限（最初の1回＋自動＋押した分）
    static var maxLoads: Int { 1 + automaticLimit + manualLimit }
}
