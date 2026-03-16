//
//  dBMeterUITestsLaunchTests.swift
//  dBMeterUITests
//
//  Created by Sam Glover on 3/13/26.
//

import XCTest
import ApplicationServices
import AppIntents

final class dBMeterUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false

        guard AXIsProcessTrusted() else {
            throw XCTSkip("UI tests require Accessibility permission for UI automation.")
        }
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
