//
//  ContentView.swift
//  Autostream
//
//  Created by Michael Bino on 4/20/25.
//

import SwiftUI
import AVKit

struct FullscreenPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

struct ContentView: View {
    private enum SheetDestination: Identifiable {
        case settings
        case presets

        var id: Int {
            switch self {
            case .settings: return 0
            case .presets: return 1
            }
        }
    }

    static let playOnOpenKey = "playOnAppOpen"
    static let retryTimeoutKey = "retryTimeout"
    static let lastStreamURLKey = "lastStreamURL"
    static let autoResumeKey = "autoResume"
    static let settingsDisabledKey = "settingsDisabled"
    static let channelPresetsKey = "channelPresets"
    static let defaultChannelKey = "defaultChannel"
    static let channelPresetsManagedKey = "channelPresetsManaged"
    static let selectedPresetIndexKey = "selectedPresetIndex"

    @StateObject private var viewModel = StreamViewModel()
    @State private var activeSheet: SheetDestination?
    @State private var showPlayer = false
    @State private var presentationAttempts = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Selected Stream")
                            .font(.headline)

                        TextField(
                            "Enter HLS Stream URL",
                            text: Binding(
                                get: { viewModel.streamURL },
                                set: { newValue in
                                    viewModel.updateStreamURL(newValue)
                                }
                            )
                        )
                        .padding(.vertical, 8)

                        Button {
                            if let _ = URL(string: viewModel.streamURL) {
                                viewModel.playStream()
                                showPlayer = true
                            }
                        } label: {
                            Text("Play Stream")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.streamURL.isEmpty)

                        Text("Enter a URL to play an HLS stream.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if !viewModel.channelPresets.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Stream Presets")
                                .font(.headline)

                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(viewModel.channelPresets.enumerated()), id: \.offset) { index, preset in
                                    Button {
                                        viewModel.selectPreset(at: index)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Preset \(index + 1)")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                                Text(preset.isEmpty ? "(empty)" : viewModel.displayName(for: preset))
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
                                            if viewModel.selectedPresetIndex == index {
                                                Spacer()
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }

                            if viewModel.channelPresetsManaged {
                                Text("Stream presets are managed by your administrator.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        Button {
                            activeSheet = .presets
                        } label: {
                            Text("Manage Stream Presets")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.channelPresetsManaged)

                        Button {
                            activeSheet = .settings
                        } label: {
                            Text("Settings")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.settingsDisabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.vertical, 36)
            }
            .navigationTitle("Autostream")
            .sheet(item: $activeSheet) { destination in
                switch destination {
                case .settings:
                    SettingsView(
                        isPlayingOnOpen: $viewModel.isPlayingOnOpen,
                        retryTimeout: $viewModel.retryTimeout,
                        autoResume: $viewModel.autoResume,
                        settingsDisabled: $viewModel.settingsDisabled,
                        onRetryTimeoutChanged: {
                            viewModel.updateSettings(
                                isPlayingOnOpen: viewModel.isPlayingOnOpen,
                                retryTimeout: viewModel.retryTimeout,
                                autoResume: viewModel.autoResume,
                                settingsDisabled: viewModel.settingsDisabled
                            )
                        }
                    )
                case .presets:
                    ChannelPresetsView(viewModel: viewModel)
                }
            }
            .onAppear {
                viewModel.startStreamIfNeeded()
                scheduleAutoPlayPresentation()
            }
            .onDisappear {
                viewModel.stopRetryTimer()
            }
            .onChangeOld(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    viewModel.startStreamIfNeeded()
                    scheduleAutoPlayPresentation()
                case .background:
                    viewModel.stopRetryTimer()
                default:
                    break
                }
            }
            .fullScreenCover(isPresented: $showPlayer) {
                if let player = viewModel.player {
                    FullscreenPlayerView(player: player)
                        .edgesIgnoringSafeArea(.all)
                        .onAppear {
                            player.play()
                        }
                }
            }
        }
    }
}

// MARK: - Auto-play fullscreen presentation (Issue #3)

private extension ContentView {
    static let maxPresentationAttempts = 3
    static let presentationRetryDelay: TimeInterval = 1.0

    @MainActor
    func scheduleAutoPlayPresentation() {
        guard viewModel.isPlayingOnOpen, !viewModel.streamURL.isEmpty else { return }
        presentationAttempts = 0
        attemptPresentation()
    }

    @MainActor
    func attemptPresentation() {
        guard viewModel.isPlayingOnOpen, !showPlayer else { return }
        guard presentationAttempts < Self.maxPresentationAttempts else {
            viewModel.logger.log("Auto-play presentation failed after \(Self.maxPresentationAttempts) attempts")
            return
        }

        presentationAttempts += 1

        // Ensure player is ready
        if viewModel.player == nil || viewModel.player?.currentItem == nil {
            viewModel.playStream()
        }

        if viewModel.player != nil, viewModel.player?.currentItem != nil {
            showPlayer = true
        } else {
            // Retry after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.presentationRetryDelay) {
                self.attemptPresentation()
            }
        }
    }
}
