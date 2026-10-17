import XCTest

@MainActor
final class PetProfileUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
#if !targetEnvironment(simulator)
        throw XCTSkip("UI fixtures run in Simulator to keep device saves untouched.")
#endif
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws { app?.terminate() }

    func testAuthorSupportSuccessAndPendingDoNotBlockClosing() {
        for mode in ["", "-support-pending"] {
            app.launchArguments = ["-release-support-preview", mode, "-AppleLanguages", "(en)"]
            app.launch()
            let buy = app.buttons["support.buy.org.bortongo.PetIsland.tip.small"]
            XCTAssertTrue(buy.waitForExistence(timeout: 10))
            reveal(buy)
            buy.tap()
            let notice = app.staticTexts[mode.isEmpty ? "support.notice.thanks" : "support.notice.pending"]
            XCTAssertTrue(notice.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Done"].isHittable)
            if !mode.isEmpty { XCTAssertFalse(buy.isEnabled) }
            capture(mode.isEmpty ? "Support — thanks" : "Support — pending")
            app.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts["support.preview.closed"].waitForExistence(timeout: 5))
            XCTAssertFalse(buy.exists)
            app.terminate()
        }
    }

    func testAuthorSupportPendingRetryRequiresConfirmationInBothLanguages() {
        for language in ["en", "ru"] {
            app.launchArguments = ["-release-support-preview", "-support-pending", "-AppleLanguages", "(\(language))"]
            app.launch()
            let buy = app.buttons["support.buy.org.bortongo.PetIsland.tip.small"]
            XCTAssertTrue(buy.waitForExistence(timeout: 10))
            reveal(buy)
            buy.tap()
            let retry = app.buttons["support.retry.org.bortongo.PetIsland.tip.small"]
            XCTAssertTrue(retry.waitForExistence(timeout: 5))
            reveal(retry)
            XCTAssertEqual(retry.label, language == "en" ? "Retry declined request" : "Повторить отклонённый запрос")
            retry.tap()
            let cancel = app.alerts.buttons["support.retry.cancel"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
            cancel.tap()
            XCTAssertFalse(buy.isEnabled)
            XCTAssertTrue(retry.isEnabled)
            retry.tap()
            let confirm = app.alerts.buttons["support.retry.confirm"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
            capture("Support — declined request confirmation \(language)")
            confirm.tap()
            XCTAssertTrue(app.staticTexts["support.notice.pending"].waitForExistence(timeout: 5))
            XCTAssertFalse(buy.isEnabled)
            app.terminate()
        }
    }

    func testAuthorSupportUnavailableAtLargestRussianText() {
        app.launchArguments = ["-release-support-preview", "-support-empty", "-AppleLanguages", "(ru)",
                               "-AppleLocale", "ru_RU", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let reload = app.buttons["support.reload"]
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        reveal(reload)
        XCTAssertTrue(reload.isHittable)
        XCTAssertEqual(reload.label, "Обновить цены")
        capture("Support — unavailable, largest Russian text")
        XCTAssertTrue(app.buttons.matching(identifier: "support.buy.org.bortongo.PetIsland.tip.small").allElementsBoundByIndex.isEmpty)
    }

    func testPrivacyPolicyAndCopyContactWorkOffline() {
        app.launchArguments = ["-release-privacy-preview", "-AppleLanguages", "(en)"]
        app.launch()
        let copy = app.buttons["privacy.copyEmail"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        copy.tap()
        XCTAssertEqual(copy.label, "Email copied")
        capture("Privacy — contact copied")
        let policy = app.staticTexts["privacy.policy"]
        reveal(policy)
        XCTAssertTrue(policy.isHittable)
        let deletion = app.staticTexts["Deleting your data"]
        reveal(deletion)
        XCTAssertTrue(deletion.isHittable)
    }

    func testSupportAndPrivacyOpenAndCloseFromSettings() {
        launchSettings()
        for identifier in ["settings.authorSupport", "settings.supportPrivacy"] {
            let row = app.buttons[identifier]
            reveal(row)
            row.tap()
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
            app.buttons["Done"].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
        }
    }

    func testAppLanguageOpensInEnglishAndRussianWithoutChangingPets() {
        for russian in [false, true] {
            launchSettings(russian ? "-settings-russian" : "")
            let row = app.buttons["settings.language"]
            reveal(row)
            XCTAssertTrue(row.label.contains(russian ? "Русский" : "English"))
            row.tap()
            let open = app.buttons["language.openSettings"]
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            XCTAssertEqual(open.label, russian ? "Выбрать язык в настройках iOS" : "Choose language in iOS Settings")
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "language.option.en").firstMatch.exists)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "language.option.ru").firstMatch.exists)
            capture(russian ? "Language — Russian" : "Language — English")
            app.buttons[russian ? "Готово" : "Done"].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testAppLanguageLargestRussianTextKeepsSettingsAndHelpReachable() {
        launchSettings("-settings-russian", "-settings-largest")
        let row = app.buttons["settings.language"]
        reveal(row)
        row.tap()
        let open = app.buttons["language.openSettings"]
        reveal(open, fullyVisible: true)
        XCTAssertTrue(open.isHittable)
        let help = app.buttons["Нет пункта «Язык»?"]
        reveal(help)
        help.tap()
        capture("Language — largest Russian text")
        XCTAssertTrue(app.buttons["Готово"].isHittable)
        app.buttons["Готово"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    private func launch(_ arguments: String...) {
        let russian = arguments.contains("-profile-russian")
        app.launchArguments = ["-pet-profile-preview", "-AppleLanguages", russian ? "(ru)" : "(en)", "-AppleLocale", russian ? "ru_RU" : "en_US"] + arguments
        if arguments.contains("-profile-large") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        } else if arguments.contains("-profile-largest") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
    }

    private func reveal(_ element: XCUIElement, fullyVisible: Bool = false) {
        // Large fling gestures can carry a control behind a pinned header.
        // Keep the target in the visible middle and use short, deliberate drags.
        for _ in 0..<35 {
            let visible = app.frame
            var top = (app.navigationBars.allElementsBoundByIndex.last?.frame.maxY ?? visible.minY) + 8
            let category = app.buttons["shop.category"]
            if category.exists && category.isHittable { top = max(top, category.frame.maxY + 8) }
            let hasEditorFooter = app.buttons["habitat.save"].exists && app.buttons["habitat.save"].isHittable
            let footer = hasEditorFooter
                ? app.otherElements["habitat.saveBar"] : app.otherElements["wardrobe.pinnedControls"]
            let bottom = footer.exists ? footer.frame.minY - 12 : visible.maxY
            // A hittable centre does not mean a tall button is fully visible.
            // Geometry assertions request full visibility; ordinary interactions
            // and oversized paragraphs only need a reachable centre.
            if element.exists && element.isHittable {
                let frame = element.frame
                if fullyVisible && frame.height <= bottom - top {
                    if frame.minY >= top && frame.maxY <= bottom { return }
                } else if frame.midY > top && frame.midY < bottom { return }
            }
            if !hasEditorFooter, element.exists && element.frame.minY > visible.maxY + 100 {
                app.swipeUp()
                continue
            }
            let down = element.exists && (fullyVisible && element.frame.height <= bottom - top
                ? element.frame.minY < top : element.frame.midY < top)
            let from: XCUICoordinate
            let to: XCUICoordinate
            if hasEditorFooter {
                // Keep gestures inside the scroll area, above the pinned save
                // button even when its label wraps at accessibility sizes.
                let height = max(0, bottom - top)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                var distance = height * 0.6
                if fullyVisible, element.exists, element.isHittable, element.frame.height <= height {
                    let overflow = down ? top - element.frame.minY : element.frame.maxY - bottom
                    distance = min(distance, max(24, overflow + 12))
                }
                let start = top + height * (down ? 0.2 : 0.8)
                from = origin.withOffset(CGVector(dx: visible.width * 0.88, dy: start))
                to = origin.withOffset(CGVector(dx: visible.width * 0.88, dy: start + (down ? distance : -distance)))
            } else {
                from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: down ? 0.43 : 0.63))
                to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: down ? 0.63 : 0.43))
            }
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTAssertTrue(element.isHittable, "Unreachable control: \(element)")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func auditVisibleContent(pinnedHeader: XCUIElement? = nil, pinnedFooter: XCUIElement? = nil) throws {
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .textClipped]) { issue in
            guard issue.auditType == .textClipped, let element = issue.element else { return false }
            let frame = element.frame, window = self.app.frame
            // Text in a scroll view may straddle the screen or sticky header.
            // Keep auditing truncation inside visible labels, including the
            // header itself; only these expected vertical scroll clips are exempt.
            if frame.minY < window.minY || frame.maxY > window.maxY { return true }
            if let header = pinnedHeader, header.isHittable,
               frame.minY < header.frame.maxY && frame.maxY > header.frame.maxY { return true }
            if let footer = pinnedFooter, footer.isHittable,
               frame.minY < footer.frame.minY && frame.maxY > footer.frame.minY { return true }
            return false
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func chooseShopCategory(_ name: String) {
        let category = app.buttons["shop.category"]
        XCTAssertTrue(category.isHittable)
        category.tap()
        app.buttons[name].tap()
    }

    private func launchHomeClarity(_ arguments: String...) {
        let large = arguments.contains("-home-large")
        app.launchArguments = ["-home-clarity-preview", "-AppleLanguages", large ? "(ru)" : "(en)",
                               "-AppleLocale", large ? "ru_RU" : "en_US"] + arguments
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["discoveries.open"].waitForExistence(timeout: 10))
    }

    func testHomeClarityNavigationKeepsResidentsAndPlayroom() throws {
        launchHomeClarity("-home-multiple")
        XCTAssertEqual(app.staticTexts["island.residentCount"].label, "Here now: 2")
        capture("Home — clear resident count and compact actions")
        try auditVisibleContent(pinnedFooter: app.tabBars.firstMatch)
        app.buttons["island.editEnclosure"].tap()
        XCTAssertTrue(app.buttons["habitat.close"].waitForExistence(timeout: 5))
        app.buttons["habitat.close"].tap()
        app.buttons["island.settings"].tap()
        XCTAssertTrue(app.navigationBars["Island setup"].waitForExistence(timeout: 5))
        app.navigationBars["Island setup"].buttons["Done"].tap()
        let play = app.buttons["island.play"]
        reveal(play)
        XCTAssertTrue(play.isEnabled)
        play.tap()
        XCTAssertTrue(app.navigationBars["Playroom"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("Pixel").exists)
        XCTAssertTrue(element("Luna").exists)
        app.navigationBars["Playroom"].buttons["Close"].tap()
        XCTAssertTrue(app.buttons["island.play"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["island.residentCount"])
        XCTAssertEqual(app.staticTexts["island.residentCount"].label, "Here now: 2")
    }

    func testHomeClarityAwayPetExplainsDisabledActionsAndOpensWalk() throws {
        launchHomeClarity("-home-away")
        XCTAssertEqual(app.staticTexts["island.residentCount"].label, "Here now: 0")
        XCTAssertEqual(app.buttons["discoveries.open"].value as? String, "Pixel is out exploring")
        let placement = app.buttons["island.placement"]
        reveal(placement)
        XCTAssertFalse(placement.isEnabled)
        XCTAssertTrue(placement.label.contains("Pixel is out exploring"))
        XCTAssertFalse(app.buttons["island.play"].isEnabled)
        XCTAssertTrue(app.staticTexts["island.playReason"].exists)
        capture("Home — away companion and readable disabled actions")
        try auditVisibleContent(pinnedFooter: app.tabBars.firstMatch)
        reveal(app.buttons["discoveries.open"])
        app.buttons["discoveries.open"].tap()
        XCTAssertTrue(app.navigationBars["Walks"].waitForExistence(timeout: 5))
        app.navigationBars["Walks"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["discoveries.open"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["island.residentCount"].label, "Here now: 0")
        XCTAssertFalse(app.buttons["island.play"].isEnabled)
    }

    func testHomeClarityCompanionReturnsToEnclosureAndEnablesPlay() {
        launchHomeClarity("-home-with-you")
        XCTAssertEqual(app.staticTexts["island.residentCount"].label, "Here now: 0")
        let summary = element("island.residentSummary")
        reveal(summary)
        XCTAssertTrue(summary.label.contains("Pixel is with you"))
        XCTAssertFalse(app.buttons["island.play"].isEnabled)
        let placement = app.buttons["island.placement"]
        reveal(placement)
        XCTAssertTrue(placement.label.contains("Bring Pixel home"))
        XCTAssertTrue(placement.isEnabled)
        capture("Home — companion is with you")
        placement.tap()
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: app.buttons["island.play"])
        waitForExpectations(timeout: 8)
        XCTAssertTrue(placement.label.contains("Take Pixel with you"))
        reveal(app.staticTexts["island.residentCount"])
        XCTAssertEqual(app.staticTexts["island.residentCount"].label, "Here now: 1")
        XCTAssertTrue(element("island.residentSummary").label.contains("Pixel"))
        XCTAssertFalse(app.staticTexts["island.playReason"].exists)
    }

    func testHomeClarityLargestRussianTextKeepsNamesAndControlsReadable() throws {
        launchHomeClarity("-home-large")
        let edit = app.buttons["island.editEnclosure"]
        reveal(edit)
        XCTAssertEqual(app.staticTexts["island.residentCount"].label, "Сейчас здесь: 2")
        capture("Home — large Russian heading stays outside the scene")
        edit.tap()
        XCTAssertTrue(app.buttons["habitat.close"].waitForExistence(timeout: 5))
        app.buttons["habitat.close"].tap()
        let summary = element("island.residentSummary")
        reveal(summary, fullyVisible: true)
        XCTAssertTrue(summary.label.contains("Пиксель Длиннохвостый"))
        XCTAssertTrue(summary.label.contains("Луна Пушистая"))
        capture("Home — largest text and complete companion names")
        try auditVisibleContent(pinnedFooter: app.tabBars.firstMatch)
        reveal(app.buttons["island.play"])
        XCTAssertTrue(app.buttons["island.play"].isEnabled)
    }

    func testHomeClarityEmptySceneFitsLargestRussianText() throws {
        launchHomeClarity("-home-away", "-home-large", "-home-single")
        app.swipeUp()
        let empty = app.staticTexts["Вольер пуст"]
        reveal(empty, fullyVisible: true)
        XCTAssertLessThanOrEqual(empty.frame.maxY, app.tabBars.firstMatch.frame.minY,
                                 "The complete empty-state label must be readable above the tab bar")
        capture("Home — empty scene at largest Russian text")
        try auditVisibleContent(pinnedFooter: app.tabBars.firstMatch)
        XCTAssertEqual(app.staticTexts["island.residentCount"].label, "Сейчас здесь: 0")
        reveal(app.buttons["island.play"])
        XCTAssertFalse(app.buttons["island.play"].isEnabled)
    }

    private func launchEnclosureEditor(_ arguments: String...) {
        let russian = arguments.contains("-editor-russian-large")
        app.launchArguments = ["-enclosure-editor-preview", "-AppleLanguages", russian ? "(ru)" : "(en)",
                               "-AppleLocale", russian ? "ru_RU" : "en_US"] + arguments
        if russian { app.launchArguments += ["-editor-light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["habitat.close"].waitForExistence(timeout: 10))
    }

    private func resident(_ index: Int) -> XCUIElement {
        app.buttons["habitat.resident.ED000000-0000-0000-0000-00000000000\(index)"]
    }

    private func chooseEnclosureTheme(_ theme: String) {
        let choice = app.buttons["habitat.theme.\(theme)"]
        reveal(choice)
        choice.tap()
        XCTAssertTrue(choice.isSelected)
    }

    private func placeEditorBox() {
        let furniture = app.buttons["furniture.open"]
        reveal(furniture)
        furniture.tap()
        XCTAssertTrue(app.navigationBars["Furniture"].waitForExistence(timeout: 5))
        let box = app.buttons["furniture.cozyBox"]
        reveal(box)
        box.tap()
        XCTAssertTrue(app.buttons["furniture.place.left"].waitForExistence(timeout: 5))
        app.buttons["furniture.place.left"].tap()
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        XCTAssertTrue(box.isSelected)
        app.navigationBars["Furniture"].buttons["Done"].tap()
    }

    func testEnclosureEditorGuardsDraftAndDiscardKeepsFurniture() {
        launchEnclosureEditor()
        chooseEnclosureTheme("sunnyMeadow")
        XCTAssertEqual(app.staticTexts["habitat.saveStatus"].label, "Unsaved background or residents")
        app.navigationBars["Enclosure"].swipeDown()
        XCTAssertTrue(app.buttons["habitat.close"].isHittable, "An accidental swipe must not discard the draft")
        app.buttons["habitat.close"].tap()
        XCTAssertTrue(app.alerts.buttons["Keep editing"].waitForExistence(timeout: 5))
        capture("Enclosure — explicit discard confirmation")
        app.alerts.buttons["Keep editing"].tap()
        chooseEnclosureTheme("meadow")
        XCTAssertEqual(app.buttons["habitat.save"].label, "Done", "Returning to the original choice clears the unsaved state")
        app.buttons["habitat.close"].tap()
        XCTAssertTrue(app.buttons["editor.fixture.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["editor.fixture.open"].tap()
        chooseEnclosureTheme("sunnyMeadow")
        placeEditorBox()
        app.buttons["habitat.close"].tap()
        XCTAssertTrue(app.alerts.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.alerts.buttons["Discard changes"].tap()
        XCTAssertTrue(app.staticTexts["editor.fixture.theme"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editor.fixture.theme"].label, "meadow")
        XCTAssertEqual(app.staticTexts["editor.fixture.residents"].label, "Pixel,Luna")
        XCTAssertEqual(app.staticTexts["editor.fixture.furniture"].label, "cozyBox:left")
        XCTAssertEqual(app.staticTexts["editor.fixture.coins"].label, "120")
    }

    func testEnclosureEditorFailureKeepsDraftAndRetryPersistsResidents() {
        launchEnclosureEditor("-editor-fail-save")
        chooseEnclosureTheme("sunnyMeadow")
        let luna = resident(2)
        reveal(luna)
        luna.tap()
        let pixel = resident(1)
        XCTAssertFalse(pixel.isEnabled)
        XCTAssertTrue(pixel.label.contains("At least one resident is required"))
        app.buttons["habitat.save"].tap()
        XCTAssertTrue(app.alerts["Could not save"].waitForExistence(timeout: 5))
        capture("Enclosure — failed save retains the draft")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(pixel.isSelected)
        XCTAssertFalse(luna.isSelected)
        XCTAssertEqual(app.staticTexts["habitat.saveStatus"].label, "Unsaved background or residents")
        app.buttons["habitat.save"].tap()
        XCTAssertTrue(app.buttons["editor.fixture.reload"].waitForExistence(timeout: 5))
        app.buttons["editor.fixture.reload"].tap()
        XCTAssertEqual(app.staticTexts["editor.fixture.theme"].label, "sunnyMeadow")
        XCTAssertEqual(app.staticTexts["editor.fixture.residents"].label, "Pixel")
        XCTAssertEqual(app.staticTexts["editor.fixture.pets"].label, "Pixel,Luna,Mochi")
        app.buttons["editor.fixture.open"].tap()
        XCTAssertTrue(app.buttons["habitat.save"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["habitat.save"].label, "Done")
        reveal(luna)
        luna.tap()
        XCTAssertTrue(pixel.isEnabled, "Choosing a second resident makes the first removable again")
        app.buttons["habitat.save"].tap()
        XCTAssertTrue(app.staticTexts["editor.fixture.residents"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editor.fixture.residents"].label, "Pixel,Luna")
    }

    func testEnclosureEditorCapacityExplainsHowToChooseAnotherResident() throws {
        launchEnclosureEditor("-editor-full")
        let spare = resident(7)
        reveal(spare)
        XCTAssertFalse(spare.isEnabled)
        XCTAssertTrue(spare.label.contains("No free places"))
        let selected = resident(6)
        reveal(selected)
        selected.tap()
        reveal(spare)
        XCTAssertTrue(spare.isEnabled)
        spare.tap()
        XCTAssertTrue(spare.isSelected)
        XCTAssertFalse(selected.isEnabled)
        XCTAssertTrue(selected.label.contains("No free places"))
        capture("Enclosure — full selection with visible reasons")
        try auditVisibleContent(pinnedFooter: app.otherElements["habitat.saveBar"])
        app.buttons["habitat.save"].tap()
        XCTAssertTrue(app.staticTexts["editor.fixture.residents"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editor.fixture.residents"].label, "Pixel,Luna,Mochi,Leo,Kiwi,Sunny")
        XCTAssertEqual(app.staticTexts["editor.fixture.pets"].label, "Pixel,Luna,Mochi,Leo,Kiwi,Snow,Sunny")
    }

    func testEnclosureEditorWalkingResidentAndLargestRussianText() throws {
        launchEnclosureEditor("-editor-away", "-editor-russian-large")
        let luna = resident(2)
        reveal(luna, fullyVisible: true)
        XCTAssertTrue(luna.isSelected)
        XCTAssertFalse(luna.isEnabled)
        XCTAssertTrue(luna.label.contains("Место"))
        capture("Enclosure — walking resident, largest Russian text")
        try auditVisibleContent(pinnedFooter: app.otherElements["habitat.saveBar"])
        let mochi = resident(3)
        reveal(mochi)
        mochi.tap()
        XCTAssertTrue(luna.isSelected)
        XCTAssertFalse(luna.isEnabled)
        XCTAssertTrue(app.buttons["habitat.save"].isHittable)
        app.buttons["habitat.save"].tap()
        XCTAssertTrue(app.staticTexts["editor.fixture.residents"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editor.fixture.residents"].label, "Pixel,Luna,Mochi")
        XCTAssertEqual(app.staticTexts["editor.fixture.coins"].label, "120")
    }

    func testEnclosureEditorFurnitureOnlySavesWithoutDraftConfirmation() {
        launchEnclosureEditor()
        placeEditorBox()
        XCTAssertEqual(app.buttons["habitat.save"].label, "Done")
        XCTAssertEqual(app.staticTexts["habitat.saveStatus"].label, "Background and residents are saved")
        app.buttons["habitat.close"].tap()
        XCTAssertTrue(app.buttons["editor.fixture.reload"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["editor.fixture.reload"].tap()
        XCTAssertEqual(app.staticTexts["editor.fixture.theme"].label, "meadow")
        XCTAssertEqual(app.staticTexts["editor.fixture.residents"].label, "Pixel,Luna")
        XCTAssertEqual(app.staticTexts["editor.fixture.furniture"].label, "cozyBox:left")
        app.buttons["editor.fixture.open"].tap()
        XCTAssertTrue(app.buttons["habitat.save"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["habitat.save"].label, "Done")
    }

    private func launchFurniture(russianLarge: Bool = false) {
        app.launchArguments = ["-furniture-clarity-preview", "-AppleLanguages", russianLarge ? "(ru)" : "(en)",
                               "-AppleLocale", russianLarge ? "ru_RU" : "en_US"]
        if russianLarge {
            app.launchArguments += ["-furniture-light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.navigationBars[russianLarge ? "Предметы для вольера" : "Furniture"].waitForExistence(timeout: 10))
    }

    private func assertFurnitureFixture(layout: String) {
        XCTAssertTrue(app.staticTexts["furniture.fixture.layout"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["furniture.fixture.layout"].label, layout)
        XCTAssertEqual(app.staticTexts["furniture.fixture.coins"].label, "120")
        XCTAssertEqual(app.staticTexts["furniture.fixture.pets"].label, "Pixel,Luna")
    }

    func testFurnitureOpeningAndCancelDoNotChangePlacement() throws {
        launchFurniture()
        app.navigationBars["Furniture"].buttons["Done"].tap()
        let layout = "birdPerch:perch,cozyBox:left,softBed:right"
        assertFurnitureFixture(layout: layout)
        let revision = app.staticTexts["furniture.fixture.revision"].label
        app.buttons["furniture.fixture.open"].tap()
        let box = app.buttons["furniture.cozyBox"]
        reveal(box)
        XCTAssertTrue(box.isSelected)
        XCTAssertEqual(box.value as? String, "Left corner")
        box.tap()
        let current = app.buttons["furniture.place.left"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertTrue(current.isSelected)
        XCTAssertFalse(current.isEnabled)
        XCTAssertTrue(app.buttons["furniture.remove"].isHittable)
        capture("Furniture — current place and explicit removal")
        try auditVisibleContent()
        app.navigationBars["Cozy box"].buttons["Cancel"].tap()
        XCTAssertTrue(box.isSelected)
        app.navigationBars["Furniture"].buttons["Done"].tap()
        assertFurnitureFixture(layout: layout)
        XCTAssertEqual(app.staticTexts["furniture.fixture.revision"].label, revision)
    }

    func testFurnitureMoveRemoveAndPlaceKeepsOwnershipAndCoins() {
        launchFurniture()
        let box = app.buttons["furniture.cozyBox"]
        reveal(box)
        box.tap()
        app.buttons["furniture.place.right"].tap()
        XCTAssertTrue(app.alerts.buttons["Replace"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(identifier: "Returns to collection: Soft bed (Right corner)").firstMatch.exists)
        app.alerts.buttons["Replace"].tap()
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        XCTAssertEqual(box.value as? String, "Right corner")
        box.tap()
        let remove = app.buttons["furniture.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        XCTAssertFalse(box.isSelected)
        XCTAssertEqual(box.value as? String, "Purchased")
        box.tap()
        XCTAssertTrue(app.buttons["furniture.place.left"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["furniture.remove"].exists)
        app.buttons["furniture.place.left"].tap()
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        XCTAssertEqual(box.value as? String, "Left corner")
        XCTAssertEqual(app.buttons["furniture.softBed"].value as? String, "Purchased")
        capture("Furniture — moved, removed and placed without another purchase")
        app.navigationBars["Furniture"].buttons["Done"].tap()
        assertFurnitureFixture(layout: "birdPerch:perch,cozyBox:left")
    }

    func testFurnitureBulkyReplacementExplainsBothItemsAndCanBeCancelled() {
        launchFurniture()
        let nest = app.buttons["furniture.leafNest"]
        reveal(nest)
        nest.tap()
        XCTAssertTrue(app.staticTexts["The box and leaf nest share one large-item space."].waitForExistence(timeout: 5))
        let right = app.buttons["furniture.place.right"]
        XCTAssertTrue(right.label.contains("Cozy box (Left corner)"))
        XCTAssertTrue(right.label.contains("Soft bed (Right corner)"))
        right.tap()
        let replace = app.alerts.buttons["Replace"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5))
        capture("Furniture — named replacement confirmation")
        app.alerts.buttons["Cancel"].tap()
        app.navigationBars["Leaf nest"].buttons["Cancel"].tap()
        app.navigationBars["Furniture"].buttons["Done"].tap()
        assertFurnitureFixture(layout: "birdPerch:perch,cozyBox:left,softBed:right")
        app.buttons["furniture.fixture.open"].tap()
        reveal(nest)
        nest.tap()
        right.tap()
        XCTAssertTrue(replace.waitForExistence(timeout: 5))
        replace.tap()
        XCTAssertTrue(nest.waitForExistence(timeout: 5))
        XCTAssertEqual(nest.value as? String, "Right corner")
        app.navigationBars["Furniture"].buttons["Done"].tap()
        assertFurnitureFixture(layout: "birdPerch:perch,leafNest:right")
    }

    func testFurnitureLargestRussianTextAndLockedShopRemainReachable() throws {
        launchFurniture(russianLarge: true)
        let box = app.buttons["furniture.cozyBox"]
        reveal(box)
        box.tap()
        let current = app.buttons["furniture.place.left"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        reveal(current)
        XCTAssertTrue(current.isSelected)
        let remove = app.buttons["furniture.remove"]
        reveal(remove, fullyVisible: true)
        capture("Furniture — largest Russian text, light theme")
        try auditVisibleContent()
        app.navigationBars.buttons["Отмена"].tap()
        let locked = app.buttons["furniture.warmStone"]
        reveal(locked)
        locked.tap()
        let buy = app.buttons["furniture.buy.warmStone"]
        reveal(buy)
        XCTAssertTrue(buy.isEnabled)
        capture("Furniture — locked item opens the shop")
    }

    private func launchSettings(_ arguments: String...) {
        let russian = arguments.contains("-settings-russian")
        app.launchArguments = ["-settings-clarity-preview", "-AppleLanguages", russian ? "(ru)" : "(en)",
                               "-AppleLocale", russian ? "ru_RU" : "en_US"] + arguments
        if arguments.contains("-settings-largest") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["settings.appearance.system"].waitForExistence(timeout: 10))
    }

    private func waitForSettingsSave() {
        XCTAssertTrue(app.staticTexts["settings.saveHint"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings.appearance.system"].isEnabled)
    }

    func testSettingsAutosaveKeepsChoicesAndPetCollection() {
        launchSettings("-settings-slow-save")
        XCTAssertEqual(app.staticTexts["settings.saveHint"].label, "Changes save automatically.")
        app.buttons["settings.appearance.system"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isEnabled, "Reselecting the current theme must not start another save")
        let light = app.buttons["settings.appearance.light"]
        light.tap()
        XCTAssertFalse(app.buttons["settings.appearance.dark"].isEnabled)
        waitForSettingsSave()
        XCTAssertTrue(light.isSelected)
        let haptics = app.switches["settings.haptics"], motion = app.switches["settings.motion"]
        reveal(haptics); haptics.tap()
        waitForSettingsSave()
        reveal(motion); motion.tap()
        waitForSettingsSave()
        capture("Settings — saved preferences")
        app.tabBars.buttons["Pets"].tap()
        let pixel = app.buttons["pet.profile.CE000000-0000-0000-0000-000000000001"]
        let luna = app.buttons["pet.profile.CE000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(pixel.waitForExistence(timeout: 5))
        XCTAssertEqual(pixel.label, "Pixel")
        XCTAssertEqual(luna.label, "Luna")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pet.profile.'")).count, 2)
        app.tabBars.buttons["Settings"].tap()
        reveal(light)
        XCTAssertTrue(light.isSelected)
        XCTAssertEqual(haptics.value as? String, "0")
        XCTAssertEqual(motion.value as? String, "1")
    }

    func testSettingsFailureShowsPreviousChoiceAndRetrySaves() {
        launchSettings("-settings-fail-save")
        let light = app.buttons["settings.appearance.light"]
        light.tap()
        let alert = app.alerts["Settings were not saved"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.appearance.system"].isSelected)
        XCTAssertFalse(light.isSelected)
        capture("Settings — failed save and retry")
        alert.buttons["Try again"].tap()
        waitForSettingsSave()
        XCTAssertFalse(alert.exists)
        XCTAssertTrue(light.isSelected)
        let haptics = app.switches["settings.haptics"]
        reveal(haptics)
        XCTAssertEqual(haptics.value as? String, "1")
    }

    func testSettingsLargestRussianTextExplainsMotionAndRemainsReachable() throws {
        launchSettings("-settings-russian", "-settings-largest")
        XCTAssertEqual(app.staticTexts["settings.saveHint"].label, "Изменения сохраняются автоматически.")
        let dark = app.buttons["settings.appearance.dark"]
        reveal(dark); dark.tap()
        waitForSettingsSave()
        XCTAssertTrue(dark.isSelected)
        let motion = app.switches["settings.motion"]
        reveal(motion)
        XCTAssertEqual(motion.value as? String, "0")
        let hint = app.staticTexts["settings.motionHint"]
        reveal(hint)
        XCTAssertTrue(hint.label.contains("Dynamic Island"))
        capture("Settings — largest Russian text and motion explanation")
        try auditVisibleContent()
        let guide = app.buttons["settings.guide"]
        reveal(guide); guide.tap()
        reveal(element("guide.walks"))
        XCTAssertTrue(element("guide.walks").isHittable)
    }

    private func launchOnboarding(russian: Bool = false, largest: Bool = false, failingSave: Bool = false) {
        app.launchArguments = ["-onboarding-preview", "-AppleLanguages", russian ? "(ru)" : "(en)",
                               "-AppleLocale", russian ? "ru_RU" : "en_US"]
        if largest {
            app.launchArguments += ["-onboarding-light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if failingSave { app.launchArguments += ["-onboarding-fail-save"] }
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
    }

    private func enterFirstPetName(_ value: String) {
        let field = app.textFields["petPicker.name"]
        reveal(field)
        field.tap()
        let count = (field.value as? String ?? "").count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + value)
    }

    func testOnboardingBackPreservesChoiceAndKeyboardClosesBeforeReview() throws {
        launchOnboarding()
        XCTAssertEqual(app.staticTexts["onboarding.step"].label, "Step 1 of 3")
        XCTAssertFalse(app.buttons["onboarding.back"].exists)
        capture("Onboarding — welcome")
        app.buttons["onboarding.next"].tap()
        let cat = app.buttons["petPicker.species.cat"]
        XCTAssertTrue(cat.waitForExistence(timeout: 5))
        reveal(cat); cat.tap()
        let british = app.buttons["petPicker.variant.britishShorthair.family"]
        reveal(british); british.tap()
        enterFirstPetName("  Luna   ")
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["onboarding.petName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding.petName"].label, "Luna")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("Onboarding — review and two destinations")
        app.buttons["onboarding.back"].tap()
        XCTAssertEqual(app.textFields["petPicker.name"].value as? String, "Luna")
        XCTAssertTrue(cat.isSelected)
        XCTAssertTrue(british.isSelected)
        app.buttons["onboarding.back"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(british.isSelected)
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.tabBars.buttons["Pets"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Pets"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pet.profile.' AND label == 'Luna'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.value as? String, "British shorthair")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pet.profile.'")).count, 1)
    }

    func testOnboardingFailedSaveKeepsDraftAndAllowsRetry() throws {
        launchOnboarding(failingSave: true)
        app.buttons["onboarding.next"].tap()
        enterFirstPetName("Milo")
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        let alert = app.alerts["Your pet could not be saved"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        capture("Onboarding — save failure keeps draft")
        alert.buttons["OK"].tap()
        XCTAssertEqual(app.staticTexts["onboarding.petName"].label, "Milo")
        XCTAssertTrue(app.buttons["onboarding.next"].isEnabled)
        app.buttons["onboarding.back"].tap()
        XCTAssertEqual(app.textFields["petPicker.name"].value as? String, "Milo")
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.tabBars.buttons["Pets"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Pets"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pet.profile.' AND label == 'Milo'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pet.profile.'")).count, 1)
    }

    func testOnboardingLargestRussianTextNamesAndControlsRemainReachable() throws {
        launchOnboarding(russian: true, largest: true)
        capture("Onboarding — Russian welcome, largest text")
        app.buttons["onboarding.next"].tap()
        enterFirstPetName("12345678901234567890")
        XCTAssertEqual(app.textFields["petPicker.name"].value as? String, "12345678901234567890")
        XCTAssertTrue(app.staticTexts["petPicker.savedName"].label.contains("1234567890123456"))
        app.buttons["onboarding.next"].tap()
        XCTAssertEqual(app.staticTexts["onboarding.petName"].label, "1234567890123456")
        app.buttons["onboarding.back"].tap()
        XCTAssertEqual(app.textFields["petPicker.name"].value as? String, "1234567890123456")
        enterFirstPetName("   ")
        app.buttons["onboarding.next"].tap()
        XCTAssertEqual(app.staticTexts["onboarding.petName"].label, "Pixel")
        XCTAssertEqual(app.staticTexts["onboarding.step"].label, "Шаг 3 из 3")
        reveal(element("guide.companion"))
        XCTAssertTrue(app.buttons["onboarding.next"].isHittable)
        capture("Onboarding — Russian guide, largest text")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .textClipped])
        app.buttons["onboarding.back"].tap()
        XCTAssertEqual(app.textFields["petPicker.name"].value as? String, "Pixel")
        reveal(app.buttons["petPicker.species.cat"])
        app.buttons["petPicker.species.cat"].tap()
        let british = app.buttons["petPicker.variant.britishShorthair.family"]
        // The breed list scrolls horizontally, independently of the page.
        let breeds = app.scrollViews.containing(.button, identifier: "petPicker.variant.classicCat.family").element(boundBy: 0)
        if !british.isHittable { breeds.swipeLeft() }
        reveal(british)
        capture("Onboarding — Russian choice, largest text")
        british.tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.tabBars.buttons["Питомцы"].waitForExistence(timeout: 10))
    }

    func testQuickGuideExplainsExistingRoutesWithoutChangingPet() throws {
        launch("-profile-collection", "-profile-russian", "-profile-largest", "-profile-light")
        XCTAssertTrue(app.tabBars.buttons["Настройки"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Настройки"].tap()
        let guide = app.buttons["settings.guide"]
        reveal(guide); guide.tap()
        for id in ["walks", "companion", "wardrobe", "furniture"] {
            let tip = element("guide.\(id)")
            reveal(tip)
            XCTAssertFalse(tip.label.isEmpty)
        }
        capture("Settings — quick guide, largest Russian text")
        try auditVisibleContent()
        app.tabBars.buttons["Питомцы"].tap()
        let pet = app.buttons["pet.profile.CD000000-0000-0000-0000-000000000002"]
        reveal(pet)
        XCTAssertEqual(pet.label, "Пиксель")
    }

    func testInterfaceShopCategoriesKeepCompanionWalletAndStock() throws {
        launch("-profile-route=shop")
        XCTAssertTrue(app.navigationBars["Pet Arcade"].waitForExistence(timeout: 10))
        let stock = element("shop.stock.food")
        reveal(stock)
        XCTAssertTrue(stock.label.contains("3"))
        capture("Interface — care first, dark")
        let buy = app.buttons["shop.buy.food"]
        reveal(buy)
        XCTAssertGreaterThanOrEqual(buy.frame.height, 44)
        buy.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["OK"].tap()
        XCTAssertTrue(stock.label.contains("4"))
        let give = app.buttons["shop.give.food"]
        reveal(give)
        XCTAssertGreaterThanOrEqual(give.frame.height, 44)
        give.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["OK"].tap()
        XCTAssertTrue(stock.label.contains("3"))
        chooseShopCategory("Accessories")
        XCTAssertTrue(app.buttons["accessories.shop.knitHat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["shop.buy.food"].exists)
        XCTAssertEqual(element("shop.balance").label, "108 coins")
        capture("Interface — accessories category")
        chooseShopCategory("Furniture")
        let box = app.buttons["furniture.buy.cozyBox"]
        reveal(box)
        XCTAssertTrue(box.isEnabled)
        XCTAssertFalse(app.buttons["accessories.shop.knitHat"].exists)
        capture("Interface — furniture category")
        chooseShopCategory("Care")
        XCTAssertEqual(element("shop.balance").label, "108 coins")
        reveal(stock)
        XCTAssertTrue(stock.label.contains("3"))
        XCTAssertTrue(app.buttons["shop.give.food"].label.contains("Пиксель"))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
    }

    func testInterfaceWardrobePurchaseWearAndRemoveRemainSeparate() throws {
        launch("-profile-route=wardrobe", "-profile-reduced-motion")
        XCTAssertTrue(app.navigationBars["Wardrobe"].waitForExistence(timeout: 10))
        let crown = app.buttons["wardrobe.select.tinyCrown"]
        reveal(crown); crown.tap()
        XCTAssertTrue(crown.isSelected)
        let buy = app.buttons["wardrobe.buy"]
        XCTAssertTrue(buy.isHittable)
        buy.tap()
        let apply = app.buttons["wardrobe.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertTrue(apply.isEnabled, "Buying does not silently change the pet's outfit")
        XCTAssertEqual(element("wardrobe.balance").label, "10 coins")
        capture("Interface — purchased crown, before wearing")
        apply.tap()
        let applied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: apply)
        XCTAssertEqual(XCTWaiter.wait(for: [applied], timeout: 5), .completed)
        XCTAssertEqual(crown.value as? String, "Wearing now")
        let none = app.buttons["wardrobe.select.none"]
        for _ in 0..<6 { if none.isHittable { break }; app.swipeDown() }
        none.tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: apply)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        XCTAssertEqual(none.value as? String, "Wearing now")
        XCTAssertEqual(element("wardrobe.balance").label, "10 coins")
        capture("Interface — accessory removed")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
    }

    func testInterfaceWardrobeExplainsDisabledActionsBesideButtonAtLargestText() {
        for away in [false, true] {
            launch("-profile-route=wardrobe", "-profile-largest", "-profile-light", "-profile-russian",
                   "-profile-long-name", away ? "-profile-away" : "-profile-no-coins", "-profile-reduced-motion")
            XCTAssertTrue(app.navigationBars["Гардероб"].waitForExistence(timeout: 10))
            let choice = app.buttons[away ? "wardrobe.select.none" : "wardrobe.select.tinyCrown"]
            reveal(choice); choice.tap()
            let reason = app.staticTexts["wardrobe.availability"]
            let action = app.buttons[away ? "wardrobe.apply" : "wardrobe.buy"]
            reveal(reason)
            XCTAssertTrue(reason.isHittable)
            reveal(action, fullyVisible: true)
            XCTAssertTrue(action.isHittable)
            XCTAssertFalse(action.isEnabled)
            XCTAssertLessThanOrEqual(reason.frame.maxY, action.frame.minY)
            XCTAssertLessThanOrEqual(action.frame.maxY, app.frame.maxY)
            capture(away ? "Interface — away explanation, largest Russian text" : "Interface — no coins, largest Russian text")
        }
    }

    func testInterfaceLongNameAndWalkRoutesRemainAccessibleAtLargestText() throws {
        launch("-profile-collection", "-profile-long-name", "-profile-largest", "-profile-light", "-profile-russian")
        let card = app.buttons["pet.profile.CD000000-0000-0000-0000-000000000002"]
        reveal(card)
        XCTAssertEqual(card.label, "Пиксель Пушистый Исследователь Острова")
        capture("Interface — collection, largest text")
        card.tap()
        XCTAssertTrue(app.navigationBars["Карточка питомца"].waitForExistence(timeout: 5))
        capture("Interface — long name in card")
        let walks = app.buttons["profile.walks"]
        reveal(walks); walks.tap()
        XCTAssertTrue(app.navigationBars["Прогулки"].waitForExistence(timeout: 5))
        for route in ["garden", "grove", "shore"] {
            let row = app.buttons["discoveries.route.\(route)"]
            reveal(row); row.tap()
            XCTAssertTrue(row.isSelected)
            XCTAssertFalse(row.label.isEmpty)
            XCTAssertFalse((row.value as? String ?? "").isEmpty)
        }
        capture("Interface — route choice, largest text")
        let start = app.buttons["discoveries.confirmStart"]
        reveal(start)
        XCTAssertTrue(start.isEnabled)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
    }

    func testInterfaceShopLargestTextKeepsCategoryAndPurchaseReachable() throws {
        launch("-profile-route=shop", "-profile-largest", "-profile-light", "-profile-long-name", "-profile-russian")
        XCTAssertTrue(app.navigationBars["Аркада питомцев"].waitForExistence(timeout: 10))
        let buy = app.buttons["shop.buy.food"]
        reveal(buy)
        XCTAssertTrue(buy.isEnabled)
        XCTAssertTrue(app.buttons["shop.category"].isHittable, "Only compact navigation stays pinned")
        capture("Interface — shop, largest text")
        chooseShopCategory("Аксессуары")
        let crown = app.buttons["accessories.shop.tinyCrown"]
        reveal(crown)
        XCTAssertEqual(crown.value as? String, "Монеты: 110")
        XCTAssertTrue(app.buttons["shop.category"].isHittable)
        capture("Interface — accessory row, largest text")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
        chooseShopCategory("Предметы для вольера")
        let furniture = app.buttons["furniture.buy.cozyBox"]
        reveal(furniture)
        XCTAssertTrue(furniture.isEnabled)
        XCTAssertTrue(app.buttons["shop.category"].isHittable)
        capture("Interface — furniture, largest text")
        try auditVisibleContent(pinnedHeader: app.buttons["shop.category"])
    }

    func testEnclosureMeetingFacesNeighbourPausesAndFinishes() {
        app.launchArguments = ["-habitat-encounter-preview", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["encounter.meet"].tap()
        let phase = app.staticTexts["encounter.phase"]
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        let greeted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'greeting'"), object: phase)
        XCTAssertEqual(XCTWaiter.wait(for: [greeted], timeout: 12), .completed)
        capture("Enclosure — greeting with original artwork")
        app.buttons["encounter.pause"].tap()
        let pausedPhase = phase.label
        let unchanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", pausedPhase), object: phase)
        unchanged.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [unchanged], timeout: 3), .completed)
        app.buttons["encounter.pause"].tap()
        let resting = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'resting'"), object: phase)
        XCTAssertEqual(XCTWaiter.wait(for: [resting], timeout: 8), .completed)
        capture("Enclosure — resting together")
        let free = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'free'"), object: phase)
        XCTAssertEqual(XCTWaiter.wait(for: [free], timeout: 12), .completed)
    }

    func testEnclosurePettingAndDepartureReleaseThePair() {
        app.launchArguments = ["-habitat-encounter-preview", "-encounter-light", "-AppleLanguages", "(ru)",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        app.buttons["encounter.meet"].tap()
        let phase = app.staticTexts["encounter.phase"]
        let greeted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'greeting'"), object: phase)
        XCTAssertEqual(XCTWaiter.wait(for: [greeted], timeout: 12), .completed)
        let neighbour = app.descendants(matching: .any).matching(identifier: "habitat.pet.EC000000-0000-0000-0000-000000000002").firstMatch
        XCTAssertEqual(neighbour.value as? String, "Здоровается")
        capture("Enclosure — light, large text, Russian accessibility")
        neighbour.tap()
        XCTAssertEqual(phase.label, "free")
        app.buttons["encounter.remove"].tap()
        XCTAssertFalse(neighbour.exists)
        XCTAssertFalse(app.buttons["encounter.meet"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "habitat.pet.EC000000-0000-0000-0000-000000000001").firstMatch.exists)
    }

    func testEnclosureReduceMotionDoesNotStartAMeeting() {
        app.launchArguments = ["-habitat-encounter-preview", "-encounter-reduced-motion"]
        app.launch()
        app.buttons["encounter.meet"].tap()
        XCTAssertEqual(app.staticTexts["encounter.phase"].label, "free")
        capture("Enclosure — reduced motion")
        let meeting = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != 'free'"), object: app.staticTexts["encounter.phase"])
        meeting.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [meeting], timeout: 3), .completed)
    }

    func testCollectionOpensCardAndCareUpdatesStock() {
        launch("-profile-collection")
        let tile = app.buttons["pet.profile.CD000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        capture("Pets — compact collection")
        let actions = app.buttons["pet.actions.CD000000-0000-0000-0000-000000000002"]
        actions.tap()
        let quickWardrobe = app.buttons["Wardrobe"]
        XCTAssertTrue(quickWardrobe.waitForExistence(timeout: 5))
        quickWardrobe.tap()
        XCTAssertTrue(app.navigationBars["Wardrobe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Пиксель"].exists)
        app.navigationBars["Wardrobe"].buttons["Done"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        XCTAssertTrue(app.navigationBars["Pet card"].waitForExistence(timeout: 5))
        capture("Card — dark")
        let give = app.buttons["profile.give.food"]
        reveal(give)
        XCTAssertEqual(app.staticTexts["profile.stock.food"].label, "In stock: 3")
        give.tap()
        let used = NSPredicate(format: "label == %@", "In stock: 2")
        expectation(for: used, evaluatedWith: app.staticTexts["profile.stock.food"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["profile.care.feedback"].exists)
        let wardrobe = app.buttons["profile.wardrobe"]
        reveal(wardrobe); wardrobe.tap()
        XCTAssertTrue(app.navigationBars["Wardrobe"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Пиксель"].exists)
        app.navigationBars["Wardrobe"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Pet card"].waitForExistence(timeout: 5))
        capture("Card — actions and memories")
        app.buttons["profile.edit"].tap()
        XCTAssertTrue(app.navigationBars["Pet"].waitForExistence(timeout: 5))
        app.navigationBars["Pet"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Pet card"].waitForExistence(timeout: 5))
    }

    func testShopAndWalkKeepTheCardCompanion() {
        launch()
        let shop = app.buttons["profile.shop"]
        XCTAssertTrue(app.navigationBars["Pet card"].waitForExistence(timeout: 10))
        reveal(shop); shop.tap()
        XCTAssertTrue(app.navigationBars["Pet Arcade"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Shop"].isSelected)
        XCTAssertTrue(app.buttons["Пиксель"].isSelected)
        app.buttons["shop.category"].tap()
        app.buttons["Accessories"].tap()
        XCTAssertTrue(app.buttons["accessories.shop.knitHat"].waitForExistence(timeout: 5))
        capture("Shop from card")
        app.navigationBars["Pet Arcade"].buttons["Close"].tap()
        let walks = app.buttons["profile.walks"]
        reveal(walks); walks.tap()
        XCTAssertTrue(app.navigationBars["Walks"].waitForExistence(timeout: 5))
        let companion = app.buttons["discoveries.companion"]
        XCTAssertTrue(companion.waitForExistence(timeout: 5))
        XCTAssertTrue(companion.label.contains("Пиксель") || String(describing: companion.value).contains("Пиксель"))
        let start = app.buttons["discoveries.confirmStart"]
        reveal(start); start.tap()
        XCTAssertTrue(app.buttons["End walk"].waitForExistence(timeout: 5))
        app.navigationBars["Walks"].buttons["Done"].tap()
        let give = app.buttons["profile.give.food"]
        // The card keeps its scroll position when a child sheet is dismissed.
        for _ in 0..<6 {
            if give.isHittable { break }
            app.swipeDown()
        }
        XCTAssertFalse(give.isEnabled)
        capture("Card — walking, care disabled")
    }

    func testReadyFindAndPersonalAlbum() {
        launch("-profile-ready")
        XCTAssertTrue(app.navigationBars["Pet card"].waitForExistence(timeout: 10))
        let walks = app.buttons["profile.walks"]
        reveal(walks)
        XCTAssertTrue(walks.label.contains("A find for you!"))
        walks.tap()
        let collect = app.buttons["discoveries.collect"]
        XCTAssertTrue(collect.waitForExistence(timeout: 5))
        reveal(collect); collect.tap()
        XCTAssertTrue(app.navigationBars["A new memory"].waitForExistence(timeout: 5))
        app.navigationBars["A new memory"].buttons["Done"].tap()
        app.navigationBars["Walks"].buttons["Done"].tap()
        let album = app.buttons["profile.album"]
        reveal(album); album.tap()
        XCTAssertTrue(app.navigationBars["Finds album"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 of 12 treasures"].exists)
        capture("Personal finds album")
    }

    func testLargeTextAndEmptySuppliesRemainReachable() {
        launch("-profile-empty", "-profile-light", "-profile-large", "-profile-collection")
        let tile = app.buttons["pet.profile.CD000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(app.buttons["pet.profile.CD000000-0000-0000-0000-000000000001"].waitForExistence(timeout: 10))
        capture("Pets — light, large text")
        reveal(tile)
        tile.tap()
        XCTAssertTrue(app.navigationBars["Pet card"].waitForExistence(timeout: 10))
        capture("Card — light, large text")
        let give = app.buttons["profile.give.food"]
        reveal(give)
        XCTAssertFalse(give.isEnabled)
        XCTAssertEqual(app.staticTexts["profile.stock.food"].label, "In stock: 0")
        capture("Card — accessible care")
        let wardrobe = app.buttons["profile.wardrobe"]
        reveal(wardrobe)
        XCTAssertTrue(wardrobe.isEnabled)
        let empty = app.staticTexts["Your first shared memory is still ahead. Bring back a find from a walk."]
        reveal(empty)
        capture("Card — empty memories")
    }

    func testPersonalStoriesAlbumKeepsEachVersionAndReopensTheSameStory() {
        launch("-profile-stories", "-profile-route=album")
        XCTAssertTrue(app.navigationBars["Finds album"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["4 of 12 treasures"].exists)
        app.segmentedControls.buttons["Stories"].tap()
        XCTAssertTrue(app.staticTexts["8 of 36 stories"].waitForExistence(timeout: 5))
        let memories = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discoveries.memory."))
        let memory = memories.firstMatch
        reveal(memory)
        XCTAssertTrue(memory.label.contains("Пиксель"))
        XCTAssertFalse(memories.matching(NSPredicate(format: "label CONTAINS %@", "Корги")).firstMatch.exists)
        let identifier = memory.identifier
        capture("Walks — personal stories album")
        memory.tap()
        XCTAssertTrue(app.navigationBars["Walk memory"].waitForExistence(timeout: 5))
        let story = app.staticTexts["discoveries.story.text"]
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        let originalText = story.label
        XCTAssertTrue(originalText.contains("Пиксель"))
        XCTAssertTrue(app.staticTexts["A curious detour"].exists)
        capture("Walks — saved story")
        let journal = app.buttons["Along the way"]
        reveal(journal); journal.tap()
        let first = app.descendants(matching: .any).matching(identifier: "discoveries.chapter.0").firstMatch
        reveal(first)
        XCTAssertTrue(first.label.contains("First steps"))
        let last = app.descendants(matching: .any).matching(identifier: "discoveries.chapter.2").firstMatch
        reveal(last)
        capture("Walks — complete journal")
        app.navigationBars["Walk memory"].buttons["Done"].tap()
        app.buttons[identifier].tap()
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        XCTAssertEqual(story.label, originalText)
    }

    func testRussianStoryCountIsLocalized() {
        launch("-profile-stories", "-profile-route=album", "-profile-russian")
        XCTAssertTrue(app.navigationBars["Альбом находок"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["Истории"].tap()
        capture("Walk polish — Russian story count")
        XCTAssertTrue(app.staticTexts["8 из 36 историй"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["8 of 36 stories"].exists)
    }

    func testWalkStartSaveFailureCanBeRetriedInPlace() {
        launch("-profile-route=walks", "-profile-fail-walk-save")
        let start = app.buttons["discoveries.confirmStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        let companion = app.buttons["discoveries.companion"]
        companion.tap()
        XCTAssertTrue(app.buttons["Корги"].waitForExistence(timeout: 5))
        app.buttons["Корги"].tap()
        XCTAssertEqual(companion.value as? String, "Корги")
        companion.tap()
        app.buttons["Пиксель"].tap()
        XCTAssertEqual(companion.value as? String, "Пиксель")
        reveal(start); start.tap()
        let error = app.alerts["Could not save"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        capture("Walk polish — start save error")
        error.buttons["OK"].tap()
        XCTAssertTrue(start.isEnabled)
        start.tap()
        XCTAssertTrue(app.buttons["End walk"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testFindCollectionSaveFailureKeepsFindAvailable() {
        launch("-profile-ready", "-profile-route=walks", "-profile-fail-walk-save")
        let collect = app.buttons["discoveries.collect"]
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        reveal(collect); collect.tap()
        let error = app.alerts["Could not save"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        error.buttons["OK"].tap()
        XCTAssertTrue(collect.isEnabled)
        collect.tap()
        XCTAssertTrue(app.navigationBars["A new memory"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["discoveries.story.text"].label.contains("Пиксель"))
        app.navigationBars["A new memory"].buttons["Done"].tap()
        XCTAssertFalse(collect.exists)
        let album = app.buttons["discoveries.album"]
        reveal(album); album.tap()
        XCTAssertTrue(app.staticTexts["2 of 12 treasures"].waitForExistence(timeout: 5))
    }

    func testCancellationSaveFailureKeepsWalkAndCanRetry() {
        launch("-profile-away", "-profile-route=walks", "-profile-fail-walk-save")
        let end = app.buttons["End walk"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        reveal(end); end.tap()
        app.buttons.matching(identifier: "End walk").allElementsBoundByIndex.last!.tap()
        let error = app.alerts["Could not save"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        error.buttons["OK"].tap()
        XCTAssertTrue(end.isEnabled)
        end.tap()
        app.buttons.matching(identifier: "End walk").allElementsBoundByIndex.last!.tap()
        XCTAssertTrue(app.buttons["discoveries.confirmStart"].waitForExistence(timeout: 5))
        let album = app.buttons["discoveries.album"]
        reveal(album); album.tap()
        XCTAssertTrue(app.staticTexts["1 of 12 treasures"].waitForExistence(timeout: 5))
    }

    func testWalkReturnsAfterBackgroundWithReducedMotion() {
        launch("-profile-returning", "-profile-route=walks", "-profile-reduced-motion")
        XCTAssertTrue(app.navigationBars["Walks"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["discoveries.collect"].exists)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 16)
        app.activate()
        let collect = app.buttons["discoveries.collect"]
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        let scene = app.descendants(matching: .any).matching(identifier: "discoveries.scene").firstMatch
        XCTAssertEqual(scene.value as? String, "The walk is over. Your pet is home.")
        capture("Walk polish — returned after background")
        reveal(collect); collect.tap()
        XCTAssertTrue(app.navigationBars["A new memory"].waitForExistence(timeout: 5))
    }

    func testEmptyWalkAlbumAndLongNameRemainReachableWithLargeText() {
        launch("-profile-empty", "-profile-long-name", "-profile-large", "-profile-light", "-profile-route=walks")
        XCTAssertTrue(app.navigationBars["Walks"].waitForExistence(timeout: 10))
        let companion = app.buttons["discoveries.companion"]
        XCTAssertTrue(companion.label.contains("Пиксель Пушистый Исследователь Острова")
                      || String(describing: companion.value).contains("Пиксель Пушистый Исследователь Острова"))
        XCTAssertGreaterThanOrEqual(companion.frame.minY, app.staticTexts["Who's going?"].frame.maxY)
        XCTAssertGreaterThanOrEqual(app.staticTexts["discoveries.routes.title"].frame.minY, companion.frame.maxY)
        capture("Walk polish — large name and routes")
        let start = app.buttons["discoveries.confirmStart"]
        reveal(start)
        XCTAssertTrue(start.isEnabled)
        let album = app.buttons["discoveries.album"]
        reveal(album); album.tap()
        XCTAssertTrue(app.staticTexts["0 of 12 treasures"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Stories"].tap()
        let empty = app.staticTexts["Your first walk story is still ahead."]
        reveal(empty)
        XCTAssertTrue(app.staticTexts["0 of 36 stories"].exists)
        capture("Walk polish — empty stories, large text")
    }

    func testActiveWalkShowsOnlyTheCurrentJournalChapter() {
        launch("-profile-away", "-profile-route=walks")
        XCTAssertTrue(app.navigationBars["Walks"].waitForExistence(timeout: 10))
        capture("Walks — active shore")
        let chapter = app.descendants(matching: .any).matching(identifier: "discoveries.chapter.0").firstMatch
        reveal(chapter)
        XCTAssertTrue(chapter.label.contains("First steps"))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "discoveries.chapter.1").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "discoveries.chapter.2").firstMatch.exists)
        XCTAssertFalse(app.buttons["discoveries.collect"].exists)
        XCTAssertTrue(app.buttons["End walk"].exists)
        capture("Walks — first note, no find spoiler")
        app.buttons["End walk"].tap()
        // The system confirmation can be a popover without a Cancel button.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2)).tap()
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "End walk").count, 1)
    }

    func testRussianWalkStoryAndJournalRemainReachableWithLargeText() {
        launch("-profile-ready", "-profile-stories", "-profile-route=walks", "-profile-russian", "-profile-light", "-profile-large")
        let collect = app.buttons["discoveries.collect"]
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        reveal(collect); collect.tap()
        let story = app.staticTexts["discoveries.story.text"]
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        reveal(story)
        XCTAssertTrue(story.label.contains("Пиксель"))
        capture("Walks — Russian story, large text")
        let journal = app.buttons["По дороге"]
        reveal(journal); journal.tap()
        let first = app.descendants(matching: .any).matching(identifier: "discoveries.chapter.0").firstMatch
        reveal(first)
        XCTAssertTrue(first.label.contains("Первые шаги"))
        capture("Walks — Russian journal, large text")
        let last = app.descendants(matching: .any).matching(identifier: "discoveries.chapter.2").firstMatch
        reveal(last)
        XCTAssertTrue(last.label.contains("Сюрприз для дома"))
        let share = app.buttons["Поделиться воспоминанием"]
        reveal(share)
        XCTAssertTrue(share.isEnabled)
    }

    func testNewWalkPostcardSharesAnImageAndKeepsTheMemory() {
        launch("-profile-ready", "-profile-route=walks")
        let collect = app.buttons["discoveries.collect"]
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        reveal(collect); collect.tap()
        let story = app.staticTexts["discoveries.story.text"]
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        let originalText = story.label
        let postcard = app.buttons["discoveries.postcard"]
        reveal(postcard); postcard.tap()
        let image = app.images["postcard.image"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        XCTAssertTrue(image.label.contains("Пиксель"))
        XCTAssertTrue((image.value as? String ?? "").contains(originalText))
        capture("Postcard — shore preview")
        let share = app.buttons["postcard.share"]
        reveal(share); share.tap()
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10), app.debugDescription)
        capture("Postcard — system image sharing")
        // Copy is a local share action and exercises PNG transfer without sending anything.
        copy.tap()
        XCTAssertTrue(app.navigationBars["Walk postcard"].waitForExistence(timeout: 5))
        app.navigationBars["Walk postcard"].buttons["Done"].tap()
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        XCTAssertEqual(story.label, originalText)
        app.navigationBars["A new memory"].buttons["Done"].tap()
        let album = app.buttons["discoveries.album"]
        reveal(album); album.tap()
        XCTAssertTrue(app.staticTexts["2 of 12 treasures"].waitForExistence(timeout: 5))
    }

    func testSavedWalkPostcardExportsPNGToFiles() {
        launch("-profile-stories", "-profile-route=album")
        XCTAssertTrue(app.navigationBars["Finds album"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["Stories"].tap()
        let memory = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "discoveries.memory.")).firstMatch
        reveal(memory); memory.tap()
        let postcard = app.buttons["discoveries.postcard"]
        reveal(postcard); postcard.tap()
        let export = app.buttons["postcard.save"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        reveal(export); export.tap()
        // Match the system picker action without depending on its private
        // navigation-controller name or where iOS places the button.
        let save = app.buttons
            .matching(NSPredicate(format: "identifier == %@ OR label IN %@", "DOCPicker.actionButton", ["Save", "Сохранить"])).firstMatch
        let pickerOpened = save.waitForExistence(timeout: 10)
        if !pickerOpened { capture("Postcard — document picker diagnostic"); print(app.debugDescription) }
        XCTAssertTrue(pickerOpened)
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Отменить"])).firstMatch
        if cancel.exists { cancel.tap() }
        else { app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].swipeDown() }
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["postcard.saved"].exists)
        export.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 5))
        XCTAssertTrue((filename.value as? String ?? "").contains("Pet-Island-Postcard-"))
        filename.tap(); filename.typeText("Postcard-" + UUID().uuidString.prefix(8) + "\n")
        capture("Postcard — PNG in Files")
        save.tap()
        let feedback = app.staticTexts["postcard.saved"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        reveal(feedback)
        XCTAssertEqual(feedback.label, "Postcard saved.")
        app.navigationBars["Walk postcard"].buttons["Done"].tap()
        app.navigationBars["Walk memory"].buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["8 of 36 stories"].waitForExistence(timeout: 5))
    }

    func testRussianPostcardKeepsLongNameAndActionsReachableWithLargeText() {
        launch("-profile-ready", "-profile-route=walks", "-profile-russian", "-profile-long-name", "-profile-large", "-profile-light")
        let collect = app.buttons["discoveries.collect"]
        XCTAssertTrue(collect.waitForExistence(timeout: 10))
        reveal(collect); collect.tap()
        let postcard = app.buttons["discoveries.postcard"]
        reveal(postcard)
        XCTAssertEqual(postcard.label, "Сделать открытку")
        postcard.tap()
        let image = app.images["postcard.image"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        XCTAssertTrue(image.label.contains("Пиксель Пушистый Исследователь Острова"))
        capture("Postcard — Russian, long name")
        let share = app.buttons["postcard.share"]
        reveal(share)
        XCTAssertEqual(share.label, "Поделиться открыткой")
        let save = app.buttons["postcard.save"]
        reveal(save)
        XCTAssertTrue(save.isEnabled)
        capture("Postcard — Russian, accessible actions")
        app.navigationBars["Открытка с прогулки"].buttons["Готово"].tap()
        XCTAssertTrue(app.buttons["discoveries.postcard"].waitForExistence(timeout: 5))
    }

    func testQuietMomentIsFreeAndOnlyAppliesToTheOpenedPet() {
        launch("-profile-collection")
        let pet = app.buttons["pet.profile.CD000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(pet.waitForExistence(timeout: 10))
        pet.tap()
        let attention = app.buttons["profile.bond.attention"]
        reveal(attention)
        XCTAssertTrue(attention.isEnabled)
        attention.tap()
        XCTAssertTrue(app.staticTexts["profile.bond.feedback"].waitForExistence(timeout: 5))
        XCTAssertFalse(attention.isEnabled)
        capture("Friendship — first moment")
        reveal(app.staticTexts["profile.stock.food"])
        XCTAssertEqual(app.staticTexts["profile.stock.food"].label, "In stock: 3")
        app.navigationBars["Pet card"].buttons["Done"].tap()
        app.buttons["pet.profile.CD000000-0000-0000-0000-000000000001"].tap()
        reveal(attention)
        XCTAssertTrue(attention.isEnabled)
        app.navigationBars["Pet card"].buttons["Done"].tap()
        pet.tap()
        reveal(attention)
        XCTAssertFalse(attention.isEnabled)
    }

    func testFriendshipHabitsRemainReadableWithLargeTextAndAwayPet() {
        launch("-profile-bond", "-profile-away", "-profile-light", "-profile-large")
        XCTAssertTrue(app.navigationBars["Pet card"].waitForExistence(timeout: 10))
        let attention = app.buttons["profile.bond.attention"]
        reveal(attention)
        XCTAssertFalse(attention.isEnabled)
        XCTAssertEqual(app.staticTexts["profile.bond.stage"].label, "Trusted friend")
        let habits = app.buttons["profile.bond.habits"]
        reveal(habits); habits.tap()
        let game = app.staticTexts["Bubble Paws"]
        reveal(game)
        capture("Friendship — habits, large text")
        let explanation = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Attention, useful care")).firstMatch
        reveal(explanation)
        capture("Friendship — no missed-day penalty")
    }

    func testRussianFriendshipShowsLocalizedActionAndFeedback() {
        launch("-profile-russian")
        let attention = app.buttons["profile.bond.attention"]
        XCTAssertTrue(attention.waitForExistence(timeout: 10))
        reveal(attention)
        XCTAssertTrue(attention.label.contains("Побыть рядом"))
        XCTAssertEqual(app.staticTexts["profile.bond.stage"].label, "Знакомитесь")
        attention.tap()
        XCTAssertTrue(app.staticTexts["profile.bond.feedback"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["profile.bond.feedback"].label, "Пиксель радуется, что ты рядом.")
        XCTAssertTrue(attention.label.contains("Вы побыли рядом"))
        capture("Friendship — Russian")
    }

    func testBackupPreviewCancellationKeepsCurrentPetWithLargeText() {
        launch("-profile-backup", "-profile-light", "-profile-large")
        let backups = app.buttons["settings.backup"]
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        reveal(backups); backups.tap()
        XCTAssertTrue(app.navigationBars["Island backup"].waitForExistence(timeout: 5))
        let previous = app.buttons["backup.recovery"]
        reveal(previous); previous.tap()
        XCTAssertTrue(app.navigationBars["Backup contents"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Луна"].exists)
        XCTAssertTrue(app.buttons["backup.restore"].isHittable)
        capture("Backup preview — large text")
        app.navigationBars["Backup contents"].buttons["Cancel"].tap()
        app.navigationBars["Island backup"].buttons["Done"].tap()
        app.tabBars.buttons["Pets"].tap()
        let pet = app.buttons["pet.profile.CD000000-0000-0000-0000-000000000002"]
        reveal(pet)
        XCTAssertTrue(pet.label.contains("Пиксель"))
    }

    func testBackupRestoresSelectedCopyAndOffersReturnToPreviousIsland() {
        launch("-profile-backup")
        let backups = app.buttons["settings.backup"]
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        reveal(backups); backups.tap()
        XCTAssertTrue(app.navigationBars["Island backup"].waitForExistence(timeout: 5))
        capture("Backup — dark")
        let previous = app.buttons["backup.recovery"]
        reveal(previous); previous.tap()
        XCTAssertTrue(app.navigationBars["Backup contents"].waitForExistence(timeout: 5))
        capture("Backup — contents")
        app.buttons["backup.restore"].tap()
        XCTAssertTrue(app.staticTexts["Replace your current island?"].waitForExistence(timeout: 5))
        // The background button has the same label. Its ordering relative to
        // the confirmation differs between iOS releases and screen sizes.
        let confirm = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "Restore this island", "backup.restore"
        )).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isHittable)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Your island has been restored."].waitForExistence(timeout: 10))
        reveal(previous); previous.tap()
        XCTAssertTrue(app.navigationBars["Backup contents"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Пиксель"].exists)
        app.navigationBars["Backup contents"].buttons["Cancel"].tap()
        app.navigationBars["Island backup"].buttons["Done"].tap()
        app.tabBars.buttons["Pets"].tap()
        XCTAssertTrue(app.buttons["pet.profile.CD000000-0000-0000-0000-000000000002"].label.contains("Луна"))
    }

    func testBackupFileExportAndImportKeepIslandUntilConfirmation() {
        launch("-profile-backup")
        let backups = app.buttons["settings.backup"]
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        reveal(backups); backups.tap()
        XCTAssertTrue(app.navigationBars["Island backup"].waitForExistence(timeout: 5))
        app.buttons["backup.export"].tap()
        // Files on iOS 26 does not expose the iOS 27 Save identifier.
        let save = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].buttons
            .matching(NSPredicate(format: "identifier == %@ OR label IN %@", "DOCPicker.actionButton", ["Save", "Сохранить"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        // Files persists between test launches; never overwrite or import a previous run's copy.
        let uniqueName = "Backup-" + UUID().uuidString.prefix(8)
        let filename = app.textFields["DOCPicker.filenameTextField"]
        // On a fresh iOS Files provider the first export may offer only its
        // default filename. Cancellation is valid in either presentation.
        capture("Backup — initial Files export")
        // Cancelling an export must not show an error or leave the next export
        // with an empty document. The island stays unchanged throughout.
        let cancel = app.buttons["Cancel"]
        if cancel.exists { cancel.tap() }
        else { app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].swipeDown() }
        XCTAssertTrue(app.buttons["backup.export"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["backup.export"].tap()
        XCTAssertTrue(filename.waitForExistence(timeout: 10), app.debugDescription)
        filename.tap()
        filename.typeText(uniqueName + "\n")
        capture("Backup — Files export")
        save.tap()
        XCTAssertTrue(app.staticTexts["Backup saved."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["backup.import"].waitForExistence(timeout: 5))
        app.buttons["backup.import"].tap()
        let file = app.collectionViews.cells.matching(NSPredicate(format: "label CONTAINS %@", uniqueName)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
        capture("Backup — Files import")
        file.tap()
        XCTAssertTrue(app.navigationBars["Backup contents"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Пиксель"].exists)
        app.navigationBars["Backup contents"].buttons["Cancel"].tap()
        app.navigationBars["Island backup"].buttons["Done"].tap()
        app.tabBars.buttons["Pets"].tap()
        XCTAssertTrue(app.buttons["pet.profile.CD000000-0000-0000-0000-000000000002"].label.contains("Пиксель"))
    }
}
