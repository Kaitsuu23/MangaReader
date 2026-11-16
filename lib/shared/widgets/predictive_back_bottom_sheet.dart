import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps bottom sheet content to provide native Android 14+ Predictive Back animation.
///
/// As the user swipes from either screen edge, the sheet scales down and translates
/// downwards in real-time tracking the finger. If released, the sheet smoothly pops.
/// If cancelled, it springs back into place.
class PredictiveBackBottomSheet extends StatefulWidget {
  final Widget child;

  const PredictiveBackBottomSheet({
    super.key,
    required this.child,
  });

  @override
  State<PredictiveBackBottomSheet> createState() => _PredictiveBackBottomSheetState();
}

class _PredictiveBackBottomSheetState extends State<PredictiveBackBottomSheet>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  double _progress = 0.0;
  bool _isGestureInProgress = false;
  late AnimationController _cancelController;
  late Animation<double> _cancelAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cancelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        setState(() {
          _progress = _cancelAnimation.value;
        });
      });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelController.dispose();
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!mounted) return false;
    // Only handle if this modal sheet is the topmost active route
    final modalRoute = ModalRoute.of(context);
    if (modalRoute == null || !modalRoute.isCurrent) {
      return false;
    }

    _cancelController.stop();
    setState(() {
      _isGestureInProgress = true;
      _progress = backEvent.progress;
    });
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!mounted || !_isGestureInProgress) return;
    setState(() {
      _progress = backEvent.progress;
    });
  }

  @override
  void handleCancelBackGesture() {
    if (!mounted || !_isGestureInProgress) return;
    _cancelAnimation = Tween<double>(begin: _progress, end: 0.0).animate(
      CurvedAnimation(parent: _cancelController, curve: Curves.easeOutCubic),
    );
    _cancelController.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _isGestureInProgress = false;
          _progress = 0.0;
        });
      }
    });
  }

  @override
  void handleCommitBackGesture() {
    if (!mounted) return;
    _isGestureInProgress = false;
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null && modalRoute.isCurrent) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // In-place scale: shrinking centered in place without dropping downwards
    final scale = 1.0 - (_progress * 0.10);
    final bottomRadius = _progress * 20.0;

    Widget content = RepaintBoundary(child: widget.child);

    if (_progress > 0.01) {
      content = ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(bottomRadius),
          bottomRight: Radius.circular(bottomRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }

    return Transform.scale(
      scale: scale,
      alignment: Alignment.center,
      child: content,
    );
  }
}
