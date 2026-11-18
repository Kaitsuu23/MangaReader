package org.dhiksn.yomika

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import okhttp3.OkHttpClient
import okhttp3.Request
import org.dhiksn.yomika.parsers.core.ParserRegistry
import java.io.File
import java.io.InputStream
import java.net.URLEncoder
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

class TrackerNotificationManager(private val context: Context) {

    companion object {
        const val CHANNEL_UPDATES = "tracker_updates"
        const val CHANNEL_SERVICE = "tracker_service"

        const val PROGRESS_NOTIFICATION_ID = 1001
        private const val GROUP_NOTIFICATION_ID = 1002
        private const val GROUP_NEW_CHAPTERS = "group_new_chapters"
        const val PERMISSION_REQUEST_CODE = 1010
        const val ACTION_CANCEL_CHECK = "org.dhiksn.yomika.CANCEL_CHECK"
        const val ACTION_AUTO_CHECK = "org.dhiksn.yomika.ACTION_AUTO_CHECK"

        /**
         * Sets the application launcher icon badge number across various Android launchers
         * (Xiaomi/MIUI/HyperOS, Samsung, Sony, Vivo, Oppo, Huawei).
         */
        fun applyAppBadge(context: Context, count: Int) {
            val safeCount = if (count < 0) 0 else count

            // 1. ShortcutBadger (De-facto standard across Xiaomi, Samsung, Huawei, Sony, Vivo, Oppo, etc.)
            try {
                if (safeCount > 0) {
                    me.leolin.shortcutbadger.ShortcutBadger.applyCount(context, safeCount)
                } else {
                    me.leolin.shortcutbadger.ShortcutBadger.removeCount(context)
                }
            } catch (_: Throwable) {}

            // 2. Xiaomi / MIUI / HyperOS broadcast
            try {
                val intent = Intent("android.intent.action.APPLICATION_MESSAGE_UPDATE").apply {
                    putExtra("android.intent.extra.update_application_component_name", "${context.packageName}/org.dhiksn.yomika.MainActivity")
                    putExtra("android.intent.extra.update_application_message_text", if (safeCount > 0) safeCount.toString() else "")
                }
                context.sendBroadcast(intent)
            } catch (_: Throwable) {}

            // Xiaomi MIUI content resolver (MIUI 10+)
            try {
                val bundle = Bundle().apply {
                    putString("package", context.packageName)
                    putString("class", "org.dhiksn.yomika.MainActivity")
                    putInt("badgenumber", safeCount)
                }
                context.contentResolver.call(
                    Uri.parse("content://com.miui.launcher.badge/"),
                    "set_badge",
                    null,
                    bundle
                )
            } catch (_: Throwable) {}

            // 3. Samsung launcher
            try {
                val intent = Intent("android.intent.action.BADGE_COUNT_UPDATE").apply {
                    putExtra("badge_count", safeCount)
                    putExtra("badge_count_package_name", context.packageName)
                    putExtra("badge_count_class_name", "org.dhiksn.yomika.MainActivity")
                }
                context.sendBroadcast(intent)
            } catch (_: Throwable) {}

            // 4. Sony Xperia
            try {
                val intent = Intent("com.sonyericsson.home.action.UPDATE_BADGE").apply {
                    putExtra("com.sonyericsson.home.intent.extra.badge.PACKAGE_NAME", context.packageName)
                    putExtra("com.sonyericsson.home.intent.extra.badge.ACTIVITY_NAME", "org.dhiksn.yomika.MainActivity")
                    putExtra("com.sonyericsson.home.intent.extra.badge.SHOW_MESSAGE", safeCount > 0)
                    putExtra("com.sonyericsson.home.intent.extra.badge.MESSAGE", safeCount.toString())
                }
                context.sendBroadcast(intent)
            } catch (_: Throwable) {}

            // 5. Vivo / Oppo
            try {
                val intent = Intent("launcher.action.CHANGE_APPLICATION_NOTIFICATION_NUM").apply {
                    putExtra("packageName", context.packageName)
                    putExtra("className", "org.dhiksn.yomika.MainActivity")
                    putExtra("notificationNum", safeCount)
                }
                context.sendBroadcast(intent)
            } catch (_: Throwable) {}

            // 6. Huawei
            try {
                val bundle = Bundle().apply {
                    putString("package", context.packageName)
                    putString("class", "org.dhiksn.yomika.MainActivity")
                    putInt("badgenumber", safeCount)
                }
                context.contentResolver.call(
                    Uri.parse("content://com.huawei.android.launcher.settings/badge/"),
                    "change_badge",
                    null,
                    bundle
                )
            } catch (_: Throwable) {}
        }
    }

