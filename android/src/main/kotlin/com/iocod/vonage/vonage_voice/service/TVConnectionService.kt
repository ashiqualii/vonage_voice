package com.iocod.vonage.vonage_voice.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import androidx.core.app.NotificationCompat
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.iocod.vonage.vonage_voice.call.TVCallConnection
import com.iocod.vonage.vonage_voice.call.TVCallInviteConnection
import com.iocod.vonage.vonage_voice.constants.Constants
import com.iocod.vonage.vonage_voice.IncomingCallActivity
import com.iocod.vonage.vonage_voice.AnswerCallTrampolineActivity
import com.vonage.voice.api.VoiceClient
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.content.BroadcastReceiver
import android.content.IntentFilter
import androidx.core.app.Person

/**
 * TVConnectionService — TelecomVoice ConnectionService.
 *
 * Extends Android's [ConnectionService] to integrate Vonage voice calls
 * with the Android Telecom framework. This enables:
 *   - Native system call UI (incoming call screen, in-call screen)
 *   - Bluetooth headset support
 *   - Car kit / wearable integration
 *   - Proper audio focus management
 *
 * Communication flow:
 *
 *   VonageVoicePlugin → startService(Intent) → onStartCommand()
 *        ↓
 *   TVConnectionService handles call actions (answer, hangup, mute etc.)
 *        ↓
 *   Vonage VoiceClient SDK calls
 *        ↓
 *   LocalBroadcast events → TVBroadcastReceiver → VonageVoicePlugin → Flutter
 *
 * Active connections are tracked in [activeConnections] map keyed by callId.
 * Invite connections are tracked in [pendingInvites] map keyed by callId.
 */
class TVConnectionService : ConnectionService() {

    private lateinit var broadcastManager: LocalBroadcastManager
    private var audioFocusRequest: AudioFocusRequest? = null
    private var audioDeviceCallback: AudioDeviceCallback? = null
    private var scoReceiver: BroadcastReceiver? = null
    private var incomingCallWakeLock: PowerManager.WakeLock? = null

    // ── Service-level ringtone & vibration ────────────────────────────────
    // Ringing is managed by the service (not IncomingCallActivity) so it
    // works reliably in background and locked states where the activity
    // may fail to launch due to BAL restrictions.
    private var serviceRingtone: Ringtone? = null
    private var serviceVibrator: Vibrator? = null
    private var isServiceRinging = false

    companion object {
        /**
         * Map of currently active call connections keyed by callId.
         * Accessed by VonageVoicePlugin to query call state.
         */
        val activeConnections: HashMap<String, TVCallConnection> = HashMap()

        /**
         * Map of pending incoming call invite connections keyed by callId.
         * Moved to activeConnections once the call is answered.
         */
        val pendingInvites: HashMap<String, TVCallInviteConnection> = HashMap()

        /**
         * Returns true if there is at least one active call connection.
         */
        fun hasActiveCall(): Boolean = activeConnections.isNotEmpty()

        /**
         * Returns the callId of the first active connection, or null.
         */
        fun getActiveCallId(): String? = activeConnections.keys.firstOrNull()

        /**
         * Returns the first active TVCallConnection, or null.
         * Used by VonageVoicePlugin for direct state updates (e.g. selectAudioDevice).
         */
        fun getActiveConnection(): TVCallConnection? = activeConnections.values.firstOrNull()
    }

    // ── Service lifecycle ─────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        broadcastManager = LocalBroadcastManager.getInstance(this)

