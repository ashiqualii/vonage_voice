import Flutter
import UIKit
import AVFoundation
import PushKit
import CallKit
import VonageClientSDKVoice

// MARK: - Main Plugin

public class VonageVoicePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // MARK: - Shared Instance

    /// Shared instance for AppDelegate to forward PushKit events when needed.
    public static var sharedInstance: VonageVoicePlugin?

    // MARK: - Flutter Channels

    private var eventSink: FlutterEventSink?
    private var pendingEvents: [Any] = []
    private static let maxPendingEvents = 50

    // MARK: - Vonage SDK

    private var voiceClient: VGVoiceClient!
    private var accessToken: String?
    private var deviceId: String?

    // MARK: - CallKit

    private var callKitProvider: CXProvider!
    private var callKitCallController: CXCallController!
    private var callKitCompletionCallback: ((Bool) -> Void)?

    // MARK: - PushKit

    private var voipRegistry: PKPushRegistry!
    private var deviceToken: Data? {
        get { UserDefaults.standard.data(forKey: kCachedDeviceToken) }
        set { UserDefaults.standard.set(newValue, forKey: kCachedDeviceToken) }
    }

    // MARK: - Push Environment

    /// Whether to register VoIP push tokens against Apple's sandbox APNS.
    /// Set from Dart via the `isSandbox` parameter in `setTokens()`.
    /// Defaults to `false` (production).
    private var isSandbox: Bool = false

    // MARK: - Call State

    /// Stores pending call invites keyed by UUID: (callId, from, to, customParams)
    private var callInvites: [UUID: CallInviteInfo] = [:]
    /// Stores active calls keyed by UUID -> callId
    private var activeCalls: [UUID: String] = [:]
    /// Maps Vonage callId -> CallKit UUID for quick lookup
    private var callIdToUUID: [String: UUID] = [:]
    /// The UUID of the currently active (foreground) call
    private var activeCallUUID: UUID?

    private var callOutgoing: Bool = false
    private var userInitiatedDisconnect: Bool = false
    private var callTo: String = ""
    private var identity: String = ""
    private var callArgs: [String: Any] = [:]
    private var outgoingCallerName: String = ""

    // MARK: - Audio State

    private var isMuted: Bool = false
    private var isHolding: Bool = false
    private var desiredSpeakerState: Bool = false
    private var desiredBluetoothState: Bool = false
    private var userExplicitlyChangedAudioRoute: Bool = false
    private var isChangingAudioRoute: Bool = false

    // MARK: - Caller Registry

    private var clients: [String: String] = [:]
    private var defaultCaller: String = "Unknown Caller"

    // MARK: - Persistence Keys

    private let kCachedDeviceToken = "VonageCachedDeviceToken"
    private let kCachedBindingDate = "VonageCachedBindingDate"
    private let kClientList = "VonageContactList"
    private let kCachedJwt = "VonageCachedJwt"
    private let kCachedDeviceId = "VonageCachedDeviceId"
    private let kDefaultCallKitIcon = "callkit_icon"

    // MARK: - App Name

    static var appName: String {
        return (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? "Vonage Voice"
    }

    // MARK: - Init

    public override init() {
        voipRegistry = PKPushRegistry(queue: DispatchQueue.main)

        let configuration = CXProviderConfiguration(localizedName: VonageVoicePlugin.appName)
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.phoneNumber, .generic]
        configuration.supportsVideo = false

        clients = UserDefaults.standard.object(forKey: kClientList) as? [String: String] ?? [:]
        callKitProvider = CXProvider(configuration: configuration)
        callKitCallController = CXCallController()

        super.init()

        callKitProvider.setDelegate(self, queue: nil)

        // Initialize Vonage Voice Client
        voiceClient = VGVoiceClient()
        voiceClient.delegate = self

        // Tell the Vonage SDK that CallKit manages the audio session.
        // Without this, the SDK won't hook into CallKit's audio lifecycle.
        VGVoiceClient.isUsingCallKit = true

        // Set default CallKit icon
        let defaultIcon = UserDefaults.standard.string(forKey: kDefaultCallKitIcon) ?? kDefaultCallKitIcon
        _ = updateCallKitIcon(icon: defaultIcon)

        // Listen for audio route changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    deinit {
        callKitProvider.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Plugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = VonageVoicePlugin()

        let methodChannel = FlutterMethodChannel(
            name: "vonage_voice/messages",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "vonage_voice/events",
            binaryMessenger: registrar.messenger()
        )

        eventChannel.setStreamHandler(instance)
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        registrar.addApplicationDelegate(instance)

        VonageVoicePlugin.sharedInstance = instance

        // Set up PushKit for VoIP pushes.
        // When a VoIP push arrives, Apple wakes the app and delivers it via
        // PKPushRegistryDelegate. The plugin processes it through the Vonage SDK,
        // which fires didReceiveInviteForCall, and we report to CallKit.
        instance.voipRegistry.delegate = instance
        instance.voipRegistry.desiredPushTypes = [.voIP]
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink

        // Replay queued events
        if !pendingEvents.isEmpty {
            let eventsToReplay = pendingEvents
            pendingEvents.removeAll()
            for event in eventsToReplay {
                DispatchQueue.main.async {
                    eventSink(event)
                }
            }
        }

        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - Event Sending

    private func sendPhoneCallEvents(description: String, isError: Bool = false) {
        NSLog("[VonageVoice] \(description)")

        if isError {
            let err = FlutterError(code: "unavailable", message: description, details: nil)
            sendEvent(err)
        } else {
            sendEvent(description)
        }
    }

    private func sendEvent(_ event: Any) {
        guard let eventSink = eventSink else {
            // Queue critical call events for replay when Flutter reconnects
            if let strEvent = event as? String, !strEvent.hasPrefix("LOG|") {
                if pendingEvents.count < VonageVoicePlugin.maxPendingEvents {
                    pendingEvents.append(event)
                } else {
                    pendingEvents.removeFirst()
                    pendingEvents.append(event)
                }
            }
            return
        }
        DispatchQueue.main.async {
            eventSink(event)
        }
    }

    // MARK: - Method Channel Handler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]

        switch call.method {

        // Session
        case "tokens":
            handleTokens(arguments: arguments, result: result)
        case "unregister":
            handleUnregister(arguments: arguments, result: result)
        case "refreshSession":
            handleRefreshSession(arguments: arguments, result: result)

        // Calls
        case "makeCall":
            handleMakeCall(arguments: arguments, result: result)
        case "hangUp":
            handleHangUp(result: result)
        case "answer":
            handleAnswer(result: result)
        case "isOnCall":
            result(!activeCalls.isEmpty)
        case "call-sid":
            if let uuid = activeCallUUID, let callId = activeCalls[uuid] {
                result(callId)
            } else {
                result(nil)
            }

        // Hold
        case "holdCall":
            handleHoldCall(arguments: arguments, result: result)
        case "isHolding":
            result(isHolding)

        // Mute
        case "toggleMute":
            handleToggleMute(arguments: arguments, result: result)
        case "isMuted":
            result(isMuted)

        // Speaker
        case "toggleSpeaker":
            handleToggleSpeaker(arguments: arguments, result: result)
        case "isOnSpeaker":
            result(isSpeakerOn())

        // Bluetooth
        case "toggleBluetooth":
            handleToggleBluetooth(arguments: arguments, result: result)
        case "isBluetoothOn":
            result(isBluetoothOn())
        case "isBluetoothAvailable":
            result(isBluetoothAvailable())
        case "isBluetoothEnabled":
            // iOS doesn't expose BT adapter state directly — return true if BT audio is available
            result(isBluetoothAvailable())
        case "showBluetoothEnablePrompt":
            // Not available on iOS
            result(false)
        case "openBluetoothSettings":
            // Open iOS Settings app
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            result(true)

        // DTMF
        case "sendDigits":
            handleSendDigits(arguments: arguments, result: result)

        // Permissions
        case "hasMicPermission":
            let permission = AVAudioSession.sharedInstance().recordPermission
            result(permission == .granted)
        case "requestMicPermission":
            handleRequestMicPermission(result: result)
        case "hasBluetoothPermission":
            result(true)
        case "requestBluetoothPermission":
            result(true)

        // Caller Registry
        case "registerClient":
            handleRegisterClient(arguments: arguments, result: result)
        case "unregisterClient":
            handleUnregisterClient(arguments: arguments, result: result)
        case "defaultCaller":
            handleDefaultCaller(arguments: arguments, result: result)

        // Notifications
        case "showNotifications":
            let show = arguments["show"] as? Bool ?? true
            UserDefaults.standard.set(show, forKey: "vonage-show-notifications")
            result(true)

        // CallKit Icon
        case "updateCallKitIcon":
            let icon = arguments["icon"] as? String ?? kDefaultCallKitIcon
            result(updateCallKitIcon(icon: icon))

        // Push processing
        case "processVonagePush":
            handleProcessPush(arguments: arguments, result: result)

        // Telecom (Android-only, return defaults)
        case "hasRegisteredPhoneAccount", "registerPhoneAccount",
             "isPhoneAccountEnabled", "openPhoneAccountSettings":
            result(true)

        // Android-only permissions (return true)
        case "hasReadPhoneStatePermission", "requestReadPhoneStatePermission",
             "hasCallPhonePermission", "requestCallPhonePermission",
             "hasManageOwnCallsPermission", "requestManageOwnCallsPermission",
             "hasReadPhoneNumbersPermission", "requestReadPhoneNumbersPermission",
             "hasNotificationPermission", "requestNotificationPermission":
            result(true)

        // Android-only settings (return defaults)
        case "rejectCallOnNoPermissions":
            result(true)
        case "isRejectingCallOnNoPermissions":
            result(false)
        case "isBatteryOptimized":
            result(false)
        case "requestBatteryOptimizationExemption":
            result(true)
        case "canUseFullScreenIntent":
            result(true)
        case "openFullScreenIntentSettings":
            result(true)
        case "backgroundCallUI":
            result(true)

        // Platform version
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - Session Management

extension VonageVoicePlugin {

    private func handleTokens(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let jwt = arguments["jwt"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing jwt", details: nil))
            return
        }

        self.accessToken = jwt
        self.isSandbox = arguments["isSandbox"] as? Bool ?? false
        storeJwt(jwt)

        sendPhoneCallEvents(description: "LOG|tokens: Creating session with Vonage")

        voiceClient.createSession(jwt) { [weak self] error, sessionId in
            guard let self = self else { return }
            if let error = error {
                self.sendPhoneCallEvents(description: "LOG|createSession failed: \(error.localizedDescription)")
                result(FlutterError(code: "SESSION_ERROR", message: error.localizedDescription, details: nil))
                return
            }

            self.sendPhoneCallEvents(description: "LOG|Session created successfully: \(sessionId ?? "nil")")

            // Register VoIP push token if available
            if let token = self.deviceToken {
                self.registerPushToken(token)
            }

            result(true)
        }
    }

    private func handleUnregister(arguments: [String: Any], result: @escaping FlutterResult) {
        // Unregister push token
        if let deviceId = self.deviceId {
            voiceClient.unregisterDeviceTokens(byDeviceId: deviceId) { [weak self] error in
                if let error = error {
                    self?.sendPhoneCallEvents(description: "LOG|unregisterDeviceTokens failed: \(error.localizedDescription)")
                }
            }
        }

        // Delete session
        voiceClient.deleteSession { [weak self] error in
            if let error = error {
                self?.sendPhoneCallEvents(description: "LOG|deleteSession failed: \(error.localizedDescription)")
            } else {
                self?.sendPhoneCallEvents(description: "LOG|Session deleted successfully")
            }
        }

        self.accessToken = nil
        self.deviceId = nil
        UserDefaults.standard.removeObject(forKey: kCachedDeviceId)
        clearStoredJwt()
        result(true)
    }

    private func handleRefreshSession(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let jwt = arguments["jwt"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing jwt", details: nil))
            return
        }

        self.accessToken = jwt
        storeJwt(jwt)

        voiceClient.refreshSession(jwt) { [weak self] error in
            if let error = error {
                self?.sendPhoneCallEvents(description: "LOG|refreshSession failed: \(error.localizedDescription)")
                result(FlutterError(code: "REFRESH_ERROR", message: error.localizedDescription, details: nil))
            } else {
                self?.sendPhoneCallEvents(description: "LOG|Session refreshed successfully")
                result(true)
            }
        }
    }

    private func registerPushToken(_ token: Data) {
        // If we have a previously stored deviceId (from a prior session/install),
        // unregister it first to free up a device slot on Vonage's side.
        let storedDeviceId = UserDefaults.standard.string(forKey: kCachedDeviceId)
        if let oldDeviceId = storedDeviceId, oldDeviceId != self.deviceId {
            sendPhoneCallEvents(description: "LOG|Unregistering old deviceId before re-registering: \(oldDeviceId)")
            voiceClient.unregisterDeviceTokens(byDeviceId: oldDeviceId) { [weak self] error in
                if let error = error {
                    self?.sendPhoneCallEvents(description: "LOG|Old device unregister failed (non-fatal): \(error.localizedDescription)")
                } else {
                    self?.sendPhoneCallEvents(description: "LOG|Old device unregistered successfully")
                }
                // Proceed with registration regardless of unregister result
                self?.doRegisterVoipToken(token, isRetry: false)
            }
        } else {
            doRegisterVoipToken(token, isRetry: false)
        }
    }

    private func doRegisterVoipToken(_ token: Data, isRetry: Bool) {
        let hexToken = token.map { String(format: "%02x", $0) }.joined()
        NSLog("[VonageVoice-Push] registerVoipToken sandbox=%d retry=%d tokenLen=%d hex=%@", isSandbox ? 1 : 0, isRetry ? 1 : 0, token.count, hexToken)
        sendPhoneCallEvents(description: "LOG|Registering VoIP push token with Vonage (sandbox=\(isSandbox), retry=\(isRetry)) hex=\(hexToken)")
        voiceClient.registerVoipToken(token, isSandbox: isSandbox) { [weak self] error, deviceId in
            guard let self = self else { return }
            if let error = error {
                let errorDesc = error.localizedDescription
                self.sendPhoneCallEvents(description: "LOG|registerVoipToken failed: \(errorDesc)")

                // Handle max-device-limit: unregister stored device and retry once
                if !isRetry && errorDesc.contains("max-device-limit") {
                    self.sendPhoneCallEvents(description: "LOG|Max device limit reached — attempting to unregister stored device and retry")
                    if let oldId = self.deviceId ?? UserDefaults.standard.string(forKey: self.kCachedDeviceId) {
                        self.voiceClient.unregisterDeviceTokens(byDeviceId: oldId) { [weak self] unregError in
                            if let unregError = unregError {
                                self?.sendPhoneCallEvents(description: "LOG|Unregister for retry failed: \(unregError.localizedDescription)")
                            }
                            // Retry registration once
                            self?.doRegisterVoipToken(token, isRetry: true)
                        }
                    } else {
                        self.sendPhoneCallEvents(description: "LOG|No stored deviceId to unregister — cannot auto-recover from max-device-limit. Use Vonage REST API to clear old devices.")
                    }
                }
            } else {
                self.deviceId = deviceId
                // Persist deviceId so we can unregister it on next install/session
                if let deviceId = deviceId {
                    UserDefaults.standard.set(deviceId, forKey: self.kCachedDeviceId)
                }
                self.sendPhoneCallEvents(description: "LOG|VoIP push token registered. deviceId=\(deviceId ?? "nil")")
            }
        }
    }
}

// MARK: - Call Management

extension VonageVoicePlugin {

    private func handleMakeCall(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let to = arguments["to"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing 'to' parameter", details: nil))
            return
        }
        let from = arguments["from"] as? String ?? identity
        let callerName = arguments["CallerName"] as? String ?? ""

        self.callArgs = arguments
        self.callOutgoing = true
        self.callTo = to
        self.identity = from
        self.outgoingCallerName = callerName

        // Check for pending incoming call
        if !callInvites.isEmpty {
            sendPhoneCallEvents(description: "LOG|Cannot make call - pending incoming call exists")
            result(FlutterError(code: "CALL_IN_PROGRESS", message: "Cannot make call while there's a pending incoming call", details: nil))
            return
        }

        let uuid = UUID()
        performStartCallAction(uuid: uuid, handle: to)
        result(true)
    }

    private func handleHangUp(result: @escaping FlutterResult) {
        if let uuid = activeCallUUID, activeCalls[uuid] != nil {
            sendPhoneCallEvents(description: "LOG|hangUp: ending active call uuid=\(uuid)")
            userInitiatedDisconnect = true
            performEndCallAction(uuid: uuid)
        } else if let (uuid, _) = callInvites.first {
            sendPhoneCallEvents(description: "LOG|hangUp: rejecting pending invite uuid=\(uuid)")
            performEndCallAction(uuid: uuid)
        }
        result(true)
    }

    private func handleAnswer(result: @escaping FlutterResult) {
        if let (uuid, _) = callInvites.first {
            sendPhoneCallEvents(description: "LOG|answer: answering invite uuid=\(uuid)")
            let answerAction = CXAnswerCallAction(call: uuid)
            let transaction = CXTransaction(action: answerAction)
            callKitCallController.request(transaction) { [weak self] error in
                if let error = error {
                    self?.sendPhoneCallEvents(description: "LOG|AnswerCallAction failed: \(error.localizedDescription)")
                }
            }
        } else {
            result(FlutterError(code: "ANSWER_ERROR", message: "No call invite to answer", details: nil))
            return
        }
        result(true)
    }

    private func handleHoldCall(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let shouldHold = arguments["shouldHold"] as? Bool else {
            result(false)
            return
        }

        guard let uuid = activeCallUUID, let callId = activeCalls[uuid] else {
            result(false)
            return
        }

        if shouldHold && !isHolding {
            isHolding = true
            // Vonage SDK doesn't have a native hold — mute audio as hold behavior
            voiceClient.mute(callId) { [weak self] error in
                if let error = error {
                    self?.sendPhoneCallEvents(description: "LOG|Hold (mute) failed: \(error.localizedDescription)")
                }
            }
            sendPhoneCallEvents(description: "Hold")
        } else if !shouldHold && isHolding {
            isHolding = false
            voiceClient.unmute(callId) { [weak self] error in
                if let error = error {
                    self?.sendPhoneCallEvents(description: "LOG|Unhold (unmute) failed: \(error.localizedDescription)")
                }
            }
            sendPhoneCallEvents(description: "Unhold")
        }
        result(true)
    }

    private func handleToggleMute(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let muted = arguments["muted"] as? Bool else {
            result(false)
            return
        }

        guard let uuid = activeCallUUID, let callId = activeCalls[uuid] else {
            result(FlutterError(code: "MUTE_ERROR", message: "No active call", details: nil))
            return
        }

        if muted {
            voiceClient.mute(callId) { [weak self] error in
                if let error = error {
                    self?.sendPhoneCallEvents(description: "LOG|Mute failed: \(error.localizedDescription)")
                } else {
                    self?.isMuted = true
                    self?.sendPhoneCallEvents(description: "Mute")
                }
            }
        } else {
            voiceClient.unmute(callId) { [weak self] error in
                if let error = error {
                    self?.sendPhoneCallEvents(description: "LOG|Unmute failed: \(error.localizedDescription)")
                } else {
                    self?.isMuted = false
                    self?.sendPhoneCallEvents(description: "Unmute")
                }
            }
        }
        result(true)
    }

    private func handleSendDigits(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let digits = arguments["digits"] as? String else {
            result(false)
            return
        }

        guard let uuid = activeCallUUID, let callId = activeCalls[uuid] else {
            result(false)
            return
        }

        voiceClient.sendDTMF(callId, withDigits: digits) { [weak self] error in
            if let error = error {
                self?.sendPhoneCallEvents(description: "LOG|sendDTMF failed: \(error.localizedDescription)")
            }
        }
        result(true)
    }

    private func handleProcessPush(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let data = arguments["data"] as? [String: Any] else {
            result(nil)
            return
        }

        // Check if it's a Vonage push using the static method
        let pushType = VGBaseClient.vonagePushType(data)
        if pushType == .incomingCall {
            voiceClient.processCallInvitePushData(data)
            result("processed")
        } else {
            result(nil)
        }
    }
}

// MARK: - Audio Management

extension VonageVoicePlugin {

    private func handleToggleSpeaker(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let speakerOn = arguments["speakerIsOn"] as? Bool else {
            result(false)
            return
        }

        desiredSpeakerState = speakerOn
        if speakerOn {
            desiredBluetoothState = false
        }
        userExplicitlyChangedAudioRoute = true
        applySpeakerSetting(toSpeaker: speakerOn)
        result(true)
    }

    private func handleToggleBluetooth(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let bluetoothOn = arguments["bluetoothOn"] as? Bool else {
            result(false)
            return
        }

        if bluetoothOn {
            desiredBluetoothState = true
            desiredSpeakerState = false
        } else {
            desiredBluetoothState = false
        }
        userExplicitlyChangedAudioRoute = true
        toggleBluetoothAudio(bluetoothOn: bluetoothOn)
        result(true)
    }

    private func applySpeakerSetting(toSpeaker: Bool) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            if toSpeaker {
                try audioSession.overrideOutputAudioPort(.speaker)
                sendPhoneCallEvents(description: "Speaker On")
            } else {
                try audioSession.overrideOutputAudioPort(.none)
                // Set built-in mic as preferred input to route to earpiece
                if let availableInputs = audioSession.availableInputs {
                    for input in availableInputs {
                        if input.portType == .builtInMic {
                            try audioSession.setPreferredInput(input)
                            break
                        }
                    }
                }
                sendPhoneCallEvents(description: "Speaker Off")
            }
        } catch {
            sendPhoneCallEvents(description: "LOG|applySpeakerSetting failed: \(error.localizedDescription)")
        }
    }

    private func toggleBluetoothAudio(bluetoothOn: Bool) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            if bluetoothOn {
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat,
                                            options: [.allowBluetooth, .allowBluetoothA2DP])
                // Find and set Bluetooth input
                if let availableInputs = audioSession.availableInputs {
                    for input in availableInputs {
                        if input.portType == .bluetoothHFP ||
                           input.portType == .bluetoothA2DP ||
                           input.portType == .bluetoothLE {
                            try audioSession.setPreferredInput(input)
                            break
                        }
                    }
                }
                try audioSession.overrideOutputAudioPort(.none)
                sendPhoneCallEvents(description: "Bluetooth On")
            } else {
                // Route to earpiece
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [])
                if let availableInputs = audioSession.availableInputs {
                    for input in availableInputs {
                        if input.portType == .builtInMic {
                            try audioSession.setPreferredInput(input)
                            break
                        }
                    }
                }
                try audioSession.overrideOutputAudioPort(.none)
                sendPhoneCallEvents(description: "Bluetooth Off")
            }
        } catch {
            sendPhoneCallEvents(description: "LOG|toggleBluetoothAudio failed: \(error.localizedDescription)")
        }
    }

    private func isSpeakerOn() -> Bool {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        for output in currentRoute.outputs {
            if output.portType == .builtInSpeaker {
                return true
            }
        }
        return false
    }

    private func isBluetoothOn() -> Bool {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        for output in currentRoute.outputs {
            if output.portType == .bluetoothHFP ||
               output.portType == .bluetoothA2DP ||
               output.portType == .bluetoothLE {
                return true
            }
        }
        return false
    }

    private func isBluetoothAvailable() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()

        // Check current route first
        let currentRoute = audioSession.currentRoute
        for output in currentRoute.outputs {
            if output.portType == .bluetoothHFP ||
               output.portType == .bluetoothA2DP ||
               output.portType == .bluetoothLE {
                return true
            }
        }
        for input in currentRoute.inputs {
            if input.portType == .bluetoothHFP ||
               input.portType == .bluetoothA2DP ||
               input.portType == .bluetoothLE {
                return true
            }
        }

        // Check available inputs
        if let availableInputs = audioSession.availableInputs {
            for input in availableInputs {
                if input.portType == .bluetoothHFP ||
                   input.portType == .bluetoothA2DP ||
                   input.portType == .bluetoothLE {
                    return true
                }
            }
        }

        return false
    }

    @objc private func handleAudioRouteChange(notification: Notification) {
        guard !isChangingAudioRoute else { return }
        guard !userExplicitlyChangedAudioRoute else {
            userExplicitlyChangedAudioRoute = false
            return
        }

        // Only send audio route events when there are active calls
        guard !activeCalls.isEmpty else { return }

        let currentRoute = getAudioRoute()
        let btAvailable = isBluetoothAvailable()

        sendPhoneCallEvents(description: "AudioRoute|\(currentRoute)|bluetoothAvailable=\(btAvailable)")
    }

    private func getAudioRoute() -> String {
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute

        for output in currentRoute.outputs {
            switch output.portType {
            case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
                return "bluetooth"
            case .builtInSpeaker:
                return "speaker"
            case .headphones, .headsetMic:
                return "wired_headset"
            default:
                break
            }
        }

        // Fallback: check desired state
        if desiredSpeakerState { return "speaker" }
        if desiredBluetoothState { return "bluetooth" }
        return "earpiece"
    }
}

