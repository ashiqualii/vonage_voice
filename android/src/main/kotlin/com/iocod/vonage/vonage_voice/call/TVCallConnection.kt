package com.iocod.vonage.vonage_voice.call

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.DisconnectCause
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import android.content.Intent
import com.iocod.vonage.vonage_voice.constants.Constants

/**
 * TVCallConnection — TelecomVoice active call connection.
 *
 * Extends Android's [Connection] class to represent a live voice call
 * inside the Android Telecom framework. This is what the system dialer,
 * Bluetooth headsets, and car kits interact with.
 *
 * Responsibilities:
 *   - Mute / unmute microphone via AudioManager
 *   - Hold / resume call via Telecom state machine
 *   - Route audio to speaker or Bluetooth
 *   - Broadcast all state changes back to VonageVoicePlugin via LocalBroadcast
 *
 * One instance is created per active call and stored in
 * TVConnectionService.activeConnections map keyed by callId.
 */
class TVCallConnection(
    private val context: Context,
    val callId: String,
    val from: String,
    val to: String
) : Connection() {

    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val broadcastManager = LocalBroadcastManager.getInstance(context)

    // ── Local state tracking ──────────────────────────────────────────────

    var isMuted: Boolean = false
        private set

    var isOnHold: Boolean = false
        private set

    var isSpeakerOn: Boolean = false
        private set

    var isBluetoothOn: Boolean = false
        private set

    // ── Connection lifecycle callbacks (called by Android Telecom) ────────

    /**
     * Called when the system (or user via headset button) requests a disconnect.
     * We broadcast this so VonageVoicePlugin can call client.hangup(callId).
     */
    override fun onDisconnect() {
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
        broadcastEvent(Constants.BROADCAST_CALL_ENDED)
    }

    /**
     * Called when the system requests the call be placed on hold.
     * e.g. when another call comes in or the user taps hold in the system UI.
     */
    override fun onHold() {
        setOnHold()
        isOnHold = true
        broadcastStateEvent(Constants.BROADCAST_HOLD_STATE, isOnHold)
    }

    /**
     * Called when the system requests the call be resumed from hold.
     */
    override fun onUnhold() {
        setActive()
        isOnHold = false
        broadcastStateEvent(Constants.BROADCAST_HOLD_STATE, isOnHold)
    }

    /**
     * Called when the system audio route changes (speaker, earpiece, Bluetooth).
     * We sync our local state and broadcast to Flutter.
     */
    override fun onCallAudioStateChanged(state: CallAudioState) {
        isMuted = state.isMuted

        val newSpeaker = state.route == CallAudioState.ROUTE_SPEAKER
        val newBluetooth = state.route == CallAudioState.ROUTE_BLUETOOTH

        if (newSpeaker != isSpeakerOn) {
            isSpeakerOn = newSpeaker
            broadcastStateEvent(Constants.BROADCAST_SPEAKER_STATE, isSpeakerOn)
        }

        if (newBluetooth != isBluetoothOn) {
            isBluetoothOn = newBluetooth
            broadcastStateEvent(Constants.BROADCAST_BLUETOOTH_STATE, isBluetoothOn)
        }

        broadcastStateEvent(Constants.BROADCAST_MUTE_STATE, isMuted)
    }

    // ── Public control methods (called by TVConnectionService) ────────────

    /**
     * Mute or unmute the microphone.
     * Uses AudioManager directly since Vonage SDK mute/unmute
     * is called from VonageVoicePlugin, not here.
     */
    fun setMuted(muted: Boolean) {
        isMuted = muted
        audioManager.isMicrophoneMute = muted
        broadcastStateEvent(Constants.BROADCAST_MUTE_STATE, muted)
    }

    /**
     * Put the call on hold or resume it programmatically
     * (from Flutter, not from system UI).
     */
    fun setHold(hold: Boolean) {
        if (hold) {
            setOnHold()
            isOnHold = true
        } else {
            setActive()
            isOnHold = false
        }
        broadcastStateEvent(Constants.BROADCAST_HOLD_STATE, isOnHold)
    }

    /**
     * Route audio to speakerphone or back to earpiece.
     */
    fun setSpeaker(speakerOn: Boolean) {
        isSpeakerOn = speakerOn
        audioManager.isSpeakerphoneOn = speakerOn
        broadcastStateEvent(Constants.BROADCAST_SPEAKER_STATE, speakerOn)
    }

    /**
     * Route audio to Bluetooth SCO headset or back to earpiece.
     */
    fun setBluetooth(bluetoothOn: Boolean) {
        isBluetoothOn = bluetoothOn
        if (bluetoothOn) {
            audioManager.startBluetoothSco()
            audioManager.isBluetoothScoOn = true
        } else {
            audioManager.stopBluetoothSco()
            audioManager.isBluetoothScoOn = false
        }
        broadcastStateEvent(Constants.BROADCAST_BLUETOOTH_STATE, bluetoothOn)
    }

    /**
     * Mark the connection as active (call has been answered and connected).
     * Called by TVConnectionService once Vonage SDK confirms the call is live.
     */
    fun setCallActive() {
        setActive()
    }

    /**
     * Disconnect and clean up this connection.
     * Called when Vonage SDK fires the hangup callback.
     */
    fun disconnect() {
        setDisconnected(DisconnectCause(DisconnectCause.REMOTE))
        destroy()
    }

    // ── Private broadcast helpers ─────────────────────────────────────────

    /**
     * Broadcast a simple event with no extra data.
     */
    private fun broadcastEvent(action: String) {
        val intent = Intent(action).apply {
            putExtra(Constants.EXTRA_CALL_ID, callId)
        }
        broadcastManager.sendBroadcast(intent)
    }

    /**
     * Broadcast a boolean state change event.
     * e.g. mute=true, hold=false, speaker=true
     */
    private fun broadcastStateEvent(action: String, state: Boolean) {
        val intent = Intent(action).apply {
            putExtra(Constants.EXTRA_CALL_ID, callId)
            putExtra("state", state)
        }
        broadcastManager.sendBroadcast(intent)
    }
}