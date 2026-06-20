package com.jnj.assettracker

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.text.InputType
import android.view.View
import android.widget.EditText
import android.widget.GridLayout
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import com.jnj.assettracker.databinding.ActivityMainBinding
import java.net.Inet4Address
import java.net.NetworkInterface

class MainActivity : AppCompatActivity() {

    companion object {}

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

    // ── Permission launcher ───────────────────────────────────────────────────

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { results ->
        if (results.values.all { it }) {
            requestBatteryOptimisationExemption()
        } else {
            Toast.makeText(this, "Bluetooth permissions are required for BLE scanning",
                Toast.LENGTH_LONG).show()
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupVersion()
        setupModeSelector()
        setupSettings()
        setupButtons()
        setupTagList()
        restoreLastLabSelection()
        restoreSettings()
        TagRepository.loadFromPrefs(this)
        requestBlePermissions()
    }

    override fun onResume() {
        super.onResume()
        updateEndpointPrefix()
        tagRefreshHandler.post(tagRefreshRunnable)
    }

    override fun onPause() {
        super.onPause()
        tagRefreshHandler.removeCallbacks(tagRefreshRunnable)
    }

    // ── Version ───────────────────────────────────────────────────────────────

    private fun setupVersion() {
        try {
            val versionName = packageManager.getPackageInfo(packageName, 0).versionName
            binding.tvVersion.text = "v$versionName"
        } catch (_: Exception) {
            binding.tvVersion.text = "v1.0"
        }
    }

    // ── Tag list ──────────────────────────────────────────────────────────────

    private fun setupTagList() {
        tagAdapter = TagAdapter(
            onRename    = { showRenameDialog(it) },
            onColorPick = { showColorDialog(it) },
            onRemove    = { showRemoveDialog(it) },
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
            totalCount == 0           -> getString(R.string.label_active_tags)
            activeCount == totalCount -> "${getString(R.string.label_active_tags)}  ·  $totalCount seen"
            else                      -> "${getString(R.string.label_active_tags)}  ·  $activeCount active / $totalCount total"
        }
        binding.tvNoTags.visibility = if (tags.isEmpty()) View.VISIBLE else View.GONE
    }

    // ── Mode selector ─────────────────────────────────────────────────────────

    private fun setupModeSelector() {
        binding.rgMode.setOnCheckedChangeListener { _: RadioGroup, checkedId: Int ->
            val isAggregator = checkedId == R.id.rbAggregator
            binding.layoutAggregatorUrl.visibility = if (isAggregator) View.VISIBLE else View.GONE
            binding.layoutWebServiceUrl.visibility = if (isAggregator) View.GONE else View.VISIBLE
            binding.layoutPushInterval.visibility  = if (isAggregator) View.VISIBLE else View.GONE
            if (!isAggregator) updateEndpointPrefix()
        }
    }

    // ── Settings ──────────────────────────────────────────────────────────────

    private fun setupSettings() {
        binding.switchFilterPop.setOnCheckedChangeListener { _, isChecked ->
            TagRepository.filterPopOnly = isChecked
            getSharedPreferences(WebServerService.PREFS_NAME, MODE_PRIVATE)
                .edit().putBoolean(WebServerService.PREF_FILTER_POP, isChecked).apply()
        }
    }

    private fun restoreSettings() {
        val prefs = getSharedPreferences(WebServerService.PREFS_NAME, MODE_PRIVATE)

        // Mode (default: aggregator = true)
        val isAggregator = prefs.getBoolean(WebServerService.PREF_PUSH_ENABLED, true)
        binding.rgMode.check(if (isAggregator) R.id.rbAggregator else R.id.rbWebService)
        binding.layoutAggregatorUrl.visibility = if (isAggregator) View.VISIBLE else View.GONE
        binding.layoutWebServiceUrl.visibility = if (isAggregator) View.GONE else View.VISIBLE
        binding.layoutPushInterval.visibility  = if (isAggregator) View.VISIBLE else View.GONE

        // Aggregator URL
        val aggregatorUrl = prefs.getString(WebServerService.PREF_AGGREGATOR_URL,
            WebServerService.DEFAULT_AGGREGATOR_URL) ?: WebServerService.DEFAULT_AGGREGATOR_URL
        binding.etAggregatorUrl.setText(aggregatorUrl)

        // Web service port
        val port = prefs.getInt(WebServerService.PREF_PORT, WebServerService.DEFAULT_PORT)
        binding.etWebServicePort.setText(port.toString())

        // Intervals
        val aliveInterval = prefs.getInt(WebServerService.PREF_ALIVE_INTERVAL,
            WebServerService.DEFAULT_ALIVE_INTERVAL)
        binding.etAliveInterval.setText(aliveInterval.toString())

        val scanInterval = prefs.getInt(WebServerService.PREF_SCAN_INTERVAL,
            WebServerService.DEFAULT_SCAN_INTERVAL)
        binding.etScanInterval.setText(scanInterval.toString())

        val pushInterval = prefs.getInt(WebServerService.PREF_PUSH_INTERVAL,
            WebServerService.DEFAULT_PUSH_INTERVAL)
        binding.etPushInterval.setText(pushInterval.toString())

        // Filter toggle (default: on)
        val filterPop = prefs.getBoolean(WebServerService.PREF_FILTER_POP, true)
        binding.switchFilterPop.isChecked = filterPop
        TagRepository.filterPopOnly = filterPop
        TagRepository.TAG_ACTIVE_MS = aliveInterval * 1_000L
    }

    private fun saveSettings() {
        val isAggregator = binding.rgMode.checkedRadioButtonId == R.id.rbAggregator
        val aliveInterval  = binding.etAliveInterval.text.toString().toIntOrNull()
            ?: WebServerService.DEFAULT_ALIVE_INTERVAL
        val scanInterval   = binding.etScanInterval.text.toString().toIntOrNull()
            ?: WebServerService.DEFAULT_SCAN_INTERVAL
        val pushInterval   = binding.etPushInterval.text.toString().toIntOrNull()
            ?: WebServerService.DEFAULT_PUSH_INTERVAL
        val port           = binding.etWebServicePort.text.toString().toIntOrNull()
            ?: WebServerService.DEFAULT_PORT
        val aggregatorUrl  = binding.etAggregatorUrl.text.toString().trim()
            .ifEmpty { WebServerService.DEFAULT_AGGREGATOR_URL }

        getSharedPreferences(WebServerService.PREFS_NAME, MODE_PRIVATE).edit()
            .putBoolean(WebServerService.PREF_PUSH_ENABLED,   isAggregator)
            .putInt(WebServerService.PREF_ALIVE_INTERVAL,     aliveInterval)
            .putInt(WebServerService.PREF_SCAN_INTERVAL,      scanInterval)
            .putInt(WebServerService.PREF_PUSH_INTERVAL,      pushInterval)
            .putInt(WebServerService.PREF_PORT,               port)
            .putString(WebServerService.PREF_AGGREGATOR_URL,  aggregatorUrl)
            .putBoolean(WebServerService.PREF_FILTER_POP,     binding.switchFilterPop.isChecked)
            .apply()

        TagRepository.TAG_ACTIVE_MS  = aliveInterval * 1_000L
        TagRepository.filterPopOnly  = binding.switchFilterPop.isChecked
    }

    // ── Buttons ───────────────────────────────────────────────────────────────

    private fun setupButtons() {
        binding.btnStart.setOnClickListener {
            if (!checkBlePermissions()) { requestBlePermissions(); return@setOnClickListener }
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

        binding.btnViewLog.setOnClickListener { showLogDialog() }

        updateButtonState()
    }

    // ── Service control ───────────────────────────────────────────────────────

    private fun startScanService(labId: String) {
        saveSettings()
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
            binding.tvScanStatus.text = "● SCANNING"
            binding.tvScanStatus.setTextColor(0xFF43A047.toInt())
        } else {
            binding.tvScanStatus.text = "● STOPPED"
            binding.tvScanStatus.setTextColor(0xFF78909C.toInt())
        }
    }

    // ── Endpoint prefix (web service mode) ───────────────────────────────────

    private fun updateEndpointPrefix() {
        val ip = getLanIpAddress() ?: "--"
        binding.tvEndpointPrefix.text = "http://$ip:"
    }

    // ── Log dialog ────────────────────────────────────────────────────────────

    private fun showLogDialog() {
        Thread {
            val log = try {
                val pid = android.os.Process.myPid()
                val proc = Runtime.getRuntime()
                    .exec(arrayOf("logcat", "-d", "-t", "300", "--pid=$pid"))
                proc.inputStream.bufferedReader().readText()
            } catch (e: Exception) {
                "Error reading log: ${e.message}"
            }
            runOnUiThread { showLogText(log) }
        }.start()
    }

    @SuppressLint("SetTextI18n")
    private fun showLogText(log: String) {
        val textView = TextView(this).apply {
            text = log.ifBlank { "(No log entries found)" }
            textSize = 10f
            typeface = Typeface.MONOSPACE
            setTextColor(0xFFECEFF1.toInt())
            setPadding(32, 32, 32, 32)
        }
        val scrollView = ScrollView(this).apply {
            addView(textView)
            // scroll to bottom
            post { fullScroll(ScrollView.FOCUS_DOWN) }
        }
        AlertDialog.Builder(this)
            .setTitle("App Log")
            .setView(scrollView)
            .setNeutralButton("Copy All") { _, _ ->
                copyToClipboard("App Log", log)
            }
            .setNegativeButton("Close", null)
            .show()
    }

    // ── Lab field ─────────────────────────────────────────────────────────────

    private fun restoreLastLabSelection() {
        val prefs = getSharedPreferences(WebServerService.PREFS_NAME, MODE_PRIVATE)
        val lastLab = prefs.getString(WebServerService.PREF_LAB_ID, null) ?: return
        binding.etLabId.setText(lastLab)
    }

    private fun saveLabId() {
        val labId = binding.etLabId.text.toString().trim()
        if (labId.isEmpty()) return
        getSharedPreferences(WebServerService.PREFS_NAME, MODE_PRIVATE)
            .edit().putString(WebServerService.PREF_LAB_ID, labId).apply()
    }

    // ── Tag dialogs ───────────────────────────────────────────────────────────

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
                    width = swatchPx; height = swatchPx
                    setMargins(marginPx, marginPx, marginPx, marginPx)
                }
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(color.argb)
                    if (entry.colorIndex == index)
                        setStroke((3 * density).toInt(), 0xFFFFFFFF.toInt())
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

