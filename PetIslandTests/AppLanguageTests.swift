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
        XCTAssertTrue(Set(["en", "ru"]).isSubset(of: Set(Bundle.main.localizations)))
        for language in PetAppLanguage.allCases {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language.rawValue, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "App language", value: nil, table: "ReleaseSupport"),
                           language == .russian ? "Язык приложения" : "App language")
            XCTAssertEqual(bundle.localizedString(forKey: "In Settings, tap Language and choose English or Russian. Then reopen Pet Island.", value: nil, table: "ReleaseSupport"),
                           language == .russian
                           ? "В настройках нажмите «Язык» и выберите English или «Русский». Затем откройте Pet Island снова."
                           : "In Settings, tap Language and choose English or Russian. Then reopen Pet Island.")
            XCTAssertEqual(bundle.localizedString(forKey: "Open privacy policy online", value: nil, table: "ReleaseSupport"),
                           language == .russian ? "Открыть политику на сайте" : "Open privacy policy online")
            XCTAssertEqual(bundle.localizedString(forKey: "In stock: %@", value: nil, table: nil),
                           language == .russian ? "В запасе: %@" : "In stock: %@")
            let step = bundle.localizedString(forKey: "Step %@ of 3", value: nil, table: nil)
            XCTAssertEqual(String(format: step, "2"), language == .russian ? "Шаг 2 из 3" : "Step 2 of 3")
        }
    }

    func testSystemLanguageSelectionIsAvailableWithOneDeviceLanguage() throws {
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIPrefersShowingLanguageSettings") as? Bool, true,
                       "The app must expose language selection even when iOS has only one preferred language.")
        let languages = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String])
        XCTAssertEqual(Set(languages), Set(PetAppLanguage.allCases.map(\.rawValue)))
    }

    func testPrivacyWebsiteMatchesTheAppLanguageAndPublishedPages() {
        XCTAssertEqual(PetSupportContact.privacyPolicyURL(for: .russian).absoluteString,
                       "https://bortongo.github.io/pet-island-support/privacy.html")
        XCTAssertEqual(PetSupportContact.privacyPolicyURL(for: .english).absoluteString,
                       "https://bortongo.github.io/pet-island-support/en/privacy.html")
        XCTAssertEqual(PetSupportContact.privacyPolicyURL(), PetSupportContact.privacyPolicyURL(for: .current))
    }
}
