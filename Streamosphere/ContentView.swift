//
//  ContentView.swift
//  Streamosphere
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
    static let playOnOpenKey = "playOnAppOpen"
    static let retryTimeoutKey = "retryTimeout"
    static let lastStreamURLKey = "lastStreamURL"
    static let autoResumeKey = "autoResume"

    @StateObject private var viewModel = StreamViewModel()
    @State private var showingSettings = false
    @State private var showPlayer = false

    var body: some View {
        NavigationView {
            VStack {
                TextField("Enter HLS Stream URL", text: $viewModel.streamURL)
                    .padding()
                    .onChange(of: viewModel.streamURL) { newValue in
                        viewModel.updateStreamURL(newValue)
                    }

                Text("Enter a URL to play an HLS stream.")
                    .padding()

                Button("Play Stream") {
                    if let url = URL(string: viewModel.streamURL) {
                        viewModel.player = AVPlayer(url: url)
                        showPlayer = true
                    }
                }
                .padding()
                .disabled(viewModel.streamURL.isEmpty)

                Spacer()

                Button("Settings") {
                    showingSettings = true
                }
                .padding()
            }
            .navigationTitle("Streamosphere")
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    isPlayingOnOpen: $viewModel.isPlayingOnOpen,
                    retryTimeout: $viewModel.retryTimeout,
                    autoResume: $viewModel.autoResume,
                    onRetryTimeoutChanged: {
                        viewModel.updateSettings(
                            isPlayingOnOpen: viewModel.isPlayingOnOpen,
                            retryTimeout: viewModel.retryTimeout,
                            autoResume: viewModel.autoResume
                        )
                    }
                )
            }
            .onAppear {
                viewModel.startStreamIfNeeded()
                if viewModel.isPlayingOnOpen, let url = URL(string: viewModel.streamURL) {
                    viewModel.player = AVPlayer(url: url)
                    showPlayer = true
                }
            }
            .onDisappear {
                viewModel.stopRetryTimer()
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
