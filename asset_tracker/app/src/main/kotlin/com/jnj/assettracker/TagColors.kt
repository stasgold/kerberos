package com.jnj.assettracker

/**
 * Chipolo POP physical tag colors.
 * Matches the Flutter chipolo_monitor_app palette so colors are consistent
 * across both apps and the /tags JSON API.
 */
data class TagColor(val label: String, val argb: Int)

val CHIPOLO_TAG_COLORS = listOf(
    TagColor("Red",    0xFFE53935.toInt()),
    TagColor("Black",  0xFF424242.toInt()),
    TagColor("White",  0xFFEEEEEE.toInt()),
    TagColor("Yellow", 0xFFFFD600.toInt()),
    TagColor("Green",  0xFF43A047.toInt()),
    TagColor("Blue",   0xFF1E88E5.toInt()),
    TagColor("Orange", 0xFFFF6D00.toInt()),
    TagColor("Pink",   0xFFEC407A.toInt()),
)
