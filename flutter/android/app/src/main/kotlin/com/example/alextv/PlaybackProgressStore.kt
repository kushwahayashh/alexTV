package com.example.alextv

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * On-device store of Library watch progress, ported from the reference app.
 *
 * Progress is keyed on a file's stable backend path (e.g.
 * "/Breaking Bad/S01E01.mkv"), NOT the stream URL — the Library streams through
 * a fast tunnel whose URL can change or expire, but the path is stable. Playback
 * launched without a mediaPath (e.g. TMDB/Details) passes a blank key and is
 * simply not tracked.
 *
 * Entries live in SharedPreferences as one JSON object keyed by mediaPath. An
 * entry is dropped once playback is effectively complete (≥95% watched or <60s
 * remaining) and only offered as a resume point past 30s with >30s remaining.
 */
object PlaybackProgressStore {
    private const val PREFS_NAME = "playback_progress"
    private const val KEY_ENTRIES = "entries"
    private const val MIN_TRACKED_POSITION_MS = 5_000L
    private const val MIN_RESUME_POSITION_MS = 30_000L
    private const val MIN_REMAINING_FOR_RESUME_MS = 30_000L
    private const val COMPLETION_REMAINING_MS = 60_000L
    private const val COMPLETION_RATIO = 0.95

    data class Entry(
        val mediaPath: String,
        val title: String,
        val positionMs: Long,
        val durationMs: Long,
        val updatedAt: Long
    ) {
        fun progressFraction(): Double {
            if (durationMs <= 0L) return 0.0
            return (positionMs.toDouble() / durationMs.toDouble()).coerceIn(0.0, 1.0)
        }

        fun shouldResume(): Boolean {
            if (positionMs < MIN_RESUME_POSITION_MS) return false
            if (durationMs <= 0L) return false
            return durationMs - positionMs > MIN_REMAINING_FOR_RESUME_MS
        }
    }

    fun getResumePositionMs(context: Context, mediaPath: String): Long {
        return getEntry(context, mediaPath)?.takeIf { it.shouldResume() }?.positionMs ?: 0L
    }

    fun saveProgress(
        context: Context,
        mediaPath: String,
        title: String,
        positionMs: Long,
        durationMs: Long
    ) {
        if (mediaPath.isBlank()) return

        if (shouldClearEntry(positionMs, durationMs)) {
            clearProgress(context, mediaPath)
            return
        }

        if (positionMs < MIN_TRACKED_POSITION_MS) {
            return
        }

        val entries = readEntries(context)
        entries.put(
            mediaPath,
            JSONObject().apply {
                put("mediaPath", mediaPath)
                put("title", title)
                put("positionMs", positionMs.coerceAtLeast(0L))
                put("durationMs", durationMs.coerceAtLeast(0L))
                put("updatedAt", System.currentTimeMillis())
            }
        )
        writeEntries(context, entries)
    }

    fun clearProgress(context: Context, mediaPath: String) {
        if (mediaPath.isBlank()) return
        val entries = readEntries(context)
        entries.remove(mediaPath)
        writeEntries(context, entries)
    }

    fun clearAll(context: Context) {
        writeEntries(context, JSONObject())
    }

    /** Progress for a set of paths, as a JSON object keyed by mediaPath. */
    fun getProgressPayload(context: Context, pathsJson: String): String {
        val result = JSONObject()
        val paths = try {
            JSONArray(pathsJson)
        } catch (_: Exception) {
            JSONArray()
        }

        for (i in 0 until paths.length()) {
            val mediaPath = paths.optString(i)
            if (mediaPath.isBlank()) continue
            val entry = getEntry(context, mediaPath) ?: continue
            result.put(
                mediaPath,
                JSONObject().apply {
                    put("title", entry.title)
                    put("positionMs", entry.positionMs)
                    put("durationMs", entry.durationMs)
                    put("updatedAt", entry.updatedAt)
                    put("progress", entry.progressFraction())
                    put("shouldResume", entry.shouldResume())
                }
            )
        }

        return result.toString()
    }

    private fun getEntry(context: Context, mediaPath: String): Entry? {
        if (mediaPath.isBlank()) return null
        val entry = readEntries(context).optJSONObject(mediaPath) ?: return null
        return Entry(
            mediaPath = mediaPath,
            title = entry.optString("title"),
            positionMs = entry.optLong("positionMs"),
            durationMs = entry.optLong("durationMs"),
            updatedAt = entry.optLong("updatedAt")
        )
    }

    private fun shouldClearEntry(positionMs: Long, durationMs: Long): Boolean {
        if (durationMs <= 0L) return false
        val remainingMs = durationMs - positionMs
        val ratio = if (durationMs > 0L) positionMs.toDouble() / durationMs.toDouble() else 0.0
        return remainingMs <= COMPLETION_REMAINING_MS || ratio >= COMPLETION_RATIO
    }

    private fun readEntries(context: Context): JSONObject {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_ENTRIES, null) ?: return JSONObject()
        return try {
            JSONObject(raw)
        } catch (_: Exception) {
            JSONObject()
        }
    }

    private fun writeEntries(context: Context, entries: JSONObject) {
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_ENTRIES, entries.toString())
            .apply()
    }
}
