import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class FloatingNavbarItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badgeCount;

  /// Opsional: path asset SVG untuk menggantikan IconData
  final String? svgAsset;

  const FloatingNavbarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badgeCount = 0,
    this.svgAsset,
  });
}

enum _NavItemAnimation { history, favorites, explore, feed }

class FloatingNavbar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FloatingNavbarItem> items;
  final bool showLabels;
  /// true = floating pill style, false = nempel di bawah (non-floating)
  final bool isFloating;
  /// Notifier dari MainScreen — true saat search overlay terbuka (nav bar slide down)
  final ValueNotifier<bool>? searchOpenNotifier;

  const FloatingNavbar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.showLabels = true,
    this.isFloating = true,
    this.searchOpenNotifier,
  });

  @override
  State<FloatingNavbar> createState() => _FloatingNavbarState();
}

class _FloatingNavbarState extends State<FloatingNavbar>
    with TickerProviderStateMixin {
  late AnimationController _pillController;
  late Animation<double> _pillAnimation;
  int _previousIndex = 0;

  late List<AnimationController> _tapControllers;

  // ── Search hide/show slide ─────────────────────────────────────────────────
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  static const _animDuration = Duration(milliseconds: 700);
  // Kotatsu: hide 175ms FastOutLinearIn, show 225ms LinearOutSlowIn
  static const _slideHideDuration = Duration(milliseconds: 175);
  static const _slideShowDuration  = Duration(milliseconds: 225);

  _NavItemAnimation _animTypeFor(int index) {
    switch (index) {
      case 0:  return _NavItemAnimation.history;
      case 1:  return _NavItemAnimation.favorites;
      case 2:  return _NavItemAnimation.explore;
      default: return _NavItemAnimation.feed;
    }
  }

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.currentIndex;
    _pillController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pillAnimation = CurvedAnimation(
      parent: _pillController,
      curve: Curves.easeInOutCubic,
    );
    _tapControllers = List.generate(
      widget.items.length,
      (_) => AnimationController(vsync: this, duration: _animDuration),
    );

    // Slide controller: nilai 0.0 = tampak, 1.0 = tersembunyi di bawah
    _slideController = AnimationController(
      vsync: this,
      duration: _slideHideDuration,
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 1.5),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.fastOutSlowIn,
    ));

    widget.searchOpenNotifier?.addListener(_onSearchOpenChanged);
  }

  void _onSearchOpenChanged() {
    final isOpen = widget.searchOpenNotifier?.value ?? false;
    if (isOpen) {
      // Hide: 175ms FastOutLinearIn
      _slideController.duration = _slideHideDuration;
      _slideController.animateTo(
        1.0,
        curve: Curves.fastOutSlowIn,
      );
    } else {
      // Show: 225ms LinearOutSlowIn
      _slideController.duration = _slideShowDuration;
      _slideController.animateTo(
        0.0,
        curve: Curves.decelerate,
      );
    }
  }

  @override
  void didUpdateWidget(FloatingNavbar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _previousIndex = old.currentIndex;
      _pillController.forward(from: 0);
      _tapControllers[widget.currentIndex].forward(from: 0);
    }
    if (old.searchOpenNotifier != widget.searchOpenNotifier) {
      old.searchOpenNotifier?.removeListener(_onSearchOpenChanged);
      widget.searchOpenNotifier?.addListener(_onSearchOpenChanged);
    }
  }

  @override
  void dispose() {
    widget.searchOpenNotifier?.removeListener(_onSearchOpenChanged);
    _slideController.dispose();
    _pillController.dispose();
    for (final c in _tapControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Animasi per jenis ──────────────────────────────────────────────────────

  /// History: rotate searah jarum jam 360°
  Widget _buildHistoryAnim(int index, Widget iconWidget) {
    final ctrl = _tapControllers[index];
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        final angle = -(Curves.easeInOut.transform(ctrl.value) * 2 * math.pi);
        return Transform.rotate(angle: angle, child: child);
      },
      child: iconWidget,
    );
  }

  /// Favorites: heartbeat — double scale pulse
  Widget _buildFavoritesAnim(int index, Widget iconWidget) {
    final ctrl = _tapControllers[index];
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        final t = ctrl.value;
        double scale;
        if      (t < 0.20) { scale = 1.00 + 0.35 * (t / 0.20); }
        else if (t < 0.35) { scale = 1.35 - 0.20 * ((t - 0.20) / 0.15); }
        else if (t < 0.50) { scale = 1.15 + 0.20 * ((t - 0.35) / 0.15); }
        else if (t < 0.65) { scale = 1.35 - 0.35 * ((t - 0.50) / 0.15); }
        else               { scale = 1.00; }
        return Transform.scale(scale: scale, child: child);
      },
      child: iconWidget,
    );
  }

  /// Explore: kompas berputar 360° dengan elasticOut
  Widget _buildExploreAnim(int index, Widget iconWidget) {
    final ctrl = _tapControllers[index];
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        final angle = Curves.elasticOut.transform(ctrl.value) * 2 * math.pi;
        return Transform.rotate(angle: angle, child: child);
      },
      child: iconWidget,
    );
  }

  /// Feed: sinyal build-up — saat idle tampilkan Icon biasa,
  /// saat animasi jalan ganti dengan painter yang menggambar signal bertahap.
  Widget _buildFeedAnim(
    int index,
    Color iconColor,
    IconData iconData,
    int badgeCount,
  ) {
    final ctrl = _tapControllers[index];
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, child) {
        final p = ctrl.value;

        // Icon biasa untuk state idle
        final staticIcon = Badge(
          isLabelVisible: badgeCount > 0,
          label: Text(
            badgeCount > 99 ? '+99' : '+$badgeCount',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
          ),
          child: Icon(iconData, size: 22, color: iconColor),
        );

        if (p == 0.0) return staticIcon;

        // Saat animasi jalan, ganti dengan painter signal build-up
        return Badge(
          isLabelVisible: badgeCount > 0,
          label: Text(
            badgeCount > 99 ? '+99' : '+$badgeCount',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
          ),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CustomPaint(
              painter: _SignalBuildPainter(progress: p, color: iconColor),
            ),
          ),
        );
      },
    );
  }

  Widget _wrapWithAnim(
    int index,
    Widget iconWidget,
    Color iconColor,
    IconData iconData,
    int badgeCount,
  ) {
    switch (_animTypeFor(index)) {
      case _NavItemAnimation.history:
        return _buildHistoryAnim(index, iconWidget);
      case _NavItemAnimation.favorites:
        return _buildFavoritesAnim(index, iconWidget);
      case _NavItemAnimation.explore:
        return _buildExploreAnim(index, iconWidget);
      case _NavItemAnimation.feed:
        return _buildFeedAnim(index, iconColor, iconData, badgeCount);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Tinggi konten navbar
    const double navHeight = 72;

    // Container navbar — beda style tergantung isFloating
    Widget navbar = SizedBox(
      height: navHeight,
      child: _buildNavContent(context, colorScheme),
    );

    Widget result;
    if (widget.isFloating) {
      // Floating: ada padding, rounded, shadow
      result = SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _buildNavContent(context, colorScheme),
          ),
        ),
      );
    } else {
      // Non-floating: nempel di bawah, ikut SafeArea, full-width
      result = Material(
        color: colorScheme.surfaceContainer,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: navbar,
        ),
      );
    }

    // Bungkus dengan SlideTransition agar nav bar bisa slide down saat search terbuka
    return SlideTransition(
      position: _slideAnimation,
      child: result,
    );
  }

  Widget _buildNavContent(BuildContext context, ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / widget.items.length;

              return Stack(
                children: [
                  // Sliding pill indicator
                  AnimatedBuilder(
                    animation: _pillAnimation,
                    builder: (context, child) {
                      final fromX = _previousIndex * itemWidth;
                      final toX   = widget.currentIndex * itemWidth;
                      final curX  = fromX + (toX - fromX) * _pillAnimation.value;
                      return Positioned(
                        left:   curX + 10,
                        top:    8,
                        bottom: 8,
                        width:  itemWidth - 20,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      );
                    },
                  ),

                  // Nav items
                  Row(
                    children: List.generate(widget.items.length, (index) {
                      final item = widget.items[index];

                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            widget.onTap(index);
                            if (index == widget.currentIndex) {
                              _tapControllers[index].forward(from: 0);
                            }
                          },
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            height: 64,
                            child: AnimatedBuilder(
                              animation: _pillAnimation,
                              builder: (context, child) {
                                final t = _pillAnimation.value;
                                final isFrom = index == _previousIndex;
                                final isTo   = index == widget.currentIndex;

                                Color iconColor;
                                FontWeight fontWeight;
                                bool useActive;

                                if (isTo) {
                                  iconColor = Color.lerp(
                                    colorScheme.onSurface.withValues(alpha: 0.65),
                                    colorScheme.onSecondaryContainer,
                                    t,
                                  )!;
                                  fontWeight = FontWeight.lerp(
                                      FontWeight.w500, FontWeight.w700, t) ??
                                      FontWeight.w600;
                                  useActive = t > 0.5;
                                } else if (isFrom) {
                                  iconColor = Color.lerp(
                                    colorScheme.onSecondaryContainer,
                                    colorScheme.onSurface.withValues(alpha: 0.65),
                                    t,
                                  )!;
                                  fontWeight = FontWeight.lerp(
                                      FontWeight.w700, FontWeight.w500, t) ??
                                      FontWeight.w500;
                                  useActive = t < 0.5;
                                } else {
                                  iconColor = colorScheme.onSurface.withValues(alpha: 0.65);
                                  fontWeight = FontWeight.w500;
                                  useActive = false;
                                }

                                final iconData = useActive ? item.activeIcon : item.icon;

                                // Bangun icon widget (SVG / Icon biasa)
                                Widget iconWidget;
                                if (item.svgAsset != null) {
                                  iconWidget = SvgPicture.asset(
                                    item.svgAsset!,
                                    width: 20,
                                    height: 20,
                                    colorFilter: ColorFilter.mode(
                                        iconColor, BlendMode.srcIn),
                                  );
                                } else {
                                  iconWidget = Badge(
                                    isLabelVisible: item.badgeCount > 0,
                                    label: Text(
                                      item.badgeCount > 99
                                          ? '+99'
                                          : '+${item.badgeCount}',
                                      style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    child: Icon(iconData,
                                        size: 22, color: iconColor),
                                  );
                                }

                                final animatedIcon = _wrapWithAnim(
                                  index,
                                  iconWidget,
                                  iconColor,
                                  iconData,
                                  item.badgeCount,
                                );

                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    animatedIcon,
                                    if (widget.showLabels) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.label,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: fontWeight,
                                          color: iconColor,
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          );
  }
}

// ── Signal Build-up Painter ────────────────────────────────────────────────────
//
// Meniru persis ic_feed.xml Kotatsu (viewBox 24×24):
//   - dot      : lingkaran di kiri-bawah (cx≈6.18, cy≈17.82, r≈2.18)
//   - arc kecil: radius ~7.07 dari (4,20) → area (4,10.1)–(13.9,20)
//   - arc besar: radius ~12.73 dari (4,20) → area (4,4.4)–(19.6,19.9)
//
// Animasi (sama seperti avd_feed_enter.xml):
//   progress 0.00–0.33 → dot muncul
//   progress 0.33–0.66 → arc kecil muncul
//   progress 0.66–1.00 → arc besar muncul
class _SignalBuildPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _SignalBuildPainter({required this.progress, required this.color});

  // Skala dari viewBox 24 → size
  double _s(double v, double size) => v / 24.0 * size;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Semua koordinat dalam viewBox 24×24, di-scale ke canvas
    // Pusat arc ada di pojok kiri-bawah: (4, 20) di viewBox
    final cx = _s(4.0, w);
    final cy = _s(20.0, h);

    final dotPaint = Paint()..style = PaintingStyle.fill;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // --- Dot: lingkaran di (6.18, 17.82) r=2.18 ---
    final dotAlpha = _phase(progress, 0.00, 0.33);
    if (dotAlpha > 0) {
      dotPaint.color = color.withValues(alpha: dotAlpha);
      canvas.drawCircle(
        Offset(_s(6.18, w), _s(17.82, h)),
        _s(2.18, w),
        dotPaint,
      );
    }

    // --- Arc kecil: r = 9.9 (dari path: 7.07 fill + stroke 2.83/2 ≈ 9.9) ---
    final sw1 = _s(2.83, w);
    final arc1Alpha = _phase(progress, 0.33, 0.66);
    if (arc1Alpha > 0) {
      arcPaint
        ..color = color.withValues(alpha: arc1Alpha)
        ..strokeWidth = sw1;
      // Center di kiri-bawah (4,20), arc dari atas (-90°) ke kanan (0°)
      // start = -π/2 (atas), sweep = +π/2 (searah jarum jam ke kanan)
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: _s(9.9, w)),
        -math.pi / 2,
        math.pi / 2,
        false,
        arcPaint,
      );
    }

    // --- Arc besar: r = 15.56 ---
    final sw2 = _s(2.83, w);
    final arc2Alpha = _phase(progress, 0.66, 1.00);
    if (arc2Alpha > 0) {
      arcPaint
        ..color = color.withValues(alpha: arc2Alpha)
        ..strokeWidth = sw2;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: _s(15.56, w)),
        -math.pi / 2,
        math.pi / 2,
        false,
        arcPaint,
      );
    }
  }

  double _phase(double p, double start, double end) {
    if (p <= start) return 0.0;
    if (p >= end)   return 1.0;
    return (p - start) / (end - start);
  }

  @override
  bool shouldRepaint(_SignalBuildPainter old) =>
      old.progress != progress || old.color != color;
}