// MARK: - Permissions

extension VonageVoicePlugin {

    private func handleRequestMicPermission(result: @escaping FlutterResult) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            result(true)
        case .denied:
            result(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                result(granted)
            }
        @unknown default:
            result(false)
        }
    }
}

// MARK: - Caller Registry

extension VonageVoicePlugin {

    private func handleRegisterClient(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let clientId = arguments["id"] as? String,
              let clientName = arguments["name"] as? String else {
            result(false)
            return
        }
        if clients[clientId] == nil || clients[clientId] != clientName {
            clients[clientId] = clientName
            UserDefaults.standard.set(clients, forKey: kClientList)
        }
        result(true)
    }

    private func handleUnregisterClient(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let clientId = arguments["id"] as? String else {
            result(false)
            return
        }
        clients.removeValue(forKey: clientId)
        UserDefaults.standard.set(clients, forKey: kClientList)
        result(true)
    }

    private func handleDefaultCaller(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let caller = arguments["defaultCaller"] as? String else {
            result(false)
            return
        }
        defaultCaller = caller
        if clients["defaultCaller"] == nil || clients["defaultCaller"] != defaultCaller {
            clients["defaultCaller"] = defaultCaller
            UserDefaults.standard.set(clients, forKey: kClientList)
        }
        result(true)
    }
}

