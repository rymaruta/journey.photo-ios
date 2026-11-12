import XCTest
@testable import JourneyPhoto
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// プロフィールの QR（札 #545 の第1段・2026-11-12）。中身は公開プロフィールの URL、読み取りは journey-photo.com の
/// 人の URL だけを人の頁で開く。入口はマイページの名前の横（owner の決定）
final class ProfileQRTests: XCTestCase {

    private let base = URL(string: "https://journey-photo.com")!
    private let staging = URL(string: "https://staging.journey-photo.com")!
    private let uid = "a1b2c3d4-0000-4111-8222-333344445555"

    // MARK: - 中身

    /// QR に入れるのは、だれでも開ける `/users?id=<id>`（投稿の無い人の `/users/<id>` は次のビルドまで無い）
    func testURLIsThePublicProfile() {
        XCTAssertEqual(ProfileQR.url(userId: uid, base: base)?.absoluteString,
                       "https://journey-photo.com/users?id=\(uid)")
        // URL に入れられない id は作らない（空の QR を出さない）
        XCTAssertNil(ProfileQR.url(userId: "", base: base))
        XCTAssertNil(ProfileQR.url(userId: "a/b", base: base))
        XCTAssertNil(ProfileQR.url(userId: "a b", base: base))
    }

    /// 作った URL を読むと同じ人に戻る
    func testRoundTrip() throws {
        let url = try XCTUnwrap(ProfileQR.url(userId: uid, base: base))
        XCTAssertEqual(ProfileQR.userId(from: url.absoluteString, base: base), uid)
        let onStaging = try XCTUnwrap(ProfileQR.url(userId: uid, base: staging))
        XCTAssertEqual(ProfileQR.userId(from: onStaging.absoluteString, base: staging), uid)
    }

    // MARK: - 読み取り

    func testReadsEveryPersonURLShape() {
        for text in ["https://journey-photo.com/users?id=\(uid)",
                     "https://www.journey-photo.com/users?id=\(uid)",
                     "https://journey-photo.com/users/\(uid)",
                     "https://journey-photo.com/users/\(uid)/",
                     "https://journey-photo.com/u/\(uid)",
                     "  https://journey-photo.com/users?id=\(uid)\n",
                     "HTTPS://Journey-Photo.com/users?id=\(uid)"] {
            XCTAssertEqual(ProfileQR.userId(from: text, base: base), uid, text)
        }
        // staging の版でも本番の QR を読める
        XCTAssertEqual(ProfileQR.userId(from: "https://journey-photo.com/users?id=\(uid)", base: staging), uid)
        XCTAssertEqual(ProfileQR.userId(from: "https://staging.journey-photo.com/users?id=\(uid)", base: staging), uid)
    }

    /// ほかのサイト・人でない頁・おかしな id は開かない（外のサイトへ連れ出さない）
    func testRejectsOtherCodes() {
        for text in ["https://example.com/users?id=\(uid)",
                     "https://journey-photo.com.evil.example/users?id=\(uid)",
                     "https://evil.example/?u=https://journey-photo.com/users?id=\(uid)",
                     "javascript:alert(1)",
                     "journey-photo.com/users?id=\(uid)",
                     "ftp://journey-photo.com/users?id=\(uid)",
                     "https://journey-photo.com/users/search",
                     "https://journey-photo.com/users/trip",
                     "https://journey-photo.com/users",
                     "https://journey-photo.com/users?id=",
                     "https://journey-photo.com/users?id=a%2Fb",
                     "https://journey-photo.com/photo/\(uid)",
                     "https://journey-photo.com/users/\(uid)/extra",
                     "WIFI:S:home;T:WPA;P:secret;;",
                     ""] {
            XCTAssertNil(ProfileQR.userId(from: text, base: base), text)
        }
    }

