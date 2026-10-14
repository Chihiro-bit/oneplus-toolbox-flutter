import 'package:flutter/material.dart';

/// 与 TS 版 styles.css 中的颜色变量一一对应
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.sidebar,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
  });

  final Color bg;
  final Color sidebar;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color accentSoft;
  final Color ok;
  final Color okSoft;
  final Color warn;
  final Color warnSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  static const light = Palette(
    bg: Color(0xFFF4F5F7),
    sidebar: Color(0xFFECEEF1),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF6F7F9),
    border: Color(0xFFE3E5E9),
    text: Color(0xFF1B1D22),
    muted: Color(0xFF6B7079),
    accent: Color(0xFFE5173F),
    accentSoft: Color(0xFFFDE8EC),
    ok: Color(0xFF16A34A),
    okSoft: Color(0xFFE7F6EC),
    warn: Color(0xFFC27803),
    warnSoft: Color(0xFFFDF4E3),
    danger: Color(0xFFD92D20),
    dangerSoft: Color(0xFFFDECEB),
    info: Color(0xFF2563EB),
    infoSoft: Color(0xFFE8EFFD),
  );

  static const dark = Palette(
    bg: Color(0xFF16171B),
    sidebar: Color(0xFF111215),
    surface: Color(0xFF1E2025),
    surface2: Color(0xFF25272D),
    border: Color(0xFF2E3138),
    text: Color(0xFFE8E9EC),
    muted: Color(0xFF9298A3),
    accent: Color(0xFFFF3B5C),
    accentSoft: Color(0xFF3A1D24),
    ok: Color(0xFF4ADE80),
    okSoft: Color(0xFF173123),
    warn: Color(0xFFF5B546),
    warnSoft: Color(0xFF382C16),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0xFF3A1C1C),
    info: Color(0xFF7AA2FF),
    infoSoft: Color(0xFF1C2640),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) => t < 0.5 || other is! Palette ? this : other;
}

extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

const _fontFallback = ['Segoe UI Variable Text', 'Segoe UI', 'Microsoft YaHei UI', 'PingFang SC'];

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: brightness,
    primary: c.accent,
    onPrimary: Colors.white,
    surface: c.surface,
    onSurface: c.text,
    error: c.danger,
    outline: c.border,
    outlineVariant: c.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Microsoft YaHei UI',
    fontFamilyFallback: _fontFallback,
    dividerColor: c.border,
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    extensions: [c],
  );
  final text = base.textTheme.apply(bodyColor: c.text, displayColor: c.text);
  final btnShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  const btnPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 12);
  const btnText = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);
  return base.copyWith(
    textTheme: text.copyWith(bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.55)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: btnShape, padding: btnPadding, textStyle: btnText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: btnShape,
        padding: btnPadding,
        textStyle: btnText,
        foregroundColor: c.text,
        backgroundColor: c.surface2,
        side: BorderSide(color: c.border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: btnShape, padding: btnPadding, textStyle: btnText, foregroundColor: c.text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: c.muted, fontSize: 13.5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.accent)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.danger)),
      focusedErrorBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.danger)),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: c.muted, width: 1.5),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      textStyle: TextStyle(fontSize: 12, color: c.bg),
      decoration: BoxDecoration(color: c.text, borderRadius: BorderRadius.circular(6)),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.muted.withOpacity(0.4)),
      radius: const Radius.circular(4),
    ),
  );
}
