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

    private func launch(_ arguments: String...) {
        app.launchArguments = ["-pet-profile-preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        if arguments.contains("-profile-large") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        }
        app.launch()
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Unreachable control: \(element)")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        let confirm = app.buttons.matching(identifier: "Restore this island").allElementsBoundByIndex.last
        XCTAssertNotNil(confirm)
        confirm?.tap()
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
        let save = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        // Files persists between test launches; never overwrite or import a previous run's copy.
        let uniqueName = "Backup-" + UUID().uuidString.prefix(8)
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 5))
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
