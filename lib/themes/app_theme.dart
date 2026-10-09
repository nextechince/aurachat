import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Core Brand Colors (Telegram — muted, matte) ───
  static const Color primaryColor = Color(0xFF3390EC);
  static const Color primaryDark = Color(0xFF2B7CD3);
  static const Color primaryDarker = Color(0xFF1E5FA8);
  static const Color accentColor = Color(0xFF3390EC);
  static const Color primaryGreen = Color(0xFF4FAE4F);
  static const Color primaryGreenDark = Color(0xFF3D8B3D);

  // ─── Secondary Colors (muted — no neon) ───
  static const Color accentCyan = Color(0xFF5FB4D9);
  static const Color accentPink = Color(0xFFE07A9A);
  static const Color accentPurple = Color(0xFF8B7BB8);
  static const Color accentOrange = Color(0xFFE0954A);
  static const Color accentBlue = Color(0xFF3390EC);

  // ─── Background Colors — Dark ───
  static const Color bgPrimary = Color(0xFF212121);
  static const Color bgSecondary = Color(0xFF1F1F1F);
  static const Color bgTertiary = Color(0xFF2B2B2B);
  static const Color bgElevated = Color(0xFF2B2B2B);
  static const Color bgCard = Color(0xFF1F1F1F);
  static const Color bgInput = Color(0xFF2A2A2A);
  static const Color bgModal = Color(0xFF1F1F1F);
  static const Color darkChatBg = Color(0xFF0E1621);

  // ─── Background Colors — Light ───
  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightChatBg = Color(0xFFE7EBF0);
  static const Color lightInput = Color(0xFFF1F1F1);
  static const Color lightDivider = Color(0xFFE4E4E5);

  // ─── Text — Dark theme ───
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color textTertiary = Color(0xFF707579);
  static const Color textMuted = Color(0xFF5A5A5A);

  // ─── Text — Light theme ───
  static const Color textLight = Color(0xFF000000);
  static const Color textLightSecondary = Color(0xFF707579);

  // ─── Status Colors ───
  static const Color online = Color(0xFF4FAE4F);
  static const Color away = Color(0xFFE0954A);
  static const Color offline = Color(0xFF707579);
  static const Color typing = Color(0xFF3390EC);

  // ─── Message Bubbles — Dark ───
  static const Color sentMessage = Color(0xFF2B5278);
  static const Color sentMessageLight = Color(0xFF2B5278);
  static const Color receivedMessage = Color(0xFF182533);
  static const Color receivedMessageLight = Color(0xFF182533);

  // ─── Message Bubbles — Light ───
  static const Color lightSentBubble = Color(0xFFEEFFDE);
  static const Color lightRecvBubble = Color(0xFFFFFFFF);

  // ─── Semantic ───
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

  // ─── Shadows — flat (API kept for compatibility) ───
  static List<BoxShadow> get cardShadow => const [];
  static List<BoxShadow> get elevatedShadow => const [];

  // ══════════════════════════════════════════════════════════════════════════
  // LIGHT THEME — Telegram Day
  // ══════════════════════════════════════════════════════════════════════════
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: lightBg,
      dividerColor: lightDivider,

      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        onPrimary: Colors.white,
        secondary: primaryColor,
        onSecondary: Colors.white,
        surface: lightSurface,
        onSurface: textLight,
        background: lightBg,
        onBackground: textLight,
        error: error,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: lightSurface,
        foregroundColor: textLight,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        iconTheme: const IconThemeData(color: textLight),
        titleTextStyle: GoogleFonts.roboto(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textLight,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),

      cardTheme: CardTheme(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      textTheme: GoogleFonts.robotoTextTheme().copyWith(
        headlineLarge: GoogleFonts.roboto(
          fontSize: 32, fontWeight: FontWeight.w600, color: textLight),
        headlineMedium: GoogleFonts.roboto(
          fontSize: 24, fontWeight: FontWeight.w600, color: textLight),
        titleLarge: GoogleFonts.roboto(
          fontSize: 20, fontWeight: FontWeight.w600, color: textLight),
        titleMedium: GoogleFonts.roboto(
          fontSize: 16, fontWeight: FontWeight.w500, color: textLight),
        bodyLarge: GoogleFonts.roboto(
          fontSize: 16, color: textLight),
        bodyMedium: GoogleFonts.roboto(
          fontSize: 14, color: textLightSecondary),
        bodySmall: GoogleFonts.roboto(
          fontSize: 12, color: textLightSecondary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightInput,
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
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
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
          foregroundColor: primaryColor,
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),

      dividerTheme: const DividerThemeData(
        color: lightDivider,
        thickness: 0.5,
        space: 0.5,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightSurface,
        selectedItemColor: primaryColor,
        unselectedItemColor: textLightSecondary,
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

  // ══════════════════════════════════════════════════════════════════════════
  // DARK THEME — Telegram Night
  // ══════════════════════════════════════════════════════════════════════════
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: bgPrimary,
      dividerColor: divider,

      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        onPrimary: Colors.white,
        secondary: primaryColor,
        onSecondary: Colors.white,
        surface: bgSecondary,
        onSurface: textPrimary,
        background: bgPrimary,
        onBackground: textPrimary,
        error: error,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: bgSecondary,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        iconTheme: const IconThemeData(color: textPrimary),
        titleTextStyle: GoogleFonts.roboto(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),

      cardTheme: CardTheme(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),

      textTheme: GoogleFonts.robotoTextTheme(ThemeData.dark().textTheme).copyWith(
        headlineLarge: GoogleFonts.roboto(
          fontSize: 32, fontWeight: FontWeight.w600, color: textPrimary),
        headlineMedium: GoogleFonts.roboto(
          fontSize: 24, fontWeight: FontWeight.w600, color: textPrimary),
        titleLarge: GoogleFonts.roboto(
          fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
        titleMedium: GoogleFonts.roboto(
          fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary),
        bodyLarge: GoogleFonts.roboto(
          fontSize: 16, color: textPrimary),
        bodyMedium: GoogleFonts.roboto(
          fontSize: 14, color: textSecondary),
        bodySmall: GoogleFonts.roboto(
          fontSize: 12, color: textSecondary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgInput,
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
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
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
          foregroundColor: primaryColor,
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),

      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 0.5,
        space: 0.5,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bgSecondary,
        selectedItemColor: primaryColor,
        unselectedItemColor: textSecondary,
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

// ============================================================================
// GRADIENTS — flat (kept API-compatible)
// ============================================================================
class AppGradients {
  static const LinearGradient primary = LinearGradient(
    colors: [AppTheme.primaryColor, AppTheme.primaryColor],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accent = LinearGradient(
    colors: [AppTheme.primaryColor, AppTheme.primaryColor],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dark = LinearGradient(
    colors: [AppTheme.bgSecondary, AppTheme.bgPrimary],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static final LinearGradient glass = LinearGradient(
    colors: [AppTheme.bgTertiary, AppTheme.bgSecondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ============================================================================
// ANIMATIONS
// ============================================================================
class AppAnimations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Curve curve = Curves.easeInOutCubic;
  static const Curve bounce = Curves.elasticOut;
}
