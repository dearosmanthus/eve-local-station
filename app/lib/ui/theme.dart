import 'package:flutter/material.dart';

abstract final class StationColors {
  static const background = Color(0xFF0D1117);
  static const panel = Color(0xFF151B23);
  static const elevated = Color(0xFF1D2630);
  static const border = Color(0xFF303A46);
  static const cyan = Color(0xFF84BEB8);
  static const muted = Color(0xFFA1ADBA);
  static const amber = Color(0xFFFFC26F);
  static const red = Color(0xFFEF7888);
}

ThemeData stationTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: StationColors.cyan,
    brightness: Brightness.dark,
    surface: StationColors.panel,
    primary: StationColors.cyan,
    secondary: StationColors.amber,
    error: StationColors.red,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: StationColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: StationColors.background,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: StationColors.panel,
      indicatorColor: StationColors.cyan.withValues(alpha: 0.14),
      height: 56,
      labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 11)),
    ),
    dividerTheme: const DividerThemeData(color: StationColors.border, space: 1),
    cardTheme: CardThemeData(
      color: StationColors.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: StationColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: StationColors.background,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: StationColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: StationColors.border),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: const BorderSide(color: StationColors.border),
      ),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(fontSize: 13, height: 1.3),
      bodySmall: TextStyle(
        fontSize: 11,
        color: StationColors.muted,
        height: 1.3,
      ),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {this.trailing, super.key});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Container(width: 3, height: 14, color: StationColors.cyan),
            const SizedBox(width: 9),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

void notice(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}
