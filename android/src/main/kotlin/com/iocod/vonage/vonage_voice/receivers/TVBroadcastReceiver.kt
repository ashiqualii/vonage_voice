package com.iocod.vonage.vonage_voice.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.iocod.vonage.vonage_voice.constants.Constants

/**
 * TVBroadcastReceiver — TelecomVoice LocalBroadcast relay.
 *
 * Acts as the internal event bus between background services and
 * VonageVoicePlugin. Since TVConnectionService and
 * VonageFirebaseMessagingService run in separate contexts, they
 * cannot call VonageVoicePlugin directly. Instead they fire
 * LocalBroadcasts which this receiver picks up and forwards.
 *
 * Registration:
 *   This receiver is registered programmatically (not in AndroidManifest)
 *   inside VonageVoicePlugin.onAttachedToEngine() so it only lives
 *   while the Flutter engine is active.
 *
 * Flow:
 *   TVConnectionService → LocalBroadcast
 *     → TVBroadcastReceiver.onReceive()
 *       → listener.onBroadcastReceived(intent)
 *         → VonageVoicePlugin.handleBroadcastIntent()
 *           → eventSink.success("Ringing|...")  → Flutter
 *
 * All broadcast action strings are defined in [Constants].
 */
class TVBroadcastReceiver(
    private val listener: BroadcastListener
) : BroadcastReceiver() {

    // ── Broadcast listener interface ──────────────────────────────────────

    /**
     * Implemented by VonageVoicePlugin to handle incoming broadcasts.
     * Keeps the receiver decoupled from the plugin implementation.
     */
    interface BroadcastListener {
        fun onBroadcastReceived(intent: Intent)
    }

    // ── BroadcastReceiver override ────────────────────────────────────────

    /**
     * Called when any registered broadcast action is received.
     * Simply forwards the intent to the listener — all routing
     * logic lives in VonageVoicePlugin.handleBroadcastIntent().
     */
    override fun onReceive(context: Context, intent: Intent) {
        listener.onBroadcastReceived(intent)
    }

    // ── Registration helpers ──────────────────────────────────────────────

    /**
     * Register this receiver with LocalBroadcastManager to listen
     * for all call and audio state events from the services.
     *
     * Called from VonageVoicePlugin.onAttachedToEngine().
     */
    fun register(context: Context) {
        val filter = IntentFilter().apply {

            // ── Call state events ─────────────────────────────────────────
            addAction(Constants.BROADCAST_CALL_RINGING)
            addAction(Constants.BROADCAST_CALL_CONNECTED)
            addAction(Constants.BROADCAST_CALL_ENDED)
            addAction(Constants.BROADCAST_CALL_INVITE)
            addAction(Constants.BROADCAST_CALL_INVITE_CANCELLED)
            addAction(Constants.BROADCAST_CALL_RECONNECTING)
            addAction(Constants.BROADCAST_CALL_RECONNECTED)
            addAction(Constants.BROADCAST_CALL_FAILED)

            // ── Audio state events ────────────────────────────────────────
            addAction(Constants.BROADCAST_MUTE_STATE)
            addAction(Constants.BROADCAST_SPEAKER_STATE)
            addAction(Constants.BROADCAST_BLUETOOTH_STATE)
            addAction(Constants.BROADCAST_SYSTEM_DISCONNECT)

            // ── FCM token refresh ─────────────────────────────────────────
            addAction(Constants.BROADCAST_NEW_FCM_TOKEN)

            // ── Permission results ────────────────────────────────────────
            addAction(Constants.BROADCAST_PERMISSION_RESULT)
        }

        LocalBroadcastManager.getInstance(context).registerReceiver(this, filter)
    }

    /**
     * Unregister this receiver from LocalBroadcastManager.
     *
     * Called from VonageVoicePlugin.onDetachedFromEngine() to
     * prevent memory leaks when the Flutter engine is destroyed.
     */
    fun unregister(context: Context) {
        LocalBroadcastManager.getInstance(context).unregisterReceiver(this)
    }
}