//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

#if os(iOS)

import AVFoundation
import Foundation
import UIKit

/// An user of the `AudioSession`, for example a media player object.
public protocol AudioSessionUser: AnyObject {
    /// Audio session configuration to use for this user.
    var audioConfiguration: AudioSession.Configuration { get }

    /// Called when an audio interruption (e.g. phone call) finishes, to resume audio playback or
    /// recording.
    func play()
}

public extension AudioSessionUser {
    var audioConfiguration: AudioSession.Configuration {
        .init()
    }
}

/// Manages the app's audio session for Readium audio consumers.
public protocol AudioSessionManaging {
    /// Starts a new audio session with the given `user`.
    func start(with user: AudioSessionUser, isPlaying: Bool)

    /// Ends the current audio session.
    func end(for user: AudioSessionUser)

    /// Indicates whether the `user` is playing.
    func user(_ user: AudioSessionUser, didChangePlaying isPlaying: Bool)
}

/// Manages an activated `AVAudioSession`.
@MainActor
public final class AudioSession: AudioSessionManaging, Loggable {
    public struct Configuration: Equatable {
        public let category: AVAudioSession.Category
        public let mode: AVAudioSession.Mode
        public let routeSharingPolicy: AVAudioSession.RouteSharingPolicy
        public let options: AVAudioSession.CategoryOptions

        public init(
            category: AVAudioSession.Category = .playback,
            mode: AVAudioSession.Mode = .default,
            routeSharingPolicy: AVAudioSession.RouteSharingPolicy = .default,
            options: AVAudioSession.CategoryOptions = []
        ) {
            self.category = category
            self.mode = mode
            self.routeSharingPolicy = routeSharingPolicy
            self.options = options
        }
    }

    /// Shared `AudioSession` for this app.
    public nonisolated static let shared = AudioSession()

    private nonisolated init() {
        Task {
            await observeAppStateChanges()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    fileprivate struct User {
        let id: ObjectIdentifier
        private(set) weak var user: AudioSessionUser?

        init(_ user: AudioSessionUser) {
            id = ObjectIdentifier(user)
            self.user = user
        }
    }

    /// Current user of the `AudioSession`.
    private var user: User?

    /// Starts a new audio session with the given `user`.
    public nonisolated func start(with user: AudioSessionUser, isPlaying: Bool) {
        Task {
            await start(with: user, isPlaying: isPlaying)
        }
    }

    private func start(with user: AudioSessionUser, isPlaying: Bool) async {
        let id = ObjectIdentifier(user)
        guard self.user?.id != id else {
            return
        }

        if let oldUser = self.user {
            end(forUserID: oldUser.id)
        }
        self.user = User(user)
        self.isPlaying = false

        startSession(with: user.audioConfiguration)
    }

    /// Ends the current audio session.
    public nonisolated func end(for user: AudioSessionUser) {
        let id = ObjectIdentifier(user)
        Task {
            await end(forUserID: id)
        }
    }

    private func end(forUserID id: ObjectIdentifier) {
        guard user?.id == id else {
            return
        }

        user = nil
        isPlaying = false

        endSession()
    }

    /// Indicates whether the `user` is playing.
    private var isPlaying: Bool = false

    public nonisolated func user(_ user: AudioSessionUser, didChangePlaying isPlaying: Bool) {
        Task {
            await self.user(user, didChangePlaying: isPlaying)
        }
    }

    private func user(_ user: AudioSessionUser, didChangePlaying isPlaying: Bool) async {
        let id = ObjectIdentifier(user)
        guard self.user?.id == id, self.isPlaying != isPlaying else {
            return
        }

        self.isPlaying = isPlaying

        if isPlaying {
            startSession(with: user.audioConfiguration)
        } else if UIApplication.shared.applicationState != .active {
            endSession()
        }
    }

    // MARK: App background state

    private func observeAppStateChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc private func appDidEnterBackground() {
        if !isPlaying {
            endSession()
        }
    }

    // MARK: Session management

    private var isSessionStarted = false

    private func startSession(with config: Configuration) {
        guard !isSessionStarted else {
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(config.category, mode: config.mode, policy: config.routeSharingPolicy, options: config.options)
            try audioSession.setActive(true)
            log(.info, "Started audio session with category: \(config.category), mode: \(config.mode), policy: \(config.routeSharingPolicy), options: \(config.options)")
        } catch {
            log(.error, "Failed to start the audio session: \(error)")
        }

        isSessionStarted = true

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioSessionInterruption(notification: notification)
        }
    }

    private func endSession() {
        guard isSessionStarted else {
            return
        }

        do {
            AVAudioSession.sharedInstance()
            try AVAudioSession.sharedInstance().setActive(false)
            log(.info, "Ended audio session")
        } catch {
            log(.error, "Failed to end the audio session: \(error)")
        }

        isSessionStarted = false
        interruptionObserver = nil
    }

    /// Whether the audio session is currently interrupted, e.g. by a phone call.
    public private(set) var isInterrupted: Bool = false

    /// The observer of audio session interruption notifications.
    private var interruptionObserver: Any?

    private nonisolated func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawInterruptionType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: rawInterruptionType)
        else {
            return
        }

