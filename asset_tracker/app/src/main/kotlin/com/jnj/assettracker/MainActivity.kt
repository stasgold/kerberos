package com.jnj.assettracker

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.text.InputType
import android.view.View
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.GridLayout
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import com.jnj.assettracker.databinding.ActivityMainBinding
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Main activity — configuration and control panel for the BLE scanner service.
 *
 * UI elements (AT-SRD-001 §3.3):
 *  ① Lab ID dropdown (Spinner) — predefined list matching config.py keys
 *  ② Start button  — launches [WebServerService] with selected lab ID
 *  ③ Stop button   — stops [WebServerService]
 *  ④ LAN IP display (read-only) — shows current Wi-Fi IP address (APP-F-08)
 *  ⑤ Endpoint display — shows the full /tags URL for convenience
 *
 * On first launch, BLUETOOTH_SCAN and BLUETOOTH_CONNECT runtime permissions
 * are requested.  After permissions are granted the activity prompts the user
 * to exempt the app from battery optimisation (APP-NF-06).
 */
class MainActivity : AppCompatActivity() {

    companion object {
        /**
         * Lab IDs displayed in the dropdown.
         * MUST exactly match the keys in config.py LABS dict on the aggregator
         * (AT-SRD-001 §3.3 Configuration Note).
         */
        val LAB_IDS = listOf("F1-LAB-A", "F1-LAB-B", "F2-LAB-A", "F2-LAB-B", "F3-LAB-A")
    }

    private lateinit var binding: ActivityMainBinding
    private var serviceRunning = false

    private lateinit var tagAdapter: TagAdapter
    private val tagRefreshHandler = Handler(Looper.getMainLooper())
    private val tagRefreshRunnable = object : Runnable {
        override fun run() {
            refreshTagList()
            tagRefreshHandler.postDelayed(this, 1_000L)
        }
    }

    // ── Permission request launcher ───────────────────────────────────────────

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { results ->
        val allGranted = results.values.all { it }
        if (!allGranted) {
            Toast.makeText(
                this,
                "Bluetooth permissions are required for BLE scanning",
                Toast.LENGTH_LONG,
            ).show()
        } else {
            // Permissions granted — request battery optimisation exemption
            requestBatteryOptimisationExemption()
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupLabDropdown()
        setupButtons()
        setupTagList()
        restoreLastLabSelection()
        TagRepository.loadFromPrefs(this)
        requestBlePermissions()
    }

    override fun onResume() {
        super.onResume()
        // Refresh IP every time the screen comes back (e.g. after Wi-Fi change)
        updateNetworkInfo()
        // Start 1-second tag list polling
        tagRefreshHandler.post(tagRefreshRunnable)
    }

    override fun onPause() {
        super.onPause()
        tagRefreshHandler.removeCallbacks(tagRefreshRunnable)
    }

    // ── UI setup ──────────────────────────────────────────────────────────────

    private fun setupTagList() {
        tagAdapter = TagAdapter(
            onRename    = { showRenameDialog(it) },
            onColorPick = { showColorDialog(it) },
        )
        binding.rvTags.apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = tagAdapter
        }
    }