    /// 自分の QR は開かず「あなたの QR です」
    func testScanResult() {
        let mine = "https://journey-photo.com/users?id=\(uid)"
        XCTAssertEqual(ProfileQRScanResult.of(mine, myUserId: uid, base: base), .mine)
        XCTAssertEqual(ProfileQRScanResult.of(mine, myUserId: "someone-else", base: base), .person(uid))
        XCTAssertEqual(ProfileQRScanResult.of("https://example.com", myUserId: uid, base: base), .other)
    }

    // MARK: - 更新できる QR に備える（2026-11-12 owner の要望・サーバーは承認待ち）

    /// `/qr?t=<合図>` を今から見分ける（引くのは ProfileQRSource）。ほかの家・おかしな合図は見分けない。
    /// 2026-11-12 秘書室の決定: 道は `/qr?t=`（`/q` は Web の今日の一問・`/qr/<合図>` の形は使わない）
    func testRecognizesPassLinks() {
        XCTAssertEqual(ProfileQRLink.parse("https://journey-photo.com/qr?t=Ab3_x-9Zq", base: base), .pass("Ab3_x-9Zq"))
        XCTAssertEqual(ProfileQRLink.parse("https://www.journey-photo.com/qr/?t=abc", base: base), .pass("abc"))
        XCTAssertEqual(ProfileQRLink.parse("https://journey-photo.com/u/\(uid)", base: base), .person(uid))
        for text in ["https://example.com/qr?t=abc",
                     "https://journey-photo.com/qr",
                     "https://journey-photo.com/qr?t=",
                     "https://journey-photo.com/qr?id=abc",
                     "https://journey-photo.com/qr?t=a%2Fb",
                     "https://journey-photo.com/qr/abc",
                     "https://journey-photo.com/q?t=abc"] {
            XCTAssertNil(ProfileQRLink.parse(text, base: base), text)
        }
        // 合図は人の id としては読まない（引かずに人の頁を開かない）
        XCTAssertNil(ProfileQR.userId(from: "https://journey-photo.com/qr?t=abc", base: base))
        XCTAssertEqual(ProfileQRScanResult.of("https://journey-photo.com/qr?t=abc", myUserId: uid, base: base), .pass("abc"))
    }

