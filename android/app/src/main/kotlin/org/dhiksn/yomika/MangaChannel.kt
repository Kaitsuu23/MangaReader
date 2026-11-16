package org.dhiksn.yomika

import org.dhiksn.yomika.parsers.core.ParserRegistry
import org.dhiksn.yomika.parsers.util.CloudFlareBlockedException
import org.dhiksn.yomika.parsers.util.CloudFlareProtectedException
import org.dhiksn.yomika.parsers.util.ImageSlicer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * MethodChannel bridge between Flutter (Dart) and the Kotlin manga parsers.
 *
 * Channel name : "org.dhiksn.yomika/manga"
 *
 * Supported methods (all receive a Map<String, Any> as arguments):
 *   getSources()
 *   getPopular(source, page)
 *   getLatest(source, page, category?)
 *   search(source, query, page)
 *   getGenres(source)
 *   getByGenre(source, genre, page)
 *   getTypes(source)
 *   getByType(source, type, page)
 *   getDetails(source, slug)
 *   getPages(source, slug, chapter, server?)
 *   getPageSlices(url, referer?, sliceHeight?)
 *   clearPageSliceCache()
 */
class MangaChannel(
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
    private val cacheDirProvider: () -> File? = { null },
) {

    companion object {
        const val CHANNEL = "org.dhiksn.yomika/manga"
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val response = dispatch(call)
                // Switch back to main thread to reply
                kotlinx.coroutines.withContext(Dispatchers.Main) {
                    result.success(response)
                }
            } catch (e: CloudFlareProtectedException) {
                kotlinx.coroutines.withContext(Dispatchers.Main) {
                    result.error("CLOUDFLARE_PROTECTED", e.message ?: "Cloudflare verification required", e.url)
                }
            } catch (e: CloudFlareBlockedException) {
                kotlinx.coroutines.withContext(Dispatchers.Main) {
                    result.error("CLOUDFLARE_BLOCKED", e.message ?: "Cloudflare blocked access", e.url)
                }
            } catch (e: Exception) {
                kotlinx.coroutines.withContext(Dispatchers.Main) {
                    result.error("PARSER_ERROR", e.message ?: "Unknown error", null)
                }
            }
        }
    }

    private suspend fun dispatch(call: MethodCall): Any? {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()

        fun str(key: String) = args[key]?.toString() ?: ""
        fun int(key: String, default: Int = 1) = (args[key] as? Number)?.toInt() ?: default

        return when (call.method) {
            "getSources" -> {
                ParserRegistry.listSources().map { s ->
                    mapOf(
                        "id" to s.id,
                        "name" to s.name,
                        "lang" to s.lang,
                        "baseUrl" to s.baseUrl,
                        "icon" to s.iconUrl,
                        "isNsfw" to s.isNsfw,
                        "sorts" to s.sorts.map { mapOf("id" to it.id, "name" to it.name) },
                    )
                }
            }

            "getPopular" -> {
                val parser = requireParser(str("source"))
                val status = str("status").ifEmpty { null }
                val r = if (status != null) {
                    parser.getList(page = int("page"), sort = "popular", status = status)
                } else {
                    parser.getPopular(int("page"))
                }
                pagedResultToMap(r)
            }

            "getLatest" -> {
                val parser = requireParser(str("source"))
                val status = str("status").ifEmpty { null }
                val r = if (status != null) {
                    parser.getList(page = int("page"), sort = "latest", status = status, category = str("category").ifEmpty { null })
                } else {
                    parser.getLatest(int("page"), str("category").ifEmpty { "all" })
                }
                pagedResultToMap(r)
            }

            "getBySort" -> {
                val parser = requireParser(str("source"))
                val r = parser.getList(
                    page = int("page"),
                    sort = str("sort").ifEmpty { null },
                    status = str("status").ifEmpty { null },
                    genre = str("genre").ifEmpty { null },
                    type = str("type").ifEmpty { null },
                    category = str("category").ifEmpty { null },
                )
                pagedResultToMap(r)
            }

            "getList" -> {
                val parser = requireParser(str("source"))
                val r = if (parser is org.dhiksn.yomika.parsers.sources.KomikindochParser) {
                    parser.getList(
                        page = int("page"),
                        sort = str("sort").ifEmpty { null },
                        status = str("status").ifEmpty { null },
                        genre = str("genre").ifEmpty { null },
                        type = str("type").ifEmpty { null },
                        category = str("category").ifEmpty { null },
                        tema = str("tema").ifEmpty { null },
                        demografis = str("demografis").ifEmpty { null },
                    )
                } else {
                    parser.getList(
                        page = int("page"),
                        sort = str("sort").ifEmpty { null },
                        status = str("status").ifEmpty { null },
                        genre = str("genre").ifEmpty { null },
                        type = str("type").ifEmpty { null },
                        category = str("category").ifEmpty { null },
                    )
                }
                pagedResultToMap(r)
            }

            "getTema" -> {
                val parser = requireParser(str("source"))
                if (parser is org.dhiksn.yomika.parsers.sources.KomikindochParser) {
                    parser.getTema().map { mapOf("name" to it.name, "slug" to it.slug) }
                } else {
                    emptyList<Map<String, String>>()
                }
            }

            "getDemografis" -> {
                val parser = requireParser(str("source"))
                if (parser is org.dhiksn.yomika.parsers.sources.KomikindochParser) {
                    parser.getDemografis().map { mapOf("name" to it.name, "slug" to it.slug) }
                } else {
                    emptyList<Map<String, String>>()
                }
            }

            "search" -> {
                val parser = requireParser(str("source"))
                val r = parser.search(str("query"), int("page"))
                pagedResultToMap(r)
            }

            "getGenres" -> {
                val parser = requireParser(str("source"))
                parser.getGenres().map { mapOf("name" to it.name, "slug" to it.slug) }
            }

            "getByGenre" -> {
                val parser = requireParser(str("source"))
                val status = str("status").ifEmpty { null }
                val r = if (status != null) {
                    parser.getList(page = int("page"), genre = str("genre"), status = status)
                } else {
                    parser.getByGenre(str("genre"), int("page"))
                }
                pagedResultToMap(r)
            }

            "getTypes" -> {
                val parser = requireParser(str("source"))
                parser.getTypes()
            }

            "getByType" -> {
                val parser = requireParser(str("source"))
                val status = str("status").ifEmpty { null }
                val r = if (status != null) {
                    parser.getList(page = int("page"), type = str("type"), status = status)
                } else {
                    parser.getByType(str("type"), int("page"))
                }
                pagedResultToMap(r)
            }

            "getDetails" -> {
                val parser = requireParser(str("source"))
                val d = parser.getDetails(str("slug"))
                mapOf(
                    "id" to d.id,
                    "mangaId" to d.id,
                    "source" to d.source,
                    "title" to d.title,
                    "slug" to d.slug,
                    "altTitle" to d.altTitle,
                    "cover" to d.cover,
                    "synopsis" to d.synopsis,
                    "author" to d.author,
                    "year" to d.year,
                    "status" to d.status,
                    "type" to d.type,
                    "rating" to d.rating,
                    "genres" to d.genres.map { mapOf("name" to it.name, "slug" to it.slug) },
                    "totalChapters" to d.totalChapters,
                    "chapters" to d.chapters.map { ch ->
                        mapOf(
                            "id" to ch.id,
                            "slug" to ch.slug,
                            "chapterNumber" to ch.chapterNumber,
                            "title" to ch.title,
                            "uploadDate" to ch.uploadDate,
                        )
                    },
                    "similar" to d.similar.map { itemToMap(it) },
                    "series" to d.series.map {
                        mapOf(
                            "title" to it.title,
                            "slug" to it.slug,
                        )
                    },
                )
            }

            "getPages" -> {
                val parser = requireParser(str("source"))
                val cp = parser.getPages(str("slug"), str("chapter"), int("server", 1))
                mapOf(
                    "source" to cp.source,
                    "title" to cp.title,
                    "slug" to cp.slug,
                    "chapter" to cp.chapter,
                    "totalPages" to cp.totalPages,
                    "referer" to cp.referer,
                    "pages" to cp.pages.map { mapOf("page" to it.page, "url" to it.url) },
                )
            }

            "getPageSlices" -> {
                val cacheDir = cacheDirProvider()
                    ?: error("Cache directory is not available")
                val referer = str("referer").ifEmpty { null }
                val result = ImageSlicer.slice(
                    url = str("url"),
                    cacheRoot = File(cacheDir, "page_slices"),
                    referer = referer,
                    sliceHeight = int("sliceHeight", ImageSlicer.DEFAULT_SLICE_HEIGHT),
                )
                mapOf(
                    "width" to result.width,
                    "height" to result.height,
                    "sliced" to result.sliced,
                    "slices" to result.slices.map {
                        mapOf("path" to it.path, "width" to it.width, "height" to it.height)
                    },
                )
            }

            "clearPageSliceCache" -> {
                cacheDirProvider()?.let { ImageSlicer.clearCache(File(it, "page_slices")) }
                true
            }

            "setDohConfig" -> {
                val provider = str("provider").ifEmpty { "none" }
                val customUrl = str("customUrl").ifEmpty { null }
                org.dhiksn.yomika.parsers.util.HttpClientConfig.dohProvider = provider
                org.dhiksn.yomika.parsers.util.HttpClientConfig.customDohUrl = customUrl
                org.dhiksn.yomika.parsers.util.HttpClientConfig.clearDnsCache()
                true
            }

            else -> null
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun requireParser(source: String) =
        ParserRegistry.get(source) ?: error("Unknown source: '$source'")

    private fun itemToMap(item: org.dhiksn.yomika.parsers.core.MangaItem) = mapOf(
        "id" to item.id,
        "mangaId" to item.id,
        "title" to item.title,
        "slug" to item.slug,
        "cover" to item.cover,
        "type" to item.type,
        "status" to item.status,
        "latestChapter" to item.latestChapter,
        "rating" to item.rating,
        "contentRating" to item.contentRating,
        "updatedAt" to item.updatedAt,
        "source" to item.source,
        "genres" to item.genres,
    )

    private fun pagedResultToMap(r: org.dhiksn.yomika.parsers.core.PagedResult<org.dhiksn.yomika.parsers.core.MangaItem>) = mapOf(
        "source" to r.source,
        "page" to r.page,
        "hasNextPage" to r.hasNextPage,
        "data" to r.data.map { itemToMap(it) },
    )
}
