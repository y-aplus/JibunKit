//
//  ZapApp.swift
//  Zap
//
//  Created by Zigao Wang on 9/18/24.
//

import SwiftUI

public struct ZapRootView: View {
    // Initialize the AppearanceManager at the app level
    @StateObject private var appearanceManager = AppearanceManager()

    public init() {}

    public var body: some View {
        Group {
            ContentView()
                .environmentObject(appearanceManager)
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowToolbarStyle(.unified)
        #endif
    }
}