// MARK: - CallKit Icon

extension VonageVoicePlugin {

    private func updateCallKitIcon(icon: String) -> Bool {
        guard let newIcon = UIImage(named: icon) else { return false }

        let configuration = callKitProvider.configuration
        configuration.iconTemplateImageData = newIcon.pngData()
        callKitProvider.configuration = configuration
        UserDefaults.standard.set(icon, forKey: kDefaultCallKitIcon)
        return true
    }
}

// MARK: - JWT Persistence

extension VonageVoicePlugin {

    private func storeJwt(_ jwt: String) {
        UserDefaults.standard.set(jwt, forKey: kCachedJwt)
    }

    private func getStoredJwt() -> String? {
        return UserDefaults.standard.string(forKey: kCachedJwt)
    }

    private func clearStoredJwt() {
        UserDefaults.standard.removeObject(forKey: kCachedJwt)
    }
}

// MARK: - CallKit Actions

extension VonageVoicePlugin {

    private func performStartCallAction(uuid: UUID, handle: String) {
        let callHandle = CXHandle(type: .generic, value: handle)
        let startCallAction = CXStartCallAction(call: uuid, handle: callHandle)
        let transaction = CXTransaction(action: startCallAction)

        callKitCallController.request(transaction) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.sendPhoneCallEvents(description: "LOG|StartCallAction failed: \(error.localizedDescription)")
                return
            }

