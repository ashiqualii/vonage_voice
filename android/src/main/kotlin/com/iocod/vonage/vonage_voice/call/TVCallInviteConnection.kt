package com.iocod.vonage.vonage_voice.call

import android.content.Context
import android.content.Intent
import android.telecom.Connection
import android.telecom.DisconnectCause
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.iocod.vonage.vonage_voice.constants.Constants

/**
 * TVCallInviteConnection — TelecomVoice incoming call invite connection.
 *
 * Represents an incoming call that has arrived via FCM push but has NOT
 * yet been answered or rejected by the user. This is the ringing state.
 *
 * Lifecycle:
 *   1. FCM push arrives → VonageFirebaseMessagingService processes it
 *   2. TVConnectionService creates this connection → system shows incoming call UI
 *   3a. User answers → onAnswer() → broadcasts ACTION_ANSWER → plugin calls client.answer(callId)
 *   3b. User rejects → onReject() → broadcasts ACTION_HANGUP → plugin calls client.reject(callId)
 *   3c. Caller cancels → disconnect() called externally → connection destroyed
 *
 * Once answered, TVConnectionService replaces this with a [TVCallConnection]
 * that manages the live call state.
 */
class TVCallInviteConnection(
    private val context: Context,
    val callId: String,
    val from: String,
    val to: String
) : Connection() {

    private val broadcastManager = LocalBroadcastManager.getInstance(context)

    init {
        // Set connection to ringing state immediately on creation
        // so the system UI shows the incoming call screen
        setRinging()
    }

    // ── Connection lifecycle callbacks (called by Android Telecom) ────────

    /**
     * Called when the user answers the call via the system UI,
     * a Bluetooth headset button, or from Flutter via client.answer().
     *
     * We broadcast ACTION_ANSWER so TVConnectionService / VonageVoicePlugin
     * can call VoiceClient.answer(callId) on the Vonage SDK.
     */
    override fun onAnswer() {
        broadcastInviteEvent(Constants.ACTION_ANSWER)
    }

    /**
     * Called when the user rejects the call via the system UI
     * or from Flutter via client.reject().
     *
     * We broadcast ACTION_HANGUP so the plugin can call
     * VoiceClient.reject(callId) on the Vonage SDK.
     */
    override fun onReject() {
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroy()
        broadcastInviteEvent(Constants.ACTION_HANGUP)
    }

    /**
     * Called when the system requests an abort — e.g. the caller
     * cancelled before the user answered.
     */
    override fun onAbort() {
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
        destroy()
        broadcastEvent(Constants.BROADCAST_CALL_INVITE_CANCELLED)
    }

    // ── Public control methods ────────────────────────────────────────────

    /**
     * Called externally when the remote party cancels the invite
     * (Vonage SDK fires setCallInviteCancelListener).
     * Cleans up this connection and notifies Flutter.
     */
    fun cancel() {
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
        destroy()
        broadcastEvent(Constants.BROADCAST_CALL_INVITE_CANCELLED)
    }

    // ── Private broadcast helpers ─────────────────────────────────────────

    /**
     * Broadcast an invite action (answer / reject) with callId attached.
     * TVConnectionService listens for these to trigger Vonage SDK calls.
     */
    private fun broadcastInviteEvent(action: String) {
        val intent = Intent(action).apply {
            putExtra(Constants.EXTRA_CALL_ID, callId)
            putExtra(Constants.EXTRA_CALL_FROM, from)
            putExtra(Constants.EXTRA_CALL_TO, to)
        }
        broadcastManager.sendBroadcast(intent)
    }

    /**
     * Broadcast a simple call event with callId attached.
     */
    private fun broadcastEvent(action: String) {
        val intent = Intent(action).apply {
            putExtra(Constants.EXTRA_CALL_ID, callId)
        }
        broadcastManager.sendBroadcast(intent)
    }
}