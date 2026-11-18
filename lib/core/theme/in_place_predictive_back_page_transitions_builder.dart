import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// In-place Android 14+ Predictive Back Page Transitions Builder.
///
/// Matches Android U's Material 3 predictive back motion specs and curves,
/// but keeps the shrinking card strictly centered in-place (Alignment.center)
/// without shifting downwards or sideways, and maintains 100% opacity during
/// the active gesture.
class InPlacePredictiveBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const InPlacePredictiveBackPageTransitionsBuilder({
    this.fallbackColor,
    this.anchorRect,
  });

  final Color? fallbackColor;
  final Rect? anchorRect;

  @override
  Duration get transitionDuration =>
      const Duration(milliseconds: FadeForwardsPageTransitionsBuilder.kTransitionMilliseconds);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _PredictiveBackGestureDetector(
      route: route,
      builder: (
        BuildContext context,
        _PredictiveBackPhase phase,
        PredictiveBackEvent? startBackEvent,
        PredictiveBackEvent? currentBackEvent,
      ) {
        // Kalau ada anchorRect (search bar morph), selalu pakai MorphTransition —
        // bahkan saat predictive back gesture aktif. Morph collapse ke search bar
        // jauh lebih tepat daripada in-place shrink ke tengah layar.
        if (anchorRect != null) {
          return _SearchBarMorphPageTransition(
            animation: animation,
            anchorRect: anchorRect!,
            child: child,
          );
        }

        if (route.popGestureInProgress) {
          return _InPlacePredictiveBackSharedElementPageTransition(
            animation: animation,
            phase: phase,
            secondaryAnimation: secondaryAnimation,
            child: child,
          );
        }

        return FadeForwardsPageTransitionsBuilder(
          backgroundColor: fallbackColor,
        ).buildTransitions(route, context, animation, secondaryAnimation, child);
      },
    );
  }
}

typedef _PredictiveBackGestureDetectorWidgetBuilder = Widget Function(
  BuildContext context,
  _PredictiveBackPhase phase,
  PredictiveBackEvent? startBackEvent,
  PredictiveBackEvent? currentBackEvent,
);

enum _PredictiveBackPhase {
  idle,
  start,
  update,
  commit,
  cancel,
}

class _PredictiveBackGestureDetector extends StatefulWidget {
  const _PredictiveBackGestureDetector({
    required this.route,
    required this.builder,
  });

  final _PredictiveBackGestureDetectorWidgetBuilder builder;
  final PageRoute<dynamic> route;

  @override
  State<_PredictiveBackGestureDetector> createState() => _PredictiveBackGestureDetectorState();
}

