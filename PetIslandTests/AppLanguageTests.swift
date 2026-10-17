import XCTest
@testable import PetIsland

final class AppLanguageTests: XCTestCase {
    func testRegionalPreferencesAndUnsupportedLanguageFallback() {
        XCTAssertEqual(PetAppLanguage.resolve(preferences: ["ru-RU", "en-US"]), .russian)
        XCTAssertEqual(PetAppLanguage.resolve(preferences: ["en-GB", "ru"]), .english)
        XCTAssertEqual(PetAppLanguage.resolve(preferences: ["fr", "ru"]), .russian)
        XCTAssertEqual(PetAppLanguage.resolve(preferences: ["zh-Hans"]), .english)
    }

    func testBothLanguagesArePresentInTheAppBundle() throws {
        for language in PetAppLanguage.allCases {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language.rawValue, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "App language", value: nil, table: "ReleaseSupport"),
                           language == .russian ? "Язык приложения" : "App language")
            XCTAssertEqual(bundle.localizedString(forKey: "In stock: %@", value: nil, table: nil),
                           language == .russian ? "В запасе: %@" : "In stock: %@")
            let step = bundle.localizedString(forKey: "Step %@ of 3", value: nil, table: nil)
            XCTAssertEqual(String(format: step, "2"), language == .russian ? "Шаг 2 из 3" : "Step 2 of 3")
        }
    }
}
