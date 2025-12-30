//
//  WRhythm_Watch_AppUITests.swift
//  WRhythm Watch AppUITests
//
//  Created by Justin Restivo on 12/23/25.
//

import XCTest

final class WRhythm_Watch_AppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testAppLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.state == .runningForeground)
    }

    @MainActor
    func testNavigationExists() throws {
        let app = XCUIApplication()
        app.launch()

        sleep(2)

        let tablesQuery = app.tables
        XCTAssertTrue(tablesQuery.count > 0 || app.buttons.count > 0)
    }

    @MainActor
    func testSettingsNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        sleep(2)

        if app.buttons["Settings"].exists {
            app.buttons["Settings"].tap()
            sleep(1)
            XCTAssertTrue(app.navigationBars["Settings"].exists || app.staticTexts["Settings"].exists)
        }
    }

    @MainActor
    func testDownloadsViewExists() throws {
        let app = XCUIApplication()
        app.launch()

        sleep(2)

        if app.buttons["Downloads"].exists {
            app.buttons["Downloads"].tap()
            sleep(1)
            XCTAssertTrue(app.navigationBars["Downloads"].exists || app.staticTexts["Downloads"].exists)
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
