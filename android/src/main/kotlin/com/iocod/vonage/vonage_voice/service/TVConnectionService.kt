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
import com.vonage.voice.api.VoiceClient
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager

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
    // private lateinit var voiceClient: VoiceClient

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
    }

    // ── Service lifecycle ─────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        broadcastManager = LocalBroadcastManager.getInstance(this)
    }

    /**
     * Entry point for all actions sent from VonageVoicePlugin via startService(Intent).
     * Each action maps to a specific call operation.
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let { handleIntent(it) }
        return START_NOT_STICKY
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
        val from = intent.getStringExtra(Constants.EXTRA_CALL_FROM) ?: Constants.DEFAULT_UNKNOWN_CALLER
        val to = intent.getStringExtra(Constants.EXTRA_CALL_TO) ?: ""

        // Create invite connection and store in pending map
        val connection = TVCallInviteConnection(this, callId, from, to)
        pendingInvites[callId] = connection

        // Start foreground service so we can keep running in background
        startCallForegroundService()

        // Broadcast to plugin so Flutter receives the "Incoming" event
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
        pendingInvites[callId]?.cancel()
        pendingInvites.remove(callId)

        if (activeConnections.isEmpty() && pendingInvites.isEmpty()) {
            stopForeground(true)
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
        // "to" is the only required key — everything else is optional custom data
        val callContext = HashMap<String, String>().apply {
            put("to", callTo)
            if (callFrom.isNotEmpty()) put("from", callFrom)
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
            }

    private fun releaseAudioFocus() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.mode = AudioManager.MODE_NORMAL
    }


    private fun handleAnswer(intent: Intent) {
        val callId = intent.getStringExtra(Constants.EXTRA_CALL_ID) ?: return

        val client = VonageClientHolder.voiceClient ?: run {
            broadcastError("VoiceClient not initialised")
            return
        }

        client.answer(callId) { error ->
            if (error != null) {
                broadcastError("answer failed: ${error.message}")
                return@answer
            }

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

            // Broadcast connected event to Flutter
            val broadcast = Intent(Constants.BROADCAST_CALL_CONNECTED).apply {
                putExtra(Constants.EXTRA_CALL_ID, callId)
                putExtra(Constants.EXTRA_CALL_FROM, invite?.from ?: "")
                putExtra(Constants.EXTRA_CALL_TO, invite?.to ?: "")
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

        val client = VonageClientHolder.voiceClient ?: run {
            broadcastError("VoiceClient not initialised")
            return
        }

        // Check if this is a pending invite (reject) or active call (hangup)
        if (pendingInvites.containsKey(callId)) {
            client.reject(callId) { error ->
                if (error != null) {
                    broadcastError("reject failed: ${error.message}")
                    return@reject
                }
                pendingInvites.remove(callId)
                broadcastCallEnded(callId)
            }
        } else {
            client.hangup(callId) { error ->
                if (error != null) {
                    broadcastError("hangup failed: ${error.message}")
                    return@hangup
                }
            }
            // Call ended broadcast is fired by the SDK hangup listener
            // in VonageVoicePlugin, not here — avoid double firing
        }

        // Clean up connection
        activeConnections[callId]?.disconnect()
        activeConnections.remove(callId)

        if (activeConnections.isEmpty() && pendingInvites.isEmpty()) {
            releaseAudioFocus()
            stopForeground(true)
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

        val notification = buildCallNotification()

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
     * Create the notification channel required on API 26+.
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
     * Build a minimal persistent notification for the foreground service.
     * The app's launch intent is used as the tap action.
     */
    private fun buildCallNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, Constants.NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Vonage Voice Call")
            .setContentText("Call in progress")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
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
}