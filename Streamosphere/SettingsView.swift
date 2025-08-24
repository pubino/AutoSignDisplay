//
//  SettingsView.swift
//  Streamosphere
//
//  Created by Michael Bino on 4/20/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPlayingOnOpen: Bool
    @Binding var retryTimeout: Double
    @Binding var autoResume: Bool
    var onRetryTimeoutChanged: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Toggle("Play on App Open", isOn: $isPlayingOnOpen)
                    .onChange(of: isPlayingOnOpen) { newValue in
                        UserDefaults.standard.set(newValue, forKey: ContentView.playOnOpenKey)
                        onRetryTimeoutChanged()
                    }

                Toggle("Auto Resume on Network Interrupt", isOn: $autoResume)
                    .onChange(of: autoResume) { newValue in
                        UserDefaults.standard.set(newValue, forKey: ContentView.autoResumeKey)
                        onRetryTimeoutChanged()
                    }

                HStack {
                    Text("Retry Timeout (seconds):")
                    TextField("Timeout", value: $retryTimeout, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                        .onChange(of: retryTimeout) { newValue in
                            UserDefaults.standard.set(newValue, forKey: ContentView.retryTimeoutKey)
                            onRetryTimeoutChanged()
                        }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
