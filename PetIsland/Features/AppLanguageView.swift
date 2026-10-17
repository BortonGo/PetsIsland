import SwiftUI
import UIKit

enum PetAppLanguage: String, CaseIterable {
    case english = "en"
    case russian = "ru"

    var nativeName: String { self == .russian ? "Русский" : "English" }

    static var current: Self {
        resolve(preferences: Bundle.main.preferredLocalizations)
    }

    static func resolve(preferences: [String]) -> Self {
        let match = Bundle.preferredLocalizations(from: allCases.map(\.rawValue), forPreferences: preferences).first
        return Self(rawValue: match ?? "en") ?? .english
    }
}

/// iOS owns the preference so Foundation, SwiftUI, widgets and system UI
/// resolve language together. Do not override AppleLanguages or recreate saves.
struct AppLanguageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var settingsUnavailable = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(String(localized: "Choose a language for Pet Island", table: "ReleaseSupport"))
                        .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(PetAppLanguage.allCases, id: \.self) { language in
                            HStack {
                                Text(verbatim: language.nativeName)
                                Spacer()
                                if language == .current {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                            }
                            .padding(16)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(language == .current ? [.isSelected] : [])
                            .accessibilityIdentifier("language.option.\(language.rawValue)")
                            if language != PetAppLanguage.allCases.last { Divider() }
                        }
                    }.petSurface()
                    Text(String(localized: "iOS saves the language for this app. Your iPhone’s language and your island stay the same. Pet Island may reopen after the change.", table: "ReleaseSupport"))
                        .foregroundStyle(PetDesign.secondary)
                    Button(String(localized: "Choose language in iOS Settings", table: "ReleaseSupport")) {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else {
                            settingsUnavailable = true
                            return
                        }
                        openURL(url) { accepted in settingsUnavailable = !accepted }
                    }
                    .buttonStyle(PetPrimaryButtonStyle())
                    .accessibilityIdentifier("language.openSettings")
                    if settingsUnavailable {
                        Text(String(localized: "Open Settings on your iPhone, find Pet Island and tap Language.", table: "ReleaseSupport"))
                            .foregroundStyle(PetDesign.secondary)
                    }
                    DisclosureGroup(String(localized: "Can’t find the Language option?", table: "ReleaseSupport")) {
                        Text(String(localized: "In iPhone Settings, open General → Language & Region and add English or Russian. Keep your current primary language. Then return to Pet Island’s settings and choose Language.", table: "ReleaseSupport"))
                            .font(.footnote).foregroundStyle(PetDesign.secondary).padding(.top, 12)
                    }
                }.padding(24)
            }
            .petPage()
            .navigationTitle(String(localized: "App language", table: "ReleaseSupport"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