class _PredictiveBackGestureDetectorState extends State<_PredictiveBackGestureDetector>
    with WidgetsBindingObserver {
  bool get _isEnabled => widget.route.isCurrent && widget.route.popGestureEnabled;

  _PredictiveBackPhase get phase => _phase;
  _PredictiveBackPhase _phase = _PredictiveBackPhase.idle;
  set phase(_PredictiveBackPhase phase) {
    if (_phase != phase && mounted) {
      setState(() => _phase = phase);
    }
  }

  PredictiveBackEvent? get startBackEvent => _startBackEvent;
  PredictiveBackEvent? _startBackEvent;
  set startBackEvent(PredictiveBackEvent? startBackEvent) {
    if (_startBackEvent != startBackEvent && mounted) {
      setState(() => _startBackEvent = startBackEvent);
    }
  }

  PredictiveBackEvent? get currentBackEvent => _currentBackEvent;
  PredictiveBackEvent? _currentBackEvent;
  set currentBackEvent(PredictiveBackEvent? currentBackEvent) {
    if (_currentBackEvent != currentBackEvent && mounted) {
      setState(() => _currentBackEvent = currentBackEvent);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    phase = _PredictiveBackPhase.start;
    final bool gestureInProgress = !backEvent.isButtonEvent && _isEnabled;
    if (!gestureInProgress) {
      return false;
    }

    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    startBackEvent = currentBackEvent = backEvent;
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    phase = _PredictiveBackPhase.update;
    widget.route.handleUpdateBackGestureProgress(progress: 1 - backEvent.progress);
    currentBackEvent = backEvent;
  }

  @override
  void handleCancelBackGesture() {
    phase = _PredictiveBackPhase.cancel;
    widget.route.handleCancelBackGesture();
    startBackEvent = currentBackEvent = null;
  }

  @override
  void handleCommitBackGesture() {
    phase = _PredictiveBackPhase.commit;
    widget.route.handleCommitBackGesture();
    startBackEvent = currentBackEvent = null;
  }

  @override
  Widget build(BuildContext context) {
    final _PredictiveBackPhase effectivePhase =
        widget.route.popGestureInProgress ? phase : _PredictiveBackPhase.idle;
    return widget.builder(context, effectivePhase, startBackEvent, currentBackEvent);
  }
}

class _InPlacePredictiveBackSharedElementPageTransition extends StatefulWidget {
  const _InPlacePredictiveBackSharedElementPageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.phase,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final _PredictiveBackPhase phase;
  final Widget child;

  @override
  State<_InPlacePredictiveBackSharedElementPageTransition> createState() =>
      _InPlacePredictiveBackSharedElementPageTransitionState();
}

class _InPlacePredictiveBackSharedElementPageTransitionState
    extends State<_InPlacePredictiveBackSharedElementPageTransition>
    with SingleTickerProviderStateMixin {
  static const double _kMinScale = 0.88;
  static const int _kCommitMilliseconds = 400;
  static const Curve _kCurve = Curves.easeInOutCubicEmphasized;
  static const Interval _kCommitInterval = Interval(
    0.0,
    _kCommitMilliseconds / FadeForwardsPageTransitionsBuilder.kTransitionMilliseconds,
    curve: _kCurve,
  );

  static const double _kDeviceBorderRadius = 32.0;

  final Tween<double> _borderRadiusTween = Tween<double>(begin: 0.0, end: _kDeviceBorderRadius);
  final Tween<double> _opacityTween = Tween<double>(begin: 1.0, end: 0.0);
  final Tween<double> _scaleTween = Tween<double>(begin: 1.0, end: _kMinScale);

  final ProxyAnimation _commitAnimation = ProxyAnimation();
  final ProxyAnimation _bounceAnimation = ProxyAnimation();
  double _lastBounceAnimationValue = 0.0;
  final ProxyAnimation _animation = ProxyAnimation();

  CurvedAnimation? _curvedAnimation;
  CurvedAnimation? _curvedAnimationReversed;

  void _updateAnimations() {
    _animation.parent = switch (widget.phase) {
      _PredictiveBackPhase.commit => _curvedAnimationReversed,
      _ => widget.animation,
    };

    _bounceAnimation.parent = switch (widget.phase) {
      _PredictiveBackPhase.commit => Tween<double>(
        begin: 0.0,
        end: _lastBounceAnimationValue,
      ).animate(_curvedAnimation!),
      _ => ReverseAnimation(widget.animation),
    };

    _commitAnimation.parent = switch (widget.phase) {
      _PredictiveBackPhase.commit => _animation,
      _ => kAlwaysDismissedAnimation,
    };
  }

  void _updateCurvedAnimations() {
    _curvedAnimation?.dispose();
    _curvedAnimationReversed?.dispose();
    _curvedAnimation = CurvedAnimation(parent: widget.animation, curve: _kCommitInterval);
    _curvedAnimationReversed = CurvedAnimation(
      parent: ReverseAnimation(widget.animation),
      curve: _kCommitInterval,
    );
  }

  @override
  void didUpdateWidget(_InPlacePredictiveBackSharedElementPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      _updateCurvedAnimations();
    }
    if (widget.phase != oldWidget.phase && widget.phase == _PredictiveBackPhase.commit) {
      _updateAnimations();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateCurvedAnimations();
    _updateAnimations();
  }

  @override
  void dispose() {
    _curvedAnimation?.dispose();
    _curvedAnimationReversed?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (BuildContext context, Widget? child) {
        _lastBounceAnimationValue = _bounceAnimation.value;
        return Transform.scale(
          scale: _scaleTween.evaluate(_bounceAnimation),
          alignment: Alignment.center,
          child: Opacity(
            opacity: _opacityTween.evaluate(_commitAnimation),
            child: ClipRRect(
              borderRadius: MediaQuery.displayCornerRadiiOf(context) ??
                  BorderRadius.circular(_borderRadiusTween.evaluate(_bounceAnimation)),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          ),
        );
      },
      child: RepaintBoundary(child: widget.child),
    );
  }
}

/// Transisi ekspansi morph kapsul search bar menjadi layar penuh ala Material 3
class _SearchBarMorphPageTransition extends StatelessWidget {
  final Animation<double> animation;
  final Rect anchorRect;
  final Widget child;

  const _SearchBarMorphPageTransition({
    required this.animation,
    required this.anchorRect,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final animVal = animation.value.clamp(0.0, 1.0);
        final screenSize = MediaQuery.sizeOf(context);
        final fullScreenRect = Offset.zero & screenSize;

        // Kurva pergerakan transisi:
        // Saat membuka (forward): gunakan kurva pembuka ekspansi Material 3 yang elegan.
        // Saat menutup / swap back (reverse/pop): gunakan kurva responsif langsung (Curves.easeIn)
        // yang langsung menyusutkan page search ke atas sejak piksel pertama tanpa ada fase jeda / diam.
        final double t;
        if (animation.status == AnimationStatus.forward) {
          t = Curves.easeInOutCubicEmphasized.transform(animVal);
        } else {
          t = Curves.easeIn.transform(animVal);
        }

        final currentRect = Rect.lerp(anchorRect, fullScreenRect, t)!;
        final currentRadius = lerpDouble(24.0, 0.0, t)!;
        final elevation = lerpDouble(3.0, 0.0, t)!;

        final theme = Theme.of(context);
        final progressFactor = (currentRect.height / screenSize.height).clamp(0.0, 1.0);
        final containerColor = theme.colorScheme.surfaceContainerHigh;

        // Konten memudar lembut saat menyusut ke atas ke kapsul search bar
        final contentOpacity = const Interval(0.12, 1.0, curve: Curves.easeOut).transform(progressFactor);

        return Stack(
          children: [
            Positioned.fromRect(
              rect: currentRect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(currentRadius),
                child: Material(
                  color: containerColor,
                  elevation: elevation,
                  shadowColor: Colors.black.withValues(alpha: 0.2),
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: screenSize.width,
                    maxWidth: screenSize.width,
                    minHeight: screenSize.height,
                    maxHeight: screenSize.height,
                    child: Transform.translate(
                      offset: Offset(-currentRect.left, -currentRect.top),
                      child: Opacity(
                        opacity: contentOpacity,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Route that explicitly enables centered in-place predictive back transition,
/// and supports optional search bar capsule morphing when anchorRect is provided.
class PredictiveBackPageRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  final Rect? anchorRect;

  PredictiveBackPageRoute({
    required this.builder,
    this.anchorRect,
    super.settings,
    this.maintainState = true,
    super.fullscreenDialog,
    super.allowSnapshotting = true,
    super.barrierDismissible = false,
  });

  @override
  final bool maintainState;

  @override
  bool get opaque => anchorRect == null;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration =>
      const Duration(milliseconds: FadeForwardsPageTransitionsBuilder.kTransitionMilliseconds);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final builder = InPlacePredictiveBackPageTransitionsBuilder(
      fallbackColor: null,
      anchorRect: anchorRect,
    );
    return builder.buildTransitions(this, context, animation, secondaryAnimation, child);
  }
}
