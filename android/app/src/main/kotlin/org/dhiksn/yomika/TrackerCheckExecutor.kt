package org.dhiksn.yomika

import android.content.Context
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.dhiksn.yomika.parsers.core.Chapter
import org.dhiksn.yomika.parsers.core.ParserRegistry
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

object TrackerCheckExecutor {

    private const val CONFIG_FILE = "tracker_config.json"
    private const val PENDING_UPDATES_FILE = "pending_feed_updates.json"
    private const val PENDING_BASELINES_FILE = "pending_baselines.json"
    private const val ITEM_TIMEOUT_MS = 10_000L

    fun getConfigFile(context: Context): File = File(context.filesDir, CONFIG_FILE)
    fun getPendingUpdatesFile(context: Context): File = File(context.filesDir, PENDING_UPDATES_FILE)
    fun getPendingBaselinesFile(context: Context): File = File(context.filesDir, PENDING_BASELINES_FILE)

    data class CheckResult(
        val totalChecked: Int,
        val updatedMangaCount: Int,
        val totalNewChapters: Int,
        val pendingNotificationItems: List<TrackerNotificationManager.UpdateNotificationItem> = emptyList(),
    )

    suspend fun executeCheck(
        context: Context,
        onProgress: ((current: Int, total: Int, title: String) -> Unit)? = null,
    ): CheckResult = withContext(Dispatchers.IO) {
        // Ensure default User-Agent is initialized safely
        runCatching {
            if (org.dhiksn.yomika.parsers.util.HttpClientConfig.defaultUserAgent.isNullOrBlank()) {
                try {
                    org.dhiksn.yomika.parsers.util.HttpClientConfig.defaultUserAgent =
                        android.webkit.WebSettings.getDefaultUserAgent(context)
                } catch (_: Throwable) {
                    org.dhiksn.yomika.parsers.util.HttpClientConfig.defaultUserAgent =
                        System.getProperty("http.agent")
                            ?: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
                }
            }
        }

        val configFile = getConfigFile(context)
        if (!configFile.exists()) {
            return@withContext CheckResult(0, 0, 0)
        }

        val configJson = try {
            JSONObject(configFile.readText(Charsets.UTF_8))
        } catch (_: Exception) {
            return@withContext CheckResult(0, 0, 0)
        }

        val isEnabled = configJson.optBoolean("enabled", true)
        if (!isEnabled) {
            return@withContext CheckResult(0, 0, 0)
        }

        val itemsArray = configJson.optJSONArray("items") ?: JSONArray()
        val totalItems = itemsArray.length()
        if (totalItems == 0) {
            return@withContext CheckResult(0, 0, 0)
        }

        val notificationManager = TrackerNotificationManager(context)
        var updatedMangaCount = 0
        var totalNewChapters = 0
        val updatedTitles = mutableListOf<String>()
        val newUpdatesJson = mutableListOf<JSONObject>()
        val pendingNotificationItems = mutableListOf<TrackerNotificationManager.UpdateNotificationItem>()

        for (i in 0 until totalItems) {
            if (!coroutineContext.isActive) break

            val itemObj = itemsArray.getJSONObject(i)
            val slug = itemObj.optString("slug")
            val source = itemObj.optString("source")
            val title = itemObj.optString("title", slug)
            val currentNumber = i + 1

            // Notify progress sequentially so comic order strictly matches Favorites display
            onProgress?.invoke(currentNumber, totalItems, title)

            val cover = itemObj.optString("cover").takeIf { it.isNotBlank() }
            val prevLastSlug = itemObj.optString("lastChapterSlug", "").trim()
            val prevTotal = itemObj.optInt("totalChapters", 0)
            val percent = itemObj.optDouble("percent", 0.0)
            val isCompleted = itemObj.optBoolean("isCompleted", percent >= 0.99)
            val modeId = itemObj.optString("modeId", "normal")
            val modeName = itemObj.optString("modeName", "Normal")

            val readChapterSlugs = itemObj.optJSONArray("readChapterSlugs")?.let { arr ->
                val set = mutableSetOf<String>()
                for (idx in 0 until arr.length()) set.add(arr.getString(idx).trim())
                set
            } ?: emptySet()
            val lastReadSlug = itemObj.optString("lastReadSlug", "").trim()

            val feedChapterSlugs = itemObj.optJSONArray("feedChapterSlugs")?.let { arr ->
                val set = mutableSetOf<String>()
                for (idx in 0 until arr.length()) set.add(arr.getString(idx).trim())
                set
            } ?: emptySet()

            try {
                val parser = ParserRegistry.get(source) ?: continue
                // Apply timeout per manga so slow or stalled sites never hang the check
                val details = withTimeoutOrNull(ITEM_TIMEOUT_MS) {
                    parser.getDetails(slug)
                } ?: run {
                    android.util.Log.w("TrackerCheckExecutor", "Timeout fetching $slug ($source)")
                    continue
                }

                val rawChapters = details.chapters
                if (rawChapters.isNotEmpty()) {
                    val sortedChapters = sortChaptersChronologically(rawChapters)
                    val currentTotal = sortedChapters.size
                    val latestChapter = sortedChapters.last()
                    val latestSlug = latestChapter.slug

                    fun normalizeSlug(s: String): String {
                        return s.trim().trim('/').split('/').lastOrNull()?.trim() ?: s.trim()
                    }

                    fun fnv1aHash(s: String): String {
                        val clean = s.trim().trim('/').split('/').lastOrNull()?.trim()?.lowercase() ?: s.trim().lowercase()
                        var hash = java.lang.Long.parseUnsignedLong("cbf29ce484222325", 16).toULong()
                        val prime = java.lang.Long.parseUnsignedLong("100000001b3", 16).toULong()
                        val maxMask = 0x7FFFFFFFFFFFFFFFL.toULong()
                        val target = if (clean.isNotEmpty()) clean else s.lowercase()
                        for (b in target.toByteArray(Charsets.UTF_8)) {
                            val bVal = b.toUByte().toULong()
                            hash = hash xor bVal
                            hash = (hash * prime) and maxMask
                        }
                        return (hash % maxMask).toString()
                    }

                    fun isChapterRead(ch: Chapter): Boolean {
                        val chIndex = sortedChapters.indexOf(ch)
                        if (isCompleted) {
                            if (prevTotal > 0 && (chIndex in 0 until prevTotal)) {
                                return true
                            }
                        }

                        val norm = normalizeSlug(ch.slug)
                        val chHash = fnv1aHash(ch.slug)
                        val numStr = ch.chapterNumber?.let { if (it % 1.0f == 0.0f) it.toInt().toString() else it.toString() }

                        if (lastReadSlug.isNotBlank()) {
                            val normLast = normalizeSlug(lastReadSlug)
                            if (normLast == norm || ch.slug == lastReadSlug || lastReadSlug == chHash) {
                                return true
                            }
                            if (numStr != null && (normLast == numStr || normLast == "chapter-$numStr" || normLast == "ch-$numStr" || normLast == "bab-$numStr")) {
                                return true
                            }
                        }
                        return readChapterSlugs.any { r ->
                            val normR = normalizeSlug(r)
                            normR == norm || r == ch.slug || r == chHash ||
                            (numStr != null && (normR == numStr || normR == "chapter-$numStr" || normR == "ch-$numStr" || normR == "bab-$numStr"))
                        }
                    }

                    // Determine candidate new chapters
                    val candidateChapters = mutableListOf<Chapter>()
                    val hasBaseline = prevLastSlug.isNotBlank() || prevTotal > 0

                    if (!hasBaseline) {
                        // First check of a brand new manga with 0 baseline: establish baseline silently without notifying
                        itemObj.put("lastChapterSlug", latestSlug)
                        itemObj.put("totalChapters", currentTotal)
                    } else {
                        // If prevTotal is known and current total hasn't grown, no new chapters published by source!
                        if (prevTotal > 0 && currentTotal <= prevTotal) {
                            // Count has not increased: no candidate new chapters
                        } else {
                            val prevIndex = if (prevLastSlug.isNotBlank()) {
                                sortedChapters.indexOfFirst {
                                    val norm = normalizeSlug(it.slug)
                                    norm == normalizeSlug(prevLastSlug) || fnv1aHash(it.slug) == prevLastSlug || it.slug == prevLastSlug
                                }
                            } else -1

                            if (prevIndex != -1 && prevIndex < currentTotal - 1) {
                                // Regular check: chapters added after previous tracked baseline
                                candidateChapters.addAll(sortedChapters.subList(prevIndex + 1, currentTotal))
                            } else if (prevTotal > 0 && currentTotal > prevTotal) {
                                val diff = currentTotal - prevTotal
                                candidateChapters.addAll(sortedChapters.takeLast(diff))
                            } else if (prevLastSlug.isNotBlank() && normalizeSlug(latestSlug) != normalizeSlug(prevLastSlug) && fnv1aHash(latestSlug) != prevLastSlug) {
                                candidateChapters.add(latestChapter)
                            }
                        }

                        // Filter out chapters that the user has already read OR are already present in the feed
                        val unreadNewChapters = candidateChapters.distinctBy { normalizeSlug(it.slug) }.filter { ch ->
                            !isChapterRead(ch) && !feedChapterSlugs.any { normalizeSlug(it) == normalizeSlug(ch.slug) }
                        }

                        if (unreadNewChapters.isNotEmpty()) {
                            updatedMangaCount++
                            val newChTitles = unreadNewChapters.map { it.title }
                            val newChSlugs = unreadNewChapters.map { it.slug }
                            totalNewChapters += unreadNewChapters.size

                            val notifTitle = if (modeId == "normal" || modeName.equals("Normal", ignoreCase = true)) {
                                title
                            } else {
                                "[$modeName] $title"
                            }
                            updatedTitles.add(notifTitle)

                            val createdAt = System.currentTimeMillis()

                            // Queue notification item to be posted in batch once checking completes
                            pendingNotificationItems.add(
                                TrackerNotificationManager.UpdateNotificationItem(
                                    title = notifTitle,
                                    newChaptersCount = unreadNewChapters.size,
                                    chapters = newChTitles,
                                    slug = slug,
                                    source = source,
                                    coverUrl = cover ?: details.cover,
                                    timestamp = createdAt,
                                    modeId = modeId,
                                )
                            )

                            // Queue pending update for Flutter to import on launch
                            val updateEntry = JSONObject().apply {
                                put("id", "${modeId}_${slug}_$createdAt")
                                put("mangaSlug", slug)
                                put("mangaTitle", title)
                                put("mangaCover", cover ?: details.cover)
                                put("mangaSource", source)
                                put("newChaptersCount", unreadNewChapters.size)
                                put("newChapters", JSONArray(newChTitles))
                                put("newChapterSlugs", JSONArray(newChSlugs))
                                put("createdAt", createdAt)
                                put("isNew", true)
                                put("modeId", modeId)
                                put("modeName", modeName)
                            }
                            newUpdatesJson.add(updateEntry)
                        }

                        // Always advance baseline so subsequent checks won't repeat notifications
                        itemObj.put("lastChapterSlug", latestSlug)
                        itemObj.put("totalChapters", sortedChapters.size)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("TrackerCheckExecutor", "Failed checking $slug ($source): ${e.message}")
            }
        }

        // Save updated baseline back to tracker_config.json
        try {
            configFile.writeText(configJson.toString(2), Charsets.UTF_8)
        } catch (e: Exception) {
            android.util.Log.e("TrackerCheckExecutor", "Failed saving updated config: ${e.message}")
        }

        // Save pending baselines so Flutter can sync them back to LocalStorage
        try {
            val baselinesFile = getPendingBaselinesFile(context)
            val baselinesArray = JSONArray()
            for (i in 0 until totalItems) {
                val itemObj = itemsArray.getJSONObject(i)
                val mSlug = itemObj.optString("slug")
                val mModeId = itemObj.optString("modeId", "normal")
                val mLastSlug = itemObj.optString("lastChapterSlug")
                val mTotal = itemObj.optInt("totalChapters", 0)
                if (mSlug.isNotBlank() && mLastSlug.isNotBlank()) {
                    baselinesArray.put(JSONObject().apply {
                        put("slug", mSlug)
                        put("modeId", mModeId)
                        put("lastChapterSlug", mLastSlug)
                        put("totalChapters", mTotal)
                    })
                }
            }
            baselinesFile.writeText(baselinesArray.toString(2), Charsets.UTF_8)
        } catch (e: Exception) {
            android.util.Log.e("TrackerCheckExecutor", "Failed saving pending baselines: ${e.message}")
        }

        // Save pending feed updates
        if (newUpdatesJson.isNotEmpty()) {
            try {
                val pendingFile = getPendingUpdatesFile(context)
                val existingPending = if (pendingFile.exists()) {
                    try {
                        JSONArray(pendingFile.readText(Charsets.UTF_8))
                    } catch (_: Exception) {
                        JSONArray()
                    }
                } else {
                    JSONArray()
                }

                for (update in newUpdatesJson) {
                    existingPending.put(update)
                }
                pendingFile.writeText(existingPending.toString(2), Charsets.UTF_8)
            } catch (e: Exception) {
                android.util.Log.e("TrackerCheckExecutor", "Failed saving pending updates: ${e.message}")
            }
        }

        // Cancel progress notification so the progress bar disappears cleanly
        try {
            notificationManager.cancelProgressNotification()
        } catch (_: Exception) {}

        return@withContext CheckResult(
            totalChecked = totalItems,
            updatedMangaCount = updatedMangaCount,
            totalNewChapters = totalNewChapters,
            pendingNotificationItems = pendingNotificationItems,
        )
    }

    private fun sortChaptersChronologically(chapters: List<Chapter>): List<Chapter> {
        if (chapters.size <= 1) return chapters
        val firstNum = chapters.firstOrNull { it.chapterNumber != null }?.chapterNumber
        val lastNum = chapters.lastOrNull { it.chapterNumber != null }?.chapterNumber
        if (firstNum != null && lastNum != null && firstNum > lastNum) {
            return chapters.reversed()
        }
        return chapters
    }
}