            self.sendPhoneCallEvents(description: "LOG|StartCallAction successful")

            let callUpdate = CXCallUpdate()
            callUpdate.remoteHandle = callHandle
            callUpdate.localizedCallerName = self.outgoingCallerName.isEmpty ? handle : self.outgoingCallerName
            callUpdate.supportsDTMF = true
            callUpdate.supportsHolding = true
            callUpdate.supportsGrouping = false
            callUpdate.supportsUngrouping = false
            callUpdate.hasVideo = false

            self.callKitProvider.reportCall(with: uuid, updated: callUpdate)
        }
    }

    private func reportIncomingCall(from: String, uuid: UUID, completion: ((Error?) -> Void)? = nil) {
        let callHandle = CXHandle(type: .generic, value: from)

        let callUpdate = CXCallUpdate()
        callUpdate.remoteHandle = callHandle
        callUpdate.localizedCallerName = clients[from] ?? from
        callUpdate.supportsDTMF = true
        callUpdate.supportsHolding = true
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false
        callUpdate.hasVideo = false

        callKitProvider.reportNewIncomingCall(with: uuid, update: callUpdate) { [weak self] error in
            if let error = error {
                self?.sendPhoneCallEvents(description: "LOG|reportNewIncomingCall failed: \(error.localizedDescription)")
            } else {
                self?.sendPhoneCallEvents(description: "LOG|Incoming call successfully reported to CallKit")
            }
            completion?(error)
        }
    }

    private func performEndCallAction(uuid: UUID) {
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        callKitCallController.request(transaction) { [weak self] error in
            if let error = error {
                self?.sendPhoneCallEvents(description: "LOG|EndCallAction failed: \(error.localizedDescription)")
            }
        }
    }

    private func callDisconnected(uuid: UUID) {
        let callId = activeCalls[uuid]
        activeCalls.removeValue(forKey: uuid)
        callInvites.removeValue(forKey: uuid)

        // Remove from callId -> UUID mapping
        if let callId = callId {
            callIdToUUID.removeValue(forKey: callId)
        }

        if activeCallUUID == uuid {
            activeCallUUID = nil
        }

        // Reset state when all calls end
        if activeCalls.isEmpty && callInvites.isEmpty {
            callOutgoing = false
            userInitiatedDisconnect = false
            isMuted = false
            isHolding = false
            desiredSpeakerState = false
            desiredBluetoothState = false
            userExplicitlyChangedAudioRoute = false
        }
    }
}

