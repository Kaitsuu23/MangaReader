import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/storage/local_storage.dart';
import '../../core/storage/cover_cache_manager.dart';
import 'shimmer_loading.dart';

const _defaultMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

/// Returns the appropriate Referer and User-Agent headers for a given image URL.
/// Most manga CDNs block hotlinking without a valid Referer or block default Dart User-Agent.
Map<String, String> refererFor(String url, {String? source}) {
  final u = url.toLowerCase();
  final headers = <String, String>{
    'User-Agent': _defaultMobileUserAgent,
  };

  if (u.contains('wsrv.nl')) {
    // wsrv.nl proxy needs no custom referer
    return headers;
  }

  // Prioritas 1: Gunakan source ID jika eksplisit diberikan (seperti Kotatsu MangaSourceHeaderInterceptor)
  final s = source?.toLowerCase().trim();
  if (s != null && s.isNotEmpty) {
    if (s.contains('komikstation')) {
      headers['Referer'] = 'https://komikstation.org/';
      return headers;
    } else if (s.contains('komikindoch') || s == 'komikindo.ch') {
      headers['Referer'] = 'https://komikindo.ch/';
      return headers;
    } else if (s.contains('komikindo')) {
      headers['Referer'] = 'https://komikindo.click/';
      return headers;
    } else if (s.contains('softkomik')) {
      headers['Referer'] = 'https://softkomik.app/';
      return headers;
    } else if (s.contains('komiku')) {
      headers['Referer'] = 'https://komiku.org/';
      return headers;
    } else if (s.contains('shinigami')) {
      headers['Referer'] = 'https://s1.shinigami.mx/';
      return headers;
    } else if (s.contains('hwago')) {
      headers['Referer'] = 'https://01.hwago.com/';
      return headers;
    } else if (s.contains('desu') || s.contains('doujin')) {
      headers['Referer'] = 'https://doujin.desu.xxx/';
      return headers;
    } else if (s.contains('kiryuu')) {
      headers['Referer'] = 'https://v7.kiryuu.to/';
      return headers;
    } else if (s.contains('komiktap')) {
      headers['Referer'] = 'https://komiktap.info/';
      return headers;
    } else if (s.contains('westmanga')) {
      headers['Referer'] = 'https://v1.westmanga.my/';
      return headers;
    } else if (s.contains('bacakomik')) {
      headers['Referer'] = 'https://bacakomik.my/';
      return headers;
    } else if (s.contains('apkomik')) {
      headers['Referer'] = 'https://01.apkomik.com/';
      return headers;
    } else if (s.contains('lumos')) {
      headers['Referer'] = 'https://03.lumosgg.com/';
      return headers;
    } else if (s.contains('holodek')) {
      headers['Referer'] = 'https://holodek.run/';
      return headers;
    } else if (s.contains('pixhentai')) {
      headers['Referer'] = 'https://pixhentai.com/';
      return headers;
    } else if (s.contains('hentaicrot')) {
      headers['Referer'] = 'https://hentaicrot.com/';
      return headers;
    } else if (s.contains('ikiru')) {
      headers['Referer'] = 'https://09.ikiru.wtf/';
      return headers;
    } else if (s.contains('voratoon')) {
      headers['Referer'] = 'https://v10.voratoon.com/';
      return headers;
    } else if (s.contains('luvyaa')) {
      headers['Referer'] = 'https://v5.luvyaa.co/';
      return headers;
    } else if (s.contains('crotpedia')) {
      headers['Referer'] = 'https://crotpedia.net/';
      return headers;
    } else if (s.contains('mihentai')) {
      headers['Referer'] = 'https://mihentai.net/';
      return headers;
    } else if (s.contains('soulscans')) {
      headers['Referer'] = 'https://v1.soulscans.asia/';
      return headers;
    } else if (s.contains('sasangeyou')) {
      headers['Referer'] = 'https://sasangeyou.net/';
      return headers;
    } else if (s.contains('kanzenin')) {
      headers['Referer'] = 'https://kanzenin.info/';
      return headers;
    } else if (s.contains('mangasusuku') || s.contains('mangsusuku')) {
      headers['Referer'] = 'https://mangasusuku.com/';
      return headers;
    } else if (s.contains('izanamiscans')) {
      headers['Referer'] = 'https://izanamiscans.my.id/';
      return headers;
    } else if (s.contains('cgbum')) {
      headers['Referer'] = 'https://cgbum.com/';
      return headers;
    } else if (s.contains('lepoytl')) {
      headers['Referer'] = 'https://www.lepoytl.my.id/';
      return headers;
    } else if (s.contains('yurilab')) {
      headers['Referer'] = 'https://yurilab.top/';
      return headers;
    } else if (s.contains('maid')) {
      headers['Referer'] = 'https://www.maid.my.id/';
      return headers;
    } else if (s.contains('natsu')) {
      headers['Referer'] = 'https://natsu.one/';
      return headers;
    } else if (s.contains('komikremaja')) {
      headers['Referer'] = 'https://komikremaja.art/';
      return headers;
    } else if (s.contains('shirodoujin')) {
      headers['Referer'] = 'https://shirodoujin.com/';
      return headers;
    } else if (s.contains('fanfox')) {
      headers['Referer'] = 'https://fanfox.net/';
      return headers;
    } else if (s.contains('mangapill')) {
      headers['Referer'] = 'https://mangapill.com/';
      return headers;
    } else if (s.contains('komikapk')) {
      headers['Referer'] = 'https://komikapk.app/';
      return headers;
    }
  }

  // Prioritas 2: Fallback berbasis URL pattern
  if (u.contains('komikindo') || u.contains('linksaya')) {
    headers['Referer'] = 'https://komikindo.click/';
  } else if (u.contains('softdevices') || u.contains('komik.im')) {
    headers['Referer'] = 'https://softkomik.app/';
  } else if (u.contains('komiku') || u.contains('thumbnail.komiku')) {
    headers['Referer'] = 'https://komiku.org/';
  } else if (u.contains('shngm') || u.contains('shinigami')) {
    headers['Referer'] = 'https://s1.shinigami.mx/';
  } else if (u.contains('hwago') || u.contains('hwg') || u.contains('imgsvr')) {
    headers['Referer'] = 'https://01.hwago.com/';
  } else if (u.contains('desu') || u.contains('doujin')) {
    headers['Referer'] = 'https://doujin.desu.xxx/';
  } else if (u.contains('kiryuu')) {
    headers['Referer'] = 'https://v7.kiryuu.to/';
  } else if (u.contains('komiktap') || u.contains('cdnasu') || u.contains('uqni')) {
    headers['Referer'] = 'https://komiktap.info/';
  } else if (u.contains('westmanga')) {
    headers['Referer'] = 'https://v1.westmanga.my/';
  } else if (u.contains('apkomik') || u.contains('cdnap')) {
    headers['Referer'] = 'https://01.apkomik.com/';
  } else if (u.contains('bacakomik')) {
    headers['Referer'] = 'https://bacakomik.my/';
  } else if (u.contains('lumos') || u.contains('imgsvr')) {
    headers['Referer'] = 'https://03.lumosgg.com/';
  } else if (u.contains('holodek') || u.contains('holotoon')) {
    headers['Referer'] = 'https://holodek.run/';
  } else if (u.contains('pixhentai') || u.contains('openhentai')) {
    headers['Referer'] = 'https://pixhentai.com/';
  } else if (u.contains('hentaicrot')) {
    headers['Referer'] = 'https://hentaicrot.com/';
  } else if (u.contains('ikiru')) {
    headers['Referer'] = 'https://09.ikiru.wtf/';
  } else if (u.contains('voratoon')) {
    headers['Referer'] = 'https://v10.voratoon.com/';
  } else if (u.contains('luvyaa')) {
    headers['Referer'] = 'https://v5.luvyaa.co/';
  } else if (u.contains('crotpedia') || u.contains('eromanga')) {
    headers['Referer'] = 'https://crotpedia.net/';
  } else if (u.contains('mihentai')) {
    headers['Referer'] = 'https://mihentai.net/';
  } else if (u.contains('soulscans') || u.contains('dbms.my.id')) {
    headers['Referer'] = 'https://v1.soulscans.asia/';
  } else if (u.contains('komikstation')) {
    headers['Referer'] = 'https://komikstation.org/';
  } else if (u.contains('komikindoch') || u.contains('komikindo.ch')) {
    headers['Referer'] = 'https://komikindo.ch/';
  } else if (u.contains('sasangeyou')) {
    headers['Referer'] = 'https://sasangeyou.net/';
  } else if (u.contains('kanzenin')) {
    headers['Referer'] = 'https://kanzenin.info/';
  } else if (u.contains('mangasusuku')) {
    headers['Referer'] = 'https://mangasusuku.com/';
  } else if (u.contains('izanamiscans')) {
    headers['Referer'] = 'https://izanamiscans.my.id/';
  } else if (u.contains('cgbum')) {
    headers['Referer'] = 'https://cgbum.com/';
  } else if (u.contains('lepoytl')) {
    headers['Referer'] = 'https://www.lepoytl.my.id/';
  } else if (u.contains('yurilab')) {
    headers['Referer'] = 'https://yurilab.top/';
  } else if (u.contains('maid')) {
    headers['Referer'] = 'https://www.maid.my.id/';
  } else if (u.contains('natsu')) {
    headers['Referer'] = 'https://natsu.one/';
  } else if (u.contains('komikremaja')) {
    headers['Referer'] = 'https://komikremaja.art/';
  } else if (u.contains('shirodoujin')) {
    headers['Referer'] = 'https://shirodoujin.com/';
  } else if (u.contains('fanfox') || u.contains('mfcdn.net') || u.contains('mangafox')) {
    headers['Referer'] = 'https://fanfox.net/';
  } else if (u.contains('mangapill') || u.contains('readdetectiveconan') || u.contains('mpcdn')) {
    headers['Referer'] = 'https://mangapill.com/';
  } else if (u.contains('komikapk') || u.contains('cdn-guard.com')) {
    headers['Referer'] = 'https://komikapk.app/';
  } else if (u.contains('wp.com')) {
    if (u.contains('sasangeyou')) {
      headers['Referer'] = 'https://sasangeyou.net/';
    } else if (u.contains('komikindo') || u.contains('linksaya')) {
      headers['Referer'] = 'https://komikindo.click/';
    } else if (u.contains('bacakomik')) {
      headers['Referer'] = 'https://bacakomik.my/';
    } else if (u.contains('komiku')) {
      headers['Referer'] = 'https://komiku.org/';
    } else if (u.contains('mihentai')) {
      headers['Referer'] = 'https://mihentai.net/';
    } else if (u.contains('crotpedia') || u.contains('eromanga')) {
      headers['Referer'] = 'https://crotpedia.net/';
    }
  } else {
    try {
      final uri = Uri.parse(url);
      if (uri.hasScheme && uri.host.isNotEmpty) {
        headers['Referer'] = '${uri.scheme}://${uri.host}/';
      }
    } catch (_) {}
  }
  return headers;
}