    private fun refreshTagList() {
        val tags = TagRepository.getAllTags()
        tagAdapter.submitList(tags)
        val activeCount = tags.count { it.isActive() }
        val totalCount  = tags.size
        binding.tvTagsHeader.text = when {
            totalCount == 0           -> "Active Tags"
            activeCount == totalCount -> "Active Tags  ·  $totalCount seen"
            else                      -> "Active Tags  ·  $activeCount active  /  $totalCount total"
        }
        binding.tvNoTags.visibility = if (tags.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE
    }

    private fun showRenameDialog(entry: TagEntry) {
        val input = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_WORDS
            setText(entry.customName ?: entry.name)
            hint = getString(R.string.hint_tag_name)
            selectAll()
            setPadding(48, 32, 48, 16)
        }
        AlertDialog.Builder(this)
            .setTitle("Rename Tag")
            .setView(input)
            .setPositiveButton("Save") { _, _ ->
                val newName = input.text.toString().trim()
                TagRepository.setMeta(entry.address, newName.ifEmpty { null }, entry.colorIndex)
            }
            .setNeutralButton("Clear") { _, _ ->
                TagRepository.setMeta(entry.address, null, entry.colorIndex)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showColorDialog(entry: TagEntry) {
        val density = resources.displayMetrics.density
        val swatchPx = (52 * density).toInt()
        val marginPx = (8 * density).toInt()

        val grid = GridLayout(this).apply {
            columnCount = 4
            setPadding(marginPx * 2, marginPx * 2, marginPx * 2, marginPx)
        }

        var dialog: AlertDialog? = null

        CHIPOLO_TAG_COLORS.forEachIndexed { index, color ->
            val swatch = View(this).apply {
                layoutParams = GridLayout.LayoutParams().apply {
                    width = swatchPx
                    height = swatchPx
                    setMargins(marginPx, marginPx, marginPx, marginPx)
                }
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(color.argb)
                    if (entry.colorIndex == index) {
                        setStroke((3 * density).toInt(), 0xFFFFFFFF.toInt())
                    }
                }
                contentDescription = color.label
                setOnClickListener {
                    TagRepository.setMeta(entry.address, entry.customName, index)
                    dialog?.dismiss()
                }
            }
            grid.addView(swatch)
        }

        dialog = AlertDialog.Builder(this)
            .setTitle("Tag Color — ${entry.displayName}")
            .setView(grid)
            .setNeutralButton("Clear Color") { _, _ ->
                TagRepository.setMeta(entry.address, entry.customName, null)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun setupLabDropdown() {
        val adapter = ArrayAdapter(
            this,
            android.R.layout.simple_dropdown_item_1line,
            LAB_IDS,
        )
        binding.etLabId.setAdapter(adapter)
        binding.etLabId.threshold = 0
        // Show suggestions on tap even with empty text
        binding.etLabId.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) {
                binding.etLabId.showDropDown()
            } else {
                // Save the lab name whenever the field loses focus
                saveLabId()
            }
        }
        binding.etLabId.setOnClickListener { binding.etLabId.showDropDown() }
    }

    private fun restoreLastLabSelection() {
        val prefs = getSharedPreferences(WebServerService.PREFS_NAME, MODE_PRIVATE)
        val lastLab = prefs.getString(WebServerService.PREF_LAB_ID, null) ?: return
        binding.etLabId.setText(lastLab)
    }

    /** Persist the current lab name without starting the service. */
    private fun saveLabId() {
        val labId = binding.etLabId.text.toString().trim()
        if (labId.isEmpty()) return
        getSharedPreferences(WebServerService.PREFS_NAME, MODE_PRIVATE)
            .edit().putString(WebServerService.PREF_LAB_ID, labId).apply()
    }

    private fun setupButtons() {
        binding.btnStart.setOnClickListener {
            if (!checkBlePermissions()) {
                requestBlePermissions()
                return@setOnClickListener
            }
            if (!isBluetoothEnabled()) {
                Toast.makeText(this, "Please enable Bluetooth", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            val labId = binding.etLabId.text.toString().trim()
            if (labId.isEmpty()) {
                binding.etLabId.error = "Enter a lab name"
                return@setOnClickListener
            }
            startScanService(labId)
        }

        binding.btnStop.setOnClickListener { stopScanService() }

        updateButtonState()
    }

    // ── Service control ───────────────────────────────────────────────────────

    private fun startScanService(labId: String) {
        val intent = Intent(this, WebServerService::class.java).apply {
            putExtra(WebServerService.EXTRA_LAB_ID, labId)
        }
        startForegroundService(intent)
        serviceRunning = true
        updateButtonState()
        Toast.makeText(this, "Scanner started for $labId", Toast.LENGTH_SHORT).show()
    }

    private fun stopScanService() {
        stopService(Intent(this, WebServerService::class.java))
        serviceRunning = false
        updateButtonState()
        Toast.makeText(this, "Scanner stopped", Toast.LENGTH_SHORT).show()
    }

    private fun updateButtonState() {
        binding.btnStart.isEnabled = !serviceRunning
        binding.btnStop.isEnabled  = serviceRunning
        if (serviceRunning) {
            binding.tvScanStatus.text      = "●  SCANNING"
            binding.tvScanStatus.setTextColor(0xFF43A047.toInt()) // green
        } else {
            binding.tvScanStatus.text      = "●  STOPPED"
            binding.tvScanStatus.setTextColor(0xFF78909C.toInt()) // gray
        }
    }

    // ── Network info ──────────────────────────────────────────────────────────

    @SuppressLint("SetTextI18n")
    private fun updateNetworkInfo() {
        val ip = getLanIpAddress()
        if (ip != null) {
            binding.tvLanIp.text = "LAN IP: $ip"
            binding.tvEndpoint.text = "Endpoint: http://$ip:${LocalServer.PORT}/tags"
        } else {
            binding.tvLanIp.text = "LAN IP: (not connected)"
            binding.tvEndpoint.text = "Endpoint: (not available)"
        }
    }

    /** Returns the device's IPv4 address on the current Wi-Fi network, or null. */
    private fun getLanIpAddress(): String? {
        return try {
            NetworkInterface.getNetworkInterfaces()
                ?.asSequence()
                ?.filter { it.isUp && !it.isLoopback }
                ?.flatMap { it.inetAddresses.asSequence() }
                ?.filterIsInstance<Inet4Address>()
                ?.filterNot { it.isLoopbackAddress }
                ?.map { it.hostAddress }
                ?.firstOrNull()
        } catch (_: Exception) {
            null
        }
    }

    // ── Bluetooth / permission helpers ────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun isBluetoothEnabled(): Boolean {
        val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        return btManager.adapter?.isEnabled == true
    }

    private fun checkBlePermissions(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) ==
                PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED

    private fun requestBlePermissions() {
        if (!checkBlePermissions()) {
            permissionLauncher.launch(
                arrayOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT,
                )
            )
        } else {
            // Permissions already granted on this launch
            requestBatteryOptimisationExemption()
        }
    }

    /** Prompts the user to exempt the app from battery optimisation (APP-NF-06). */
    private fun requestBatteryOptimisationExemption() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
            )
        }
    }
}