// MARK: - CXProviderDelegate

extension VonageVoicePlugin: CXProviderDelegate {

    public func providerDidReset(_ provider: CXProvider) {
        sendPhoneCallEvents(description: "LOG|providerDidReset")
        // Clean up all calls
        activeCalls.removeAll()
        callInvites.removeAll()
        callIdToUUID.removeAll()
        activeCallUUID = nil
    }

    public func providerDidBegin(_ provider: CXProvider) {
        sendPhoneCallEvents(description: "LOG|providerDidBegin")
    }

    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        sendPhoneCallEvents(description: "LOG|provider:didActivateAudioSession")

        // CRITICAL: Tell the Vonage SDK to start audio.
        // This hooks WebRTC into the CallKit-managed audio session.
        // Without this call, the call connects but no audio flows.
        VGVoiceClient.enableAudio(audioSession)

        // Configure audio session for voice call
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat,
                                        options: [.allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
        } catch {
            sendPhoneCallEvents(description: "LOG|Audio session configuration failed: \(error.localizedDescription)")
        }

        // Apply initial audio route
        if desiredSpeakerState {
            applySpeakerSetting(toSpeaker: true)
        } else if isBluetoothAvailable() {
            desiredBluetoothState = true
            toggleBluetoothAudio(bluetoothOn: true)
        }
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        sendPhoneCallEvents(description: "LOG|provider:didDeactivateAudioSession")