        // Clean up the old notification channel that had sound/vibration.
        // Must happen here (before any startForeground call) because
        // Android throws SecurityException if you delete a channel while
        // a foreground service is using it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.deleteNotificationChannel(Constants.INCOMING_CALL_CHANNEL_ID_OLD)
        }
    }

    /**
     * Entry point for all actions sent from VonageVoicePlugin via
     * startService() or startForegroundService(Intent).
     *
     * When started via startForegroundService(), Android requires
     * startForeground() to be called within 5 seconds. We ensure
     * this by immediately promoting to foreground for any action
     * that arrives while the service is not yet in foreground.
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Ensure we satisfy the startForeground contract for every
        // startForegroundService() call. If the service is already in
        // foreground (from handleIncomingCall), this is a no-op update.
        ensureForeground(intent?.action)
        intent?.let { handleIntent(it) }
        return START_NOT_STICKY
    }

    /**
     * Ensures the service is promoted to foreground.
     * Called early in onStartCommand to prevent the 5-second ANR
     * when the service is started via startForegroundService().
     *
     * [intentAction] is used to determine the notification type BEFORE
     * the intent is fully processed. This ensures the very first
     * startForeground() call uses the HIGH importance incoming call
     * channel when appropriate, so the notification is always visible
     * on devices that "sticky" the first channel importance.
     */
    private fun ensureForeground(intentAction: String? = null) {
        createNotificationChannel()
        createIncomingCallNotificationChannel()

        val isIncomingAction = intentAction == Constants.ACTION_INCOMING_CALL
                || intentAction == Constants.ACTION_ANSWER

        val notification = if (pendingInvites.isNotEmpty()) {
            val entry = pendingInvites.entries.first()
            buildIncomingCallNotification(entry.key, entry.value.from)
        } else if (isIncomingAction) {
            // Incoming call intent is about to be processed — use a
            // placeholder notification on the HIGH channel WITHOUT action
            // buttons. Real Answer/Decline buttons are added when
            // handleIncomingCall() rebuilds with the actual callId.
            buildPlaceholderIncomingNotification()
        } else if (activeConnections.isNotEmpty()) {
            buildActiveCallNotification()
        } else {
            buildActiveCallNotification()
        }

        // For incoming calls, use PHONE_CALL type (doesn't require RECORD_AUDIO).
        // For active calls, use MICROPHONE type (already have permission by then).
        val serviceType = if (isIncomingAction || pendingInvites.isNotEmpty()) {
            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
        } else {
            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(Constants.NOTIFICATION_ID, notification, serviceType)
        } else {
            startForeground(Constants.NOTIFICATION_ID, notification)
        }

        // Acquire FULL_WAKE_LOCK for incoming calls to physically turn the screen on.
        // Without this, the fullScreenIntent may not fire on some devices.
        if (isIncomingAction && incomingCallWakeLock == null) {
            acquireIncomingCallWakeLock()
        }
    }

    // override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    // ── Intent dispatcher ─────────────────────────────────────────────────

    /**
     * Routes incoming intents to the correct handler based on action string.
     * All actions are defined in [Constants].
     */
    private fun handleIntent(intent: Intent) {
        when (intent.action) {
            Constants.ACTION_INCOMING_CALL -> handleIncomingCall(intent)
            Constants.ACTION_CANCEL_CALL_INVITE -> handleCancelCallInvite(intent)
            Constants.ACTION_PLACE_OUTGOING_CALL -> handleOutgoingCall(intent)
            Constants.ACTION_ANSWER -> handleAnswer(intent)
            Constants.ACTION_HANGUP -> handleHangup(intent)
            Constants.ACTION_SEND_DIGITS -> handleSendDigits(intent)
            Constants.ACTION_TOGGLE_SPEAKER -> handleToggleSpeaker(intent)
            Constants.ACTION_TOGGLE_BLUETOOTH -> handleToggleBluetooth(intent)
            Constants.ACTION_TOGGLE_MUTE -> handleToggleMute(intent)
            Constants.ACTION_TOGGLE_HOLD -> handleToggleHold(intent)
            Constants.ACTION_CLEANUP -> handleCleanup()
        }
    }

    // ── Incoming call handling ────────────────────────────────────────────

    /**
     * Called when FCM push delivers an incoming call invite.
     * Creates a [TVCallInviteConnection] and notifies the Telecom system
     * so it can show the native incoming call UI.
     *
     * Intent extras required:
     *   EXTRA_CALL_ID   — Vonage callId string
     *   EXTRA_CALL_FROM — caller display name or number
     *   EXTRA_CALL_TO   — callee (this device's identity)
     */
    private fun handleIncomingCall(intent: Intent) {
        val callId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return
        val from = intent.getStringExtra(Constants.EXTRA_CALL_FROM)
                ?: Constants.DEFAULT_UNKNOWN_CALLER
        val to = intent.getStringExtra(Constants.EXTRA_CALL_TO) ?: ""

        // Skip if we already have a pending invite for this callId (duplicate FCM processing)
        if (pendingInvites.containsKey(callId)) {
            android.util.Log.d("TVConnectionService", "Duplicate incoming call for callId=$callId — skipping")
            return
        }

        val connection = TVCallInviteConnection(this, callId, from, to)
        pendingInvites[callId] = connection

        // ── Use incoming call notification with Answer/Decline ────────────────
        createIncomingCallNotificationChannel()
        // Use PHONE_CALL type — RECORD_AUDIO is not yet granted before the user answers.
        // MICROPHONE type requires RECORD_AUDIO permission and will crash on API 34+.
        val incomingNotification = buildIncomingCallNotification(callId, from)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                Constants.NOTIFICATION_ID,
                incomingNotification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            )
        } else {
            startForeground(Constants.NOTIFICATION_ID, incomingNotification)
        }

        // Also post via NotificationManager.notify() to ensure fullScreenIntent
        // re-fires on devices where updating the foreground notification (same ID)
        // does NOT re-trigger the full-screen intent (Samsung, Xiaomi, etc.)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(Constants.NOTIFICATION_ID, incomingNotification)

        // Acquire wake lock to ensure the screen turns on for incoming call
        if (incomingCallWakeLock == null) {
            acquireIncomingCallWakeLock()
        }

        // ── Start ringing from the service ─────────────────────────────
        // Ringing is managed by the service so it works reliably in all
        // app states (foreground, background, locked, killed). The service
        // is always alive at this point because onStartCommand → ensureForeground
        // has already been called.
        startServiceRinging()

        // ── Launch IncomingCallActivity only when Flutter is NOT attached ──
        // When Flutter is alive (foreground), Flutter's own IncomingCallScreen
        // handles the UI via the BROADCAST_CALL_INVITE event below.
        // When Flutter is NOT attached (background/killed/locked), the native
        // IncomingCallActivity provides answer/decline buttons over the lock
        // screen. The activity no longer handles ringing — the service does.
        if (!VonageClientHolder.isFlutterEngineAttached) {
            try {
                val directIntent = IncomingCallActivity.createIntent(applicationContext, callId, from)
                directIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                applicationContext.startActivity(directIntent)
            } catch (e: Exception) {
                android.util.Log.e("TVConnectionService", "Direct IncomingCallActivity launch failed: ${e.message}")
            }
        } else {
            android.util.Log.d("TVConnectionService", "Flutter attached — skipping native IncomingCallActivity")
        }

        val broadcast = Intent(Constants.BROADCAST_CALL_INVITE).apply {
            putExtra(Constants.EXTRA_CALL_ID, callId)
            putExtra(Constants.EXTRA_CALL_FROM, from)
            putExtra(Constants.EXTRA_CALL_TO, to)
        }
        broadcastManager.sendBroadcast(broadcast)
    }

    /**
     * Called when the remote party cancels the invite before it is answered.
     * Cleans up the pending invite connection and notifies Flutter.
     *
     * Intent extras required:
     *   EXTRA_CALL_ID — callId of the invite to cancel
     */
    private fun handleCancelCallInvite(intent: Intent) {
        val callId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return

        // Stop ringing — call is being cancelled
        stopServiceRinging()

        // Release the incoming call wake lock — call is being cancelled
        releaseIncomingCallWakeLock()

        // cancel() internally broadcasts BROADCAST_CALL_INVITE_CANCELLED
        // so we must not broadcast again to avoid duplicate Missed Call events
        pendingInvites[callId]?.cancel()
        pendingInvites.remove(callId)

        if (activeConnections.isEmpty() && pendingInvites.isEmpty()) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
            notificationManager.cancel(Constants.NOTIFICATION_ID)
            stopForeground(true)
            stopSelf()
        }
    }

    // ── Outgoing call handling ────────────────────────────────────────────

    /**
     * Called from VonageVoicePlugin.makeCall() to place an outbound call.
     * Creates a [TVCallConnection] and starts the Vonage SDK serverCall().
     *
     * Intent extras required:
     *   EXTRA_JWT             — Vonage JWT (passed from Flutter, never hardcoded)
     *   EXTRA_CALL_TO         — destination number / user
     *   EXTRA_CALL_FROM       — caller identity
     *   EXTRA_OUTGOING_PARAMS — optional HashMap<String,String> custom params
     */
    private fun handleOutgoingCall(intent: Intent) {
        // All call params come from Flutter via Intent extras — nothing hardcoded
        val callTo = intent.getStringExtra(Constants.EXTRA_CALL_TO) ?: return
        val callFrom = intent.getStringExtra(Constants.EXTRA_CALL_FROM) ?: ""

        @Suppress("UNCHECKED_CAST")
        val customParams = intent.getSerializableExtra(Constants.EXTRA_OUTGOING_PARAMS)
                as? HashMap<String, String> ?: HashMap()

        // Build context map for Vonage serverCall()
        // Backend expects capitalized keys: "To" and "From"
        val callContext = HashMap<String, String>().apply {
            put("To", callTo)
            if (callFrom.isNotEmpty()) put("From", callFrom)
            putAll(customParams)
        }

        // Get VoiceClient instance held by the plugin
        val client = VonageClientHolder.voiceClient ?: run {
            broadcastError("VoiceClient not initialised — call tokens() first")
            return
        }

        // Place the call via Vonage SDK
        client.serverCall(callContext) { error, callId ->
            if (error != null) {
                broadcastError("serverCall failed: ${error.message}")
                return@serverCall
            }

            if (callId.isNullOrEmpty()) {
                broadcastError("serverCall returned null callId")
                return@serverCall
            }

            // Create Telecom connection for this outgoing call
            val connection = TVCallConnection(this, callId, callFrom, callTo)
            activeConnections[callId] = connection
            connection.setCallActive()
            requestAudioFocus() 

            startCallForegroundService()

            // Broadcast ringing event to Flutter
            val broadcast = Intent(Constants.BROADCAST_CALL_RINGING).apply {
                putExtra(Constants.EXTRA_CALL_ID, callId)
                putExtra(Constants.EXTRA_CALL_FROM, callFrom)
                putExtra(Constants.EXTRA_CALL_TO, callTo)
            }
            broadcastManager.sendBroadcast(broadcast)
        }
    }

    // ── Answer ────────────────────────────────────────────────────────────

    /**
     * Answer a pending incoming call invite.
     * Moves the connection from pendingInvites → activeConnections.
     *
     * Intent extras required:
     *   EXTRA_CALL_ID — callId of the invite to answer
     */

     private fun requestAudioFocus() {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                .build()
                        )
                        .build()
                    audioFocusRequest = focusRequest
                    audioManager.requestAudioFocus(focusRequest)
                } else {
                    @Suppress("DEPRECATION")
                    audioManager.requestAudioFocus(
                        null,
                        AudioManager.STREAM_VOICE_CALL,
                        AudioManager.AUDIOFOCUS_GAIN
                    )
                }

                // Set audio mode to voice call — critical for microphone to work
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                audioManager.isSpeakerphoneOn = false
                audioManager.isMicrophoneMute = false

                // Broadcast speaker=off and mute=off so Flutter UI starts in the correct state
                val speakerOffBroadcast = Intent(Constants.BROADCAST_SPEAKER_STATE).apply {
                    putExtra("state", false)
                }
                broadcastManager.sendBroadcast(speakerOffBroadcast)

                val muteOffBroadcast = Intent(Constants.BROADCAST_MUTE_STATE).apply {
                    putExtra("state", false)
                }
                broadcastManager.sendBroadcast(muteOffBroadcast)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    // API 31+ — prefer Bluetooth if connected, otherwise earpiece
                    val devices = audioManager.availableCommunicationDevices
                    val bluetoothDevice = devices.firstOrNull {
                        it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                        it.type == android.media.AudioDeviceInfo.TYPE_BLE_HEADSET
                    }
                    val targetDevice = bluetoothDevice
                        ?: devices.firstOrNull {
                            it.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                        }
                    targetDevice?.let { audioManager.setCommunicationDevice(it) }

                    // Broadcast BT state so Flutter UI updates immediately
                    if (bluetoothDevice != null) {
                        val btBroadcast = Intent(Constants.BROADCAST_BLUETOOTH_STATE).apply {
                            putExtra("state", true)
                        }
                        broadcastManager.sendBroadcast(btBroadcast)
                    }
                } else {
                    // Pre-API 31 — only route to BT if a device is actually connected
                    val btOutputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    val hasBtDevice = btOutputs.any {
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                    }
                    if (hasBtDevice && audioManager.isBluetoothScoAvailableOffCall) {
                        audioManager.startBluetoothSco()
                        audioManager.isBluetoothScoOn = true
                        // Actual BT connected state is confirmed via SCO state listener
                    }
                }

                registerBluetoothMonitor()
    }

    private fun releaseAudioFocus() {
        unregisterBluetoothMonitor()
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }

        audioManager.mode = AudioManager.MODE_NORMAL
        audioManager.isSpeakerphoneOn = false
        audioManager.isMicrophoneMute = false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        } else {
            // Stop Bluetooth SCO if it was started
            if (audioManager.isBluetoothScoOn) {
                audioManager.stopBluetoothSco()
                audioManager.isBluetoothScoOn = false
            }
        }
    }


    // ── Bluetooth device monitoring ──────────────────────────────────────

    /**
     * Registers an AudioDeviceCallback to detect Bluetooth device
     * connections and disconnections during an active call.
     *
     * - When a BT device connects: auto-route audio to it (like native phone app)
     * - When a BT device disconnects: fall back to earpiece and notify Flutter
     */
    private fun registerBluetoothMonitor() {
        if (audioDeviceCallback != null) return
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        val callback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
                if (activeConnections.isEmpty()) return

                val btAdded = addedDevices.any { isBluetoothAudioDevice(it.type) }
                if (!btAdded) return

                // Check if already on BT — skip if so (deduplicate with onCallAudioStateChanged)
                val conn = activeConnections.values.firstOrNull()
                if (conn?.isBluetoothOn == true) return

                // Auto-route to BT like the native phone app
                audioManager.isSpeakerphoneOn = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val devices = audioManager.availableCommunicationDevices
                    val btDevice = devices.firstOrNull { isBluetoothAudioDevice(it.type) }
                    btDevice?.let { audioManager.setCommunicationDevice(it) }
                } else {
                    audioManager.startBluetoothSco()
                    audioManager.isBluetoothScoOn = true
                }

                // Update connection state
                conn?.let {
                    it.isBluetoothOn = true
                    if (it.isSpeakerOn) {
                        it.isSpeakerOn = false
                    }
                }

                val broadcast = Intent(Constants.BROADCAST_BLUETOOTH_STATE).apply {
                    putExtra("state", true)
                }
                broadcastManager.sendBroadcast(broadcast)
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
                if (activeConnections.isEmpty()) return

                val btRemoved = removedDevices.any { isBluetoothAudioDevice(it.type) }
                if (!btRemoved) return

                // Check if already off BT — skip if so (deduplicate)
                val conn = activeConnections.values.firstOrNull()
                if (conn?.isBluetoothOn == false) return

                // Fall back to earpiece
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val devices = audioManager.availableCommunicationDevices
                    val earpiece = devices.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                    }
                    earpiece?.let { audioManager.setCommunicationDevice(it) }
                } else {
                    audioManager.stopBluetoothSco()
                    audioManager.isBluetoothScoOn = false
                }

                // Update connection state
                conn?.let { it.isBluetoothOn = false }

                val broadcast = Intent(Constants.BROADCAST_BLUETOOTH_STATE).apply {
                    putExtra("state", false)
                }
                broadcastManager.sendBroadcast(broadcast)
            }
        }

        audioDeviceCallback = callback
        audioManager.registerAudioDeviceCallback(callback, null)

        // Pre-API 31: listen for SCO audio state changes to confirm BT link
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && scoReceiver == null) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(ctx: Context, intent: Intent) {
                    if (intent.action != AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED) return
                    val state = intent.getIntExtra(
                        AudioManager.EXTRA_SCO_AUDIO_STATE,
                        AudioManager.SCO_AUDIO_STATE_DISCONNECTED
                    )
                    val conn = activeConnections.values.firstOrNull() ?: return
                    when (state) {
                        AudioManager.SCO_AUDIO_STATE_CONNECTED -> {
                            if (!conn.isBluetoothOn) {
                                conn.isBluetoothOn = true
                                val bc = Intent(Constants.BROADCAST_BLUETOOTH_STATE).apply {
                                    putExtra("state", true)
                                }
                                broadcastManager.sendBroadcast(bc)
                            }
                        }
                        AudioManager.SCO_AUDIO_STATE_DISCONNECTED -> {
                            if (conn.isBluetoothOn) {
                                conn.isBluetoothOn = false
                                val bc = Intent(Constants.BROADCAST_BLUETOOTH_STATE).apply {
                                    putExtra("state", false)
                                }
                                broadcastManager.sendBroadcast(bc)
                            }
                        }
                    }
                }
            }
            scoReceiver = receiver
            val filter = IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
            registerReceiver(receiver, filter)
        }
    }

    private fun unregisterBluetoothMonitor() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioDeviceCallback?.let { audioManager.unregisterAudioDeviceCallback(it) }
        audioDeviceCallback = null

        scoReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        scoReceiver = null
    }

    private fun isBluetoothAudioDevice(type: Int): Boolean {
        return type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
               (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                type == AudioDeviceInfo.TYPE_BLE_HEADSET)
    }

    private fun handleAnswer(intent: Intent) {
        val callId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return

        // Stop ringing — call is being answered
        stopServiceRinging()

        // Release the incoming call wake lock — call is being answered
        releaseIncomingCallWakeLock()

        val client = VonageClientHolder.voiceClient ?: run {
            broadcastError("VoiceClient not initialised")
            return
        }

        doAnswer(client, callId, retriesLeft = 2)
    }

    /**
     * Attempt to answer the call. If it fails (e.g. session not yet
     * restored after app-kill), retry up to [retriesLeft] times with
     * a 1.5-second delay. This covers the race between
     * VonageFirebaseMessagingService.createSession() and the user
     * tapping Answer very quickly.
     */
    private fun doAnswer(client: VoiceClient, callId: String, retriesLeft: Int) {
        VonageClientHolder.isAnsweringInProgress = true
        client.answer(callId) { error ->
            if (error != null) {
                android.util.Log.e("TVConnectionService",
                    "answer failed (retries=$retriesLeft): ${error.message}")
                if (retriesLeft > 0) {
                    android.util.Log.d("TVConnectionService",
                        "Retrying answer in 1500ms...")
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        doAnswer(client, callId, retriesLeft - 1)
                    }, 1500)
                } else {
                    VonageClientHolder.isAnsweringInProgress = false
                    broadcastError("answer failed: ${error.message}")
                }
                return@answer
            }

            // Mark that the call was answered via the native path so that
            // registerVoiceClientListeners() (called when Flutter starts)
            // does not overwrite the setCallInviteListener and interfere
            // with this already-answered call.
            VonageClientHolder.isAnsweringInProgress = false
            VonageClientHolder.isCallAnsweredNatively = true

            // Promote invite connection to active connection
            val invite = pendingInvites.remove(callId)
            val connection = TVCallConnection(
                this,
                callId,
                invite?.from ?: "",
                invite?.to ?: ""
            )
            activeConnections[callId] = connection
            connection.setCallActive()
            requestAudioFocus() 

            // ── Switch notification from incoming → active call ───────────────────
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
            notificationManager.notify(Constants.NOTIFICATION_ID, buildActiveCallNotification())

            // Broadcast connected event to Flutter
            val broadcast = Intent(Constants.BROADCAST_CALL_CONNECTED).apply {
                putExtra(Constants.EXTRA_CALL_ID, callId)
                putExtra(Constants.EXTRA_CALL_FROM, invite?.from ?: "")
                putExtra(Constants.EXTRA_CALL_TO, invite?.to ?: "")
                putExtra(Constants.EXTRA_CALL_DIRECTION, "INCOMING")
            }
            broadcastManager.sendBroadcast(broadcast)
        }
    }

    // ── Hangup ────────────────────────────────────────────────────────────

    /**
     * Hang up or reject a call.
     * Works for both active calls and pending invites.
     *
     * Intent extras required:
     *   EXTRA_CALL_ID — callId to hang up
     */
    private fun handleHangup(intent: Intent) {
        val callId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return

        // Stop ringing — call is being declined/ended
        stopServiceRinging()

        // Release the incoming call wake lock — call is being declined/ended
        releaseIncomingCallWakeLock()

        val client = VonageClientHolder.voiceClient ?: run {
            broadcastError("VoiceClient not initialised")
            return
        }

        // Check if this is a pending invite (reject) or active call (hangup)
        if (pendingInvites.containsKey(callId)) {
            // Remove from pendingInvites immediately so cleanup runs correctly
            pendingInvites.remove(callId)

            // Broadcast CALL_INVITE_CANCELLED so IncomingCallActivity dismisses
            val cancelBroadcast = Intent(Constants.BROADCAST_CALL_INVITE_CANCELLED).apply {
                putExtra(Constants.EXTRA_CALL_ID, callId)
            }
            broadcastManager.sendBroadcast(cancelBroadcast)

            client.reject(callId) { error ->
                if (error != null) {
                    broadcastError("reject failed: ${error.message}")
                    return@reject
                }
                broadcastCallEnded(callId)
            }
        } else {
            client.hangup(callId) { error ->
                if (error != null) {
                    broadcastError("hangup failed: ${error.message}")
                    return@hangup
                }
                broadcastCallEnded(callId)
            }
        }

        // Clean up connection
        activeConnections[callId]?.disconnect()
        activeConnections.remove(callId)

        // Always cancel the notification and stop the service when no calls remain
        if (activeConnections.isEmpty() && pendingInvites.isEmpty()) {
            releaseAudioFocus()
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
            notificationManager.cancel(Constants.NOTIFICATION_ID)
            stopForeground(true)
            stopSelf()
        }
    }

    // ── Cleanup (remote hangup / external) ──────────────────────────────

    /**
     * Clean up notification and stop foreground service when no calls remain.
     * Called by VonageVoicePlugin when the SDK reports a remote hangup
     * and the local handleHangup() path was never invoked.
     */
    private fun handleCleanup() {
        stopServiceRinging()
        releaseIncomingCallWakeLock()
        if (activeConnections.isEmpty() && pendingInvites.isEmpty()) {
            releaseAudioFocus()
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
            notificationManager.cancel(Constants.NOTIFICATION_ID)
            stopForeground(true)
            stopSelf()
        }
    }

    // ── DTMF ──────────────────────────────────────────────────────────────

    /**
     * Send DTMF tones on the active call.
     *
     * Intent extras required:
     *   EXTRA_CALL_ID — active callId
     *   EXTRA_DIGITS  — digit string e.g. "1234" or "*#"
     */
    private fun handleSendDigits(intent: Intent) {
        val callId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return
        val digits = intent.getStringExtra(Constants.EXTRA_DIGITS) ?: return

        val client = VonageClientHolder.voiceClient ?: return

        client.sendDTMF(callId, digits) { error ->
            if (error != null) broadcastError("sendDTMF failed: ${error.message}")
        }
    }

    // ── Audio routing ─────────────────────────────────────────────────────

    /**
     * Toggle speakerphone on / off.
     *
     * Intent extras required:
     *   EXTRA_CALL_ID      — active callId
     *   EXTRA_SPEAKER_STATE — Boolean true = speaker on
     */
    private fun handleToggleSpeaker(intent: Intent) {
        val callId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return
        val speakerOn = intent.getBooleanExtra(Constants.EXTRA_SPEAKER_STATE, false)
        activeConnections[callId]?.setSpeaker(speakerOn)
    }

    /**
     * Toggle Bluetooth audio routing on / off.
     *
     * Intent extras required:
     *   EXTRA_CALL_ID        — active callId
     *   EXTRA_BLUETOOTH_STATE — Boolean true = Bluetooth on
     */
    private fun handleToggleBluetooth(intent: Intent) {
        val callId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return
        val bluetoothOn = intent.getBooleanExtra(Constants.EXTRA_BLUETOOTH_STATE, false)
        activeConnections[callId]?.setBluetooth(bluetoothOn)
    }

    /**
     * Toggle microphone mute on / off.
     * Also calls Vonage SDK mute/unmute so the server is aware.
     *
     * Intent extras required:
     *   EXTRA_CALL_ID   — active callId
     *   EXTRA_MUTE_STATE — Boolean true = muted
     */
    private fun handleToggleMute(intent: Intent) {
        val callId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return
        val muted = intent.getBooleanExtra(Constants.EXTRA_MUTE_STATE, false)

        val client = VonageClientHolder.voiceClient ?: return

        if (muted) {
            client.mute(callId) { error ->
                if (error != null) {
                    broadcastError("mute failed: ${error.message}")
                    return@mute
                }
                activeConnections[callId]?.setMuted(true)
            }
        } else {
            client.unmute(callId) { error ->
                if (error != null) {
                    broadcastError("unmute failed: ${error.message}")
                    return@unmute
                }
                activeConnections[callId]?.setMuted(false)
            }
        }
    }

    /**
     * Toggle call hold on / off.
     * Vonage SDK has no native hold API — handled via Telecom layer.
     *
     * Intent extras required:
     *   EXTRA_CALL_ID   — active callId
     *   EXTRA_HOLD_STATE — Boolean true = on hold
     */
    private fun handleToggleHold(intent: Intent) {
        val callId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return
        val shouldHold = intent.getBooleanExtra(Constants.EXTRA_HOLD_STATE, false)
        activeConnections[callId]?.setHold(shouldHold)
    }

    // ── Telecom ConnectionService overrides ───────────────────────────────

    /**
     * Called by the Telecom framework to create an outgoing connection.
     * Required override — returns a minimal connection so Telecom is satisfied.
     * Actual call setup is handled in handleOutgoingCall().
     */
    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val callId = getActiveCallId() ?: ""
        return activeConnections[callId] ?: TVCallConnection(this, callId, "", "")
    }

    /**
     * Called by the Telecom framework to create an incoming connection.
     * Required override — returns the pending invite connection for this callId.
     */
    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val callId = request?.extras?.getString(Constants.EXTRA_CALL_ID) ?: ""
        return pendingInvites[callId] ?: TVCallInviteConnection(this, callId, "", "")
    }

    // ── Foreground service ────────────────────────────────────────────────

    /**
     * Start a foreground service with a persistent notification so the
     * call can continue when the app is backgrounded.
     *
     * On API 29+ a FOREGROUND_SERVICE_TYPE_MICROPHONE is required.
     * On API 34+ FOREGROUND_SERVICE_MICROPHONE permission is needed
     * (declared in AndroidManifest.xml).
     */
    private fun startCallForegroundService() {
        createNotificationChannel()

        val notification = buildActiveCallNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                Constants.NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(Constants.NOTIFICATION_ID, notification)
        }
    }

    /**
     * Create the notification channel for active/ongoing calls.
     * Safe to call multiple times — system ignores duplicate registrations.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                Constants.NOTIFICATION_CHANNEL_ID,
                Constants.NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows ongoing Vonage voice call status"
                setSound(null, null)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    /**
     * Create a high-importance notification channel for incoming calls.
     * This channel must use IMPORTANCE_HIGH so that:
     *   - fullScreenIntent fires on lock screen / when app is not visible
     *   - heads-up notification appears when app is in foreground
     * Safe to call multiple times — system ignores duplicate registrations.
     */
    private fun createIncomingCallNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Silent channel — IncomingCallActivity is the sole source of
            // ringtone and vibration. No sound on the notification channel
            // prevents duplicate/overlapping ringtones.
            val channel = NotificationChannel(
                Constants.INCOMING_CALL_CHANNEL_ID,
                Constants.INCOMING_CALL_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming Vonage voice call alerts"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)
                setSound(null, null)
                enableVibration(false)
            }
            manager.createNotificationChannel(channel)
        }
    }

    /**
     * Build a minimal placeholder notification for the foreground service
     * when we don't yet have a callId (FCM placeholder startup).
     * No Answer/Decline buttons — those are added when the real callId arrives.
     */
    private fun buildPlaceholderIncomingNotification(): Notification {
        createIncomingCallNotificationChannel()

        return NotificationCompat.Builder(this, Constants.INCOMING_CALL_CHANNEL_ID)
            .setContentTitle("Incoming Call")
            .setContentText("Processing incoming call...")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    /**
     * Build a minimal persistent notification for the foreground service.
     * The app's launch intent is used as the tap action.
     */
    private fun buildIncomingCallNotification(callId: String, from: String): Notification {
        createIncomingCallNotificationChannel()

        // ── fullScreenIntent → IncomingCallActivity (native, works without Flutter) ──
        val fullScreenIntent = IncomingCallActivity.createIntent(applicationContext, callId, from)
        val fullScreenPendingIntent = PendingIntent.getActivity(
            this,
            (callId.hashCode() and 0x7FFFFFFF) % 10000 + 1000,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // ── Answer action → AnswerCallTrampolineActivity (bypasses background start restriction) ──
        val answerTrampolineIntent = Intent(applicationContext, AnswerCallTrampolineActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(AnswerCallTrampolineActivity.EXTRA_CALL_ID, callId)
            putExtra(AnswerCallTrampolineActivity.EXTRA_CALLER_NAME, from)
        }
        val answerPendingIntent = PendingIntent.getActivity(
            this,
            (callId.hashCode() and 0x7FFFFFFF) % 10000 + 2000,
            answerTrampolineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // ── Decline action ────────────────────────────────────────────────────
        val declineServiceIntent = Intent(applicationContext, TVConnectionService::class.java).apply {
            action = Constants.ACTION_HANGUP
            putExtra(Constants.EXTRA_CALL_ID, callId)
        }
        val declinePendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                this,
                (callId.hashCode() and 0x7FFFFFFF) % 10000 + 3000,
                declineServiceIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            PendingIntent.getService(
                this,
                (callId.hashCode() and 0x7FFFFFFF) % 10000 + 3000,
                declineServiceIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        // Build a Person for the caller — Samsung One UI and stock Android
        // use this to identify the notification as a real phone call and
        // prioritize it for full-screen display on the lock screen.
        val callerPerson = Person.Builder()
            .setName(from)
            .setImportant(true)
            .build()

        return NotificationCompat.Builder(this, Constants.INCOMING_CALL_CHANNEL_ID)
            .setContentTitle("Incoming Call")
            .setContentText("From: $from")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentIntent(fullScreenPendingIntent)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addPerson(callerPerson)
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_menu_call,
                    "Answer",
                    answerPendingIntent
                ).build()
            )
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_delete,
                    "Decline",
                    declinePendingIntent
                ).build()
            )
            .build()
    }

    private fun buildActiveCallNotification(): Notification {
        createNotificationChannel()

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // ── Hangup action ─────────────────────────────────────────────────────
        val hangupServiceIntent = Intent(applicationContext, TVConnectionService::class.java).apply {
            action = Constants.ACTION_HANGUP
            putExtra(Constants.EXTRA_CALL_ID, getActiveCallId() ?: "")
        }
        val hangupIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                this,
                3,
                hangupServiceIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            PendingIntent.getService(
                this,
                3,
                hangupServiceIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        return NotificationCompat.Builder(this, Constants.NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Vonage Voice Call")
            .setContentText("Call in progress")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_delete,
                    "End Call",
                    hangupIntent
                ).build()
            )
            .build()
    }

    // ── Incoming call wake lock ──────────────────────────────────────────

    /**
     * Acquire a FULL_WAKE_LOCK to physically turn the screen on for incoming calls.
     * This ensures the fullScreenIntent fires and IncomingCallActivity is visible
     * even when the device is locked and screen is off.
     */
    @Suppress("DEPRECATION")
    private fun acquireIncomingCallWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            incomingCallWakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
                "VonageVoice:IncomingCallScreenWakeLock"
            ).apply {
                acquire(60_000L) // 60 seconds for incoming call
            }
            android.util.Log.d("TVConnectionService", "Incoming call FULL_WAKE_LOCK acquired")
        } catch (e: Exception) {
            android.util.Log.e("TVConnectionService", "Failed to acquire incoming call wake lock: ${e.message}")
        }
    }

    private fun releaseIncomingCallWakeLock() {
        try {
            incomingCallWakeLock?.let { if (it.isHeld) it.release() }
            incomingCallWakeLock = null
        } catch (e: Exception) {
            android.util.Log.e("TVConnectionService", "Failed to release incoming call wake lock: ${e.message}")
        }
    }

    // ── Service-level ringtone & vibration ────────────────────────────────

    /**
     * Start playing the default ringtone and vibrating.
     * Called from [handleIncomingCall] so ringing starts immediately
     * regardless of whether IncomingCallActivity manages to launch.
     */
    private fun startServiceRinging() {
        if (isServiceRinging) return
        isServiceRinging = true

        // Play default ringtone
        try {
            val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            serviceRingtone = RingtoneManager.getRingtone(applicationContext, ringtoneUri)
            serviceRingtone?.let { ring ->
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                ring.audioAttributes = audioAttributes
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    ring.isLooping = true
                }
                ring.play()
                android.util.Log.d("TVConnectionService", "Service ringtone started")
            }
        } catch (e: Exception) {
            android.util.Log.e("TVConnectionService", "Error starting service ringtone: ${e.message}")
        }

        // Start vibration
        try {
            serviceVibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            serviceVibrator?.let { vib ->
                if (vib.hasVibrator()) {
                    val pattern = longArrayOf(0, 1000, 1000) // 1s on, 1s off
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vib.vibrate(VibrationEffect.createWaveform(pattern, 0))
                    } else {
                        @Suppress("DEPRECATION")
                        vib.vibrate(pattern, 0)
                    }
                    android.util.Log.d("TVConnectionService", "Service vibration started")
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("TVConnectionService", "Error starting service vibration: ${e.message}")
        }
    }

    /**
     * Stop ringtone and vibration. Safe to call multiple times.
     */
    private fun stopServiceRinging() {
        if (!isServiceRinging) return
        isServiceRinging = false

        try {
            serviceRingtone?.let { if (it.isPlaying) it.stop() }
            serviceRingtone = null
        } catch (e: Exception) {
            android.util.Log.e("TVConnectionService", "Error stopping service ringtone: ${e.message}")
        }

        try {
            serviceVibrator?.cancel()
            serviceVibrator = null
        } catch (e: Exception) {
            android.util.Log.e("TVConnectionService", "Error stopping service vibration: ${e.message}")
        }
    }

    // ── Broadcast helpers ─────────────────────────────────────────────────

    private fun broadcastCallEnded(callId: String) {
        val intent = Intent(Constants.BROADCAST_CALL_ENDED).apply {
            putExtra(Constants.EXTRA_CALL_ID, callId)
        }
        broadcastManager.sendBroadcast(intent)
    }

    private fun broadcastError(message: String) {
        val intent = Intent(Constants.BROADCAST_CALL_FAILED).apply {
            putExtra("error", message)
        }
        broadcastManager.sendBroadcast(intent)
    }
}

