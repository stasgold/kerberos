package com.jnj.assettracker

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.jnj.assettracker.databinding.ItemTagBinding
import java.util.concurrent.TimeUnit

/**
 * RecyclerView adapter for the live tag list in [MainActivity].
 *
 * Active tags (seen in the last 10 s) are rendered at full brightness.
 * Stale tags are dimmed and show "last seen X ago" instead of RSSI.
 */
class TagAdapter(
    private val onRename: (TagEntry) -> Unit,
    private val onColorPick: (TagEntry) -> Unit,
    private val onRemove: (TagEntry) -> Unit,
) : RecyclerView.Adapter<TagAdapter.ViewHolder>() {

    private var items: List<TagEntry> = emptyList()

    fun submitList(list: List<TagEntry>) {
        items = list
        notifyDataSetChanged()
    }

    inner class ViewHolder(val binding: ItemTagBinding) :
        RecyclerView.ViewHolder(binding.root)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val binding = ItemTagBinding.inflate(
            LayoutInflater.from(parent.context), parent, false,
        )
        return ViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val tag = items[position]
        val b = holder.binding
        val active = tag.isActive()

        b.tvTagName.text = tag.displayName
        b.tvTagAddress.text = if (active) tag.address else "${tag.address}  ·  ${lastSeenText(tag.lastSeen)}"

        if (active) {
            b.tvTagRssi.text = "${tag.rssi} dBm"
            b.tvTagRssi.setTextColor(rssiColor(tag.rssi))
            b.tvTagRssi.visibility = android.view.View.VISIBLE
        } else {
            b.tvTagRssi.visibility = android.view.View.GONE
        }

        // Dim stale tags
        val alpha = if (active) 1.0f else 0.45f
        b.root.alpha = alpha

        val swatchArgb = tag.colorIndex
            ?.let { CHIPOLO_TAG_COLORS.getOrNull(it)?.argb }
            ?: 0xFF30363D.toInt()
        b.viewColorSwatch.setBackgroundColor(swatchArgb)

        b.btnRename.setOnClickListener { onRename(tag) }
        b.btnColor.setOnClickListener  { onColorPick(tag) }
        b.btnDelete.setOnClickListener { onRemove(tag) }
    }

    override fun getItemCount(): Int = items.size

    private fun rssiColor(rssi: Int): Int = when {
        rssi > -60 -> 0xFF43A047.toInt()
        rssi > -75 -> 0xFFFFD600.toInt()
        else       -> 0xFFE53935.toInt()
    }

    private fun lastSeenText(lastSeen: Long): String {
        val elapsed = System.currentTimeMillis() - lastSeen
        val secs = TimeUnit.MILLISECONDS.toSeconds(elapsed)
        return when {
            secs < 60   -> "${secs}s ago"
            secs < 3600 -> "${secs / 60}m ago"
            else        -> "${secs / 3600}h ago"
        }
    }
}