        // Tell the Vonage SDK to stop audio when CallKit deactivates the session.
        VGVoiceClient.disableAudio(audioSession)
    }

    public func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        sendPhoneCallEvents(description: "LOG|provider:timedOutPerformingAction")
    }

    // MARK: Start Call

    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        sendPhoneCallEvents(description: "LOG|provider:performStartCallAction")

        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())

        // Build call context from stored arguments
        var context: [String: String] = [:]
        for (key, value) in callArgs {
            if key != "from" {
                context[key] = "\(value)"
            }
        }

        // Send Ringing event
        let from = identity
        let to = callTo
        sendPhoneCallEvents(description: "Ringing|\(from)|\(to)|Outgoing")

        voiceClient.serverCall(context) { [weak self] error, callId in
            guard let self = self else { return }
            if let error = error {
                self.sendPhoneCallEvents(description: "LOG|serverCall failed: \(error.localizedDescription)")
                provider.reportCall(with: action.callUUID, endedAt: Date(), reason: .failed)
                self.sendPhoneCallEvents(description: "Call Ended")
                action.fail()
                return
            }

            guard let callId = callId else {
                self.sendPhoneCallEvents(description: "LOG|serverCall returned nil callId")
                action.fail()
                return
            }

            self.sendPhoneCallEvents(description: "LOG|serverCall success, callId=\(callId)")
            self.activeCalls[action.callUUID] = callId
            self.callIdToUUID[callId] = action.callUUID
            self.activeCallUUID = action.callUUID
            self.userExplicitlyChangedAudioRoute = false

            provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
            self.sendPhoneCallEvents(description: "Connected|\(from)|\(to)|Outgoing")

            action.fulfill()
        }
    }

    // MARK: Answer Call

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        sendPhoneCallEvents(description: "LOG|provider:performAnswerCallAction uuid=\(action.callUUID)")

        guard let invite = callInvites[action.callUUID] else {
            sendPhoneCallEvents(description: "LOG|No call invite found for uuid=\(action.callUUID)")
            action.fail()
            return
        }

        voiceClient.answer(invite.callId) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.sendPhoneCallEvents(description: "LOG|answer failed: \(error.localizedDescription)")
                action.fail()
                return
            }

            self.sendPhoneCallEvents(description: "LOG|Call answered successfully callId=\(invite.callId)")

            // Move from invites to active calls
            self.activeCalls[action.callUUID] = invite.callId
            self.callIdToUUID[invite.callId] = action.callUUID
            self.activeCallUUID = action.callUUID
            self.callInvites.removeValue(forKey: action.callUUID)
            self.userExplicitlyChangedAudioRoute = false

            let from = invite.from
            let to = invite.to

            self.sendPhoneCallEvents(description: "Answer|\(from)|\(to)|Incoming")
            self.sendPhoneCallEvents(description: "Connected|\(from)|\(to)|Incoming")

            self.callKitCompletionCallback?(true)
            action.fulfill()
        }
    }

    // MARK: End Call

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        sendPhoneCallEvents(description: "LOG|provider:performEndCallAction uuid=\(action.callUUID)")

        // Check if it's a pending invite — reject it
        if let invite = callInvites[action.callUUID] {
            sendPhoneCallEvents(description: "LOG|Rejecting invite id=\(invite.callId)")
            voiceClient.reject(invite.callId) { [weak self] error in
                if let error = error {
                    self?.sendPhoneCallEvents(description: "LOG|reject failed: \(error.localizedDescription)")
                }
            }
            callInvites.removeValue(forKey: action.callUUID)
            callIdToUUID.removeValue(forKey: invite.callId)
            callDisconnected(uuid: action.callUUID)
            sendPhoneCallEvents(description: "Declined")
        } else if let callId = activeCalls[action.callUUID] {
            // Active call — hang up
            sendPhoneCallEvents(description: "LOG|Hanging up active call callId=\(callId)")
            voiceClient.hangup(callId) { [weak self] error in
                if let error = error {
                    self?.sendPhoneCallEvents(description: "LOG|hangup failed: \(error.localizedDescription)")
                }
            }
            callDisconnected(uuid: action.callUUID)
            sendPhoneCallEvents(description: "Call Ended")
        } else {
            callDisconnected(uuid: action.callUUID)
        }

        action.fulfill()
    }

    // MARK: Hold Call

    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        sendPhoneCallEvents(description: "LOG|provider:performSetHeldAction uuid=\(action.callUUID) isOnHold=\(action.isOnHold)")

        if let callId = activeCalls[action.callUUID] {
            if action.isOnHold {
                isHolding = true
                voiceClient.mute(callId) { _ in }
                sendPhoneCallEvents(description: "Hold")
            } else {
                isHolding = false
                voiceClient.unmute(callId) { _ in }
                activeCallUUID = action.callUUID
                sendPhoneCallEvents(description: "Unhold")
            }
            action.fulfill()
        } else {
            action.fail()
        }
    }

    // MARK: Mute Call

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        sendPhoneCallEvents(description: "LOG|provider:performSetMutedAction uuid=\(action.callUUID) isMuted=\(action.isMuted)")

        if let callId = activeCalls[action.callUUID] {
            if action.isMuted {
                voiceClient.mute(callId) { _ in }
                isMuted = true
            } else {
                voiceClient.unmute(callId) { _ in }
                isMuted = false
            }
            sendPhoneCallEvents(description: action.isMuted ? "Mute" : "Unmute")
            action.fulfill()
        } else {
            action.fail()
        }
    }
}

