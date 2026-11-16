package org.dhiksn.yomika

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.util.Log
import org.json.JSONObject

class TrackerBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val LOG_TAG = "TrackerReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.i(LOG_TAG, "onReceive action: $action")

        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                restoreSchedule(context)
            }

            TrackerAlarmManager.ACTION_AUTO_CHECK -> {
                handleAutoCheckTrigger(context, intent)
            }

            TrackerNotificationManager.ACTION_CANCEL_CHECK -> {
                try {
                    val serviceIntent = Intent(context, TrackerForegroundService::class.java).apply {
                        this.action = TrackerForegroundService.ACTION_CANCEL_CHECK
                    }
                    context.startService(serviceIntent)
                } catch (_: Exception) {}
            }
        }
    }

    private fun handleAutoCheckTrigger(context: Context, intent: Intent) {
        val configFile = TrackerCheckExecutor.getConfigFile(context)
        if (!configFile.exists()) return

        val configJson = try {
            JSONObject(configFile.readText(Charsets.UTF_8))
        } catch (_: Exception) {
            return
        }

        val isEnabled = configJson.optBoolean("enabled", true)
        val frequencyHours = configJson.optInt("frequencyHours", intent.getIntExtra("frequencyHours", 1))
        val isWifiOnly = configJson.optBoolean("wifiOnly", intent.getBooleanExtra("isWifiOnly", false))

        if (!isEnabled) {
            return
        }

        // 1. Reschedule next periodic alarm / work
        TrackerWorkScheduler.schedulePeriodicWork(context, frequencyHours, isWifiOnly)
        TrackerAlarmManager.schedulePeriodicCheck(context, frequencyHours, isWifiOnly)

        // 2. Delegate execution to WorkManager to prevent BroadcastReceiver ANR / 30s kill limit
        TrackerWorkScheduler.startNow(context, isWifiOnly)
    }

    private fun restoreSchedule(context: Context) {
        val configFile = TrackerCheckExecutor.getConfigFile(context)
        if (!configFile.exists()) return

        try {
            val configJson = JSONObject(configFile.readText(Charsets.UTF_8))
            val isEnabled = configJson.optBoolean("enabled", true)
            val frequencyHours = configJson.optInt("frequencyHours", 1)
            val isWifiOnly = configJson.optBoolean("wifiOnly", false)

            if (isEnabled) {
                TrackerWorkScheduler.schedulePeriodicWork(context, frequencyHours, isWifiOnly)
                TrackerAlarmManager.schedulePeriodicCheck(context, frequencyHours, isWifiOnly)
                Log.i(LOG_TAG, "Restored background tracker schedule: $frequencyHours hours")
            }
        } catch (e: Exception) {
            Log.e(LOG_TAG, "Failed to restore schedule: ${e.message}")
        }
    }

    private fun isNetworkAvailable(context: Context, isWifiOnly: Boolean): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false

        val hasInternet = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        if (!hasInternet) return false

        if (isWifiOnly) {
            return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        }
        return true
    }
}
