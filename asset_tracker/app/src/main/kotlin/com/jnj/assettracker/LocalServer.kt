package com.jnj.assettracker

import fi.iki.elonen.NanoHTTPD
import org.json.JSONArray
import org.json.JSONObject

/**
 * Embedded HTTP server bound to port 8080 on all interfaces (0.0.0.0).
 *
 * Implements the /tags endpoint defined in AT-SRD-001 §3.2.4:
 *
 *   GET /tags → 200 application/json
 *   {
 *     "lab_id":    "F2-LAB-A",
 *     "timestamp": 1718350000000,
 *     "tags": [
 *       { "address": "AA:BB:CC:DD:EE:01",
 *         "name":    "Chipolo-A1",
 *         "rssi":    -62,
 *         "last_seen": 1718350000000 }
 *     ]
 *   }
 *
 * All other paths return 404 with an empty JSON object per §3.2.4.
 *
 * NanoHTTPD binds to 0.0.0.0 by default, making the server reachable on
 * every network interface including Wi-Fi (APP-NF-07).
 */
class LocalServer(private val labId: String, port: Int = PORT) : NanoHTTPD(port) {

    companion object {
        const val PORT = 80   // default port
        private const val MIME_JSON = "application/json"
    }

    override fun serve(session: IHTTPSession): Response {
        if (session.uri != "/tags") {
            return newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_JSON, "{}")
        }

        val activeTags = TagRepository.getActiveTags()

        val tagsArray = JSONArray()
        for (tag in activeTags) {
            tagsArray.put(
                JSONObject().apply {
                    put("address", tag.address)
                    put("name", tag.displayName)
                    put("ble_name", tag.name)
                    put("rssi", tag.rssi)
                    put("last_seen", tag.lastSeen)
                    put("color", tag.colorIndex?.let { CHIPOLO_TAG_COLORS.getOrNull(it)?.label })
                    put("color_index", tag.colorIndex ?: -1)
                }
            )
        }

        val body = JSONObject().apply {
            put("lab_id", labId)
            put("timestamp", System.currentTimeMillis())
            put("tags", tagsArray)
        }.toString()

        return newFixedLengthResponse(Response.Status.OK, MIME_JSON, body)
    }
}