// MARK: - PKPushRegistryDelegate

extension VonageVoicePlugin: PKPushRegistryDelegate {

    public func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        NSLog("[VonageVoice-Push] didUpdatePushCredentials type=%@", String(describing: type))
        sendPhoneCallEvents(description: "LOG|pushRegistry:didUpdatePushCredentials")

        guard type == .voIP else { return }

        let token = pushCredentials.token
        self.deviceToken = token

        let hexToken = token.map { String(format: "%02x", $0) }.joined()
        NSLog("[VonageVoice-Push] VoIP token (%d bytes): %@", token.count, hexToken)
        sendPhoneCallEvents(description: "LOG|VoIP push token received (\(token.count) bytes) hex=\(hexToken)")

        // If we already have an access token, register the push token
        if accessToken != nil {
            registerPushToken(token)
        }
    }

    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        sendPhoneCallEvents(description: "LOG|pushRegistry:didInvalidatePushTokenForType")

        guard type == .voIP else { return }

        if let deviceId = self.deviceId {
            voiceClient.unregisterDeviceTokens(byDeviceId: deviceId) { [weak self] error in
                if let error = error {
                    self?.sendPhoneCallEvents(description: "LOG|unregisterDeviceTokens failed: \(error.localizedDescription)")
                }
            }
        }
    }

    public func pushRegistry(_ registry: PKPushRegistry,
                            didReceiveIncomingPushWith payload: PKPushPayload,
                            for type: PKPushType,
                            completion: @escaping () -> Void) {
        NSLog("[VonageVoice-Push] *** didReceiveIncomingPush *** type=%@", String(describing: type))
        NSLog("[VonageVoice-Push] Push payload keys: %@", payload.dictionaryPayload.keys.map { String(describing: $0) }.joined(separator: ", "))
        sendPhoneCallEvents(description: "LOG|pushRegistry:didReceiveIncomingPush")

        guard type == .voIP else {
            completion()
            return
        }

        // MUST report the incoming call to CallKit before returning from this method.
        // Apple kills the app if a VoIP push doesn't result in a reportNewIncomingCall.

        // Process with Vonage SDK — the delegate callback will handle the call invite
        let pushType = VGBaseClient.vonagePushType(payload.dictionaryPayload)
        NSLog("[VonageVoice-Push] Vonage push type: %@", String(describing: pushType))
        if pushType == .incomingCall {
            // If no session exists, try to restore from stored JWT
            if accessToken == nil, let storedJwt = getStoredJwt() {
                sendPhoneCallEvents(description: "LOG|Restoring session from stored JWT for push processing")
                accessToken = storedJwt
                voiceClient.createSession(storedJwt) { [weak self] error, sessionId in
                    guard let self = self else {
                        completion()
                        return
                    }
                    if let error = error {
                        self.sendPhoneCallEvents(description: "LOG|Session restore failed: \(error.localizedDescription)")
                        // Still need to report a call to CallKit — report and immediately end
                        let uuid = UUID()
                        self.reportIncomingCall(from: "Unknown", uuid: uuid) { _ in
                            self.callKitProvider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
                            completion()
                        }
                        return
                    }
                    self.voiceClient.processCallInvitePushData(payload.dictionaryPayload)
                    completion()
                }
            } else {
                voiceClient.processCallInvitePushData(payload.dictionaryPayload)
                completion()
            }
        } else {
            // Not a Vonage push — still need to report to CallKit to satisfy PushKit requirement
            let uuid = UUID()
            reportIncomingCall(from: "Unknown", uuid: uuid) { [weak self] _ in
                self?.callKitProvider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
                completion()
            }
        }
    }

    // iOS < 13 fallback
    public func pushRegistry(_ registry: PKPushRegistry,
                            didReceiveIncomingPushWith payload: PKPushPayload,
                            for type: PKPushType) {
        sendPhoneCallEvents(description: "LOG|pushRegistry:didReceiveIncomingPush (legacy)")

        guard type == .voIP else { return }

        let pushType = VGBaseClient.vonagePushType(payload.dictionaryPayload)
        if pushType == .incomingCall {
            voiceClient.processCallInvitePushData(payload.dictionaryPayload)
        }
    }
}

