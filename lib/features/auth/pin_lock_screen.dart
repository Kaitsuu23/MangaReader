import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/storage/local_storage.dart';

class PinLockScreen extends StatefulWidget {
  final VoidCallback onUnlock;
  final bool canCancel;

  const PinLockScreen({
    super.key,
    required this.onUnlock,
    this.canCancel = false,
  });

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen>
    with SingleTickerProviderStateMixin {
  String _enteredPin = '';
  String? _errorMessage;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onDigitPress(String digit) {
    if (_enteredPin.length >= 4) return;
    HapticFeedback.lightImpact();

    setState(() {
      _enteredPin += digit;
      _errorMessage = null;
    });

    if (_enteredPin.length == 4) {
      _verifyPin();
    }
  }

  void _onBackspacePress() {
    if (_enteredPin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = null;
    });
  }

  void _verifyPin() {
    final expectedPin = LocalStorage.getAppLockPin();
    if (expectedPin == null || _enteredPin == expectedPin) {
      HapticFeedback.mediumImpact();
      widget.onUnlock();
    } else {
      HapticFeedback.vibrate();
      _shakeController.forward(from: 0);
      setState(() {
        _errorMessage = 'PIN salah. Coba lagi.';
        _enteredPin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: widget.canCancel,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              if (widget.canCancel)
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                )
              else
                const SizedBox(height: 48),

              const Spacer(flex: 2),

              // Lock Icon
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 38,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),

              // Title & Subtitle
              Text(
                'Yomika Terkunci',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Masukkan 4 digit PIN keamanan',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),

              // 4 PIN Dots with shake animation
              AnimatedBuilder(
                animation: _shakeAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_shakeAnimation.value, 0),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final isFilled = index < _enteredPin.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isFilled
                            ? (_errorMessage != null
                                ? colorScheme.error
                                : colorScheme.primary)
                            : colorScheme.surfaceContainerHighest,
                        border: Border.all(
                          color: _errorMessage != null
                              ? colorScheme.error
                              : (isFilled
                                  ? colorScheme.primary
                                  : colorScheme.outline.withValues(alpha: 0.5)),
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Error text
              SizedBox(
                height: 40,
                child: Center(
                  child: _errorMessage != null
                      ? Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: colorScheme.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                ),
              ),

              const Spacer(flex: 3),

              // Keypad (1 - 9, empty, 0, backspace)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Column(
                  children: [
                    _buildKeypadRow(['1', '2', '3'], colorScheme),
                    const SizedBox(height: 16),
                    _buildKeypadRow(['4', '5', '6'], colorScheme),
                    const SizedBox(height: 16),
                    _buildKeypadRow(['7', '8', '9'], colorScheme),
                    const SizedBox(height: 16),
                    _buildBottomRow(colorScheme),
                  ],
                ),
              ),

              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadRow(List<String> digits, ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((d) => _buildKeypadButton(d, colorScheme)).toList(),
    );
  }

  Widget _buildBottomRow(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Empty spacer to balance keypad
        const SizedBox(width: 72, height: 72),
        _buildKeypadButton('0', colorScheme),
        SizedBox(
          width: 72,
          height: 72,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _onBackspacePress,
              child: Center(
                child: Icon(
                  Icons.backspace_outlined,
                  size: 26,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String digit, ColorScheme colorScheme) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _onDigitPress(digit),
          child: Center(
            child: Text(
              digit,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
