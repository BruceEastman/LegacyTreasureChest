//
//  DeveloperSettingsView.swift
//  LegacyTreasureChest
//
//  Simple in-app toggles for FeatureFlags (DEBUG only).
//

import SwiftUI

#if DEBUG
struct DeveloperSettingsView: View {

    @State private var flags = FeatureFlags()

    var body: some View {
        Form {
            Section("AI / Market") {
                Toggle("Enable Market AI (Backend)", isOn: Binding(
                    get: { flags.enableMarketAI },
                    set: { flags.enableMarketAI = $0; flags = FeatureFlags() }
                ))

                Toggle("Show Debug Logs", isOn: Binding(
                    get: { flags.showDebugInfo },
                    set: { flags.showDebugInfo = $0; flags = FeatureFlags() }
                ))
            }

            Section("Future") {
                Toggle("Enable CloudKit", isOn: Binding(
                    get: { flags.enableCloudKit },
                    set: { flags.enableCloudKit = $0; flags = FeatureFlags() }
                ))

                Toggle("Enable Households (Multi-user)", isOn: Binding(
                    get: { flags.enableHouseholds },
                    set: { flags.enableHouseholds = $0; flags = FeatureFlags() }
                ))
                .disabled(true) // keep disabled for single-user system
            }

            Section {
                Text("These settings are stored in UserDefaults and do not affect your saved items.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Developer Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
