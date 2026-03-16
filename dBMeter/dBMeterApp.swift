//
//  dBMeterApp.swift
//  dBMeter
//
//  Created by Sam Glover on 3/13/26.
//

import AppIntents
import SwiftUI

@main
struct dBMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
