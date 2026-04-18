//
//  AppApp.swift
//  App
//
//  Created by Cruz Yael Pérez González on 17/04/26.
//

import SwiftUI

#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct AppApp: App {
    init() {
        #if canImport(FirebaseCore)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
        }
    }
}
