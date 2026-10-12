//
//  SettingsView.swift
//  Zap
//
//  Created by Zigao Wang on 9/27/24.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink(destination: AppearanceSettingsView()) {
                        SettingsRowView(
                            title: NSLocalizedString("Appearance", bundle: .module, comment: "Settings appearance section"),
                            icon: "paintbrush.fill",
                            iconColor: .purple,
                            description: NSLocalizedString("Customize theme, colors and text size", bundle: .module, comment: "Settings appearance description")
                        )
                    }
                    
                    NavigationLink(destination: AboutHelpView()) {
                        SettingsRowView(
                            title: NSLocalizedString("About & Help", bundle: .module, comment: "Settings about section"),
                            icon: "info.circle.fill",
                            iconColor: .blue,
                            description: NSLocalizedString("App information and support", bundle: .module, comment: "Settings about description")
                        )
                    }
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
            .navigationTitle(NSLocalizedString("Settings", bundle: .module, comment: "Settings screen title"))
            .listStyle(InsetGroupedListStyle())
        }
    }
}

struct SettingsRowView: View {
    let title: String
    let icon: String
    let iconColor: Color
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
