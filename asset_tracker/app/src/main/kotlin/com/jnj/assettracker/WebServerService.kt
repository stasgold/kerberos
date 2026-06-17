package com.jnj.assettracker

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.IOException

/**
 * Foreground service that runs the BLE scanner and HTTP server for one lab.
 *
 * Lifecycle (AT-SRD-001 §3.2.2):
 *  - Acquires PARTIAL_WAKE_LOCK  → prevents CPU sleep           (APP-NF-05)
 *  - Acquires WIFI_MODE_FULL_HIGH_PERF WifiLock → no Wi-Fi sleep (APP-NF-04)
 *  - Returns START_STICKY → OS restarts the service if killed    (APP-F-10)
 *  - Persists the selected lab ID to SharedPreferences for the
 *    BootReceiver to use on device reboot.
 *
 * The foreground notification keeps the service visible to the user and
 * is mandatory to prevent OS process termination on modern Android.
 */
class WebServerService : Service() {

    companion object {
        private const val TAG = "WebServerService"

        /** Intent extra: lab ID string (e.g. "F2-LAB-A") */
        const val EXTRA_LAB_ID = "lab_id"

        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "asset_tracker_service"

        const val PREFS_NAME = "asset_tracker_prefs"
        const val PREF_LAB_ID = "last_lab_id"
        const val PREF_PORT = "server_port"
        const val PREF_ALIVE_INTERVAL = "alive_interval_sec"
        const val PREF_FILTER_POP = "filter_pop_only"
        const val DEFAULT_PORT = 80
        const val DEFAULT_ALIVE_INTERVAL = 60
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var bleScanner: BleScanner? = null
    private var localServer: LocalServer? = null
    private var labId: String = "UNKNOWN"
    private var serverPort: Int = DEFAULT_PORT

    // ── Service lifecycle ─────────────────────────────────────────────────────

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    @SuppressLint("MissingPermission", "WakelockTimeout")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Resolve lab ID: prefer the value from the Intent; fall back to the
        // value persisted by the last successful start (used by BootReceiver).
        labId = intent?.getStringExtra(EXTRA_LAB_ID)
            ?: getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .getString(PREF_LAB_ID, "UNKNOWN")
            ?: "UNKNOWN"

        // Persist for BootReceiver
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putString(PREF_LAB_ID, labId)
            .apply()

        // Read configurable settings
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        serverPort = prefs.getInt(PREF_PORT, DEFAULT_PORT)
        val aliveIntervalSec = prefs.getInt(PREF_ALIVE_INTERVAL, DEFAULT_ALIVE_INTERVAL)
        TagRepository.TAG_ACTIVE_MS = aliveIntervalSec * 1_000L
        TagRepository.filterPopOnly = prefs.getBoolean(PREF_FILTER_POP, false)

        // Promote to foreground immediately (must happen within 5 s on API 31+)
        // Pass foreground service type for Android 14+ enforcement (API 34).
        startForeground(
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )

        // ── WakeLock (PARTIAL) — keeps CPU awake (APP-NF-05) ──────────────
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "AssetTracker:WakeLock",
        ).also { it.acquire() }

        // ── WifiLock (HIGH_PERF) — prevents Wi-Fi power saving (APP-NF-04) ─
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION") // WIFI_MODE_FULL_HIGH_PERF is the correct mode here
        wifiLock = wm.createWifiLock(
            WifiManager.WIFI_MODE_FULL_HIGH_PERF,
            "AssetTracker:WifiLock",
        ).also { it.acquire() }

        // ── BLE scanner ───────────────────────────────────────────────────
        val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bleScanner = BleScanner(btManager.adapter).also { it.start() }

        // ── HTTP server on configured port ────────────────────────────────
        try {
            localServer = LocalServer(labId, serverPort).also { it.start() }
            Log.i(TAG, "HTTP server started on port $serverPort for lab=$labId")
        } catch (e: IOException) {
            Log.e(TAG, "Failed to start HTTP server: ${e.message}")
        }

        Log.i(TAG, "Service started: lab=$labId")
        return START_STICKY
    }

    override fun onDestroy() {
        bleScanner?.stop()
        localServer?.stop()
        wakeLock?.release()
        wifiLock?.release()
        wakeLock = null
        wifiLock = null
        TagRepository.saveToPrefs(this)
        Log.i(TAG, "Service stopped")
        super.onDestroy()
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Asset Tracker Service",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Persistent notification while BLE scanning is active"
            setShowBadge(false)
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Asset Tracker — $labId")
            .setContentText("BLE scanning active  ·  HTTP :$serverPort")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .build()
    }
}
