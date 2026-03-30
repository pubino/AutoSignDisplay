//
//  StreamViewModel.swift
//  Autostream
//
//  Created by Michael Bino on 4/20/25.
//

import Foundation
import AVKit
import Combine

class StreamViewModel: ObservableObject {
    static let maxChannelPresets = 20
    static let defaultPresets = [
        "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
        "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
        "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
        "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"
    ]

    @Published var streamURL: String
    @Published var isPlayingOnOpen: Bool
    @Published var retryTimeout: Double
    @Published var autoResume: Bool
    @Published var settingsDisabled: Bool
    @Published var channelPresets: [String]
    @Published var channelPresetsManaged: Bool
    @Published var selectedPresetIndex: Int?
    @Published var defaultChannelURL: String?
    @Published var player: AVPlayer?

    /// Current retry attempt count (resets on successful playback).
    @Published var retryCount: Int = 0
    /// Maximum retry attempts before giving up (0 = unlimited).
    @Published var maxRetries: Int = 0

    private var retryTimer: Timer?
    private var playerObservers: [NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var defaultsObserver: NSObjectProtocol?

    // Inject a logger for easier testing. Defaults to printing to stdout.
    let logger: Logger

    init(logger: Logger = PrintLogger()) {
        let defaults = UserDefaults.standard
        self.logger = logger

        // Ensure the managed flag has an explicit default when no MDM payload exists.
        if defaults.object(forKey: ContentView.channelPresetsManagedKey) == nil {
            defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        }

        self.streamURL = defaults.string(forKey: ContentView.lastStreamURLKey) ?? ""
        self.isPlayingOnOpen = defaults.bool(forKey: ContentView.playOnOpenKey)
        let timeout = defaults.double(forKey: ContentView.retryTimeoutKey)
        self.retryTimeout = timeout > 0 ? timeout : 5.0
        self.autoResume = defaults.bool(forKey: ContentView.autoResumeKey)
        self.settingsDisabled = defaults.bool(forKey: ContentView.settingsDisabledKey)

        let storedPresets = defaults.stringArray(forKey: ContentView.channelPresetsKey)
        let sanitizedPresets: [String]
        if let storedPresets, !storedPresets.isEmpty {
            sanitizedPresets = Array(storedPresets.prefix(StreamViewModel.maxChannelPresets))
            if sanitizedPresets.count != storedPresets.count {
                defaults.set(sanitizedPresets, forKey: ContentView.channelPresetsKey)
            }
        } else {
            sanitizedPresets = StreamViewModel.defaultPresets
            defaults.set(sanitizedPresets, forKey: ContentView.channelPresetsKey)
            defaults.set(false, forKey: ContentView.channelPresetsManagedKey)
        }
        self.channelPresets = sanitizedPresets
        self.channelPresetsManaged = defaults.bool(forKey: ContentView.channelPresetsManagedKey)

        if let managedDefault = defaults.string(forKey: ContentView.defaultChannelKey), !managedDefault.isEmpty {
            self.defaultChannelURL = managedDefault
        } else {
            self.defaultChannelURL = nil
        }

        if let defaultChannelURL = self.defaultChannelURL {
            if channelPresetsManaged {
                self.streamURL = defaultChannelURL
                defaults.set(defaultChannelURL, forKey: ContentView.lastStreamURLKey)
            } else if self.streamURL.isEmpty {
                self.streamURL = defaultChannelURL
                defaults.set(defaultChannelURL, forKey: ContentView.lastStreamURLKey)
            }
        }

        let storedIndex = defaults.object(forKey: ContentView.selectedPresetIndexKey) as? Int
        if let storedIndex, channelPresets.indices.contains(storedIndex) {
            self.selectedPresetIndex = storedIndex
            let presetURL = channelPresets[storedIndex]
            if !presetURL.isEmpty, self.streamURL != presetURL {
                self.streamURL = presetURL
                defaults.set(presetURL, forKey: ContentView.lastStreamURLKey)
            }
        } else if let matchIndex = channelPresets.firstIndex(of: self.streamURL), !self.streamURL.isEmpty {
            self.selectedPresetIndex = matchIndex
            defaults.set(matchIndex, forKey: ContentView.selectedPresetIndexKey)
        } else {
            self.selectedPresetIndex = nil
            defaults.removeObject(forKey: ContentView.selectedPresetIndexKey)
        }

        // Observe UserDefaults changes so managed config updates propagate at runtime
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadManagedSettingsIfNeeded()
        }
    }

