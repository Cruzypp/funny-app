//
//  AppApp.swift
//  App
//
//  Created by Cruz Yael Pérez González on 17/04/26.


import SwiftUI
import FirebaseCore

@main
struct AppApp: App {

    init() {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
        }
    }
}
