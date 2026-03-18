package com.iocod.vonage.vonage_voice.storage

/**
 * Interface for the plugin's lightweight persistence layer.
 *
 * All state that needs to survive app restarts is stored here:
 *   - Default caller display name
 *   - Caller ID → display name registry
 *   - Behaviour flags (reject on no permissions, show notifications)
 *
 * The concrete implementation [StorageImpl] uses Android SharedPreferences.
 * Having this interface makes unit testing straightforward — just mock it.
 */
interface Storage {

    // ── Default caller ────────────────────────────────────────────────────

    /**
     * Get the fallback display name shown when an incoming caller
     * has no registered mapping. Defaults to "Unknown".
     */
    fun getDefaultCaller(): String

    /**
     * Set the fallback display name for unknown callers.
     */
    fun setDefaultCaller(name: String)

    // ── Caller identity registry ──────────────────────────────────────────

    /**
     * Store a display name for a given caller ID.
     *
     * Example:
     *   addRegisteredClient("user_123", "Alice Johnson")
     */
    fun addRegisteredClient(id: String, name: String)

    /**
     * Retrieve the display name for a given caller ID.
     * Returns null if no mapping exists for this ID.
     */
    fun getRegisteredClient(id: String): String?

    /**
     * Remove a previously registered caller ID → name mapping.
     */
    fun removeRegisteredClient(id: String)

    // ── Behaviour flags ───────────────────────────────────────────────────

    /**
     * Whether to auto-reject incoming calls when required
     * Android permissions are missing.
     * Defaults to false — let the call ring even without permissions.
     */
    fun shouldRejectCallOnNoPermissions(): Boolean

    /**
     * Set the auto-reject on missing permissions behaviour.
     */
    fun setRejectCallOnNoPermissions(shouldReject: Boolean)

    /**
     * Whether to show an ongoing call notification while a call is active.
     * Defaults to true.
     */
    fun shouldShowNotifications(): Boolean

    /**
     * Set whether to show the ongoing call notification.
     */
    fun setShowNotifications(show: Boolean)
}