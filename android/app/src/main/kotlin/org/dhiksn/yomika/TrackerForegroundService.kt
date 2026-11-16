package org.dhiksn.yomika

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import kotlinx.coroutines.*
import java.io.File

class TrackerForegroundService : Service() {

    companion object {
        const val ACTION_START_PROGRESS = "org.dhiksn.yomika.ACTION_START_PROGRESS"
        const val ACTION_UPDATE_PROGRESS = "org.dhiksn.yomika.ACTION_UPDATE_PROGRESS"
        const val ACTION_STOP_PROGRESS = "org.dhiksn.yomika.ACTION_STOP_PROGRESS"
        const val ACTION_RUN_BACKGROUND_CHECK = "org.dhiksn.yomika.ACTION_RUN_BACKGROUND_CHECK"
        const val ACTION_CANCEL_CHECK = "org.dhiksn.yomika.CANCEL_CHECK"

        private const val WAKELOCK_TAG = "Yomika:TrackerWakeLock"

        var progressListener: ((current: Int, total: Int, title: String) -> Unit)? = null
        var completionListener: ((updatedCount: Int) -> Unit)? = null
        @Volatile var isRunning: Boolean = false

        fun getConfigFile(context: Context): File = TrackerCheckExecutor.getConfigFile(context)
        fun getPendingUpdatesFile(context: Context): File = TrackerCheckExecutor.getPendingUpdatesFile(context)
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var checkJob: Job? = null
    private lateinit var notificationManager: TrackerNotificationManager

    override fun onCreate() {
        super.onCreate()
        runCatching {
            val ua = android.webkit.WebSettings.getDefaultUserAgent(this)
            org.dhiksn.yomika.parsers.util.HttpClientConfig.defaultUserAgent = ua
        }
        notificationManager = TrackerNotificationManager(this)
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG)?.apply {
            setReferenceCounted(false)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return START_NOT_STICKY

        when (action) {
            ACTION_START_PROGRESS -> {
                val max = intent.getIntExtra("max", 0)
                val current = intent.getIntExtra("current", 0)
                val message = intent.getStringExtra("message") ?: "Memeriksa pembaruan..."
                acquireWakeLock(10 * 60 * 1000L) // 10 minutes max
                startServiceForeground(max, current, message)
            }

            ACTION_UPDATE_PROGRESS -> {
                val max = intent.getIntExtra("max", 0)
                val current = intent.getIntExtra("current", 0)
                val message = intent.getStringExtra("message") ?: ""
                notificationManager.showProgressNotification(max, current, message)
            }

            ACTION_STOP_PROGRESS -> {
                stopServiceForeground()
                stopSelf()
            }

            ACTION_RUN_BACKGROUND_CHECK -> {
                acquireWakeLock(20 * 60 * 1000L) // 20 minutes max
                startServiceForeground(0, 0, "Menyiapkan pembaruan...")
                isRunning = true
                checkJob?.cancel()
                checkJob = serviceScope.launch {
                    var checkResult: TrackerCheckExecutor.CheckResult? = null
                    try {
                        checkResult = TrackerCheckExecutor.executeCheck(this@TrackerForegroundService) { current, total, title ->
                            notificationManager.showProgressNotification(
                                total,
                                current,
                                "Memeriksa ($current/$total): $title",
                            )
                            progressListener?.invoke(current, total, title)
                        }

                        // Dismiss ongoing progress notification immediately before posting update alerts
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            stopForeground(STOP_FOREGROUND_REMOVE)
                        } else {
                            @Suppress("DEPRECATION")
                            stopForeground(true)
                        }
                        notificationManager.cancelProgressNotification()

                        // Post batch update notifications while service and scope are still active
                        val result = checkResult
                        if (result != null && result.pendingNotificationItems.isNotEmpty()) {
                            try {
                                notificationManager.showBatchUpdateNotifications(result.pendingNotificationItems)
                            } catch (e: Exception) {
                                android.util.Log.e("TrackerService", "Failed posting batch notifications: ${e.message}")
                            }
                        }
                        completionListener?.invoke(result?.updatedMangaCount ?: 0)
                    } catch (e: Exception) {
                        android.util.Log.e("TrackerService", "Check error: ${e.message}")
                    } finally {
                        isRunning = false
                        stopServiceForeground()
                        stopSelf()
                    }
                }
            }

            ACTION_CANCEL_CHECK -> {
                checkJob?.cancel()
                isRunning = false
                completionListener?.invoke(0)
                stopServiceForeground()
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    private fun startServiceForeground(max: Int, current: Int, message: String) {
        val notification = notificationManager.buildProgressNotification(max, current, message)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                TrackerNotificationManager.PROGRESS_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(TrackerNotificationManager.PROGRESS_NOTIFICATION_ID, notification)
        }
    }

    private fun stopServiceForeground() {
        releaseWakeLock()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {}
        try {
            notificationManager.cancelProgressNotification()
        } catch (_: Exception) {}
    }

    private fun acquireWakeLock(timeoutMs: Long) {
        try {
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire(timeoutMs)
            }
        } catch (_: Exception) {}
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        checkJob?.cancel()
        isRunning = false
        serviceScope.cancel()
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
