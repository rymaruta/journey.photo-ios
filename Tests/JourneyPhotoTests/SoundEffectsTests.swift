import XCTest
@testable import JourneyPhoto

/// 効果音（2026-11-25・カプセルが開く、硬貨を入れる）。鳴らす条件・音のファイル・つなぎを見張る
final class SoundEffectsTests: XCTestCase {

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func text(_ path: String) throws -> String {
        let raw = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        // 注記（`//`・`///`）の中は数えない
        return raw.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func soundFile(_ effect: SoundEffect) -> URL {
        root.appendingPathComponent("Sources/JourneyPhoto/Resources/Sounds/\(effect.rawValue).\(SoundEffect.fileExtension)")
    }

    // MARK: 鳴らす条件

    func testAllowedInTheApp() {
        XCTAssertTrue(SoundEffect.allowed(environment: ["HOME": "/x"], arguments: ["/app/JourneyPhoto"]))
    }

    func testMutedInUITests() {
        XCTAssertFalse(SoundEffect.allowed(environment: [:], arguments: ["/app", "-JPNoSounds", "YES"]))
        // 見本の利用者で撮る UI テスト（`ScreenshotTests`）
        XCTAssertFalse(SoundEffect.allowed(environment: [:], arguments: ["/app", "-JPPreviewUserId", "u1"]))
    }

    func testMutedInPreviews() {
        XCTAssertFalse(SoundEffect.allowed(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"], arguments: ["/app"]))
    }

    func testMutedInUnitTests() {
        XCTAssertFalse(SoundEffect.allowed(environment: ["XCTestConfigurationFilePath": "/t.xctestconfiguration"],
                                            arguments: ["/app"]))
        XCTAssertFalse(SoundEffect.allowed(environment: ["XCTestBundlePath": "/t.xctest"], arguments: ["/app"]))
    }

    /// UI テストはどれも `XCUIApplication.jp()` で起動する。そこで鳴らさない引数を渡しているか
    func testUITestLauncherPassesMute() throws {
        let launcher = try text("UITests/JourneyPhotoUITests/XCUIApplication+JP.swift")
        XCTAssertTrue(launcher.contains("\"\(SoundEffect.muteArgument)\", \"YES\""), "UI テストの起動で効果音を止めていない")
    }

    /// 音の場（`AVAudioSession`）に触らない。触ると、ほかのアプリの音楽やアプリの曲の試聴を止めたり、
    /// 試聴中の曲を消音スイッチで黙らせたりする
    func testDoesNotTouchAudioSession() throws {
        let source = try text("Sources/JourneyPhoto/Core/Sound/SoundEffects.swift")
        XCTAssertFalse(source.contains("AVAudioSession") || source.contains("setCategory") || source.contains("AVAudioPlayer"))
        XCTAssertTrue(source.contains("AudioServicesPlaySystemSound("), "消音スイッチに従う端末の効果音の道で鳴らしていない")
    }

    // MARK: 音のファイル

    /// ファイルがあり、CAF のリニア PCM（効果音の道で読める形）で、0.2〜0.8 秒、50KB 未満
    func testSoundFilesAreShortCAF() throws {
        for effect in SoundEffect.allCases {
            let data = try Data(contentsOf: soundFile(effect))
            XCTAssertLessThan(data.count, 50_000, "\(effect.rawValue) が大きすぎる")
            let bytes = [UInt8](data)
            XCTAssertEqual(String(decoding: bytes[0..<4], as: UTF8.self), "caff", effect.rawValue)
            func u32(_ at: Int) -> UInt32 { bytes[at..<at + 4].reduce(0) { $0 << 8 | UInt32($1) } }
            func u64(_ at: Int) -> UInt64 { bytes[at..<at + 8].reduce(0) { $0 << 8 | UInt64($1) } }
            // 頭の 8 バイトのあと、desc の塊（名前 4・長さ 8・中身 32 = 20〜51 バイト目）、data の塊（52 バイト目から）
            XCTAssertEqual(String(decoding: bytes[8..<12], as: UTF8.self), "desc")
            let rate = Double(bitPattern: u64(20))
            XCTAssertEqual(String(decoding: bytes[28..<32], as: UTF8.self), "lpcm")
            let bytesPerFrame = u32(36)
            XCTAssertEqual(u32(44), 1, "\(effect.rawValue) がモノラルでない")
            XCTAssertEqual(u32(48), 16)
            XCTAssertEqual(String(decoding: bytes[52..<56], as: UTF8.self), "data")
            let dataSize = Int(u64(56)) - 4  // 頭の 4 バイトは編集の回数
            XCTAssertEqual(68 + dataSize, data.count, "\(effect.rawValue) の data の長さが合わない")
            let seconds = Double(dataSize) / Double(bytesPerFrame) / rate
            XCTAssertGreaterThanOrEqual(seconds, 0.2, effect.rawValue)
            XCTAssertLessThanOrEqual(seconds, 0.8, effect.rawValue)
        }
    }

    /// 作り直せる: 合成の台本があり、全部の音を作る
    func testSoundsHaveTheirGenerator() throws {
        let script = try String(contentsOf: root.appendingPathComponent("Tools/make-sounds.py"), encoding: .utf8)
        for effect in SoundEffect.allCases {
            XCTAssertTrue(script.contains("\"\(effect.rawValue)\""), "\(effect.rawValue) を作る台本が無い")
        }
    }

    #if os(iOS)
    /// アプリの束に入っている（単体テストはアプリの中で走る）
    func testSoundFilesAreInTheAppBundle() {
        for effect in SoundEffect.allCases {
            XCTAssertNotNil(effect.url(), "\(effect.rawValue).caf がアプリの束に無い")
        }
    }
    #endif

    // MARK: つなぎ

    /// カプセルが開く瞬間（`openDelay`）に、音と触覚を同時に。動きを減らす設定でも鳴らす。硬貨は入れ口へ沈む瞬間
    func testGachaPlaysSounds() throws {
        let gacha = try text("Sources/JourneyPhoto/Features/Trunk/TrunkGachaView.swift")
        guard let popRange = gacha.range(of: "private func popOpen() {") else { return XCTFail("開いた音の関数が無い") }
        let pop = String(gacha[popRange.lowerBound...].prefix(160))
        XCTAssertTrue(pop.contains("SoundEffects" + ".play(.capsuleOpen)"), "カプセルが開いても音が鳴らない")
        XCTAssertTrue(pop.contains("pops += 1"), "開いた音と同じ瞬間に触覚が無い")
        XCTAssertTrue(gacha.contains(".sensoryFeedback(.impact(weight: .medium), trigger: pops)"))
        XCTAssertTrue(gacha.contains("Task.sleep(nanoseconds: UInt64(TrunkMotion.openDelay * 1_000_000_000))"),
                      "ふたが外れる瞬間に合わせていない")
        XCTAssertGreaterThanOrEqual(gacha.components(separatedBy: "popOpen()").count - 1, 3, "動きを減らす設定の道で鳴らしていない")
        XCTAssertTrue(gacha.contains("SoundEffects" + ".play(.coinIn)"), "硬貨を入れても音が鳴らない")
        XCTAssertTrue(gacha.contains("SoundEffects" + ".prepare(["), "先に読み込んでいない（押した瞬間に遅れる）")
    }
}