/// Drop-in replacement for [CachedNetworkImage] that automatically:
/// 1. Injects the correct Referer and User-Agent headers.
/// 2. Evicts failed cache entries so temporary glitches don't stick forever.
/// 3. Automatically falls back if an image fails (e.g. 403 Forbidden or CDN error):
///    - Attempt 0: Original responsive URL (e.g. -727x1024.jpg)
///    - Attempt 1: Unscaled original image (stripping -WxH dimensions)
///    - Attempt 2: High-availability image proxy (wsrv.nl, matching Kotatsu)
class CachedCover extends StatefulWidget {
  final String? imageUrl;
  final String? source;
  final String? slug;
  final String? customCoverPath;
  final BoxFit fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, DownloadProgress)? progressIndicatorBuilder;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final Widget Function(BuildContext, ImageProvider)? imageBuilder;
  final Map<String, String>? extraHeaders;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
  final double? width;
  final double? height;
  final FilterQuality filterQuality;
  final int? memCacheWidth;
  final int? memCacheHeight;

  const CachedCover({
    super.key,
    required this.imageUrl,
    this.source,
    this.slug,
    this.customCoverPath,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.progressIndicatorBuilder,
    this.errorWidget,
    this.imageBuilder,
    this.extraHeaders,
    this.fadeInDuration = const Duration(milliseconds: 150),
    this.fadeOutDuration = const Duration(milliseconds: 150),
    this.width,
    this.height,
    this.filterQuality = FilterQuality.medium,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  State<CachedCover> createState() => _CachedCoverState();
}

class _CachedCoverState extends State<CachedCover> {
  String? _activeUrl;
  int _retryAttempt = 0;
  bool _isTerminalError = false;
  File? _cachedFile;

  @override
  void initState() {
    super.initState();
    _activeUrl = _normalizeUrl(widget.imageUrl);
    _checkCachedFile();
  }

  void _checkCachedFile() {
    if (_activeUrl != null && _activeUrl!.isNotEmpty) return;
    final slug = widget.slug;
    final src = widget.source;
    if (slug != null && slug.isNotEmpty) {
      final saved = LocalStorage.getSavedCoverPath(slug, source: src);
      if (saved != null && File(saved).existsSync()) {
        _cachedFile = File(saved);
      }
    }
  }

  @override
  void didUpdateWidget(covariant CachedCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _retryAttempt = 0;
      _isTerminalError = false;
      _activeUrl = _normalizeUrl(widget.imageUrl);
      _checkCachedFile();
    }
  }

  String? _normalizeUrl(String? raw) {
    if (raw == null) return null;
    var url = raw.trim();
    if (url.isEmpty) return null;
    if (url.startsWith('//')) {
      url = 'https:$url';
    } else if (url.startsWith('http://')) {
      url = url.replaceFirst('http://', 'https://');
    }

    // Safely encode any spaces in URL
    url = url.replaceAll(' ', '%20');

    // Pastikan domain linksaya.com selalu menggunakan HTTPS jika sebelumnya HTTP
    if (url.startsWith('http://linksaya.com') || url.startsWith('http://cdn.linksaya.com')) {
      url = url.replaceFirst('http://', 'https://');
    }

    // Periksa pengaturan proxy gambar
    final proxyMode = LocalStorage.getImageProxy();
    if (proxyMode == 'wsrv' && !url.contains('wsrv.nl')) {
      final dimRegex = RegExp(r'-\d+x\d+(?=\.[a-zA-Z0-9]+$)');
      final cleanMaster = url.replaceFirst(dimRegex, '');
      return 'https://wsrv.nl/?url=${Uri.encodeComponent(cleanMaster)}&we';
    }

    return url;
  }

  void _handleError(String errorUrl, Object error) {
    debugPrint('[CachedCover Error] $errorUrl (attempt $_retryAttempt): $error');
    // JANGAN hapus cache disk (evictFromCache) saat terjadi kegagalan jaringan sementara!
    // Mempertahankan cache memastikan cover offline tetap utuh.

    if (!mounted || _isTerminalError) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final originalUrl = _normalizeUrl(widget.imageUrl);
      if (originalUrl == null) {
        setState(() => _isTerminalError = true);
        return;
      }

      String? nextCandidate;
      final dimRegex = RegExp(r'-\d+x\d+(?=\.[a-zA-Z0-9]+$)');
      final proxyMode = LocalStorage.getImageProxy();

      if (errorUrl.contains('linksaya.com') && _retryAttempt == 0) {
        if (errorUrl.contains('.wp.com')) {
          // Jika gagal via WordPress Photon CDN (misal 403), fallback ke URL langsung linksaya.com
          final noWp = errorUrl.replaceFirst(RegExp(r'^https?://i\d+\.wp\.com/'), '');
          final cleanDirect = 'https://${noWp.replaceAll(RegExp(r'[?&]resize=[^&]*'), '').replaceAll(RegExp(r'[?&]$'), '')}';
          if (cleanDirect != errorUrl) {
            nextCandidate = cleanDirect;
          }
        } else {
          // Jika URL langsung gagal, coba via WordPress Photon CDN
          final noScheme = errorUrl.replaceFirst(RegExp(r'^https?://'), '');
          nextCandidate = 'https://i0.wp.com/$noScheme?resize=285,425';
        }
      } else if (_retryAttempt == 0) {
        // Attempt 1 (Anti-ISP Block): Gunakan WordPress Photon CDN (i0.wp.com)
        // Photon CDN tidak pernah diblokir ISP Indonesia (Indosat, Telkomsel, dsb) dan tidak memblokir domain NSFW
        if (!errorUrl.contains('.wp.com') && !errorUrl.contains('wsrv.nl')) {
          final clean = originalUrl.replaceFirst(dimRegex, '');
          final noScheme = clean.replaceFirst(RegExp(r'^https?://'), '');
          nextCandidate = 'https://i0.wp.com/$noScheme';
        } else if (dimRegex.hasMatch(errorUrl)) {
          final unscaled = errorUrl.replaceFirst(dimRegex, '');
          if (unscaled != errorUrl) {
            nextCandidate = unscaled;
          }
        }
      } else if (_retryAttempt == 1) {
        // Attempt 2: Coba wsrv.nl proxy (Cloudflare edge proxy)
        if (proxyMode != 'none' && !errorUrl.contains('wsrv.nl')) {
          final cleanMaster = originalUrl.replaceFirst(dimRegex, '');
          nextCandidate = 'https://wsrv.nl/?url=${Uri.encodeComponent(cleanMaster)}&we';
        }
      } else if (_retryAttempt == 2) {
        // Attempt 3: Coba wsrv.nl dengan URL original persis
        if (proxyMode != 'none' && !originalUrl.contains('wsrv.nl')) {
          final directProxy = 'https://wsrv.nl/?url=${Uri.encodeComponent(originalUrl)}&we';
          if (directProxy != errorUrl) {
            nextCandidate = directProxy;
          }
        }
      }

      if (nextCandidate != null && nextCandidate != errorUrl) {
        debugPrint('[CachedCover] Retrying with candidate (attempt ${_retryAttempt + 1}): $nextCandidate');
        setState(() {
          _retryAttempt++;
          _activeUrl = nextCandidate;
        });
      } else {
        setState(() {
          _isTerminalError = true;
        });
      }
    });
  }

  void _manualRetry() {
    setState(() {
      _retryAttempt = 0;
      _isTerminalError = false;
      _activeUrl = _normalizeUrl(widget.imageUrl);
    });
  }

  bool _hasSyncedPersistent = false;

  void _syncToPersistentStorage() {
    if (_hasSyncedPersistent) return;
    _hasSyncedPersistent = true;
    if (widget.slug == null || widget.slug!.isEmpty) return;
    final slug = widget.slug!;
    final src = widget.source;
    final active = _activeUrl;
    if (active == null || active.isEmpty) return;

    Future.microtask(() async {
      try {
        if (LocalStorage.hasSavedCover(slug, source: src)) return;
        final fileInfo = await MangaCoverCacheManager.instance.getFileFromCache(active);
        if (fileInfo != null && fileInfo.file.existsSync() && fileInfo.file.lengthSync() > 100) {
          final bytes = await fileInfo.file.readAsBytes();
          await LocalStorage.savePersistentCover(slug, bytes, source: src);
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1. Check for custom replaced cover from local storage
    final customPath = widget.customCoverPath ??
        (widget.slug != null
            ? LocalStorage.getCustomCover(widget.slug!, source: widget.source)
            : null);

    if (customPath != null && customPath.isNotEmpty) {
      final file = File(customPath);
      if (file.existsSync()) {
        if (widget.imageBuilder != null) {
          return widget.imageBuilder!(context, FileImage(file));
        }
        return Image.file(
          file,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          filterQuality: widget.filterQuality,
          errorBuilder: (context, error, stackTrace) => _fallback(theme),
        );
      }
    }

    final url = _activeUrl;

    if (url == null || url.isEmpty || _isTerminalError) {
      final savedPath = (widget.slug != null && widget.slug!.isNotEmpty)
          ? LocalStorage.getSavedCoverPath(widget.slug!, source: widget.source)
          : null;
      if (savedPath != null) {
        final file = File(savedPath);
        if (file.existsSync()) {
          if (widget.imageBuilder != null) {
            return widget.imageBuilder!(context, FileImage(file));
          }
          return Image.file(
            file,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            filterQuality: widget.filterQuality,
            errorBuilder: (context, error, stackTrace) => _fallback(theme),
          );
        }
      }
      return widget.errorWidget != null
          ? widget.errorWidget!(context, url ?? '', 'Failed after retries')
          : _fallback(theme);
    }

    final headers = {...refererFor(url, source: widget.source), ...?widget.extraHeaders};

    final hasBoundedWidth = widget.width != null && widget.width!.isFinite && widget.width! > 0;
    final hasBoundedHeight = widget.height != null && widget.height!.isFinite && widget.height! > 0;

    // Optimasi Memori: Batasi resolusi decode bitmap di RAM untuk cover agar tidak decode raw image 24MB
    final bool isMangaCover = widget.slug != null || widget.fit == BoxFit.cover;
    final int? effectiveMemCacheWidth;
    if (widget.memCacheWidth != null) {
      effectiveMemCacheWidth = widget.memCacheWidth;
    } else if (hasBoundedWidth) {
      effectiveMemCacheWidth = (widget.width! * 2.5).clamp(180, 500).round();
    } else if (isMangaCover) {
      effectiveMemCacheWidth = 360;
    } else {
      effectiveMemCacheWidth = null;
    }

    final int? effectiveMemCacheHeight;
    if (widget.memCacheHeight != null) {
      effectiveMemCacheHeight = widget.memCacheHeight;
    } else if (!hasBoundedWidth && hasBoundedHeight) {
      effectiveMemCacheHeight = (widget.height! * 2.5).clamp(240, 750).round();
    } else {
      effectiveMemCacheHeight = null;
    }

    return CachedNetworkImage(
      key: ValueKey('$url-$_retryAttempt'),
      cacheManager: MangaCoverCacheManager.instance,
      imageUrl: url,
      httpHeaders: headers,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      fadeInDuration: widget.fadeInDuration,
      fadeOutDuration: widget.fadeOutDuration,
      imageBuilder: (context, imageProvider) {
        _syncToPersistentStorage();
        if (widget.imageBuilder != null) {
          return widget.imageBuilder!(context, imageProvider);
        }
        return Image(
          image: imageProvider,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          filterQuality: widget.filterQuality,
        );
      },
      progressIndicatorBuilder: widget.progressIndicatorBuilder,
      filterQuality: widget.filterQuality,
      memCacheWidth: effectiveMemCacheWidth,
      memCacheHeight: effectiveMemCacheHeight,
      placeholder: widget.progressIndicatorBuilder == null
          ? (widget.placeholder ?? (context, _) => const MangaCardCoverShimmer())
          : null,
      errorWidget: (context, errorUrl, error) {
        _handleError(errorUrl, error);
        final diskCover = (widget.slug != null && widget.slug!.isNotEmpty)
            ? LocalStorage.getSavedCoverPath(widget.slug!, source: widget.source)
            : null;
        if (diskCover != null) {
          final file = File(diskCover);
          if (file.existsSync()) {
            if (widget.imageBuilder != null) {
              return widget.imageBuilder!(context, FileImage(file));
            }
            return Image.file(
              file,
              fit: widget.fit,
              width: widget.width,
              height: widget.height,
              filterQuality: widget.filterQuality,
            );
          }
        }
        if (_cachedFile != null && _cachedFile!.existsSync()) {
          if (widget.imageBuilder != null) {
            return widget.imageBuilder!(context, FileImage(_cachedFile!));
          }
          return Image.file(
            _cachedFile!,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            filterQuality: widget.filterQuality,
          );
        }
        return widget.errorWidget != null
            ? widget.errorWidget!(context, errorUrl, error)
            : _fallback(theme);
      },
    );
  }

  Widget _fallback(ThemeData theme) {
    final savedPath = (widget.slug != null && widget.slug!.isNotEmpty)
        ? LocalStorage.getSavedCoverPath(widget.slug!, source: widget.source)
        : null;
    if (savedPath != null) {
      final file = File(savedPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          filterQuality: widget.filterQuality,
        );
      }
    }
    if (_cachedFile != null && _cachedFile!.existsSync()) {
      return Image.file(
        _cachedFile!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        filterQuality: widget.filterQuality,
      );
    }
    return InkWell(
      onTap: _manualRetry,
      child: Container(
        color: theme.colorScheme.surfaceContainerHigh,
        child: const Center(
          child: Icon(Icons.broken_image, size: 28, color: Colors.grey),
        ),
      ),
    );
  }
}