/**
 * VonageClientHolder — singleton holder for the VoiceClient instance.
 *
 * The VoiceClient is created and owned by VonageVoicePlugin but needs
 * to be accessible from TVConnectionService without passing it through
 * Intent extras (it is not Parcelable).
 *
 * Set by VonageVoicePlugin.onAttachedToEngine() and cleared on detach.
 */
object VonageClientHolder {
    var voiceClient: VoiceClient? = null
    /** Caller display name extracted from the last FCM push payload. */
    var pendingCallerDisplay: String? = null

    /** True once createSession() has succeeded on the current VoiceClient. */
    @Volatile
    var isSessionReady: Boolean = false

    /**
     * True when the Flutter engine is attached to VonageVoicePlugin.
     * Used by TVConnectionService to decide whether to launch the native
     * IncomingCallActivity (background/killed) or let Flutter handle the
     * incoming call UI (foreground).
     * Set in VonageVoicePlugin.onAttachedToEngine/onDetachedFromEngine.
     */
    @Volatile
    var isFlutterEngineAttached: Boolean = false

    /**
     * Timestamp (millis) of the last FCM push processed by the native
     * VonageFirebaseMessagingService. The Dart fallback path
     * (handleProcessPush) checks this to avoid double-processing.
     */
    @Volatile
    var lastNativePushTimestamp: Long = 0L