        let options = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt)
            .map(AVAudioSession.InterruptionOptions.init(rawValue:))
            ?? []

        Task {
            await handleAudioSessionInterruption(type: interruptionType, options: options)
        }
    }

    private func handleAudioSessionInterruption(type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            isInterrupted = true

        case .ended:
            isInterrupted = false

            // When an interruption ends, determine whether playback should resume automatically,
            // and reactivate the audio session if necessary.
            do {
                if let user = user?.user {
                    try AVAudioSession.sharedInstance().setActive(true)

                    if options.contains(.shouldResume) {
                        user.play()
                    }
                }
            } catch {
                log(.error, "Cannot resume audio session after interruption: \(error)")
            }

        @unknown default:
            break
        }
    }
}

#else

import Foundation

// macOS has no `AVAudioSession`: apps play audio without activating a session,
// and playback continues while their windows are hidden. These declarations
// keep the iOS API shape so audio consumers such as `PublicationSpeechSynthesizer`
// build on macOS, where starting and ending a session does nothing.

/// An user of the `AudioSession`, for example a media player object.
public protocol AudioSessionUser: AnyObject {
    /// Audio session configuration to use for this user.
    var audioConfiguration: AudioSession.Configuration { get }

    /// Called when an audio interruption finishes. Never called on macOS.
    func play()
}

public extension AudioSessionUser {
    var audioConfiguration: AudioSession.Configuration {
        .init()
    }
}

/// Manages the app's audio session for Readium audio consumers.
public protocol AudioSessionManaging {
    func start(with user: AudioSessionUser, isPlaying: Bool)
    func end(for user: AudioSessionUser)
    func user(_ user: AudioSessionUser, didChangePlaying isPlaying: Bool)
}

/// The macOS stand-in for the iOS audio session manager. It records nothing
/// and changes no system state.
public final class AudioSession: AudioSessionManaging, Sendable {
    /// Mirrors the iOS configuration so shared code can describe its intent.
    public struct Configuration: Equatable, Sendable {
        public struct Category: Equatable, Sendable {
            public let rawValue: String
            public static let playback = Category(rawValue: "playback")
            public static let ambient = Category(rawValue: "ambient")
        }

        public struct Mode: Equatable, Sendable {
            public let rawValue: String
            public static let `default` = Mode(rawValue: "default")
            public static let spokenAudio = Mode(rawValue: "spokenAudio")
        }

        public struct RouteSharingPolicy: Equatable, Sendable {
            public let rawValue: String
            public static let `default` = RouteSharingPolicy(rawValue: "default")
            public static let longFormAudio = RouteSharingPolicy(rawValue: "longFormAudio")
        }

        public struct CategoryOptions: OptionSet, Equatable, Sendable {
            public let rawValue: UInt
            public init(rawValue: UInt) { self.rawValue = rawValue }
        }

        public let category: Category
        public let mode: Mode
        public let routeSharingPolicy: RouteSharingPolicy
        public let options: CategoryOptions

        public init(
            category: Category = .playback,
            mode: Mode = .default,
            routeSharingPolicy: RouteSharingPolicy = .default,
            options: CategoryOptions = []
        ) {
            self.category = category
            self.mode = mode
            self.routeSharingPolicy = routeSharingPolicy
            self.options = options
        }
    }

    /// Shared `AudioSession` for this app.
    public static let shared = AudioSession()

    private init() {}

    public func start(with user: AudioSessionUser, isPlaying: Bool) {}
    public func end(for user: AudioSessionUser) {}
    public func user(_ user: AudioSessionUser, didChangePlaying isPlaying: Bool) {}
}

#endif
