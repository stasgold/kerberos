package com.jnj.assettracker

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.util.Log

/**
 * Service UUIDs advertised by Chipolo / FMDN tags.
 * Used as a secondary detection method when the device name is not in the
 * advertisement payload (FMDN tags occasionally omit the Complete Local Name).
 *
 * 0xFE65 — FMDN (Find My Device Network) service
 * 0xFE2C — Chipolo legacy service
 * 0xFEE0 / 0xFEE1 — Chipolo POP services
 */
private val CHIPOLO_SERVICE_UUIDS = setOf(
    "0000fe65-0000-1000-8000-00805f9b34fb",
    "0000fe2c-0000-1000-8000-00805f9b34fb",
    "0000fee0-0000-1000-8000-00805f9b34fb",
    "0000fee1-0000-1000-8000-00805f9b34fb",
)

/**
 * Wraps [android.bluetooth.le.BluetoothLeScanner].
 *
 * Scanning is performed in SCAN_MODE_LOW_LATENCY (APP-NF-02).
 * Results are filtered by device name containing "chipolo" (case-insensitive)
 * per APP-F-02, with a UUID-based fallback for FMDN tags that omit the name.
 * Matching tags are fed into [TagRepository].
 *
 * Requires BLUETOOTH_SCAN and BLUETOOTH_CONNECT runtime permissions which
 * are requested by [MainActivity] before the service is started.
 */
@SuppressLint("MissingPermission")
class BleScanner(private val bluetoothAdapter: BluetoothAdapter) {

    companion object {
        private const val TAG = "BleScanner"
    }

    private val leScanner = bluetoothAdapter.bluetoothLeScanner
    private var scanCallback: ScanCallback? = null
    private var _scanning = false

    val isScanning: Boolean get() = _scanning

    /** Start continuous BLE scanning in SCAN_MODE_LOW_LATENCY. */
    fun start() {
        if (_scanning || leScanner == null) {
            Log.w(TAG, "start() skipped: scanning=$_scanning, scanner=$leScanner")
            return
        }

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
            .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
            .setReportDelay(0L) // deliver results immediately
            .build()

        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                processResult(result)
            }

            override fun onBatchScanResults(results: List<ScanResult>) {
                results.forEach { processResult(it) }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.e(TAG, "BLE scan failed with error code: $errorCode")
            }
        }

        // No hardware ScanFilter: filtering is performed in processResult()
        // so that partial name matching (case-insensitive) works correctly.
        leScanner.startScan(null, settings, scanCallback!!)
        _scanning = true
        Log.i(TAG, "BLE scan started (SCAN_MODE_LOW_LATENCY, no hardware filter)")
    }

    /** Stop the BLE scan and release the callback. */
    fun stop() {
        if (!_scanning || leScanner == null) return
        scanCallback?.let { leScanner.stopScan(it) }
        scanCallback = null
        _scanning = false
        Log.i(TAG, "BLE scan stopped")
    }

    // ── Internal ─────────────────────────────────────────────────────────────

    private fun processResult(result: ScanResult) {
        if (!isChipolo(result)) return

        val address = result.device.address

        // Prefer the name from the advertisement payload (no extra permission
        // needed) over the cached platform name (requires BLUETOOTH_CONNECT).
        val name = result.scanRecord?.deviceName
            ?.takeIf { it.isNotBlank() }
            ?: result.device.name
            ?: address

        TagRepository.update(address = address, name = name, rssi = result.rssi)
    }

    /**
     * Returns true if the scan result is from a Chipolo / FMDN tag.
     *
     * Detection order (matches chipolo_monitor_app logic):
     * 1. Device name in advertisement contains "chipolo" (design requirement).
     * 2. Advertisement carries a known Chipolo/FMDN service UUID.
     * 3. Advertisement carries service data keyed by a known UUID.
     */
    private fun isChipolo(result: ScanResult): Boolean {
        val record = result.scanRecord

        // 1. Name check (primary — per design requirements)
        val advName = record?.deviceName ?: ""
        val platName = result.device.name ?: ""
        if (advName.contains("chipolo", ignoreCase = true)) return true
        if (platName.contains("chipolo", ignoreCase = true)) return true

        // 2. Service UUID check (fallback for FMDN tags that omit the name)
        val serviceUuids = record?.serviceUuids
            ?.map { it.toString().lowercase() }
            ?.toSet() ?: emptySet()
        if (serviceUuids.intersect(CHIPOLO_SERVICE_UUIDS).isNotEmpty()) return true

        // 3. Service data key check
        val serviceDataKeys = record?.serviceData?.keys
            ?.map { it.toString().lowercase() }
            ?.toSet() ?: emptySet()
        return serviceDataKeys.intersect(CHIPOLO_SERVICE_UUIDS).isNotEmpty()
    }
}
