import SwiftUI
import UIKit

enum PetSupportContact {
    static let email = "bortone52@yandex.ru"
    static var emailURL: URL? {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = email
        parts.queryItems = [URLQueryItem(name: "subject", value: "Pet Island — support")]
        return parts.url
    }
}

struct SupportPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    @State private var mailUnavailable = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Contact the author", table: "ReleaseSupport"))
                            .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        Text(PetSupportContact.email).textSelection(.enabled)
                        Button(String(localized: "Write an email", table: "ReleaseSupport")) {
                            guard let url = PetSupportContact.emailURL else { mailUnavailable = true; return }
                            openURL(url) { accepted in mailUnavailable = !accepted }
                        }.buttonStyle(PetPrimaryButtonStyle()).accessibilityIdentifier("privacy.email")
                        Button {
                            UIPasteboard.general.string = PetSupportContact.email
                            copied = true
                        } label: {
                            Text(String(localized: copied ? "Email copied" : "Copy email", table: "ReleaseSupport"))
                                .contentTransition(.identity)
                                .animation(nil, value: copied)
                        }.buttonStyle(PetQuietButtonStyle()).accessibilityIdentifier("privacy.copyEmail")
                        if mailUnavailable {
                            Text(String(localized: "No email app is available. Copy the address and use your preferred mail service.", table: "ReleaseSupport"))
                                .font(.footnote).foregroundStyle(PetDesign.secondary)
                        }
                        Text(String(localized: "For a bug report, include your iPhone model, iOS version and what happened. Please don’t send passwords or payment details.", table: "ReleaseSupport"))
                            .font(.footnote).foregroundStyle(PetDesign.secondary)
                    }
                    Divider()
                    Text(String(localized: "Privacy policy", table: "ReleaseSupport"))
                        .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("privacy.policy")
                    policy("Your island stays on your device", "Pet names, settings, care, walks, postcards, wardrobe and game progress are stored locally. The app and its widgets share this data through an App Group. There is no developer account, server, advertising SDK or tracking in Pet Island.")
                    policy("Backups and sharing are your choice", "Island backup exports a file only when you ask. You choose where to save or share it; the file may include pet names and progress. Import replaces the island after your confirmation. iOS device backups and your chosen file or sharing service follow their own privacy policies.")
                    policy("Optional payments", "Apple processes tips through the App Store. Pet Island verifies the transaction on your device and does not receive your card details. No purchase receipt or identifier is sent to the author’s server; there is no such server. Apple may retain payment records under its own policy.")
                    policy("When you contact us", "If you email the author, your email address, message and attachments are used to answer your request. Send only what is needed. You can request deletion by writing to the same address. The mailbox provider handles email under its own policy.")
                    policy("Deleting your data", "You can delete pets in the app. Deleting the app removes its local data; copies in device backups or exported files must be removed separately. Deleting Pet Island does not delete Apple’s purchase records. There is no account to close.")
                    Text(String(localized: "Updated 17 October 2026. Contact: bortone52@yandex.ru", table: "ReleaseSupport"))
                        .font(.caption).foregroundStyle(PetDesign.secondary)
                }.padding(24)
            }
            .petPage()
            .navigationTitle(String(localized: "Help and privacy", table: "ReleaseSupport"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func policy(_ title: String.LocalizationValue, _ body: String.LocalizationValue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: title, table: "ReleaseSupport")).font(.headline).accessibilityAddTraits(.isHeader)
            Text(String(localized: body, table: "ReleaseSupport")).foregroundStyle(PetDesign.secondary)
        }
    }
}
