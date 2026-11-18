import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/storage/local_storage.dart';
import '../../shared/widgets/cached_cover.dart';

class SupportedDomainItem {
  final String sourceId;
  final String sourceName;
  final List<String> domains;

  const SupportedDomainItem({
    required this.sourceId,
    required this.sourceName,
    required this.domains,
  });
}

/// Daftar domain resmi yang didukung untuk penanganan tautan web (Handle Links / Deep Linking)
const List<SupportedDomainItem> kSupportedDomains = [
  SupportedDomainItem(
    sourceId: 'shinigami',
    sourceName: 'Shinigami',
    domains: [
      's1.shinigami.mx',
      'shinigami.io',
      'shinigami.gg',
      '11.shinigami.asia',
      'id.shinigami.asia',
      'shinigami.moe',
    ],
  ),
  SupportedDomainItem(
    sourceId: 'softkomik',
    sourceName: 'Softkomik',
    domains: ['softkomik.app', 'softdevices.my.id'],
  ),
  SupportedDomainItem(
    sourceId: 'kiryuu',
    sourceName: 'Kiryuu',
    domains: ['v7.kiryuu.to', 'kiryuu.id'],
  ),
  SupportedDomainItem(
    sourceId: 'komiku',
    sourceName: 'Komiku',
    domains: ['komiku.org'],
  ),
  SupportedDomainItem(
    sourceId: 'hwago',
    sourceName: 'Hwago',
    domains: ['01.hwago.com'],
  ),
  SupportedDomainItem(
    sourceId: 'doujindesu',
    sourceName: 'DoujinDesu',
    domains: ['doujin.desu.xxx'],
  ),
  SupportedDomainItem(
    sourceId: 'komiktap',
    sourceName: 'KomikTap',
    domains: ['komiktap.info'],
  ),
  SupportedDomainItem(
    sourceId: 'westmanga',
    sourceName: 'WestManga',
    domains: ['v1.westmanga.my'],
  ),
  SupportedDomainItem(
    sourceId: 'komikindo',
    sourceName: 'Komikindo',
    domains: ['komikindo.click', '2.komikindo.shop', 'komikindo.shop', 'komikindo.co'],
  ),
  SupportedDomainItem(
    sourceId: 'apkomik',
    sourceName: 'Apkomik',
    domains: ['01.apkomik.com', 'apkomik.com'],
  ),
  SupportedDomainItem(
    sourceId: 'bacakomik',
    sourceName: 'BacaKomik',
    domains: ['bacakomik.my'],
  ),
  SupportedDomainItem(
    sourceId: 'lumos',
    sourceName: 'LumosKomik',
    domains: ['03.lumosgg.com', 'lumosgg.com'],
  ),
  SupportedDomainItem(
    sourceId: 'holotoon',
    sourceName: 'Holotoon',
    domains: ['holodek.run'],
  ),
  SupportedDomainItem(
    sourceId: 'pixhentai',
    sourceName: 'PixHentai',
    domains: ['pixhentai.com'],
  ),
  SupportedDomainItem(
    sourceId: 'ikiru',
    sourceName: 'Ikiru',
    domains: ['09.ikiru.wtf', 'ikiru.wtf'],
  ),
  SupportedDomainItem(
    sourceId: 'hentaicrot',
    sourceName: 'HentaiCrot',
    domains: ['hentaicrot.com'],
  ),
  SupportedDomainItem(
    sourceId: 'voratoon',
    sourceName: 'VoraToon',
    domains: ['v10.voratoon.com', 'voratoon.com'],
  ),
  SupportedDomainItem(
    sourceId: 'luvyaa',
    sourceName: 'Luvyaa',
    domains: ['v5.luvyaa.co', 'luvyaa.co'],
  ),
  SupportedDomainItem(
    sourceId: 'crotpedia',
    sourceName: 'CrotPedia',
    domains: ['crotpedia.net'],
  ),
  SupportedDomainItem(
    sourceId: 'mihentai',
    sourceName: 'MiHentai',
    domains: ['mihentai.net'],
  ),
  SupportedDomainItem(
    sourceId: 'ainz',
    sourceName: 'AinzScans',
    domains: ['v3.ainzscans01.com', 'api.ainzscans01.com'],
  ),
  SupportedDomainItem(
    sourceId: 'soulscans',
    sourceName: 'SoulScans',
    domains: ['v1.soulscans.asia', 'soulscans.asia'],
  ),
  SupportedDomainItem(
    sourceId: 'komikstation',
    sourceName: 'KomikStation',
    domains: ['komikstation.org', 'img.klikcdn.com'],
  ),
  SupportedDomainItem(
    sourceId: 'komikindoch',
    sourceName: 'Komikindo (CH)',
    domains: ['komikindo.ch'],
  ),
  SupportedDomainItem(
    sourceId: 'sasangeyou',
    sourceName: 'Sasangeyou',
    domains: ['sasangeyou.net', 'cdn.sasangeyouku.my.id'],
  ),
  SupportedDomainItem(
    sourceId: 'kanzenin',
    sourceName: 'Kanzenin',
    domains: ['kanzenin.info'],
  ),
  SupportedDomainItem(
    sourceId: 'mangasusuku',
    sourceName: 'MangaSusuku',
    domains: ['mangasusuku.com'],
  ),
  SupportedDomainItem(
    sourceId: 'izanamiscans',
    sourceName: 'IzanamiScans',
    domains: ['izanamiscans.my.id'],
  ),
  SupportedDomainItem(
    sourceId: 'cgbum',
    sourceName: 'CGBUM',
    domains: ['cgbum.com'],
  ),
  SupportedDomainItem(
    sourceId: 'lepoytl',
    sourceName: 'Lepoy TL',
    domains: ['lepoytl.my.id', 'www.lepoytl.my.id'],
  ),
  SupportedDomainItem(
    sourceId: 'yurilab',
    sourceName: 'YuriLab',
    domains: ['yurilab.top'],
  ),
  SupportedDomainItem(
    sourceId: 'maid',
    sourceName: 'Maid',
    domains: ['maid.my.id', 'www.maid.my.id'],
  ),
  SupportedDomainItem(
    sourceId: 'natsu',
    sourceName: 'Natsu',
    domains: ['natsu.one'],
  ),
  SupportedDomainItem(
    sourceId: 'komikremaja',
    sourceName: 'KomikRemaja',
    domains: ['komikremaja.art'],
  ),
  SupportedDomainItem(
    sourceId: 'shirodoujin',
    sourceName: 'ShiroDoujin',
    domains: ['shirodoujin.com'],
  ),
];

