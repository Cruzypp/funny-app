//
//  ContentView.swift
//  App
//
//  Caminos — safe-routing app for CDMX
//  Root view: owns the AppRouter and dispatches to all 7 screens.
//

import SwiftUI

struct ContentView: View {
    @State private var router = AppRouter()

    var body: some View {
        ZStack {
            T.bg(router.night).ignoresSafeArea()

            Group {
                switch router.screen {
                case .home:
                    ScreenHome()

                case .results(let dest):
                    ScreenResults(dest: dest)

                case .detail(let routeId):
                    ScreenDetail(routeId: routeId)

                case .nav:
                    ScreenNav()

                case .survey:
                    ScreenSurvey()

                case .impact:
                    ScreenImpact()

                case .heatmap:
                    ScreenHeatmap()
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.26), value: router.screen)
        }
        .environment(router)
        .navigationBarHidden(true)
        // Vocab switcher — long-press anywhere outside interactive areas to cycle
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(SafetyVocab.allCases, id: \.rawValue) { v in
                        Button(v.label) { router.vocab = v }
                    }
                    Divider()
                    Button(router.night ? "Modo día" : "Modo noche") {
                        withAnimation { router.night.toggle() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(T.pri(router.night))
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
