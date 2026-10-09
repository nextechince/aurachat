import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Core Brand Colors (Telegram — muted, matte) ───
  static const Color primaryColor = Color(0xFF3390EC);       // Telegram blue
  static const Color primaryDark = Color(0xFF2B7CD3);        // pressed
  static const Color primaryDarker = Color(0xFF1E5FA8);      // deep pressed
  static const Color accentColor = Color(0xFF3390EC);        // same as primary — Telegram doesn't use a second accent
  static const Color primaryGreen = Color(0xFF4FAE4F);       // muted green (status only)
  static const Color primaryGreenDark = Color(0xFF3D8B3D);

  // ─── Secondary Colors (muted — no neon) ───
  static const Color accentCyan = Color(0xFF5FB4D9);         // muted, not neon
  static const Color accentPink = Color(0xFFE07A9A);         // muted rose
  static const Color accentPurple = Color(0xFF8B7BB8);       // muted purple
  static const Color accentOrange = Color(0xFFE0954A);       // muted orange
  static const Color accentBlue = Color(0xFF3390EC);

  // ─── Background Colors — Dark (Telegram Night) ───
  static const Color bgPrimary = Color(0xFF212121);          // main bg
  static const Color bgSecondary = Color(0xFF1F1F1F);        // app bar
  static const Color bgTertiary = Color(0xFF2B2B2B);         // elevated surfaces
  static const Color bgElevated = Color(0xFF2B2B2B);
  static const Color bgCard = Color(0xFF1F1F1F);
  static const Color bgInput = Color(0xFF2A2A2A);
  static const Color bgModal = Color(0xFF1F1F1F);
  static const Color darkChatBg = Color(0xFF0E1621);         // chat wallpaper

  // ─── Background Colors — Light (Telegram Day) ───
  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightChatBg = Color(0xFFE7EBF0);
  static const Color lightInput = Color(0xFFF1F1F1);
  static const Color lightDivider = Color(0xFFE4E4E5);

  // ─── Text — Dark theme ───
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAAAAAA);      // Telegram's exact dark sub-text
  static const Color textTertiary = Color(0xFF707579);
  static const Color textMuted = Color(0xFF5A5A5A);

  // ─── Text — Light theme ───
  static const Color textLight = Color(0xFF000000);
  static const Color textLightSecondary = Color(0xFF707579);

  // ─── Status Colors (muted) ───
  static const Color online = Color(0xFF4FAE4F);
  static const Color away = Color(0xFFE0954A);
  static const Color offline = Color(0xFF707579);
  static const Color typing = Color(0xFF3390EC);

  // ─── Message Bubbles — Dark (Telegram Night exact) ───
  static const Color sentMessage = Color(0xFF2B5278);        // muted dark blue
  static const Color sentMessageLight = Color(0xFF2B5278);
  static const Color receivedMessage = Color(0xFF182533);    // muted dark navy
  static const Color receivedMessageLight = Color(0xFF182533);

  // ─── Message Bubbles — Light (Telegram Day exact) ───
  static const Color lightSentBubble = Color(0xFFEEFFDE);    // pale green
  static const Color lightRecvBubble = Color(0xFFFFFFFF);    // white

  // ─── Semantic (muted, not neon) ───
  static const Color error = Color(0xFFE53935);
  static const Color success = Color(0xFF4FAE4F);
  static const Color warning = Color(0xFFE0954A);
  static const Color info = Color(0xFF3390EC);

  // ─── Badges ───
  static const Color verifiedBlue = Color(0xFF3390EC);
  static const Color verifiedGold = Color(0xFFD4A73A);

  // ─── Moderation ───
  static const Color restricted = Color(0xFFE53935);
  static const Color suspicious = Color(0xFFE0954A);
  static const Color safe = Color(0xFF4FAE4F);

  // ─── Dividers ───
  static const Color divider = Color(0xFF2F2F2F);
  static const Color dividerLight = Color(0xFFE4E4E5);

  // ─── Shadows — REMOVED / MINIMAL for flat look ───
  // Telegram basically has no shadows. These return empty lists so
  // any code calling `AppTheme.cardShadow` still compiles but does nothing.
  static List<BoxShadow> get cardShadow => const [];
  static List<BoxShadow> get elevatedShadow => const [];
}