class SupportedDomainsScreen extends ConsumerStatefulWidget {
  const SupportedDomainsScreen({super.key});

  @override
  ConsumerState<SupportedDomainsScreen> createState() => _SupportedDomainsScreenState();
}

class _SupportedDomainsScreenState extends ConsumerState<SupportedDomainsScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _copyDomain(String domain) {
    Clipboard.setData(ClipboardData(text: domain));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        content: Text('Domain $domain disalin'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourcesAsync = ref.watch(sourcesListProvider);

    // Map source icons if available
    final Map<String, String> iconMap = {};
    sourcesAsync.whenData((sources) {
      for (final s in sources) {
        if (s.icon != null && s.icon!.isNotEmpty) {
          iconMap[s.id.toLowerCase()] = s.icon!;
        }
      }
    });

    final query = _searchQuery.trim().toLowerCase();
    final filtered = kSupportedDomains.where((item) {
      if (query.isEmpty) return true;
      if (item.sourceName.toLowerCase().contains(query)) return true;
      if (item.sourceId.toLowerCase().contains(query)) return true;
      return item.domains.any((d) => d.toLowerCase().contains(query));
    }).toList();

    final totalDomains = kSupportedDomains.fold<int>(0, (sum, item) => sum + item.domains.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Domain yang Didukung'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Info Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.open_in_browser_rounded,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Penanganan Tautan Web',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Aplikasi secara otomatis mengenali dan membuka tautan URL manga dari peramban jika domain diizinkan di pengaturan Android.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tips: Pada info aplikasi Android, pilih "Buka secara default" dan centang domain di bawah ini.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. Search Field
          TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Cari sumber atau domain...',
              hintStyle: TextStyle(
                fontSize: 13.5,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHigh,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),

          const SizedBox(height: 14),

          // 3. Header Counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daftar Sumber (${filtered.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                'Total $totalDomains Domain',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 4. Domains List
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'Tidak ada domain atau sumber yang cocok',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            ...filtered.map((item) {
              final isEnabled = LocalStorage.isSourceEnabled(item.sourceId);
              final iconUrl = iconMap[item.sourceId.toLowerCase()];
              final initial = item.sourceName.isNotEmpty ? item.sourceName[0].toUpperCase() : '?';

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 5),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Source Row
                    Row(
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: iconUrl != null && iconUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CachedCover(
                                    imageUrl: iconUrl,
                                    fit: BoxFit.contain,
                                    placeholder: (ctx, url) => const SizedBox.shrink(),
                                    errorWidget: (ctx, url, err) => Container(
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainer,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                                          width: 1,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          initial,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainer,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                                      width: 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.sourceName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                item.sourceId,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isEnabled
                                ? Colors.green.withValues(alpha: 0.15)
                                : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isEnabled ? 'Aktif' : 'Nonaktif',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isEnabled
                                  ? Colors.green.shade700
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    const Divider(height: 1, thickness: 0.5),
                    const SizedBox(height: 8),

                    // Domains Chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: item.domains.map((domain) {
                        return InkWell(
                          onTap: () => _copyDomain(domain),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.link_rounded,
                                  size: 13,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  domain,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.copy_rounded,
                                  size: 11,
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
