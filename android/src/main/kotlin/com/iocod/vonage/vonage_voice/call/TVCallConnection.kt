package com.iocod.vonage.vonage_voice.call

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.DisconnectCause
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import android.content.Intent
import androidx.core.content.ContextCompat
import com.iocod.vonage.vonage_voice.constants.Constants
import com.iocod.vonage.vonage_voice.service.TVConnectionService

/**
 * TVCallConnection — TelecomVoice active call connection.
 *
 * Extends Android's [Connection] class to represent a live voice call
 * inside the Android Telecom framework. This is what the system dialer,
 * Bluetooth headsets, and car kits interact with.
 *
 * Responsibilities:
 *   - Mute / unmute microphone via AudioManager
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

    var isSpeakerOn: Boolean = false
        internal set

    var isBluetoothOn: Boolean = false
        internal set

    // ── Connection lifecycle callbacks (called by Android Telecom) ────────

    /**
     * Called when the system (or user via headset button) requests a disconnect.
     * We broadcast SYSTEM_DISCONNECT so VonageVoicePlugin can call client.hangup(callId)
     * to properly tear down the server-side call leg.
     *
     * We also send ACTION_HANGUP directly to TVConnectionService as a fallback
     * for the killed-app lock screen case where TVBroadcastReceiver isn't
     * registered. This ensures the foreground notification is always canceled
     * and the service is stopped even without the Flutter engine running.
     */
    override fun onDisconnect() {
        audioManager.mode = AudioManager.MODE_NORMAL
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
        broadcastEvent(Constants.BROADCAST_SYSTEM_DISCONNECT)

        // Direct service intent — guaranteed cleanup path
        try {
            val intent = Intent(context, TVConnectionService::class.java).apply {
                action = Constants.ACTION_HANGUP
                putExtra(Constants.EXTRA_CALL_ID, callId)
            }
            ContextCompat.startForegroundService(context, intent)
        } catch (e: Exception) {
            android.util.Log.w("TVCallConnection",
                "onDisconnect: Failed to send hangup intent: ${e.message}")
        }
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
     * Route audio to speakerphone or back to earpiece.
     * Turning speaker on will disable Bluetooth routing.
     */
    fun setSpeaker(speakerOn: Boolean) {
        if (speakerOn && isBluetoothOn) {
            // Stop BT first so audio routes cleanly to speaker
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.clearCommunicationDevice()
            } else {
                audioManager.stopBluetoothSco()
                audioManager.isBluetoothScoOn = false
            }
            isBluetoothOn = false
            broadcastStateEvent(Constants.BROADCAST_BLUETOOTH_STATE, false)
        }
        isSpeakerOn = speakerOn
        audioManager.isSpeakerphoneOn = speakerOn
        broadcastStateEvent(Constants.BROADCAST_SPEAKER_STATE, speakerOn)
    }

    /**
     * Route audio to Bluetooth SCO headset or back to earpiece.
     * Turning Bluetooth on will disable the speakerphone.
     * Uses setCommunicationDevice() on API 31+ for reliable routing.
     */
    fun setBluetooth(bluetoothOn: Boolean) {
        if (bluetoothOn && isSpeakerOn) {
            audioManager.isSpeakerphoneOn = false
            isSpeakerOn = false
            broadcastStateEvent(Constants.BROADCAST_SPEAKER_STATE, false)
        }
        isBluetoothOn = bluetoothOn
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val devices = audioManager.availableCommunicationDevices
            if (bluetoothOn) {
                val btDevice = devices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    it.type == AudioDeviceInfo.TYPE_BLE_HEADSET
                }
                if (btDevice != null) {
                    audioManager.setCommunicationDevice(btDevice)
                } else {
                    isBluetoothOn = false
                }
            } else {
                val earpiece = devices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                }
                earpiece?.let { audioManager.setCommunicationDevice(it) }
            }
        } else {
            if (bluetoothOn) {
                // Only start SCO if a BT audio device is actually connected
                if (hasConnectedBluetoothDevice()) {
                    audioManager.startBluetoothSco()
                    audioManager.isBluetoothScoOn = true
                } else {
                    isBluetoothOn = false
                }
            } else {
                audioManager.stopBluetoothSco()
                audioManager.isBluetoothScoOn = false
            }
        }
        broadcastStateEvent(Constants.BROADCAST_BLUETOOTH_STATE, isBluetoothOn)
    }

    /**
     * Check if a Bluetooth audio output device is actually connected.
     * Uses getDevices() to detect real hardware, not just HW capability.
     */
    private fun hasConnectedBluetoothDevice(): Boolean {
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        return devices.any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
             it.type == AudioDeviceInfo.TYPE_BLE_HEADSET)
        }
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
        audioManager.mode = AudioManager.MODE_NORMAL
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