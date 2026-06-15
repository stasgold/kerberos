package com.jnj.assettracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restarts [WebServerService] automatically after device reboot (APP-F-09).
 *
 * The receiver triggers on ACTION_BOOT_COMPLETED (standard) and on
 * QUICKBOOT_POWERON (used by some HTC / OEM devices).
 *
 * The lab ID is read from SharedPreferences where [WebServerService] stored
 * it on last start.  If no lab ID is found the service is not started —
 * the user must open the app and press Start at least once before reboot
 * auto-start works.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) return

        val prefs = context.getSharedPreferences(
            WebServerService.PREFS_NAME, Context.MODE_PRIVATE,
        )
        val labId = prefs.getString(WebServerService.PREF_LAB_ID, null)
        if (labId.isNullOrBlank()) {
            Log.i(TAG, "Boot completed — no saved lab ID, skipping auto-start")
            return
        }

        Log.i(TAG, "Boot completed — restarting service for lab=$labId")
        val serviceIntent = Intent(context, WebServerService::class.java).apply {
            putExtra(WebServerService.EXTRA_LAB_ID, labId)
        }
        context.startForegroundService(serviceIntent)
    }
}