    /**
     * True when a call was answered via the native path (notification Answer button
     * or IncomingCallActivity) BEFORE Flutter's engine had attached its listeners.
     * Prevents registerVoiceClientListeners() from re-registering setCallInviteListener
     * which can interfere with the already-answered call on the Vonage SDK.
     * Cleared when the call ends.
     */
    @Volatile
    var isCallAnsweredNatively: Boolean = false

    /**
     * True while doAnswer() is in progress (including retries).
     * Prevents registerVoiceClientListeners() from overwriting SDK listeners
     * mid-answer which could reset the invite state.
     */
    @Volatile
    var isAnsweringInProgress: Boolean = false

    /**
     * Set of callIds already processed by processPushCallInvite().
     * Prevents duplicate processing when both Dart FCM forwarding
     * and VonageFirebaseMessagingService handle the same push.
     */
    private val processedPushCallIds = java.util.Collections.synchronizedSet(mutableSetOf<String>())

    /** Returns true if the callId was NOT already processed (first caller wins). */
    fun markPushProcessed(callId: String): Boolean {
        val added = processedPushCallIds.add(callId)
        // Auto-clean old entries to prevent unbounded growth
        if (processedPushCallIds.size > 20) {
            val iterator = processedPushCallIds.iterator()
            if (iterator.hasNext()) { iterator.next(); iterator.remove() }
        }
        return added
    }

