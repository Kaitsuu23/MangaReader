package org.dhiksn.yomika

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterFragmentActivity() {

    companion object {
        var pendingNotificationPayload: Map<String, Any?>? = null
    }

    private val mangaChannel = MangaChannel(cacheDirProvider = { cacheDir })
    private var connectivityCallback: ConnectivityManager.NetworkCallback? = null
    private var connectivityChannel: MethodChannel? = null
    private var notificationChannel: MethodChannel? = null
    private var isReaderImmersive: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleNotificationIntent(intent)
        runCatching {
            val rawUa = android.webkit.WebSettings.getDefaultUserAgent(this)
            val cleanUa = rawUa
                .replace(Regex(""";\s*wv""", RegexOption.IGNORE_CASE), "")
                .replace(Regex("""Version/\d+\.\d+\s*""", RegexOption.IGNORE_CASE), "")
            org.dhiksn.yomika.parsers.util.HttpClientConfig.defaultUserAgent = cleanUa
            val cm = android.webkit.CookieManager.getInstance()
            cm.setAcceptCookie(true)
            cm.setCookie("https://fanfox.net", "isAdult=1; Domain=.fanfox.net; Path=/")
            cm.setCookie("https://newm.fanfox.net", "isAdult=1; Domain=.fanfox.net; Path=/")
            cm.setCookie("https://fanfox.net", "readmode=1; Domain=.fanfox.net; Path=/")
            cm.setCookie("https://newm.fanfox.net", "readmode=1; Domain=.fanfox.net; Path=/")
        }
        if (!isInMultiWindowMode) {
            hideNavigationBar()
        }
        runCatching {
            TrackerWorkScheduler.ensureScheduled(this)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationIntent(intent)
    }

    private fun handleNotificationIntent(intent: Intent?) {
        if (intent == null) return
        val slug = intent.getStringExtra("slug")
        if (!slug.isNullOrEmpty()) {
            val payload = mapOf(
                "action" to (intent.getStringExtra("action") ?: "open_manga_detail"),
                "slug" to slug,
                "source" to (intent.getStringExtra("source") ?: ""),
                "title" to (intent.getStringExtra("title") ?: ""),
                "cover" to (intent.getStringExtra("cover") ?: ""),
                "modeId" to (intent.getStringExtra("modeId") ?: "normal"),
            )
            val channel = notificationChannel
            if (channel != null) {
                runOnUiThread {
                    try {
                        channel.invokeMethod("onNotificationTapped", payload)
                    } catch (_: Exception) {}
                }
            } else {
                pendingNotificationPayload = payload
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Device channel (battery, wakelock)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.dhiksn.yomika/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBatteryLevel" -> {
                        val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                        val level = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
                        result.success(level)
                    }
                    "setKeepScreenOn" -> {
                        val enable = call.argument<Boolean>("enable") ?: false
                        if (enable) {
                            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(true)
                    }
                    "setReaderImmersive" -> {
                        val enable = call.argument<Boolean>("enable") ?: false
                        isReaderImmersive = enable
                        if (enable) {
                            hideStatusBar()
                            window.decorView.postDelayed({
                                if (isReaderImmersive) {
                                    hideStatusBar()
                                }
                            }, 200)
                        } else {
                            showStatusBar()
                        }
                        result.success(true)
                    }
                    "hideStatusBar" -> {
                        hideStatusBar()
                        result.success(true)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                        result.success(pm?.isIgnoringBatteryOptimizations(packageName) ?: true)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            val intent = Intent(
                                android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                android.net.Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            try {
                                val intent = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    "saveImageToGallery" -> {
                        val filePath = call.argument<String>("filePath")
                        val title = call.argument<String>("title") ?: "manga_page"
                        if (filePath == null) {
                            result.error("INVALID_PATH", "File path is null", null)
                            return@setMethodCallHandler
                        }
                        val sourceFile = File(filePath)
                        if (!sourceFile.exists()) {
                            result.error("FILE_NOT_FOUND", "File does not exist", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val resolver = contentResolver
                            val contentValues = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, "${title}_${System.currentTimeMillis()}.jpg")
                                put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    put(MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/Yomika")
                                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                                }
                            }
                            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                            if (uri != null) {
                                resolver.openOutputStream(uri).use { out ->
                                    sourceFile.inputStream().use { input ->
                                        input.copyTo(out!!)
                                    }
                                }
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    contentValues.clear()
                                    contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                                    resolver.update(uri, contentValues, null, null)
                                } else {
                                    MediaScannerConnection.scanFile(
                                        this@MainActivity,
                                        arrayOf(sourceFile.absolutePath),
                                        arrayOf("image/jpeg"),
                                        null
                                    )
                                }
                                result.success(uri.toString())
                            } else {
                                result.error("URI_NULL", "Failed to create MediaStore entry", null)
                            }
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.localizedMessage, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Connectivity channel
        connectivityChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.dhiksn.yomika/connectivity")
        connectivityChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isConnected" -> {
                    result.success(isNetworkAvailable())
                }
                else -> result.notImplemented()
            }
        }
        registerConnectivityCallback()

        // Manga parser channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MangaChannel.CHANNEL)
            .setMethodCallHandler { call, result ->
                mangaChannel.handle(call, result)
            }

        // Notification channel for feed tracker
        val notificationManager = TrackerNotificationManager(this)
        val nChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.dhiksn.yomika/notifications")
        this.notificationChannel = nChannel

        TrackerForegroundService.progressListener = { current, total, title ->
            runOnUiThread {
                try {
                    nChannel.invokeMethod("onProgress", mapOf(
                        "current" to current,
                        "total" to total,
                        "title" to title
                    ))
                } catch (_: Exception) {}
            }
        }

        TrackerForegroundService.completionListener = { count ->
            runOnUiThread {
                try {
                    nChannel.invokeMethod("onCompleted", mapOf(
                        "newUpdatesCount" to count
                    ))
                } catch (_: Exception) {}
            }
        }

        nChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialNotification" -> {
                        val p = pendingNotificationPayload
                        pendingNotificationPayload = null
                        result.success(p)
                    }
                    "hasPermission" -> {
                        result.success(notificationManager.hasPermission())
                    }
                    "requestPermission" -> {
                        result.success(notificationManager.requestPermission(this))
                    }
                    "openNotificationSettings" -> {
                        notificationManager.openNotificationSettings(this)
                        result.success(true)
                    }
                    "startBackgroundCheck" -> {
                        val serviceIntent = Intent(this, TrackerForegroundService::class.java).apply {
                            action = TrackerForegroundService.ACTION_RUN_BACKGROUND_CHECK
                        }
                        ContextCompat.startForegroundService(this, serviceIntent)
                        result.success(true)
                    }
                    "isCheckRunning" -> {
                        result.success(TrackerForegroundService.isRunning)
                    }
                    "cancelCheck" -> {
                        val serviceIntent = Intent(this, TrackerForegroundService::class.java).apply {
                            action = TrackerForegroundService.ACTION_CANCEL_CHECK
                        }
                        startService(serviceIntent)
                        result.success(true)
                    }
                    "showProgress" -> {
                        val max = call.argument<Int>("max") ?: 0
                        val current = call.argument<Int>("current") ?: 0
                        val message = call.argument<String>("message") ?: ""
                        notificationManager.showProgressNotification(max, current, message)
                        val serviceIntent = Intent(this, TrackerForegroundService::class.java).apply {
                            action = TrackerForegroundService.ACTION_UPDATE_PROGRESS
                            putExtra("max", max)
                            putExtra("current", current)
                            putExtra("message", message)
                        }
                        startService(serviceIntent)
                        result.success(true)
                    }
                    "cancelProgress" -> {
                        val serviceIntent = Intent(this, TrackerForegroundService::class.java).apply {
                            action = TrackerForegroundService.ACTION_STOP_PROGRESS
                        }
                        startService(serviceIntent)
                        notificationManager.cancelProgressNotification()
                        result.success(true)
                    }
                    "startForegroundCheck" -> {
                        val max = call.argument<Int>("max") ?: 0
                        val current = call.argument<Int>("current") ?: 0
                        val message = call.argument<String>("message") ?: "Memeriksa bab baru..."
                        val serviceIntent = Intent(this, TrackerForegroundService::class.java).apply {
                            action = TrackerForegroundService.ACTION_START_PROGRESS
                            putExtra("max", max)
                            putExtra("current", current)
                            putExtra("message", message)
                        }
                        ContextCompat.startForegroundService(this, serviceIntent)
                        result.success(true)
                    }
                    "syncTrackerConfig" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        val frequencyHours = call.argument<Int>("frequencyHours") ?: 1
                        val wifiOnly = call.argument<Boolean>("wifiOnly") ?: false
                        val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()

                        try {
                            val configJson = JSONObject().apply {
                                put("enabled", enabled)
                                put("frequencyHours", frequencyHours)
                                put("wifiOnly", wifiOnly)
                                val itemsArray = JSONArray()
                                for (item in items) {
                                    itemsArray.put(JSONObject(item))
                                }
                                put("items", itemsArray)
                            }
                            val configFile = TrackerForegroundService.getConfigFile(this)
                            configFile.writeText(configJson.toString(2), Charsets.UTF_8)

                            if (enabled) {
                                TrackerWorkScheduler.schedulePeriodicWork(this, frequencyHours, wifiOnly)
                                TrackerAlarmManager.schedulePeriodicCheck(this, frequencyHours, wifiOnly)
                            } else {
                                TrackerWorkScheduler.cancelPeriodicWork(this)
                                TrackerAlarmManager.cancelPeriodicCheck(this)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CONFIG_ERROR", e.message, null)
                        }
                    }
                    "getPendingFeedUpdates" -> {
                        try {
                            val pendingFile = TrackerForegroundService.getPendingUpdatesFile(this)
                            if (pendingFile.exists()) {
                                val text = pendingFile.readText(Charsets.UTF_8)
                                val array = JSONArray(text)
                                val list = mutableListOf<Map<String, Any?>>()
                                for (i in 0 until array.length()) {
                                    val obj = array.getJSONObject(i)
                                    val map = mutableMapOf<String, Any?>()
                                    val keys = obj.keys()
                                    while (keys.hasNext()) {
                                        val key = keys.next()
                                        val value = obj.get(key)
                                        if (value is JSONArray) {
                                            val strList = mutableListOf<String>()
                                            for (j in 0 until value.length()) {
                                                strList.add(value.getString(j))
                                            }
                                            map[key] = strList
                                        } else {
                                            map[key] = value
                                        }
                                    }
                                    list.add(map)
                                }
                                pendingFile.delete()
                                result.success(list)
                            } else {
                                result.success(emptyList<Map<String, Any?>>())
                            }
                        } catch (e: Exception) {
                            result.success(emptyList<Map<String, Any?>>())
                        }
                    }
                    "getPendingBaselines" -> {
                        try {
                            val baselinesFile = TrackerCheckExecutor.getPendingBaselinesFile(this)
                            if (baselinesFile.exists()) {
                                val text = baselinesFile.readText(Charsets.UTF_8)
                                val array = JSONArray(text)
                                val list = mutableListOf<Map<String, Any?>>()
                                for (i in 0 until array.length()) {
                                    val obj = array.getJSONObject(i)
                                    val map = mutableMapOf<String, Any?>()
                                    val keys = obj.keys()
                                    while (keys.hasNext()) {
                                        val k = keys.next()
                                        map[k] = obj.opt(k)
                                    }
                                    list.add(map)
                                }
                                baselinesFile.delete()
                                result.success(list)
                            } else {
                                result.success(emptyList<Map<String, Any?>>())
                            }
                        } catch (e: Exception) {
                            result.success(emptyList<Map<String, Any?>>())
                        }
                    }
                    "showUpdateNotification" -> {
                        val title = call.argument<String>("title") ?: ""
                        val newChaptersCount = call.argument<Int>("newChaptersCount") ?: 1
                        val chapters = call.argument<List<String>>("chapters") ?: emptyList()
                        val slug = call.argument<String>("slug") ?: ""
                        val source = call.argument<String>("source") ?: ""
                        val coverUrl = call.argument<String>("coverUrl")
                        val timestamp = (call.argument<Number>("timestamp"))?.toLong()
                        val modeId = call.argument<String>("modeId") ?: "normal"
                        notificationManager.showUpdateNotification(title, newChaptersCount, chapters, slug, source, coverUrl, timestamp, modeId)
                        result.success(true)
                    }
                    "showSummaryNotification" -> {
                        val totalNewManga = call.argument<Int>("totalNewManga") ?: 0
                        val totalNewChapters = call.argument<Int>("totalNewChapters") ?: 0
                        val lines = call.argument<List<String>>("lines") ?: call.argument<List<String>>("titles") ?: emptyList()
                        notificationManager.showSummaryNotification(totalNewManga, totalNewChapters, lines)
                        result.success(true)
                    }
                    "setBadgeCount" -> {
                        val count = call.argument<Int>("count") ?: 0
                        TrackerNotificationManager.applyAppBadge(this, count)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isNetworkAvailable(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(network) ?: return false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        } else {
            @Suppress("DEPRECATION")
            val netInfo = cm.activeNetworkInfo
            netInfo != null && netInfo.isConnected
        }
    }

    private fun registerConnectivityCallback() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            connectivityCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    runOnUiThread {
                        connectivityChannel?.invokeMethod("onConnectivityChanged", true)
                    }
                }

                override fun onLost(network: Network) {
                    runOnUiThread {
                        val isStillConnected = isNetworkAvailable()
                        connectivityChannel?.invokeMethod("onConnectivityChanged", isStillConnected)
                    }
                }
            }
            try {
                cm.registerDefaultNetworkCallback(connectivityCallback!!)
            } catch (_: Exception) {}
        }
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        if (isInMultiWindowMode) {
            // Keluar dari immersive/fullscreen saat floating window
            showStatusBar()
            showNavigationBar()
        } else {
            // Kembali ke fullscreen saat layar penuh
            hideNavigationBar()
            if (isReaderImmersive) hideStatusBar()
        }
    }

    private fun showNavigationBar() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.insetsController?.show(WindowInsets.Type.navigationBars())
            } else {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = (
                    window.decorView.systemUiVisibility
                        and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION.inv()
                        and View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION.inv()
                )
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        TrackerForegroundService.progressListener = null
        TrackerForegroundService.completionListener = null
        notificationChannel = null
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        connectivityCallback?.let {
            try {
                cm?.unregisterNetworkCallback(it)
            } catch (_: Exception) {}
        }
        connectivityCallback = null
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            if (!isInMultiWindowMode) {
                hideNavigationBar()
            }
            if (isReaderImmersive && !isInMultiWindowMode) {
                hideStatusBar()
                window.decorView.postDelayed({
                    if (isReaderImmersive && !isInMultiWindowMode) {
                        hideStatusBar()
                    }
                }, 300)
                window.decorView.postDelayed({
                    if (isReaderImmersive && !isInMultiWindowMode) {
                        hideStatusBar()
                    }
                }, 600)
            }
        }
    }

    private fun hideStatusBar() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val controller = window.decorView.windowInsetsController ?: window.insetsController
                controller?.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                controller?.hide(WindowInsets.Type.statusBars())
            }
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                window.decorView.systemUiVisibility
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
        } catch (_: Exception) {}
    }

    private fun showStatusBar() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val controller = window.decorView.windowInsetsController ?: window.insetsController
                controller?.show(WindowInsets.Type.statusBars())
            }
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                window.decorView.systemUiVisibility and View.SYSTEM_UI_FLAG_FULLSCREEN.inv()
            )
        } catch (_: Exception) {}
    }

    private fun hideNavigationBar() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                controller.hide(WindowInsets.Type.navigationBars())
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
        }
    }
}
