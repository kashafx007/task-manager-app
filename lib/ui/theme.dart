/// Cute teddy-bear themes.
///
/// * Light: cream + cocoa brown + peach (inspired by a beige gingham home screen).
/// * Dark: chocolate brown + soft caramel + peach.
library;

import 'package:flutter/material.dart';

/// All colours used by the custom widgets. Look them up with
/// `AppColors.of(context)` so they follow the current light/dark theme.
class AppColors {
  const AppColors({
    required this.bg,
    required this.stripeA,
    required this.stripeB,
    required this.card,
    required this.cardAlt,
    required this.text,
    required this.subtext,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.border,
    required this.danger,
    required this.shadow,
  });

  final Color bg;
  final Color stripeA; // gingham: vertical stripes
  final Color stripeB; // gingham: horizontal stripes
  final Color card;
  final Color cardAlt;
  final Color text;
  final Color subtext;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color border;
  final Color danger;
  final Color shadow;

  static const AppColors light = AppColors(
    bg: Color(0xFFFBF5EA),
    stripeA: Color(0x55C9A98A),
    stripeB: Color(0x55C9A98A),
    card: Color(0xFFFFFCF6),
    cardAlt: Color(0xFFF1E4D0),
    text: Color(0xFF5B4034),
    subtext: Color(0xFF9A8271),
    primary: Color(0xFF9C6F55),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFF3C9A8),
    border: Color(0xFFE8D6BE),
    danger: Color(0xFFCF5A54),
    shadow: Color(0x1F5B4034),
  );

  static const AppColors dark = AppColors(
    bg: Color(0xFF2B211D),
    stripeA: Color(0x1FC9A98A),
    stripeB: Color(0x1FC9A98A),
    card: Color(0xFF3A2D27),
    cardAlt: Color(0xFF4A3A32),
    text: Color(0xFFF5E8D6),
    subtext: Color(0xFFBBA593),
    primary: Color(0xFFD4A584),
    onPrimary: Color(0xFF2B211D),
    accent: Color(0xFFF3C9A8),
    border: Color(0xFF5A483E),
    danger: Color(0xFFFF8A80),
    shadow: Color(0x66000000),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Pastel colour for each task category.
Color categoryColor(String category, {required bool dark}) {
  const base = <String, Color>{
    'Personal': Color(0xFFF5C2C7),
    'Study': Color(0xFFBFD7EA),
    'Work': Color(0xFFD9C8EE),
    'Health': Color(0xFFF6C9A8),
    'Shopping': Color(0xFFC8E3C4),
    'Other': Color(0xFFF3E2A0),
  };
  final color = base[category] ?? const Color(0xFFE6E0D0);
  return dark ? color.withAlpha(95) : color;
}

class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
    final scheme = ColorScheme.fromSeed(seedColor: c.primary, brightness: brightness).copyWith(
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.accent,
      error: c.danger,
      surface: c.card,
      onSurface: c.text,
    );
    final base = ThemeData(brightness: brightness);

    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: color, width: width),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: c.text,
        iconTheme: IconThemeData(color: c.text),
        titleTextStyle: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w800),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        hintStyle: TextStyle(color: c.subtext),
        labelStyle: TextStyle(color: c.subtext),
        border: border(c.border),
        enabledBorder: border(c.border),
        focusedBorder: border(c.primary, 2),
        errorBorder: border(c.danger),
        focusedErrorBorder: border(c.danger, 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          side: BorderSide(color: c.border, width: 1.5),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.primary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.text,
        contentTextStyle: TextStyle(color: c.bg),
        actionTextColor: c.accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.card,
        indicatorColor: c.primary.withAlpha(60),
        labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? c.text : c.subtext,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? c.primary : c.subtext,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? c.onPrimary : c.subtext,
        ),
        trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? c.primary : c.cardAlt,
        ),
      ),
      dividerColor: c.border,
    );
  }
}
