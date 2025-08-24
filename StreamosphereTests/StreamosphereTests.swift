//
//  StreamosphereTests.swift
//  StreamosphereTests
//
//  Created by Michael Bino on 4/20/25.
//

import Foundation
import Testing
@testable import Streamosphere

struct StreamosphereTests {

    @Test func autoplayCreatesPlayer() async throws {
        // Prepare UserDefaults for test
        let defaults = UserDefaults.standard
        defaults.set("https://example.com/stream.m3u8", forKey: ContentView.lastStreamURLKey)
        defaults.set(true, forKey: ContentView.playOnOpenKey)

        let vm = StreamViewModel()

        // Initially no player
        #expect(vm.player == nil)

        // Trigger start which should create the player if PlayOnAppOpen is true
        vm.startStreamIfNeeded()

        // After starting, a player should be created
        #expect(vm.player != nil)
    }

}
