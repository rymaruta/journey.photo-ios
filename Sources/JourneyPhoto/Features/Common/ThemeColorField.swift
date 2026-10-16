import SwiftUI
import UIKit

/// プロフィールの色を選ぶ欄（Web の見本8色＋パレットから自由に選ぶ丸と同じ）。
struct ThemeColorField: View {

    @Binding var themeColor: String
    /// 端末の色選び（`ThemeColorPickerSheet`）を出しているか
    @State private var showsPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("プロフィールの色", "Profile color"))
                .font(.caption)
                .foregroundStyle(.secondary)
            // **丸は Web と同じ 36、押せる枠は 44、並びの間は 0**（見える間は 8。Web は 10）。
            // 8色＋「なし」を1行に並べると 44×9＝396 で、フォームの行（393pt 幅の端末で約313〜329）
            // に入らず、端末ごとに違うところで割れる。**4色ずつ2行に決めて並べる**（`ThemeColorLayout`）
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ThemeColorLayout.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { hex in
                            swatch(hex)
                        }
                        if index == ThemeColorLayout.rows.count - 1 {
                            customSwatch
                            noneButton
                        }
                    }
                }
            }
            // 透明な枠のぶん（上・左・下の 4）を戻す——先頭の丸の左端を見出しにそろえ、
            // 見出しとの見える間も 8 のまま。最後の行の下にも余りを残さない
            .padding(.leading, -ThemeColorLayout.inset)
            .padding(.vertical, -ThemeColorLayout.inset)
            // 2026-10-16 判断: 暗すぎる色も選べるまま・色は変えない。知らせるだけ（`ThemeColor.isHardToSeeOnBlack`）
            if ThemeColor.isHardToSeeOnBlack(themeColor) {
                Text(L("黒い地の上では見えにくい色です。このままでも保存できます",
                       "This color is hard to see on black. You can still save it."))
                    .font(.caption)
                    .foregroundStyle(WebTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // 注意書きが**出た**ときだけ読み上げでも知らせる（目で見えない人には出たことが分からない）。
        // 本人が色選びで選んだときだけ——読み込み（保存してあった暗い色が入る）では知らせない
        .onChange(of: themeColor) { old, new in
            guard ThemeColor.shouldAnnounceHardToSee(old: old, new: new, picking: showsPicker) else { return }
            UIAccessibility.post(notification: .announcement,
                                 argument: L("黒い地の上では見えにくい色です。このままでも保存できます",
                                             "This color is hard to see on black. You can still save it."))
        }
    }

    /// 見本に無い色（ここで選んだ色・Web のパレットで選んだ色）が入っているか
    private var isCustom: Bool { ThemeColor.isCustom(themeColor) }

    /// **パレットから自由に選ぶ丸**（Web の `input type="color"` の丸と同じ見せ方）。
    /// 見本に無い色が入っていればその色で塗り、見本の丸と同じ外側の輪（真鍮）を付ける。
    /// 入っていなければ虹の丸（Web の `conic-gradient`）に白 30% の輪。
    ///
    /// **ふつうの Button（枠 44）で押し、端末の色選びを UIKit で直接 modal に出す**
    /// （`ThemeColorPickerPresenter`）。以前は SwiftUI の `ColorPicker` を広げて透明に近くして
    /// 下に敷いていたが、当たりが約 28 のままになる恐れがあった（2026-10-16 読み直しの指摘）
    private var customSwatch: some View {
        Button {
            // 二度押しで2つ出さない（出している間は何もしない。presenter の側でも見る）
            guard !showsPicker else { return }
            showsPicker = true
        } label: {
            Circle()
                .fill(isCustom
                      ? AnyShapeStyle(Color(hex: themeColor) ?? .gray)
                      : AnyShapeStyle(AngularGradient(colors: ThemeColorLayout.rainbow.compactMap { Color(hex: $0) },
                                                      center: .center,
                                                      startAngle: .degrees(-90), endAngle: .degrees(270))))
                .frame(width: ThemeColorLayout.swatch, height: ThemeColorLayout.swatch)
                // 選んでいれば見本と同じ輪（真鍮）、選んでいなければ白 30% の輪（Web の `ring-white/30`）——
                // 暗い色を選んでも丸の在りかが黒い地に消えない
                .overlay(Circle()
                    .strokeBorder(isCustom ? WebTheme.accent : Color.white.opacity(0.3),
                                  lineWidth: ThemeColorLayout.ringWidth)
                    .padding(-(ThemeColorLayout.ringGap + ThemeColorLayout.ringWidth)))
                .frame(width: ThemeColorLayout.target, height: ThemeColorLayout.target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        // 色選びを出す元（見えない空の画面）。丸の後ろに敷き、iPad の吹き出しの矢印もここを指す
        .background { ThemeColorPickerPresenter(isPresented: $showsPicker, themeColor: $themeColor) }
        .accessibilityLabel(L("プロフィールの色: 自由に選ぶ", "Profile color: pick any color"))
        .accessibilityValue(isCustom ? themeColor.lowercased() : L("未選択", "Not chosen"))
        .accessibilityAddTraits(isCustom ? .isSelected : [])
    }

    /// **選ばない**に戻せるようにする（押しても何も起きない状態を作らない）
    private var noneButton: some View {
        Button {
            themeColor = ""
        } label: {
            Text(L("なし", "None"))
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                // 選んでいれば真鍮の塗り＋墨（丸の輪と同じ決まり・2026-10-16 判断。`ThemeColorLayout` の注記）
                .foregroundStyle(themeColor.isEmpty ? WebTheme.accentText : WebTheme.muted)
                .background(themeColor.isEmpty ? WebTheme.accentFill : WebTheme.surface,
                            in: Capsule())
                // 札（高さ約26）の外側だけ広げる（`background` より後ろ＝見た目は変えない）
                .webTappable()
        }
        .buttonStyle(.borderless)
        // 丸の枠の余白 4 と足して、丸と札の見える間を 8 以上に
        .padding(.leading, ThemeColorLayout.inset)
        .accessibilityAddTraits(themeColor.isEmpty ? .isSelected : [])
    }

    private func swatch(_ hex: String) -> some View {
        let chosen = themeColor.lowercased() == hex
        return Button {
            themeColor = hex
        } label: {
            Circle()
                .fill(Color(hex: hex) ?? .gray)
                .frame(width: ThemeColorLayout.swatch, height: ThemeColorLayout.swatch)
                // 選んだ印は **外側の輪**（Web の `ring-2 ring-offset-2`）。間 2・輪 2 で、
                // 枠の余白 4 にちょうど収まる（輪の外径 44＝押せる枠）
                .overlay(Circle()
                    .strokeBorder(WebTheme.accent, lineWidth: ThemeColorLayout.ringWidth)
                    .padding(-(ThemeColorLayout.ringGap + ThemeColorLayout.ringWidth))
                    .opacity(chosen ? 1 : 0))
                .frame(width: ThemeColorLayout.target, height: ThemeColorLayout.target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L("色 \(hex)", "Color \(hex)"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// 色の丸の寸法と並べ方（`ThemeColorField`）。
enum ThemeColorLayout {
    /// 丸の見た目（Web の `w-9 h-9`＝36）
    static let swatch: CGFloat = 36
    /// 押せる枠（44）。枠どうしは間 0 で並べる（重ならない・見える間は 8）
    static let target: CGFloat = 44
    /// 丸の周りの透明な余白（片側）
    static var inset: CGFloat { (target - swatch) / 2 }
    /// 選んだ印の輪と丸の間・輪の太さ（Web の `ring-offset-2`・`ring-2`）。足して `inset` に収める
    static let ringGap: CGFloat = 2
    static let ringWidth: CGFloat = 2
    // **選んでいる印の色（2026-10-16 判断: 真鍮）。** 見本8色の丸・「自由に選ぶ」丸の輪は
    // `WebTheme.accent`（#C9A66B）、「なし」の札は `WebTheme.accentFill`（#B8955A）＋
    // `WebTheme.accentText`（墨・7.11:1）。板は「白＝選択」だが、owner の好み
    // 「選んでいるものは真鍮」（CLAUDE.md）を取った。欄は黒い地の上（プロフィールの編集）なので
    // 真鍮を置いてよい。以前は輪が白・「なし」が白の塗りで、同じ欄で選択の色が割れないよう3つともそろえる。
    // 画面がこの定数を使っていることは `ThemeColorFieldSourceTests` が見張る
    /// 「自由に選ぶ」の丸の虹（Web の `conic-gradient` と同じ並び）
    static let rainbow = ["#f87171", "#fbbf24", "#34d399", "#38bdf8", "#a78bfa", "#f472b6", "#f87171"]
    /// 1行の色の数
    static let columns = 4
    /// 行ごとの色。最後の行の後ろに「自由に選ぶ」の丸と「なし」が付く
    static var rows: [[String]] {
        stride(from: 0, to: ThemeColor.presets.count, by: columns).map {
            Array(ThemeColor.presets[$0..<min($0 + columns, ThemeColor.presets.count)])
        }
    }
    /// 「なし」の札の押せる幅の見積もり（字 2つ＋左右 10 の札を 44 の枠に入れ、左に 4 空ける）。
    /// 英語の「None」でも札は約 52
    static let noneWidth: CGFloat = 56
    /// いちばん広い行の幅（左の余白 4 を戻したあと）
    static var widestRow: CGFloat {
        rows.enumerated().map { index, row in
            // 最後の行は「自由に選ぶ」の丸（枠 44）と「なし」のぶん広い
            CGFloat(row.count) * target + (index == rows.count - 1 ? target + noneWidth : 0)
        }.max().map { $0 - inset } ?? 0
    }
}

/// 端末の色選び（`UIColorPickerViewController`）を **UIKit の `present` で直接 modal に出す**元。
///
/// 🔴 **2026-10-16 判断: SwiftUI の `.sheet` の中に子として埋め込まない。** 埋め込むと、
/// スポイトを押したとき（色選びが自分の画面を引っ込めて画面の色を拾う）に落ちた
/// （owner の実機・TestFlight 1.1.5/1.1.6）。色選びは自分で modal に出された形で使う。
/// - 出し方は `.popover`。iPhone（横幅の狭い画面）では UIKit が自動でシートに直し、iPad では
///   この丸を指す吹き出しになる（吹き出しは元の場所が無いと落ちるので `sourceView` を必ず渡す）。
///   `.pageSheet` を選ばないのは iPad で画面いっぱいの板になるため。**スポイトでどちらが安全かを
///   Apple の文書で確かめることはこの環境ではできなかった**——実機で確かめる
/// - 不透明だけ（`supportsAlpha = false`）。開いたときは今の色（無ければ見本の先頭）
/// - 色は `didSelect`（指で動かしている間も）で書く。**同じ色なら書かない**（`ThemeColor.nextValue`）。
///   閉じる知らせ（DidFinish）では書かない——`selectedColor` は初期色のままのことがある
/// - **二度出さない**: 出している間（`isShowing`）は出し直さない
struct ThemeColorPickerPresenter: UIViewControllerRepresentable {

    @Binding var isPresented: Bool
    @Binding var themeColor: String

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        // 見えない元。丸のボタンの指を奪わない
        host.view.isUserInteractionEnabled = false
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        let coordinator = context.coordinator
        guard isPresented, !coordinator.isShowing else { return }
        coordinator.isShowing = true

        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        if let rgb = ThemeColor.rgb(themeColor) ?? ThemeColor.rgb(ThemeColor.presets[0]) {
            picker.selectedColor = UIKit.UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
        picker.delegate = coordinator
        picker.modalPresentationStyle = .popover
        picker.popoverPresentationController?.sourceView = host.view
        picker.popoverPresentationController?.sourceRect = host.view.bounds
        // 下へ払って閉じたときも知る（DidFinish が来ない閉じ方）
        picker.presentationController?.delegate = coordinator

        // 描き直しの最中に出さない（次の回に回す）。いちばん上に出ている画面から出す
        DispatchQueue.main.async {
            var top: UIViewController = host
            while let next = top.presentedViewController { top = next }
            top.present(picker, animated: true)
        }
    }

    /// 閉じた後の処理と書く処理は閉包で渡す（`CameraPicker` と同じ形）
    func makeCoordinator() -> Coordinator {
        Coordinator(pick: { picked in
            if let next = ThemeColor.nextValue(picked: picked, current: themeColor) { themeColor = next }
        }, finished: { isPresented = false })
    }

    /// 色選びの知らせは主スレッドで来る（UIKit）
    @MainActor final class Coordinator: NSObject, UIColorPickerViewControllerDelegate,
                                        UIAdaptivePresentationControllerDelegate {
        /// 色選びを出しているか（二度出さない）
        var isShowing = false
        private let pick: (String) -> Void
        private let finished: () -> Void

        init(pick: @escaping (String) -> Void, finished: @escaping () -> Void) {
            self.pick = pick
            self.finished = finished
        }

        /// 指で動かしている間も（`continuously`）書く——欄の丸と注意書きがその場で変わる。
        /// **選んだ色はここで全部届く**
        func colorPickerViewController(_ viewController: UIColorPickerViewController,
                                       didSelect color: UIKit.UIColor, continuously: Bool) {
            write(color)
        }

        /// 🔴 **閉じるだけ。ここでは書かない。** `selectedColor` は開いたときの初期色のままなので、
        /// 「なし」のまま開いて何も触らずに閉じると、初期色（見本の先頭 #38bdf8）が書かれて
        /// 「なし」が空色に化けていた（2026-10-16 見直しの指摘）
        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            if viewController.presentingViewController != nil, !viewController.isBeingDismissed {
                viewController.dismiss(animated: true)
            }
            reset()
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            reset()
        }

        private func reset() {
            isShowing = false
            finished()
        }

        /// `UIColor.getRed` は拡張 sRGB で返す（P3 の色は 0〜1 の外）。`ThemeColor.hex` が sRGB に詰めて丸める
        private func write(_ color: UIKit.UIColor) {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            pick(ThemeColor.hex(red: Double(red), green: Double(green), blue: Double(blue)))
        }
    }
}

extension Color {
    /// `#rrggbb` から。読めない値は nil（**既定色に化かさない**——
    /// 化かすと「保存できていないのに色が付いて見える」）。
    init?(hex: String) {
        guard let rgb = ThemeColor.rgb(hex) else { return nil }
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
