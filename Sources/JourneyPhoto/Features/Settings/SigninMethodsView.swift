import SwiftUI

/// 「サインインの方法」（札 #601・2026-11-23 owner）。設定の「アカウント」の節の行と、知らせ（プッシュ）から開く。
///
/// メールアドレスとパスワード、Apple、Google を1枚の札に並べ、連携している Apple・Google に「解除」。
/// 解除は取り消せない操作なので確かめのダイアログを出す（CLAUDE.md「聞くのは取り消せない操作だけ」）。
/// 最後に残る入り方はサーバーが断るので、解除できない行には理由を出す（`SigninMethod.blockedReason`）。
///
/// 見た目は設定の下の画面（`SettingsPage`・板 43 Settings の行の寸法 `JPRowLabel` と同じ: 題 15・説明 12 text-3・
/// 左右 14・上下 13・最小 54）。「解除」はブロックした人の「解除」（板 BlockedUsers の線のボタン）と同じ形で、
/// 危ない操作なので字と縁を `WebTheme.danger` にする（系統の赤は使わない）。
/// 押す回数: 知らせから 1回（知らせ）→ 解除 → 解除する の3回。設定からは マイページ → 設定 → サインインの方法 → 解除 → 解除する
struct SigninMethodsView: View {

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var auth: AuthStore

    @State private var methods: [SigninMethod] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// 確かめのダイアログを出している相手
    @State private var confirming: SigninMethod.Provider?
    /// いま解除を送っている相手（二度押しで2回投げない）
    @State private var working: SigninMethod.Provider?

    var body: some View {
        SettingsPage(SigninMethodsText.title) {
            Text(L("ログインに使える方法です。心当たりの無い連携は解除できます。",
                   "Ways you can sign in. You can disconnect anything you don't recognize."))
                .font(JPFont.footnote)
                .foregroundStyle(WebTheme.text2)
                .padding(.horizontal, JPSpace.xxs)
            if let errorMessage {
                // 板の失敗の印（丸に「!」）と危険の色の字。色だけで伝えない（印と文）
                Label {
                    Text(errorMessage)
                        .font(JPFont.footnote)
                        .foregroundStyle(WebTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(WebTheme.danger)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, JPSpace.xxs)
                .accessibilityIdentifier("signinMethods.error")
            }
            if !methods.isEmpty {
                SettingsGroup(nil) {
                    ForEach(Array(methods.enumerated()), id: \.element.id) { index, method in
                        if index > 0 { JPCardDivider() }
                        row(method)
                    }
                }
            }
        }
        .overlay { if isLoading && methods.isEmpty { ProgressView() } }
        .task(id: auth.userId) { await load() }
        .confirmationDialog(confirming.map(SigninMethodsText.confirmTitle) ?? "",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            // メニュー・確認ダイアログは系統の部品なので `.destructive` のまま（CLAUDE.md）
            Button(SigninMethodsText.confirmButton, role: .destructive) {
                guard let provider = confirming else { return }
                Task { await remove(provider) }
            }
            .accessibilityIdentifier("signinMethods.confirm")
            Button(Labels.Common.cancel, role: .cancel) {}
        } message: {
            Text(confirming.map(SigninMethodsText.confirmMessage) ?? "")
        }
    }

    private func row(_ method: SigninMethod) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(SigninMethodsText.name(method.id))
                    .font(.subheadline)
                    .foregroundStyle(WebTheme.text)
                Text(SigninMethodsText.detail(method))
                    .font(.caption)
                    .foregroundStyle(WebTheme.faint)
                if method.linked, let reason = method.blockedReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(WebTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("signinMethods.blocked.\(method.id)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let provider = method.provider, method.linked, method.removable {
                removeButton(provider)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 54)
        // **行を入れ物の要素にしてから名前を付ける。** 並び（HStack）に直に付けると、中の要素すべてにこの名前が付き、
        // 「解除」のボタンの `signinMethods.remove.<id>` が上書きされて見つからなかった（Mac run 1771・2026-11-23）
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("signinMethods.row.\(method.id)")
    }

    private func removeButton(_ provider: SigninMethod.Provider) -> some View {
        Button {
            confirming = provider
        } label: {
            Text(working == provider ? SigninMethodsText.removing : SigninMethodsText.removeButton)
                .font(JPFont.footnote.weight(.semibold))
                .foregroundStyle(WebTheme.danger)
                .padding(.horizontal, JPSpace.m)
                .frame(minWidth: 44, minHeight: JPHeight.inlineButton)
                .overlay(Capsule().strokeBorder(WebTheme.danger.opacity(0.3), lineWidth: JPStroke.hairline))
                // 見た目は 36pt、押せる高さは 44pt（ブロックした人の「解除」と同じ）
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(working != nil)
        .accessibilityLabel(L("\(SigninMethodsText.name(provider.rawValue)) の連携を解除",
                              "Disconnect \(SigninMethodsText.name(provider.rawValue))"))
        .accessibilityIdentifier("signinMethods.remove.\(provider.rawValue)")
    }

    private func load() async {
        guard auth.userId != nil else { methods = []; isLoading = false; return }
        let owner = auth.userId
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await environment.signinMethods.list()
            guard auth.userId == owner else { return }
            methods = list ?? []
            errorMessage = list == nil ? SigninMethodsText.loadFailed : nil
        } catch is CancellationError {
            // 画面を離れた。失敗と言わない
        } catch {
            guard auth.userId == owner else { return }
            errorMessage = SigninMethodsText.failure(error, fallback: SigninMethodsText.loadFailed)
        }
    }

    private func remove(_ provider: SigninMethod.Provider) async {
        guard working == nil else { return }
        let owner = auth.userId
        working = provider
        errorMessage = nil
        defer { working = nil }
        do {
            let list = try await environment.signinMethods.remove(provider)
            guard auth.userId == owner else { return }
            methods = list
        } catch {
            guard auth.userId == owner else { return }
            // 最後に残る入り方（409）・Apple に届かない（503）は、サーバーの文。圏外などは決まった文（`SigninMethodsText.failure`）
            let message = SigninMethodsText.failure(error, fallback: SigninMethodsText.removeFailed)
            await load()
            errorMessage = message
        }
    }
}
