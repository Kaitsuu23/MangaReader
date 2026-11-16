package org.dhiksn.yomika

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object TrackerAlarmManager {

    private const val ALARM_REQUEST_CODE = 2001
    const val ACTION_AUTO_CHECK = "org.dhiksn.yomika.ACTION_AUTO_CHECK"

    fun schedulePeriodicCheck(context: Context, frequencyHours: Int, isWifiOnly: Boolean) {
        // 1. Primary: Schedule robust background work via AndroidX WorkManager (matching Kotatsu)
        try {
            TrackerWorkScheduler.schedulePeriodicWork(context, frequencyHours, isWifiOnly)
        } catch (_: Throwable) {}

        // 2. Secondary fallback: AlarmManager RTC_WAKEUP
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val hours = frequencyHours.coerceIn(1, 48)
        val intervalMillis = hours * 3600 * 1000L
        val triggerAt = System.currentTimeMillis() + intervalMillis

        val intent = Intent(context, TrackerBroadcastReceiver::class.java).apply {
            action = ACTION_AUTO_CHECK
            putExtra("isWifiOnly", isWifiOnly)
            putExtra("frequencyHours", hours)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getBroadcast(context, ALARM_REQUEST_CODE, intent, flags)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
        } catch (_: SecurityException) {
            try {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            } catch (_: Exception) {}
        }
    }

    fun cancelPeriodicCheck(context: Context) {
        // Cancel WorkManager
        try {
            TrackerWorkScheduler.cancelPeriodicWork(context)
        } catch (_: Throwable) {}

        // Cancel AlarmManager
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, TrackerBroadcastReceiver::class.java).apply {
            action = ACTION_AUTO_CHECK
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getBroadcast(context, ALARM_REQUEST_CODE, intent, flags)
        try {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        } catch (_: Exception) {}
    }
}