    private const val PREFS_NAME = "vonage_voice_prefs"
    private const val KEY_JWT = "vonage_jwt"
    private const val KEY_DEVICE_ID = "vonage_device_id"

    /** Persist the JWT so VonageFirebaseMessagingService can restore the session
     *  when the app process was killed. */
    fun storeJwt(context: android.content.Context, jwt: String) {
        context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_JWT, jwt)
            .apply()
    }

    /** Read the stored JWT (may be null if user never logged in). */
    fun getStoredJwt(context: android.content.Context): String? {
        return context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            .getString(KEY_JWT, null)
    }

    /** Clear the stored JWT on logout / unregister. */
    fun clearStoredJwt(context: android.content.Context) {
        context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_JWT)
            .apply()
    }

    /** Persist the Vonage device ID so we can unregister it on next install/session. */
    fun storeDeviceId(context: android.content.Context, deviceId: String) {
        context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DEVICE_ID, deviceId)
            .apply()
    }

    /** Read the stored Vonage device ID (may be null). */
    fun getStoredDeviceId(context: android.content.Context): String? {
        return context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            .getString(KEY_DEVICE_ID, null)
    }

    /** Clear the stored device ID on unregister. */
    fun clearStoredDeviceId(context: android.content.Context) {
        context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_DEVICE_ID)
            .apply()
    }
}