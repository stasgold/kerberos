package com.jnj.assettracker

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

/**
 * A single BLE tag reading captured during a scan.
 *
 * @param address     BLE MAC address (AA:BB:CC:DD:EE:FF)
 * @param name        Device name from the BLE advertisement record
 * @param rssi        Received Signal Strength Indicator (dBm)
 * @param lastSeen    Epoch milliseconds of the most recent advertisement
 * @param customName  User-assigned display name (null = use [name])
 * @param colorIndex  Index into [CHIPOLO_TAG_COLORS]; null = unassigned
 */
data class TagEntry(
    val address: String,
    val name: String,
    val rssi: Int,
    val lastSeen: Long,
    val customName: String? = null,
    val colorIndex: Int? = null,
) {
    val displayName: String get() = customName?.takeIf { it.isNotBlank() } ?: name
    fun isActive(): Boolean =
        System.currentTimeMillis() - lastSeen < TagRepository.TAG_ACTIVE_MS
}

/**
 * Thread-safe singleton store for BLE tag readings.
 *
 * Tags persist across scan cycles and service restarts (stored in SharedPreferences).
 * [getActiveTags] returns only recently-seen tags (used by the HTTP API).
 * [getAllTags]    returns all known tags sorted active-first (used by the UI).
 */
object TagRepository {

    /** Alive window in ms — updated from Settings (default 60 s). */
    var TAG_ACTIVE_MS = 60_000L

    /** When true, only tags whose BLE name contains "POP" are shown. */
    var filterPopOnly = false

    private const val PREFS_NAME = "tag_repository"
    private const val PREF_TAGS  = "tags_json"

    private val tags = ConcurrentHashMap<String, TagEntry>()

    /**
     * Record or refresh a tag reading. Preserves any existing metadata.
     * Called by [BleScanner] on every advertisement received.
     */
    fun update(address: String, name: String, rssi: Int) {
        val existing = tags[address]
        tags[address] = TagEntry(
            address = address,
            name = name,
            rssi = rssi,
            lastSeen = System.currentTimeMillis(),
            customName = existing?.customName,
            colorIndex = existing?.colorIndex,
        )
    }

    /**
     * Persist user-assigned metadata for a tag without touching scan data.
     * No-op if the address is not currently tracked.
     */
    fun setMeta(address: String, customName: String?, colorIndex: Int?) {
        val existing = tags[address] ?: return
        tags[address] = existing.copy(customName = customName, colorIndex = colorIndex)
    }

    /** Returns tags seen within [TAG_ACTIVE_MS], sorted by RSSI. Used by HTTP API. */
    fun getActiveTags(): List<TagEntry> {
        val cutoff = System.currentTimeMillis() - TAG_ACTIVE_MS
        return tags.values
            .filter { it.lastSeen >= cutoff }
            .filter { !filterPopOnly || it.name.contains("POP", ignoreCase = true) }
            .sortedByDescending { it.rssi }
    }

    /**
     * Returns ALL known tags sorted by display name (case-insensitive).
     * Applies POP filter when enabled. Used by the UI.
     */
    fun getAllTags(): List<TagEntry> {
        return tags.values
            .filter { !filterPopOnly || it.name.contains("POP", ignoreCase = true) }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.displayName })
    }

    /** Serialize all tags to SharedPreferences. */
    fun saveToPrefs(context: Context) {
        val json = JSONArray()
        tags.values.forEach { tag ->
            json.put(JSONObject().apply {
                put("address",    tag.address)
                put("name",       tag.name)
                put("rssi",       tag.rssi)
                put("lastSeen",   tag.lastSeen)
                put("customName", tag.customName ?: "")
                put("colorIndex", tag.colorIndex ?: -1)
            })
        }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(PREF_TAGS, json.toString()).apply()
    }

    /** Restore tags from SharedPreferences (call once on app start). */
    fun loadFromPrefs(context: Context) {
        val str = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(PREF_TAGS, null) ?: return
        try {
            val json = JSONArray(str)
            for (i in 0 until json.length()) {
                val obj = json.getJSONObject(i)
                val addr = obj.getString("address")
                tags[addr] = TagEntry(
                    address    = addr,
                    name       = obj.getString("name"),
                    rssi       = obj.getInt("rssi"),
                    lastSeen   = obj.getLong("lastSeen"),
                    customName = obj.getString("customName").takeIf { it.isNotEmpty() },
                    colorIndex = obj.getInt("colorIndex").takeIf { it >= 0 },
                )
            }
        } catch (_: Exception) {}
    }

    /** Removes a single tag by address. */
    fun remove(address: String) { tags.remove(address) }

    /** Removes all stored tags. */
    fun clear() = tags.clear()
}