// MARK: - VGVoiceClientDelegate

extension VonageVoicePlugin: VGVoiceClientDelegate {

    public func voiceClient(_ client: VGVoiceClient, didReceiveInviteForCall callId: String, from caller: String, with type: VGVoiceChannelType) {
        NSLog("[VonageVoice-Push] *** didReceiveInviteForCall *** callId=%@ from=%@", callId, caller)
        sendPhoneCallEvents(description: "LOG|didReceiveInviteForCall callId=\(callId), from=\(caller)")

        // Deduplicate: if we already have an invite for this callId (e.g. from
        // both WebSocket and push processing), ignore the duplicate.
        if callIdToUUID[callId] != nil {
            sendPhoneCallEvents(description: "LOG|Duplicate invite for callId=\(callId), ignoring")
            return
        }

        let uuid = UUID()
        let callerDisplay = clients[caller] ?? caller
        let invite = CallInviteInfo(callId: callId, from: caller, to: identity)
        callInvites[uuid] = invite
        callIdToUUID[callId] = uuid

        // Send Incoming event to Flutter (matches Dart parser's "Incoming|from|to|direction" format)
        sendPhoneCallEvents(description: "Incoming|\(caller)|\(identity)|Incoming")

        // Report to CallKit
        reportIncomingCall(from: callerDisplay, uuid: uuid)
    }

    public func voiceClient(_ client: VGVoiceClient, didReceiveInviteCancelForCall callId: String, with reason: VGVoiceInviteCancelReason) {
        NSLog("[VonageVoice-Push] *** didReceiveInviteCancelForCall *** callId=%@ reason=%@", callId, String(describing: reason))
        sendPhoneCallEvents(description: "LOG|didReceiveInviteCancelForCall callId=\(callId), reason=\(reason)")

        // Find and remove the matching call invite
        if let uuid = callIdToUUID[callId] {
            callInvites.removeValue(forKey: uuid)
            callIdToUUID.removeValue(forKey: callId)

            // Use provider API to end the call — NOT performEndCallAction.
            // performEndCallAction goes through CXCallController (user-initiated end)
            // which can race with reportNewIncomingCall. reportCall(endedAt:reason:)
            // is the correct API for server-initiated cancellation and works even if
            // CallKit hasn't fully processed the incoming call report yet.
            callKitProvider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
            callDisconnected(uuid: uuid)
        }

        if activeCalls.isEmpty {
            sendPhoneCallEvents(description: "Missed Call")
        }
    }

    public func voiceClient(_ client: VGVoiceClient, didReceiveHangupForCall callId: String, withQuality callQuality: VGRTCQuality, reason: VGHangupReason) {
        sendPhoneCallEvents(description: "LOG|didReceiveHangupForCall callId=\(callId), reason=\(reason)")

        if let uuid = callIdToUUID[callId] {
            if !userInitiatedDisconnect {
                callKitProvider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
            }
            callDisconnected(uuid: uuid)

            if activeCalls.isEmpty {
                sendPhoneCallEvents(description: "Call Ended")
            }
        }
    }

    public func voiceClient(_ client: VGVoiceClient, didReceiveMediaReconnectingForCall callId: String) {
        sendPhoneCallEvents(description: "Reconnecting")
    }

    public func voiceClient(_ client: VGVoiceClient, didReceiveMediaReconnectionForCall callId: String) {
        sendPhoneCallEvents(description: "Reconnected")
    }

    public func voiceClient(_ client: VGVoiceClient, didReceiveMediaErrorForCall callId: String, error: VGError) {
        sendPhoneCallEvents(description: "LOG|didReceiveMediaError callId=\(callId), error=\(error.localizedDescription)")
    }

    public func voiceClient(_ client: VGVoiceClient, didReceiveMuteForCall callId: String, withLegId legId: String, andStatus isMuted: DarwinBoolean) {
        let muted = isMuted.boolValue
        sendPhoneCallEvents(description: "LOG|didReceiveMute callId=\(callId), isMuted=\(muted)")
        self.isMuted = muted
        sendPhoneCallEvents(description: muted ? "Mute" : "Unmute")
    }

    public func client(_ client: VGBaseClient, didReceiveSessionErrorWith reason: VGSessionErrorReason) {
        sendPhoneCallEvents(description: "LOG|didReceiveSessionError reason=\(reason)")

        if reason == .tokenExpired || reason == VGSessionErrorReason.tokenExpired {
            sendPhoneCallEvents(description: "DEVICETOKEN|expired")
        }
    }
}

// MARK: - Helper Types

struct CallInviteInfo {
    let callId: String
    let from: String
    let to: String
    var customParams: [String: Any]? = nil
}
