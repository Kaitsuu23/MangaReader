package org.dhiksn.yomika

import android.content.Context
import android.util.Log
import androidx.work.*
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Manages scheduling of AndroidX WorkManager tasks for periodic and manual chapter update checking.
 * Matches Kotatsu-Redo's TrackWorker.Scheduler architecture:
 * - Uses PeriodicWorkRequestBuilder with BackoffPolicy.LINEAR.
 * - Enforces NetworkType constraints (CONNECTED or UNMETERED for Wi-Fi only).
 * - Enqueues unique periodic work with ExistingPeriodicWorkPolicy.UPDATE.
 */
object TrackerWorkScheduler {

    const val TAG = "yomika_tracker_work"
    const val TAG_ONESHOT = "yomika_tracker_work_oneshot"
    private const val LOG_TAG = "TrackerWorkScheduler"

    fun schedulePeriodicWork(context: Context, frequencyHours: Int, isWifiOnly: Boolean) {
        val hours = frequencyHours.coerceIn(1, 48).toLong()

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(if (isWifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED)
            .build()

        val request = PeriodicWorkRequestBuilder<TrackerWorker>(hours, TimeUnit.HOURS)
            .setConstraints(constraints)
            .addTag(TAG)
            .setBackoffCriteria(BackoffPolicy.LINEAR, 30, TimeUnit.MINUTES)
            .build()

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            TAG,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
        Log.i(LOG_TAG, "Scheduled unique periodic work: interval=$hours hours, isWifiOnly=$isWifiOnly")
    }

    fun cancelPeriodicWork(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(TAG)
        Log.i(LOG_TAG, "Cancelled unique periodic work")
    }

    fun startNow(context: Context, isWifiOnly: Boolean = false) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(if (isWifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED)
            .build()

        val request = OneTimeWorkRequestBuilder<TrackerWorker>()
            .setConstraints(constraints)
            .addTag(TAG_ONESHOT)
            .build()

        WorkManager.getInstance(context).enqueue(request)
        Log.i(LOG_TAG, "Enqueued immediate one-shot work")
    }

    /**
     * Ensures periodic work is scheduled based on existing tracker_config.json if enabled.
     * Useful on application startup and after device reboots.
     */
    fun ensureScheduled(context: Context) {
        val configFile = TrackerCheckExecutor.getConfigFile(context)
        if (!configFile.exists()) return

        try {
            val configJson = JSONObject(configFile.readText(Charsets.UTF_8))
            val isEnabled = configJson.optBoolean("enabled", true)
            val frequencyHours = configJson.optInt("frequencyHours", 1)
            val isWifiOnly = configJson.optBoolean("wifiOnly", false)

            if (isEnabled) {
                schedulePeriodicWork(context, frequencyHours, isWifiOnly)
            } else {
                cancelPeriodicWork(context)
            }
        } catch (e: Exception) {
            Log.e(LOG_TAG, "Failed to read config in ensureScheduled: ${e.message}")
        }
    }
}
