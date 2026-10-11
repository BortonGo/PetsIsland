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
        let russian = arguments.contains("-profile-russian")
        app.launchArguments = ["-pet-profile-preview", "-AppleLanguages", russian ? "(ru)" : "(en)", "-AppleLocale", russian ? "ru_RU" : "en_US"] + arguments
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
        let save = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].buttons
            .matching(NSPredicate(format: "identifier == %@ OR label IN %@", "DOCPicker.actionButton", ["Save", "Сохранить"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
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