    private val notificationManager = NotificationManagerCompat.from(context)

    init {
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Channel for new chapter releases (matching Kotatsu tracker_chapters)
            val updatesChannel = NotificationChannel(
                CHANNEL_UPDATES,
                "Sub-bab baru",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Anda akan menerima notifikasi tentang pembaruan manga yang Anda baca"
                setShowBadge(true)
                enableVibration(true)
            }

            // Channel for background checking progress (matching Kotatsu track_worker)
            val serviceChannel = NotificationChannel(
                CHANNEL_SERVICE,
                "Periksa bab baru",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Notifikasi progres pemeriksaan pembaruan bab baru"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }

            manager.createNotificationChannel(updatesChannel)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    fun hasPermission(): Boolean {
        if (!notificationManager.areNotificationsEnabled()) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun requestPermission(activity: Activity?): Boolean {
        if (hasPermission()) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && activity != null) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                PERMISSION_REQUEST_CODE,
            )
        }
        return false
    }

    fun openNotificationSettings(activity: Activity?) {
        val target = activity ?: (context as? Activity)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    if (target == null) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                (target ?: context).startActivity(intent)
            } else {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.fromParts("package", context.packageName, null)
                    if (target == null) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                (target ?: context).startActivity(intent)
            }
        } catch (_: Exception) {
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.fromParts("package", context.packageName, null)
                    if (target == null) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                (target ?: context).startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    /**
     * Notification during check — matching Kotatsu-Redo TrackWorker.createWorkerNotification
     * - Title: "Periksa bab baru"
     * - Icon: android.R.drawable.stat_notify_sync (Rotating sync arrows)
     * - Action 1: "Batal"
     * - Action 2: "Pengaturan notifikasi"
     */
    fun buildProgressNotification(max: Int, current: Int, message: String): android.app.Notification {
        val cancelIntent = PendingIntent.getBroadcast(
            context,
            1003,
            Intent(ACTION_CANCEL_CHECK).setPackage(context.packageName),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            },
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_SERVICE).apply {
            setContentTitle("Periksa bab baru")
            if (message.isNotEmpty()) {
                setContentText(message)
            }
            setSmallIcon(android.R.drawable.stat_notify_sync)
            setPriority(NotificationCompat.PRIORITY_LOW)
            setOngoing(true)
            setOnlyAlertOnce(true)
            setSilent(true)
            if (max > 0) {
                setProgress(max, current, false)
            } else {
                setProgress(0, 0, true)
            }
            setContentIntent(createLaunchIntent(PROGRESS_NOTIFICATION_ID))

            // Action 1: "Batal"
            addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Batal",
                cancelIntent,
            )

            // Action 2: "Pengaturan notifikasi"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val settingsIntent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    putExtra(Settings.EXTRA_CHANNEL_ID, CHANNEL_SERVICE)
                }
                val settingsPending = PendingIntent.getActivity(
                    context,
                    1004,
                    settingsIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                addAction(
                    android.R.drawable.ic_menu_preferences,
                    "Pengaturan notifikasi",
                    settingsPending,
                )
            }
        }
        return builder.build()
    }

    fun showProgressNotification(max: Int, current: Int, message: String) {
        if (!hasPermission()) return
        try {
            notificationManager.notify(PROGRESS_NOTIFICATION_ID, buildProgressNotification(max, current, message))
        } catch (_: SecurityException) {}
    }

    fun cancelProgressNotification() {
        try {
            notificationManager.cancel(PROGRESS_NOTIFICATION_ID)
        } catch (_: Exception) {}
    }

    data class UpdateNotificationItem(
        val title: String,
        val newChaptersCount: Int,
        val chapters: List<String>,
        val slug: String,
        val source: String,
        val coverUrl: String? = null,
        val timestamp: Long = System.currentTimeMillis(),
        val modeId: String = "normal",
    )

    private data class ItemWithBitmap(
        val item: UpdateNotificationItem,
        val bitmap: Bitmap?,
    )

    /**
     * Posts all update notifications together in a single bundled batch AFTER checking completes.
     * Matches Kotatsu-Redo:
     * - Progress notification is removed before updates are shown.
     * - Individual child notifications are bundled under GROUP_NEW_CHAPTERS so they don't pop up separately.
     * - Group summary notification is posted with setGroupSummary(true) and GROUP_ALERT_SUMMARY.
     * - Only alerts the user once instead of buzzing/ringing for each item.
     */
    suspend fun showBatchUpdateNotifications(items: List<UpdateNotificationItem>) = withContext(Dispatchers.IO) {
        if (!hasPermission() || items.isEmpty()) return@withContext

        val totalNewChapters = items.sumOf { it.newChaptersCount }
        val isMultiple = items.size > 1

        // 1. Download cover bitmaps with timeout in parallel (limited concurrency to avoid socket hang)
        val imageSemaphore = Semaphore(3)
        val itemsWithBitmaps: List<ItemWithBitmap> = coroutineScope {
            items.map { item ->
                async {
                    val bitmap: Bitmap? = if (!item.coverUrl.isNullOrEmpty()) {
                        try {
                            imageSemaphore.withPermit {
                                withTimeoutOrNull(4000L) {
                                    downloadCoverBitmap(item.coverUrl, item.source)
                                }
                            }
                        } catch (_: Exception) {
                            null
                        }
                    } else null
                    ItemWithBitmap(item, bitmap)
                }
            }.awaitAll()
        }

        // 2. Post each individual child notification (bundled under GROUP_NEW_CHAPTERS if multiple)
        for (entry in itemsWithBitmaps) {
            val item = entry.item
            val bitmap = entry.bitmap
            val notifId = ("${item.modeId}_${item.slug}".hashCode() and 0x7FFFFFFF)
            val summary = if (item.newChaptersCount == 1) "1 Sub-bab Baru" else "${item.newChaptersCount} Sub-bab Baru"

            val childBuilder = NotificationCompat.Builder(context, CHANNEL_UPDATES).apply {
                setContentTitle(item.title)
                setContentText(summary)
                if (item.source.isNotEmpty()) {
                    setSubText(item.source)
                }
                setSmallIcon(R.drawable.ic_stat_book_plus)
                setNumber(item.newChaptersCount)
                if (isMultiple) {
                    setGroup(GROUP_NEW_CHAPTERS)
                    setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_SUMMARY)
                }
                setAutoCancel(true)
                setPriority(NotificationCompat.PRIORITY_DEFAULT)
                setBadgeIconType(NotificationCompat.BADGE_ICON_SMALL)
                if (item.timestamp > 0) {
                    setWhen(item.timestamp)
                    setShowWhen(true)
                }

                if (bitmap != null) {
                    // Square crop for largeIcon (1:1 aspect ratio with rounded corners)
                    val squareIcon = createSquareCropBitmap(bitmap)
                    setLargeIcon(squareIcon)
                }

                val inboxStyle = NotificationCompat.InboxStyle(this)
                    .setBigContentTitle(summary)
                    .setSummaryText(item.title)
                for (ch in item.chapters.take(6)) {
                    inboxStyle.addLine(ch)
                }
                setStyle(inboxStyle)
                setContentIntent(createLaunchIntent(
                    requestCode = notifId,
                    slug = item.slug,
                    source = item.source,
                    title = item.title,
                    coverUrl = item.coverUrl,
                    modeId = item.modeId,
                ))
            }

            try {
                val childNotif = childBuilder.build()
                applyMiuiBadge(childNotif, item.newChaptersCount)
                notificationManager.notify(notifId, childNotif)
            } catch (_: SecurityException) {}
        }

        // 3. If multiple manga updated, post Group Summary Notification (matching Kotatsu-Redo)
        if (isMultiple) {
            val summaryTitle = if (totalNewChapters == 1) "1 Sub-bab Baru" else "$totalNewChapters Sub-bab Baru"
            val lines = items.map { it.title }

            val summaryBuilder = NotificationCompat.Builder(context, CHANNEL_UPDATES).apply {
                setContentTitle(summaryTitle)
                setContentText(lines.joinToString(", "))
                setSmallIcon(R.drawable.ic_stat_book_plus)
                setNumber(totalNewChapters)
                setGroup(GROUP_NEW_CHAPTERS)
                setGroupSummary(true)
                setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_SUMMARY)
                setAutoCancel(true)
                setBadgeIconType(NotificationCompat.BADGE_ICON_SMALL)
                setCategory(NotificationCompat.CATEGORY_SOCIAL)
                setPriority(NotificationCompat.PRIORITY_DEFAULT)

                val firstBitmap = itemsWithBitmaps.firstOrNull { it.bitmap != null }?.bitmap
                if (firstBitmap != null) {
                    setLargeIcon(createSquareCropBitmap(firstBitmap))
                }

                val inboxStyle = NotificationCompat.InboxStyle(this)
                    .setBigContentTitle(summaryTitle)
                for (item in items.take(8)) {
                    inboxStyle.addLine("${item.title} (${item.newChaptersCount})")
                }
                setStyle(inboxStyle)
                setContentIntent(createLaunchIntent(GROUP_NOTIFICATION_ID))
            }

            try {
                val summaryNotif = summaryBuilder.build()
                applyMiuiBadge(summaryNotif, totalNewChapters)
                notificationManager.notify(GROUP_NOTIFICATION_ID, summaryNotif)
            } catch (_: SecurityException) {}
        }

        if (totalNewChapters > 0) {
            applyAppBadge(context, totalNewChapters)
        }
    }

    /**
     * Notification for individual manga updates — matching Kotatsu-Redo TrackerNotificationHelper
     * - LargeIcon: Manga Cover bitmap (1:1 square crop with rounded corners)
     * - SmallIcon: ic_stat_book_plus
     * - Content: "%d Sub-bab Baru"
     */
    fun showUpdateNotification(
        title: String,
        newChaptersCount: Int,
        chapters: List<String>,
        slug: String,
        source: String,
        coverUrl: String? = null,
        timestamp: Long? = null,
        modeId: String = "normal",
    ) {
        if (!hasPermission()) return

        val notifId = ("${modeId}_$slug".hashCode() and 0x7FFFFFFF)
        val summary = if (newChaptersCount == 1) "1 Sub-bab Baru" else "$newChaptersCount Sub-bab Baru"

        fun postNotification(bitmap: Bitmap?) {
            val builder = NotificationCompat.Builder(context, CHANNEL_UPDATES).apply {
                setContentTitle(title)
                setContentText(summary)
                if (source.isNotEmpty()) {
                    setSubText(source)
                }
                setSmallIcon(R.drawable.ic_stat_book_plus)
                setNumber(newChaptersCount)
                setAutoCancel(true)
                setPriority(NotificationCompat.PRIORITY_DEFAULT)
                setBadgeIconType(NotificationCompat.BADGE_ICON_SMALL)
                if (timestamp != null && timestamp > 0) {
                    setWhen(timestamp)
                    setShowWhen(true)
                }

                if (bitmap != null) {
                    val squareIcon = createSquareCropBitmap(bitmap)
                    setLargeIcon(squareIcon)
                }

                val inboxStyle = NotificationCompat.InboxStyle(this)
                    .setBigContentTitle(summary)
                    .setSummaryText(title)
                for (ch in chapters.take(6)) {
                    inboxStyle.addLine(ch)
                }
                setStyle(inboxStyle)

                setContentIntent(createLaunchIntent(
                    requestCode = notifId,
                    slug = slug,
                    source = source,
                    title = title,
                    coverUrl = coverUrl,
                    modeId = modeId,
                ))
            }

            try {
                val notif = builder.build()
                applyMiuiBadge(notif, newChaptersCount)
                notificationManager.notify(notifId, notif)
                applyAppBadge(context, newChaptersCount)
            } catch (_: SecurityException) {}
        }

        if (!coverUrl.isNullOrEmpty()) {
            CoroutineScope(Dispatchers.IO).launch {
                val bitmap = downloadCoverBitmap(coverUrl, source)
                postNotification(bitmap)
            }
        } else {
            postNotification(null)
        }
    }

    /**
     * Summary notification when multiple manga are updated — matching Kotatsu-Redo Photo 3
     * - Content: Listing all updated manga with their new chapters count
     * - Summary flag: setGroupSummary(true)
     */
    fun showSummaryNotification(
        totalNewManga: Int,
        totalNewChapters: Int,
        lines: List<String>,
    ) {
        if (!hasPermission() || totalNewManga <= 1) return

        val title = if (totalNewChapters == 1) "1 Sub-bab Baru" else "$totalNewChapters Sub-bab Baru"

        val builder = NotificationCompat.Builder(context, CHANNEL_UPDATES).apply {
            setContentTitle(title)
            setContentText(lines.joinToString(", "))
            setSubText(if (totalNewChapters == 1) "1 bab baru" else "$totalNewChapters bab baru")
            setSmallIcon(R.drawable.ic_stat_book_plus)
            setNumber(totalNewChapters)
            setGroup(GROUP_NEW_CHAPTERS)
            setGroupSummary(true)
            setAutoCancel(true)
            setBadgeIconType(NotificationCompat.BADGE_ICON_SMALL)
            setCategory(NotificationCompat.CATEGORY_SOCIAL)

            val inboxStyle = NotificationCompat.InboxStyle(this)
                .setBigContentTitle(title)

            for (line in lines.take(8)) {
                inboxStyle.addLine(line)
            }
            setStyle(inboxStyle)

            setContentIntent(createLaunchIntent(GROUP_NOTIFICATION_ID))
        }

        try {
            val notif = builder.build()
            applyMiuiBadge(notif, totalNewChapters)
            notificationManager.notify(GROUP_NOTIFICATION_ID, notif)
            applyAppBadge(context, totalNewChapters)
        } catch (_: SecurityException) {}
    }

    private fun getRoundedCornerBitmap(bitmap: Bitmap, cornerRadiusDp: Float): Bitmap {
        return try {
            val radiusPx = cornerRadiusDp * context.resources.displayMetrics.density
            val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val rect = RectF(0f, 0f, bitmap.width.toFloat(), bitmap.height.toFloat())
            canvas.drawRoundRect(rect, radiusPx, radiusPx, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(bitmap, 0f, 0f, paint)
            output
        } catch (_: Throwable) {
            bitmap
        }
    }

    /**
     * Crops a manga cover (typically 2:3 portrait) into a 1:1 square focused on the top/character area,
     * with rounded corners. This completely eliminates letterboxing when rendered as largeIcon in notifications.
     */
    private fun createSquareCropBitmap(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        if (width <= 0 || height <= 0) return bitmap
        if (width == height) return getRoundedCornerBitmap(bitmap, 8f)

        return try {
            val size = minOf(width, height)
            val x = (width - size) / 2
            val y = if (height > width) {
                // Focus on top portion where manga character and title art are located
                0
            } else {
                (height - size) / 2
            }
            val cropped = Bitmap.createBitmap(bitmap, x, y, size, size)
            getRoundedCornerBitmap(cropped, 8f)
        } catch (_: Throwable) {
            bitmap
        }
    }

    private val imageOkHttpClient: OkHttpClient by lazy {
        val trustAll = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>?, authType: String?) = Unit
            override fun checkServerTrusted(chain: Array<X509Certificate>?, authType: String?) = Unit
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        val sslCtx = SSLContext.getInstance("TLS").apply {
            init(null, arrayOf<TrustManager>(trustAll), SecureRandom())
        }

        OkHttpClient.Builder()
            .followRedirects(true)
            .followSslRedirects(true)
            .connectTimeout(4, TimeUnit.SECONDS)
            .readTimeout(4, TimeUnit.SECONDS)
            .callTimeout(5, TimeUnit.SECONDS)
            .sslSocketFactory(sslCtx.socketFactory, trustAll)
            .hostnameVerifier { _, _ -> true }
            .build()
    }

    private fun downloadCoverBitmap(rawUrl: String, source: String? = null): Bitmap? {
        val trimmed = rawUrl.trim()
        if (trimmed.isEmpty()) return null

        // 1. Resolve full URL if relative
        val fullUrl = when {
            trimmed.startsWith("//") -> "https:$trimmed"
            trimmed.startsWith("http://") || trimmed.startsWith("https://") -> trimmed
            trimmed.startsWith("/") -> {
                val base = source?.let { ParserRegistry.get(it)?.baseUrl }?.trimEnd('/') ?: ""
                if (base.isNotEmpty()) "$base$trimmed" else trimmed
            }
            trimmed.startsWith("file://") -> trimmed.removePrefix("file://")
            else -> {
                val base = source?.let { ParserRegistry.get(it)?.baseUrl }?.trimEnd('/') ?: ""
                if (base.isNotEmpty()) "$base/$trimmed" else trimmed
            }
        }

        // 2. Check if it's a local file path
        if (fullUrl.startsWith("/")) {
            val file = File(fullUrl)
            if (file.exists() && file.isFile) {
                return try {
                    file.inputStream().use { decodeAndScaleBitmap(it) }
                } catch (_: Exception) { null }
            }
        }

        // 3. Determine Referer header based on source or URL patterns (matching CachedCover)
        fun getReferer(urlStr: String): String {
            val lower = urlStr.lowercase()
            if (source != null) {
                val base = ParserRegistry.get(source)?.baseUrl
                if (!base.isNullOrBlank()) return "$base/"
            }
            return when {
                lower.contains("komikindo") || lower.contains("linksaya") -> "https://komikindo.click/"
                lower.contains("softdevices") || lower.contains("komik.im") -> "https://softkomik.app/"
                lower.contains("komiku") || lower.contains("thumbnail.komiku") -> "https://komiku.org/"
                lower.contains("shngm") || lower.contains("shinigami") -> "https://s1.shinigami.mx/"
                lower.contains("hwago") || lower.contains("hwg") || lower.contains("imgsvr") -> "https://01.hwago.com/"
                lower.contains("desu") || lower.contains("doujin") -> "https://doujin.desu.xxx/"
                lower.contains("kiryuu") -> "https://v7.kiryuu.to/"
                lower.contains("komiktap") || lower.contains("cdnasu") || lower.contains("uqni") -> "https://komiktap.info/"
                lower.contains("westmanga") -> "https://v1.westmanga.my/"
                lower.contains("apkomik") || lower.contains("cdnap") -> "https://01.apkomik.com/"
                lower.contains("bacakomik") -> "https://bacakomik.my/"
                lower.contains("lumos") -> "https://03.lumosgg.com/"
                lower.contains("holodek") || lower.contains("holotoon") -> "https://holodek.run/"
                lower.contains("pixhentai") || lower.contains("openhentai") -> "https://pixhentai.com/"
                lower.contains("hentaicrot") -> "https://hentaicrot.com/"
                lower.contains("ikiru") -> "https://09.ikiru.wtf/"
                lower.contains("voratoon") -> "https://v10.voratoon.com/"
                lower.contains("luvyaa") -> "https://v5.luvyaa.co/"
                lower.contains("crotpedia") || lower.contains("eromanga") -> "https://crotpedia.net/"
                lower.contains("mihentai") -> "https://mihentai.net/"
                lower.contains("soulscans") -> "https://v1.soulscans.asia/"
                else -> {
                    try {
                        val uri = Uri.parse(urlStr)
                        if (uri.scheme != null && uri.host != null) "${uri.scheme}://${uri.host}/" else ""
                    } catch (_: Exception) { "" }
                }
            }
        }

        val referer = getReferer(fullUrl)
        val ua = "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

        // 4. Try direct download via OkHttp with redirects & SSL trust
        val directBitmap = tryFetchWithOkHttp(fullUrl, referer, ua)
        if (directBitmap != null) {
            return directBitmap
        }

        // 5. Fallback via wsrv.nl proxy (matching Flutter CachedCover Attempt 2)
        return try {
            val encoded = URLEncoder.encode(fullUrl, "UTF-8")
            val proxyUrl = "https://wsrv.nl/?url=$encoded&w=320&output=jpg"
            tryFetchWithOkHttp(proxyUrl, "", ua)
        } catch (_: Exception) {
            null
        }
    }

    private fun tryFetchWithOkHttp(url: String, referer: String, ua: String): Bitmap? {
        return try {
            val reqBuilder = Request.Builder()
                .url(url)
                .header("User-Agent", ua)
            if (referer.isNotEmpty()) {
                reqBuilder.header("Referer", referer)
            }
            val response = imageOkHttpClient.newCall(reqBuilder.build()).execute()
            if (!response.isSuccessful) {
                response.close()
                return null
            }
            response.body?.use { body ->
                decodeAndScaleBitmap(body.byteStream())
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun decodeAndScaleBitmap(input: InputStream): Bitmap? {
        return try {
            val bytes = input.readBytes()
            if (bytes.isEmpty()) return null

            // 1. Decode bounds to inspect width & height
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)

            // 2. Calculate inSampleSize targeting ~256-512 px max dimension for largeIcon thumbnail
            val targetSize = 256
            var inSampleSize = 1
            if (options.outHeight > targetSize || options.outWidth > targetSize) {
                val halfHeight = options.outHeight / 2
                val halfWidth = options.outWidth / 2
                while ((halfHeight / inSampleSize) >= targetSize && (halfWidth / inSampleSize) >= targetSize) {
                    inSampleSize *= 2
                }
            }

            // 3. Decode scaled bitmap
            val decodeOptions = BitmapFactory.Options().apply {
                this.inSampleSize = inSampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val sampled = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, decodeOptions) ?: return null

            // 4. If still larger than targetSize, do an exact scale
            if (sampled.width > targetSize || sampled.height > targetSize) {
                val ratio = targetSize.toFloat() / maxOf(sampled.width, sampled.height)
                val newW = (sampled.width * ratio).toInt().coerceAtLeast(1)
                val newH = (sampled.height * ratio).toInt().coerceAtLeast(1)
                Bitmap.createScaledBitmap(sampled, newW, newH, true)
            } else {
                sampled
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun createLaunchIntent(
        requestCode: Int,
        slug: String? = null,
        source: String? = null,
        title: String? = null,
        coverUrl: String? = null,
        modeId: String? = null,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (!slug.isNullOrEmpty()) {
                action = "org.dhiksn.yomika.OPEN_MANGA_DETAIL"
                putExtra("action", "open_manga_detail")
                putExtra("slug", slug)
                putExtra("source", source ?: "")
                putExtra("title", title ?: "")
                putExtra("cover", coverUrl ?: "")
                putExtra("modeId", modeId ?: "normal")
            }
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }

    private fun applyMiuiBadge(notification: Notification, count: Int) {
        try {
            val field = notification.javaClass.getDeclaredField("extraNotification")
            field.isAccessible = true
            val extraNotification = field.get(notification)
            val method = extraNotification.javaClass.getDeclaredMethod("setMessageCount", Int::class.javaPrimitiveType)
            method.isAccessible = true
            method.invoke(extraNotification, count)
        } catch (_: Throwable) {}
        try {
            me.leolin.shortcutbadger.ShortcutBadger.applyNotification(context, notification, count)
        } catch (_: Throwable) {}
    }
}
