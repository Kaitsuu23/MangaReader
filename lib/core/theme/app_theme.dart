import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Kotatsu Material 3 Theme definition matching Kotatsu-Redo 9.8.4
class AppTheme {
  // Kotatsu Official Colors from colors_kotatsu.xml
  static const Color kotatsuBlue = Color(0xFF0059C8);
  static const Color kotatsuBlueDark = Color(0xFFABC7FF);
  static const Color kotatsuPrimaryContainerLight = Color(0xFFD9E2FF);
  static const Color kotatsuPrimaryContainerDark = Color(0xFF00458F);

  static const Color lightBackground = Color(0xFFFEFBFF);
  static const Color lightSurface = Color(0xFFFBF8FD);
  static const Color lightSurfaceContainer = Color(0xFFEFEDF1);
  static const Color lightSurfaceContainerHigh = Color(0xFFE9E7EC);
  static const Color lightOnSurface = Color(0xFF1B1B1F);
  static const Color lightOutline = Color(0xFF757780);

  static const Color darkBackground = Color(0xFF1A1B1F);
  static const Color darkSurface = Color(0xFF121316);
  static const Color darkSurfaceContainer = Color(0xFF1F1F23);
  static const Color darkSurfaceContainerHigh = Color(0xFF292A2D);
  static const Color darkOnSurface = Color(0xFFC7C6CA);
  static const Color darkOutline = Color(0xFF8E9099);

  static const Color amoledBackground = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF000000);
  static const Color amoledSurfaceContainer = Color(0xFF121316);

  static const double cardRadius = 12.0;

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: kotatsuBlue,
      onPrimary: Colors.white,
      primaryContainer: kotatsuPrimaryContainerLight,
      onPrimaryContainer: const Color(0xFF001944),
      secondary: const Color(0xFF575E71),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFDBE2F9),
      onSecondaryContainer: const Color(0xFF141B2C),
      tertiary: const Color(0xFF725573),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFFDD7FB),
      onTertiaryContainer: const Color(0xFF2A132C),
      error: const Color(0xFFBA1A1A),
      onError: Colors.white,
      surface: lightSurface,
      onSurface: lightOnSurface,
      surfaceContainer: lightSurfaceContainer,
      surfaceContainerHigh: lightSurfaceContainerHigh,
      outline: lightOutline,
      outlineVariant: const Color(0xFFC5C6D0),
      shadow: Colors.black,
      scrim: Colors.black,
    );

    return _buildTheme(colorScheme, lightBackground);
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: kotatsuBlueDark,
      onPrimary: const Color(0xFF002F65),
      primaryContainer: kotatsuPrimaryContainerDark,
      onPrimaryContainer: const Color(0xFFD7E3FF),
      secondary: const Color(0xFFBEC6DC),
      onSecondary: const Color(0xFF283041),
      secondaryContainer: const Color(0xFF3E4759),
      onSecondaryContainer: const Color(0xFFDAE2F9),
      tertiary: const Color(0xFFDDBCE0),
      onTertiary: const Color(0xFF3F2844),
      tertiaryContainer: const Color(0xFF573E5C),
      onTertiaryContainer: const Color(0xFFFAD8FD),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      surface: darkSurface,
      onSurface: darkOnSurface,
      surfaceContainer: darkSurfaceContainer,
      surfaceContainerHigh: darkSurfaceContainerHigh,
      outline: darkOutline,
      outlineVariant: const Color(0xFF44474E),
      shadow: Colors.black,
      scrim: Colors.black,
    );

    return _buildTheme(colorScheme, darkBackground);
  }

  static ThemeData get amoledTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: kotatsuBlueDark,
      onPrimary: const Color(0xFF002F65),
      primaryContainer: kotatsuPrimaryContainerDark,
      onPrimaryContainer: const Color(0xFFD7E3FF),
      secondary: const Color(0xFFBEC6DC),
      onSecondary: const Color(0xFF283041),
      secondaryContainer: const Color(0xFF3E4759),
      onSecondaryContainer: const Color(0xFFDAE2F9),
      tertiary: const Color(0xFFDDBCE0),
      onTertiary: const Color(0xFF3F2844),
      tertiaryContainer: const Color(0xFF573E5C),
      onTertiaryContainer: const Color(0xFFFAD8FD),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      surface: amoledSurface,
      onSurface: darkOnSurface,
      surfaceContainer: amoledSurfaceContainer,
      surfaceContainerHigh: const Color(0xFF1C1D21),
      outline: darkOutline,
      outlineVariant: const Color(0xFF44474E),
      shadow: Colors.black,
      scrim: Colors.black,
    );

    return _buildTheme(colorScheme, amoledBackground);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme, Color scaffoldBg) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      fontFamily: GoogleFonts.inter().fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          fontFamily: GoogleFonts.inter().fontFamily,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide.none,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 3,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onPrimaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurface.withValues(alpha: 0.7));
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
