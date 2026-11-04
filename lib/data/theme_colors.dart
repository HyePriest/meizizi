import 'package:flutter/material.dart';

Color _readable(Color background) =>
    background.computeLuminance() > .179 ? Colors.black : Colors.white;

Color? _cachedSeed;
Brightness? _cachedBrightness;
ColorScheme? _cachedScheme;

ColorScheme _seedScheme(Color seed, Brightness brightness) {
  if (_cachedSeed != seed || _cachedBrightness != brightness) {
    _cachedSeed = seed;
    _cachedBrightness = brightness;
    _cachedScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
  }
  return _cachedScheme!;
}

ThemeData appTheme(
  Color seed,
  Brightness brightness, {
  Color? background,
  Color? button,
}) {
  final dark = brightness == Brightness.dark;
  final chosen = HSLColor.fromColor(seed);
  Color tone(double lightness, [double saturation = .18]) => chosen
      .withSaturation(chosen.saturation * saturation)
      .withLightness(lightness)
      .toColor();
  final surface = background ?? tone(dark ? .10 : .975);
  Color layer(double strength) => background == null
      ? tone(dark ? .10 + strength : .975 - strength)
      : Color.alphaBlend(
          (dark ? Colors.white : Colors.black).withValues(alpha: strength),
          surface,
        );
  final accent = seed;
  final buttonFill = button ?? seed;
  final buttonText = _readable(buttonFill);
  final container = Color.alphaBlend(
    seed.withValues(alpha: dark ? .24 : .15),
    surface,
  );
  final scheme = _seedScheme(seed, brightness).copyWith(
    primary: accent,
    onPrimary: _readable(accent),
    primaryContainer: container,
    onPrimaryContainer: _readable(container),
    surface: surface,
    onSurface: _readable(surface),
    onSurfaceVariant: _readable(surface),
    surfaceContainerLowest: surface,
    surfaceContainerLow: layer(.025),
    surfaceContainer: layer(.04),
    surfaceContainerHigh: layer(.06),
    surfaceContainerHighest: layer(.08),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: buttonFill,
        foregroundColor: buttonText,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonFill,
        foregroundColor: buttonText,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: buttonFill,
      foregroundColor: buttonText,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color.alphaBlend(
        accent.withValues(alpha: dark ? .16 : .07),
        scheme.surfaceContainerHigh,
      ),
      contentTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: accent,
      actionBackgroundColor: accent.withValues(alpha: .1),
      elevation: 3,
      insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: .35)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: .4)),
      ),
      textStyle: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: _readable(surface),
      actionsIconTheme: IconThemeData(color: accent),
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: accent,
      selectedColor: accent,
      selectedTileColor: container,
    ),
    inputDecorationTheme: InputDecorationTheme(
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: accent, width: 2),
      ),
      floatingLabelStyle: TextStyle(color: accent),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: .22),
      selectionHandleColor: accent,
    ),
    chipTheme: ChipThemeData(
      selectedColor: container,
      checkmarkColor: accent,
      secondaryLabelStyle: TextStyle(color: accent),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: .25)),
      ),
      textStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: accent.withValues(alpha: .2)),
      ),
    ),
    useMaterial3: true,
  );
}

Color homeSeparatorColor(ThemeData theme) {
  if (theme.scaffoldBackgroundColor.computeLuminance() <= .179) {
    return Color.alphaBlend(
      Colors.white.withValues(alpha: .10),
      theme.scaffoldBackgroundColor,
    );
  }
  final surface = HSLColor.fromColor(theme.scaffoldBackgroundColor);
  return surface
      .withSaturation(surface.saturation * .4)
      .withLightness((surface.lightness - .045).clamp(0.0, 1.0))
      .toColor();
}