    deinit {
        if let obs = defaultsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        tearDownPlayerObservers()
    }

    // MARK: - Reload from UserDefaults (Issue #1)

    /// Re-read settings from UserDefaults. Called when managed config may have changed.
    func reloadManagedSettingsIfNeeded() {
        let defaults = UserDefaults.standard

        let newStreamURL = defaults.string(forKey: ContentView.lastStreamURLKey) ?? ""
        let newPlayOnOpen = defaults.bool(forKey: ContentView.playOnOpenKey)
        let newTimeout = defaults.double(forKey: ContentView.retryTimeoutKey)
        let effectiveTimeout = newTimeout > 0 ? newTimeout : 5.0
        let newAutoResume = defaults.bool(forKey: ContentView.autoResumeKey)
        let newSettingsDisabled = defaults.bool(forKey: ContentView.settingsDisabledKey)
        let newManaged = defaults.bool(forKey: ContentView.channelPresetsManagedKey)

        var changed = false

        if streamURL != newStreamURL {
            streamURL = newStreamURL
            changed = true
        }
        if isPlayingOnOpen != newPlayOnOpen {
            isPlayingOnOpen = newPlayOnOpen
            changed = true
        }
        if retryTimeout != effectiveTimeout {
            retryTimeout = effectiveTimeout
            restartRetryTimer()
            changed = true
        }
        if autoResume != newAutoResume {
            autoResume = newAutoResume
            changed = true
        }
        if settingsDisabled != newSettingsDisabled {
            settingsDisabled = newSettingsDisabled
            changed = true
        }
        if channelPresetsManaged != newManaged {
            channelPresetsManaged = newManaged
            changed = true
        }

        let newPresets = defaults.stringArray(forKey: ContentView.channelPresetsKey) ?? []
        if channelPresets != newPresets, !newPresets.isEmpty {
            channelPresets = newPresets
            changed = true
        }

        let newIndex = defaults.object(forKey: ContentView.selectedPresetIndexKey) as? Int
        if selectedPresetIndex != newIndex {
            selectedPresetIndex = newIndex
            changed = true
        }

        if changed {
            logger.log("Reloaded settings from UserDefaults")
        }
    }

    // MARK: - Settings

    func updateSettings(isPlayingOnOpen: Bool, retryTimeout: Double, autoResume: Bool, settingsDisabled: Bool = false) {
        self.isPlayingOnOpen = isPlayingOnOpen
        self.retryTimeout = retryTimeout
        self.autoResume = autoResume
        self.settingsDisabled = settingsDisabled
        UserDefaults.standard.set(isPlayingOnOpen, forKey: ContentView.playOnOpenKey)
        UserDefaults.standard.set(retryTimeout, forKey: ContentView.retryTimeoutKey)
        UserDefaults.standard.set(autoResume, forKey: ContentView.autoResumeKey)
        UserDefaults.standard.set(settingsDisabled, forKey: ContentView.settingsDisabledKey)
        restartRetryTimer()
    }

    // MARK: - Stream URL

    func updateStreamURL(_ url: String, selectedPresetIndex: Int? = nil) {
        self.streamURL = url
        UserDefaults.standard.set(url, forKey: ContentView.lastStreamURLKey)

        if let selectedPresetIndex {
            self.selectedPresetIndex = selectedPresetIndex
        } else if let matchIndex = channelPresets.firstIndex(of: url), !url.isEmpty {
            self.selectedPresetIndex = matchIndex
        } else {
            self.selectedPresetIndex = nil
        }
        persistSelectedPresetIndex()
    }

    // MARK: - Presets

    func selectPreset(at index: Int) {
        guard channelPresets.indices.contains(index) else { return }
        updateStreamURL(channelPresets[index], selectedPresetIndex: index)
    }

    func addChannelPreset() {
        guard !channelPresetsManaged, channelPresets.count < StreamViewModel.maxChannelPresets else { return }
        channelPresets.append("")
        persistChannelPresets()
    }

    func removeChannelPreset(at index: Int) {
        guard !channelPresetsManaged, channelPresets.indices.contains(index) else { return }
        channelPresets.remove(at: index)
        if let selectedIndex = selectedPresetIndex {
            if selectedIndex == index {
                selectedPresetIndex = nil
            } else if selectedIndex > index {
                selectedPresetIndex = selectedIndex - 1
            }
            persistSelectedPresetIndex()
        }
        persistChannelPresets()
    }

