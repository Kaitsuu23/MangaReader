package org.dhiksn.yomika

import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * AndroidX WorkManager Worker for periodic and one-shot background chapter updates checking.
 * Matches Kotatsu-Redo's TrackWorker architecture:
 * - Managed directly by Android's system JobScheduler.
 * - Survives app kills, swipes from Recents, and device reboots.
 * - Promotes to Foreground Service to prevent OS/MIUI from killing or freezing the check.
 * - Acquires PARTIAL_WAKE_LOCK so CPU keeps running when phone is locked or screen is off.
 */
class TrackerWorker(
    private val context: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(context, workerParams) {

    companion object {
        const val TAG = "yomika_tracker_work"
        const val TAG_ONESHOT = "yomika_tracker_work_oneshot"
        private const val LOG_TAG = "TrackerWorker"
        private const val WAKELOCK_TAG = "Yomika:TrackerWorkerWakeLock"
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val notifManager = TrackerNotificationManager(applicationContext)
        val notif = notifManager.buildProgressNotification(0, 0, "Memeriksa bab baru...")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                TrackerNotificationManager.PROGRESS_NOTIFICATION_ID,
                notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(TrackerNotificationManager.PROGRESS_NOTIFICATION_ID, notif)
        }
    }

    private suspend fun trySetForeground(): Boolean = runCatching {
        val info = getForegroundInfo()
        setForeground(info)
    }.isSuccess

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val isForeground = trySetForeground()
        Log.i(LOG_TAG, "doWork started: tags=$tags, attempt=$runAttemptCount, isForeground=$isForeground")
        val notificationManager = TrackerNotificationManager(applicationContext)

        val configFile = TrackerCheckExecutor.getConfigFile(applicationContext)
        if (!configFile.exists()) {
            Log.i(LOG_TAG, "tracker_config.json not found, skipping background check")
            return@withContext Result.success()
        }

        val configJson = try {
            JSONObject(configFile.readText(Charsets.UTF_8))
        } catch (e: Exception) {
            Log.e(LOG_TAG, "Failed to parse tracker_config.json: ${e.message}")
            return@withContext Result.success()
        }

        val isEnabled = configJson.optBoolean("enabled", true)
        if (!isEnabled) {
            Log.i(LOG_TAG, "Tracker is disabled in config, skipping background check")
            return@withContext Result.success()
        }

        val powerManager = applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG)?.apply {
            setReferenceCounted(false)
        }

        try {
            wakeLock?.acquire(15 * 60 * 1000L) // 15 minutes max wake lock

            val checkResult = TrackerCheckExecutor.executeCheck(applicationContext) { current, total, title ->
                if (notificationManager.hasPermission()) {
                    notificationManager.showProgressNotification(
                        total,
                        current,
                        "Memeriksa ($current/$total): $title",
                    )
                }
            }

            if (checkResult.pendingNotificationItems.isNotEmpty()) {
                try {
                    notificationManager.showBatchUpdateNotifications(checkResult.pendingNotificationItems)
                } catch (e: Exception) {
                    Log.e(LOG_TAG, "Failed posting batch notifications: ${e.message}")
                }
            }

            Log.i(
                LOG_TAG,
                "doWork completed: totalChecked=${checkResult.totalChecked}, updatedManga=${checkResult.updatedMangaCount}, totalNewChapters=${checkResult.totalNewChapters}",
            )
            Result.success()
        } catch (e: CancellationException) {
            Log.w(LOG_TAG, "doWork was cancelled")
            throw e
        } catch (e: Exception) {
            Log.e(LOG_TAG, "doWork failed with error: ${e.message}", e)
            if (runAttemptCount < 3) {
                Result.retry()
            } else {
                Result.failure()
            }
        } finally {
            try {
                if (wakeLock?.isHeld == true) {
                    wakeLock.release()
                }
            } catch (_: Exception) {}
            try {
                notificationManager.cancelProgressNotification()
            } catch (_: Exception) {}
        }
    }
}