// ============================================================================
// GRADIENTS — flattened to solid-ish (kept API-compatible)
// ============================================================================
class AppGradients {
  // Was green→cyan. Now just Telegram blue → slightly lighter blue.
  static const LinearGradient primary = LinearGradient(
    colors: [AppTheme.primaryColor, AppTheme.primaryColor],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Was pink→purple. Now flat muted blue.
  static const LinearGradient accent = LinearGradient(
    colors: [AppTheme.primaryColor, AppTheme.primaryColor],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dark bg gradient — unchanged, it's already flat
  static const LinearGradient dark = LinearGradient(
    colors: [AppTheme.bgSecondary, AppTheme.bgPrimary],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Glass — flat, no opacity trickery
  static final LinearGradient glass = LinearGradient(
    colors: [AppTheme.bgTertiary, AppTheme.bgSecondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ============================================================================
// ANIMATIONS — unchanged
// ============================================================================
class AppAnimations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Curve curve = Curves.easeInOutCubic;
  static const Curve bounce = Curves.elasticOut;
}

// ============================================================================
// THEMES — Flat, matte, Telegram
// ============================================================================
extension LumaThemeData on AppTheme {
  // ─── LIGHT ───
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: AppTheme.primaryColor,
      scaffoldBackgroundColor: AppTheme.lightBg,
      dividerColor: AppTheme.lightDivider,

      colorScheme: const ColorScheme.light(
        primary: AppTheme.primaryColor,
        onPrimary: Colors.white,
        secondary: AppTheme.primaryColor,
        onSecondary: Colors.white,
        surface: AppTheme.lightSurface,
        onSurface: AppTheme.textLight,
        background: AppTheme.lightBg,
        onBackground: AppTheme.textLight,
        error: AppTheme.error,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: AppTheme.lightSurface,
        foregroundColor: AppTheme.textLight,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppTheme.textLight),
        titleTextStyle: GoogleFonts.roboto(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppTheme.textLight,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppTheme.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      textTheme: GoogleFonts.robotoTextTheme().copyWith(
        headlineLarge: GoogleFonts.roboto(
          fontSize: 32, fontWeight: FontWeight.w600, color: AppTheme.textLight),
        headlineMedium: GoogleFonts.roboto(
          fontSize: 24, fontWeight: FontWeight.w600, color: AppTheme.textLight),
        titleLarge: GoogleFonts.roboto(
          fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.textLight),
        titleMedium: GoogleFonts.roboto(
          fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textLight),
        bodyLarge: GoogleFonts.roboto(
          fontSize: 16, color: AppTheme.textLight),
        bodyMedium: GoogleFonts.roboto(
          fontSize: 14, color: AppTheme.textLightSecondary),
        bodySmall: GoogleFonts.roboto(
          fontSize: 12, color: AppTheme.textLightSecondary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppTheme.lightInput,
        hintStyle: const TextStyle(color: Color(0xFF999999)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,                          // ← no shadow
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.primaryColor,
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,                            // ← flat
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),

      dividerTheme: const DividerThemeData(
        color: AppTheme.lightDivider,
        thickness: 0.5,
        space: 0.5,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppTheme.lightSurface,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.textLightSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF303030),
        contentTextStyle: TextStyle(color: Colors.white),
        elevation: 0,
      ),
    );
  }

  // ─── DARK ───
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: AppTheme.primaryColor,
      scaffoldBackgroundColor: AppTheme.bgPrimary,
      dividerColor: AppTheme.divider,

      colorScheme: const ColorScheme.dark(
        primary: AppTheme.primaryColor,
        onPrimary: Colors.white,
        secondary: AppTheme.primaryColor,
        onSecondary: Colors.white,
        surface: AppTheme.bgSecondary,
        onSurface: AppTheme.textPrimary,
        background: AppTheme.bgPrimary,
        onBackground: AppTheme.textPrimary,
        error: AppTheme.error,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: AppTheme.bgSecondary,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        titleTextStyle: GoogleFonts.roboto(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppTheme.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      textTheme: GoogleFonts.robotoTextTheme(ThemeData.dark().textTheme).copyWith(
        headlineLarge: GoogleFonts.roboto(
          fontSize: 32, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        headlineMedium: GoogleFonts.roboto(
          fontSize: 24, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        titleLarge: GoogleFonts.roboto(
          fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        titleMedium: GoogleFonts.roboto(
          fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
        bodyLarge: GoogleFonts.roboto(
          fontSize: 16, color: AppTheme.textPrimary),
        bodyMedium: GoogleFonts.roboto(
          fontSize: 14, color: AppTheme.textSecondary),
        bodySmall: GoogleFonts.roboto(
          fontSize: 12, color: AppTheme.textSecondary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppTheme.bgInput,
        hintStyle: const TextStyle(color: Color(0xFF707579)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.primaryColor,
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),

      dividerTheme: const DividerThemeData(
        color: AppTheme.divider,
        thickness: 0.5,
        space: 0.5,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppTheme.bgSecondary,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF2F2F2F),
        contentTextStyle: TextStyle(color: Colors.white),
        elevation: 0,
      ),
    );
  }
}