    /// カメラの使い道の説明に QR の読み取りを書く（審査 5.1.1・アプリの中で QR を読むため）
    func testCameraUsageMentionsQR() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let yml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        let line = try XCTUnwrap(yml.components(separatedBy: "\n").first { $0.contains("NSCameraUsageDescription:") })
        XCTAssertTrue(line.contains("プロフィールの QR を読み取る"), line)
        for (lang, word) in [("ja", "プロフィールの QR を読み取る"), ("en", "scan profile QR codes")] {
            let strings = try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/Resources/\(lang).lproj/InfoPlist.strings"),
                                     encoding: .utf8)
            let entry = try XCTUnwrap(strings.components(separatedBy: "\n").first { $0.hasPrefix("\"NSCameraUsageDescription\"") })
            XCTAssertTrue(entry.contains(word), "\(lang): \(entry)")
        }
    }

    /// 合図を引いた結果も人の id と同じ所で決める。引けない（古い・取り消された）は人を開かない
    func testResolvedPass() {
        XCTAssertEqual(ProfileQRScanResult.resolved("someone", myUserId: uid), .person("someone"))
        XCTAssertEqual(ProfileQRScanResult.resolved(uid, myUserId: uid), .mine)
        XCTAssertEqual(ProfileQRScanResult.resolved(nil, myUserId: uid), .other)
    }

    /// 前の版の中身（公開プロフィールの URL）: 合図は引けない・更新は出さない・更新を頼まれても作らない
    func testPublicProfileSourceCannotRenew() async throws {
        let source = PublicProfileQRSource(base: base)
        let url = try await source.code(for: uid)
        XCTAssertEqual(url.absoluteString, "https://journey-photo.com/users?id=\(uid)")
        do {
            _ = try await source.code(for: "a/b")
            XCTFail("URL に入れられない id で中身を作った")
        } catch {
            XCTAssertEqual(error as? ProfileQRSourceError, .cannotMake)
        }
        let resolved = try await source.resolve(pass: "abc")
        XCTAssertNil(resolved)
        XCTAssertFalse(source.canRenew)
        do {
            _ = try await source.renew(for: uid)
            XCTFail("取り替えられない中身で更新した")
        } catch {
            XCTAssertEqual(error as? ProfileQRSourceError, .cannotMake)
        }
    }

    /// アプリが使うのは更新できる合図（2026-11-12 owner 承認・札 #545）
    func testAppUsesTheRenewableSource() throws {
        let text = try source("Core/Text/ProfileQR.swift")
        XCTAssertTrue(text.contains("static func current(api: APIClient) -> any ProfileQRSource { ServerProfileQRSource(api: api) }"))
        // Linux の試験では AppConfig を読めないので、家を渡して作る
        XCTAssertTrue(ServerProfileQRSource(api: APIClient(baseURL: base, tokenProvider: StubTokenProvider(token: nil)), base: base).canRenew)
    }

    // MARK: - 更新できる QR（2026-11-12 札 #545）

    private let token = "Ab3_x-9ZqAb3_x-9ZqAb3_x-9ZqAb3_x"

    /// 中身は `/qr?t=<合図>`（Web の `/q` は今日の一問なので `/qr`・クエリの形は静的な書き出しのため）
    func testPassURL() throws {
        XCTAssertEqual(ProfileQR.passURL(token: token, base: base)?.absoluteString, "https://journey-photo.com/qr?t=\(token)")
        XCTAssertNil(ProfileQR.passURL(token: "", base: base))
        XCTAssertNil(ProfileQR.passURL(token: "a/b", base: base))
        XCTAssertNil(ProfileQR.passURL(token: "a=b", base: base))
        // 作った URL を読むと同じ合図に戻る（staging の版でも）
        let url = try XCTUnwrap(ProfileQR.passURL(token: token, base: base))
        XCTAssertEqual(ProfileQRLink.parse(url.absoluteString, base: base), .pass(token))
        let onStaging = try XCTUnwrap(ProfileQR.passURL(token: token, base: staging))
        XCTAssertEqual(ProfileQRLink.parse(onStaging.absoluteString, base: staging), .pass(token))
        XCTAssertEqual(ProfileQRScanResult.of(url.absoluteString, myUserId: uid, base: base), .pass(token))
    }

    /// `/qr?t=` の読み分け。今日の一問の `/q?t=`・ほかの家・おかしな合図は合図と読まない
    func testParsesQueryPassLinks() {
        XCTAssertEqual(ProfileQRLink.parse("https://www.journey-photo.com/qr?t=\(token)", base: base), .pass(token))
        XCTAssertEqual(ProfileQRLink.parse("https://journey-photo.com/qr/?t=\(token)", base: base), .pass(token))
        for text in ["https://journey-photo.com/q?t=\(token)",
                     "https://example.com/qr?t=\(token)",
                     "https://journey-photo.com/qr?t=",
                     "https://journey-photo.com/qr?id=\(token)",
                     "https://journey-photo.com/qr?t=a%2Fb",
                     "https://journey-photo.com/qr?t=a+b"] {
            XCTAssertNil(ProfileQRLink.parse(text, base: base), text)
        }
    }

    private func stubbedSource() -> ServerProfileQRSource {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://api.example.test")!,
                            tokenProvider: StubTokenProvider(token: "ID-TOKEN"),
                            session: URLSession(configuration: config))
        return ServerProfileQRSource(api: api, base: base)
    }

    /// 今の合図は `GET /user/qr`（ログイン）で取り、`/qr?t=` の URL にする
    func testServerSourceCode() async throws {
        StubProtocol.reset()
        defer { StubProtocol.reset() }
        StubProtocol.respond(status: 200, body: #"{"token":"\#(token)","issuedAt":"2026-11-12T00:00:00.000Z"}"#)
        let url = try await stubbedSource().code(for: uid)
        XCTAssertEqual(url.absoluteString, "https://journey-photo.com/qr?t=\(token)")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/qr")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer ID-TOKEN")
    }

    /// 更新は `POST /user/qr/rotate`（ログイン）で、新しい合図の URL を返す。形の悪い合図が返ったら作らない
    func testServerSourceRenew() async throws {
        StubProtocol.reset()
        defer { StubProtocol.reset() }
        StubProtocol.respond(status: 200, body: #"{"token":"\#(token)"}"#)
        let source = stubbedSource()
        XCTAssertTrue(source.canRenew)
        let url = try await source.renew(for: uid)
        XCTAssertEqual(url.absoluteString, "https://journey-photo.com/qr?t=\(token)")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/qr/rotate")
        StubProtocol.respond(status: 200, body: #"{"token":"a/b"}"#)
        do {
            _ = try await source.renew(for: uid)
            XCTFail("形の悪い合図で QR を作った")
        } catch {
            XCTAssertEqual(error as? ProfileQRSourceError, .cannotMake)
        }
    }

    /// 合図を人に引く（ログイン不要）。口の 404（`{ error }`）だけを「使えない」と読み、口がまだ無い 404・
    /// 500 は投げる（圏外や不調で「使えません」と言わない）
    func testServerSourceResolve() async throws {
        StubProtocol.reset()
        defer { StubProtocol.reset() }
        let source = stubbedSource()
        StubProtocol.respond(status: 200, body: #"{"userId":"someone"}"#)
        let found = try await source.resolve(pass: token)
        XCTAssertEqual(found, "someone")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/qr/\(token)")
        XCTAssertNil(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "ログイン不要の口に鍵を付けた")

        StubProtocol.respond(status: 404, body: #"{"error":"この QR コードは使えません"}"#)
        let gone = try await source.resolve(pass: token)
        XCTAssertNil(gone)

        for (status, body) in [(404, #"{"message":"Not Found"}"#), (500, #"{"error":"失敗"}"#)] {
            StubProtocol.respond(status: status, body: body)
            do {
                _ = try await source.resolve(pass: token)
                XCTFail("\(status) \(body) を「使えない」と読んだ")
            } catch {}
        }

        // URL に入れられない合図は口を叩かずに「使えない」
        StubProtocol.reset()
        let bad = try await source.resolve(pass: "a/b")
        XCTAssertNil(bad)
        XCTAssertEqual(StubProtocol.requestCount, 0)
    }

    func testWordsAreJapaneseFirstAndNoBannedWords() {
        for text in [ProfileQRText.title, ProfileQRText.showTab, ProfileQRText.scanTab, ProfileQRText.showHint,
                     ProfileQRText.scanHint, ProfileQRText.notOurs, ProfileQRText.yours, ProfileQRText.denied,
                     ProfileQRText.retry, ProfileQRText.loading, ProfileQRText.passNotValid,
                     ProfileQRText.passCheckFailed, ProfileQRText.renew, ProfileQRText.renewTitle,
                     ProfileQRText.renewMessage, ProfileQRText.renewConfirm, ProfileQRText.renewed,
                     ProfileQRText.renewFailed] {
            XCTAssertFalse(text.isEmpty)
            for banned in ["捨てる", "撮りどき", "この場所"] {
                XCTAssertFalse(text.contains(banned), "\(text) に「\(banned)」")
            }
        }
    }

    // MARK: - 作り

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/JourneyPhoto/" + path), encoding: .utf8)
    }

    /// 入口はマイページの名前のすぐ右（「編集」の左）。押すと1枚の QR の画面（見せる／読み取るを切り替える）
    func testEntryIsNextToTheNameOnMyPage() throws {
        let page = try source("Features/Profile/MyPageView.swift")
        let row = try XCTUnwrap(page.range(of: "HStack(alignment: .center, spacing: MyPageHeaderLayout.nameEditGap)"))
        let rest = String(page[row.upperBound...].prefix(600))
        let name = try XCTUnwrap(rest.range(of: "nameLine(profile)"))
        let qr = try XCTUnwrap(rest.range(of: "qrLink()"), "QR の印が名前の段に無い")
        let edit = try XCTUnwrap(rest.range(of: "editLink()"))
        XCTAssertLessThan(name.lowerBound, qr.lowerBound)
        XCTAssertLessThan(qr.lowerBound, edit.lowerBound, "QR の印が名前の横でない")
        XCTAssertTrue(page.contains("NavigationStack { ProfileQRView(profile: profile) }"))
        XCTAssertTrue(page.contains(#".accessibilityIdentifier("mypage.qr")"#))
        // 人のページには置かない（QR は本人にだけ見える）
        let other = try source("Features/Profile/UserProfileView.swift")
        XCTAssertFalse(other.contains("ProfileQRView("), "人のページに QR の入口がある")
    }

    /// 見せると読み取るは1枚の画面の切り替え。読み取った人は同じ画面の上に開く
    func testOneScreenWithBothModes() throws {
        let view = try source("Features/Profile/ProfileQRView.swift")
        XCTAssertTrue(view.contains("segment(.show, title: ProfileQRText.showTab"))
        XCTAssertTrue(view.contains("segment(.scan, title: ProfileQRText.scanTab"))
        XCTAssertTrue(view.contains("UserProfileView(userId: person.userId)"))
        XCTAssertTrue(view.contains("switch ProfileQRScanResult.of(code, myUserId: myUserId)"))
        // 中身は ProfileQRSource の1か所だけが作る（更新できる合図・2026-11-12 owner 承認）
        XCTAssertTrue(view.contains("try await source.code(for: profile.userId)"))
        XCTAssertFalse(view.contains("ProfileQR.url("), "画面が中身を直に作っている")
        XCTAssertFalse(view.contains("ProfileQR.passURL("), "画面が中身を直に作っている")
        XCTAssertTrue(view.contains("given ?? ProfileQRSources.current(api: environment.api)"))
        XCTAssertTrue(view.contains("output.metadataObjectTypes = [.qr]"))
        // 読み取りを離れた（取り消された）あとにカメラを点けない・点いたら止める（2026-11-12 確かめ役）
        let start = try XCTUnwrap(view.components(separatedBy: "func start() async {").dropFirst().first)
            .components(separatedBy: "func stop()").first ?? ""
        let beforeRun = try XCTUnwrap(start.range(of: "guard !Task.isCancelled else { return }"), "点ける前に取り消しを見ていない")
        let run = try XCTUnwrap(start.range(of: "let ok = await run()"))
        let after = try XCTUnwrap(start.range(of: "if Task.isCancelled {\n            stop()"), "点けたあとに取り消しを見て止めていない")
        XCTAssertLessThan(beforeRun.lowerBound, run.lowerBound)
        XCTAssertLessThan(run.lowerBound, after.lowerBound)
        // 外のサイトを開かない（読み取った文字で openURL しない）
        XCTAssertFalse(view.contains("openURL(URL(string: code"))
    }

    /// QR の下に「QR コードを更新」→ 確かめ（キャンセル／更新する）→ 新しい QR と知らせ（資料 第10章）
    func testRenewFlow() throws {
        let view = try source("Features/Profile/ProfileQRView.swift")
        XCTAssertEqual(ProfileQRText.renew, "QR コードを更新")
        XCTAssertEqual(ProfileQRText.renewTitle, "QR コードを更新しますか？")
        XCTAssertEqual(ProfileQRText.renewMessage, "今の QR コードとリンクは使えなくなります")
        XCTAssertEqual(ProfileQRText.renewConfirm, "更新する")
        XCTAssertEqual(ProfileQRText.renewed, "新しい QR コードにしました")
        // 出すのは取り替えられる中身で、QR が出ているときだけ
        XCTAssertTrue(view.contains("if source.canRenew, case .ready = code {"))
        XCTAssertTrue(view.contains(#".accessibilityIdentifier("profileQR.renew")"#))
        // 押すと確かめを出す（すぐには替えない）。確かめの「更新する」で替え、キャンセルは何もしない
        XCTAssertTrue(view.contains("Button { confirmingRenew = true } label:"))
        XCTAssertTrue(view.contains(".confirmationDialog(ProfileQRText.renewTitle, isPresented: $confirmingRenew"))
        XCTAssertTrue(view.contains("Button(ProfileQRText.renewConfirm) { Task { await renew() } }"))
        XCTAssertTrue(view.contains("Button(Labels.Common.cancel, role: .cancel) {}"))
        // 替えたら新しい QR を出して知らせる。シートの中なので知らせはこの画面の上に出す
        XCTAssertTrue(view.contains("let url = try await source.renew(for: profile.userId)"))
        XCTAssertTrue(view.contains("code = .ready(url)"))
        XCTAssertTrue(view.contains("toasts.show(ProfileQRText.renewed)"))
        XCTAssertTrue(view.contains("ToastOverlay()"))
        // 押せる高さ 44pt
        XCTAssertTrue(view.contains(".frame(minWidth: WebTheme.minTapTarget, minHeight: WebTheme.minTapTarget)"))
    }

    /// 読み取った合図が使えないときは、小窓のすぐ下に danger の字で同じ言葉。圏外は別の言葉
    func testUnusablePassIsShownInDangerUnderTheCamera() throws {
        let view = try source("Features/Profile/ProfileQRView.swift")
        XCTAssertEqual(ProfileQRText.passNotValid, "この QR コードは使えません。相手に新しい QR コードを出してもらってください")
        XCTAssertTrue(view.contains(".foregroundStyle(WebTheme.danger)"))
        let pass = try XCTUnwrap(view.range(of: "case .other, .pass:"))
        let after = String(view[pass.upperBound...].prefix(160))
        XCTAssertTrue(after.contains("note = ProfileQRText.passNotValid"))
        XCTAssertTrue(after.contains("noteIsFailure = true"))
        // 引けなかった（投げた）ときは「使えません」と言わない
        let failed = try XCTUnwrap(view.range(of: "userId = try await source.resolve(pass: pass)"))
        let rest = String(view[failed.upperBound...].prefix(400))
        XCTAssertTrue(rest.contains("note = ProfileQRText.passCheckFailed"))
        XCTAssertFalse(rest.prefix(through: rest.range(of: "return")!.lowerBound).contains("passNotValid"))
    }

    /// 見本の通信（画面写真）でも QR を出して更新できる
    func testPreviewBackendServesQR() async {
        let store = PreviewBackend.Store()
        let get = await PreviewBackend.reply(method: "GET", route: ["user", "qr"], body: nil, userId: "me", store: store,
                                             publicLikes: { _ in nil })
        let rotate = await PreviewBackend.reply(method: "POST", route: ["user", "qr", "rotate"], body: nil, userId: "me",
                                                store: store, publicLikes: { _ in nil })
        let first = (try? JSONSerialization.jsonObject(with: get.body)) as? [String: Any]
        let second = (try? JSONSerialization.jsonObject(with: rotate.body)) as? [String: Any]
        let a = first?["token"] as? String, b = second?["token"] as? String
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertNotEqual(a, b, "更新しても合図が替わらない")
        XCTAssertTrue(PathID.isSafe(a ?? ""))
        XCTAssertEqual(a?.count, 32)
    }
}