    private fun showRemoveDialog(entry: TagEntry) {
        AlertDialog.Builder(this)
            .setTitle("Remove Tag")
            .setMessage("Remove \"${entry.displayName}\" from known connections?")
            .setPositiveButton("Remove") { _, _ -> TagRepository.remove(entry.address) }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ── Clipboard ─────────────────────────────────────────────────────────────

    private fun copyToClipboard(label: String, text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
        Toast.makeText(this, "Copied", Toast.LENGTH_SHORT).show()
    }

    // ── Network helpers ───────────────────────────────────────────────────────

    private fun getLanIpAddress(): String? = try {
        NetworkInterface.getNetworkInterfaces()
            ?.asSequence()
            ?.filter { it.isUp && !it.isLoopback }
            ?.flatMap { it.inetAddresses.asSequence() }
            ?.filterIsInstance<Inet4Address>()
            ?.filterNot { it.isLoopbackAddress }
            ?.map { it.hostAddress }
            ?.firstOrNull()
    } catch (_: Exception) { null }

    // ── Bluetooth helpers ─────────────────────────────────────────────────────

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
            permissionLauncher.launch(arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
            ))
        } else {
            requestBatteryOptimisationExemption()
        }
    }

    private fun requestBatteryOptimisationExemption() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            })
        }
    }
}