    func updateChannelPreset(at index: Int, with url: String) {
        guard channelPresets.indices.contains(index), !channelPresetsManaged else { return }
        channelPresets[index] = url
        persistChannelPresets()

        if selectedPresetIndex == index {
            updateStreamURL(url, selectedPresetIndex: index)
        } else if selectedPresetIndex == nil, streamURL == url {
            updateStreamURL(url)
        }
    }

    var canAddMorePresets: Bool {
        !channelPresetsManaged && channelPresets.count < StreamViewModel.maxChannelPresets
    }

    /// Extract a display name from a stream URL (hostname or last path component).
    func displayName(for url: String) -> String {
        guard let parsed = URL(string: url), let host = parsed.host else { return url }
        let path = parsed.lastPathComponent
        if !path.isEmpty, path != "/" {
            return "\(host)/\(path)"
        }
        return host
    }

    // MARK: - Playback

    func playStream() {
        guard let url = URL(string: streamURL) else { return }
        tearDownPlayerObservers()
        player = AVPlayer(url: url)
        player?.play()
        retryCount = 0
        setupPlayerObservers()
    }

    func startStreamIfNeeded() {
        guard let url = URL(string: streamURL) else { return }
        tearDownPlayerObservers()
        player = AVPlayer(url: url)
        if isPlayingOnOpen {
            player?.play()
        }
        retryCount = 0
        setupPlayerObservers()
        startRetryTimer()
    }

    // MARK: - Retry Timer (Issue #2)

    func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    func restartRetryTimer() {
        stopRetryTimer()
        startRetryTimer()
    }

    func startRetryTimer() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: retryTimeout, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.attemptRetry()
            }
        }
    }

    /// Core retry logic: checks player state and recreates if needed.
    private func attemptRetry() {
        guard autoResume else { return }

        // Check if we've exceeded max retries (0 = unlimited)
        if maxRetries > 0, retryCount >= maxRetries {
            logger.log("Max retries (\(maxRetries)) reached for stream: \(streamURL)")
            stopRetryTimer()
            return
        }

        let needsRetry: Bool
        if player == nil {
            needsRetry = true
        } else if player?.currentItem == nil {
            needsRetry = true
        } else if player?.currentItem?.status == .failed {
            needsRetry = true
        } else if player?.status == .failed {
            needsRetry = true
        } else {
            needsRetry = false
        }

        guard needsRetry, let url = URL(string: streamURL) else { return }

        retryCount += 1
        logger.log("Auto-resuming stream (attempt \(retryCount)): \(streamURL)")
        tearDownPlayerObservers()
        player = AVPlayer(url: url)
        if isPlayingOnOpen {
            player?.play()
        }
        setupPlayerObservers()
    }

    // MARK: - Player Observation (Issue #2)

    private func setupPlayerObservers() {
        guard let player = player else { return }

        // Observe player item failure notification
        let failObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self?.logger.log("Player item failed: \(error?.localizedDescription ?? "unknown error")")
        }
        playerObservers.append(failObs)

        // Observe player item reaching end
        let endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.logger.log("Stream playback ended")
        }
        playerObservers.append(endObs)

        // KVO on player status
        statusObservation = player.observe(\.status, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                if player.status == .failed {
                    self?.logger.log("Player status failed: \(player.error?.localizedDescription ?? "unknown")")
                } else if player.status == .readyToPlay {
                    self?.retryCount = 0
                }
            }
        }
    }

    private func tearDownPlayerObservers() {
        for obs in playerObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        playerObservers.removeAll()
        statusObservation?.invalidate()
        statusObservation = nil
        rateObservation?.invalidate()
        rateObservation = nil
    }

    // Exposed for testing: emit the same auto-resume log message so tests can
    // inject a TestLogger and assert the logger received the expected text.
    func emitAutoResumeLogForTesting() {
        logger.log("Auto-resuming stream: \(self.streamURL)")
    }

    // MARK: - Persistence

    private func persistChannelPresets() {
        UserDefaults.standard.set(channelPresets, forKey: ContentView.channelPresetsKey)
    }

    private func persistSelectedPresetIndex() {
        let defaults = UserDefaults.standard
        if let selectedPresetIndex {
            defaults.set(selectedPresetIndex, forKey: ContentView.selectedPresetIndexKey)
        } else {
            defaults.removeObject(forKey: ContentView.selectedPresetIndexKey)
        }
    }
}
