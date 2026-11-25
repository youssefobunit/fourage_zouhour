part of 'main.dart';

bool _usesWorkspaceRail(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return Platform.isWindows && size.width >= 900 && size.height >= 530;
}

ThemeData atelierTheme({String? fontFamily}) {
  const scheme = ColorScheme.light(
    primary: AppPalette.primary,
    onPrimary: AppPalette.background,
    secondary: AppPalette.secondary,
    onSecondary: AppPalette.background,
    primaryContainer: AppPalette.desktopAccentSoft,
    onPrimaryContainer: AppPalette.primary,
    secondaryContainer: AppPalette.desktopAccentSoft,
    onSecondaryContainer: AppPalette.primary,
    surface: AppPalette.surface,
    surfaceContainerHigh: AppPalette.surfaceRaised,
    onSurface: AppPalette.text,
    onSurfaceVariant: AppPalette.muted,
    outline: AppPalette.line,
    error: AppPalette.coral,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: fontFamily,
  );
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: AppPalette.line),
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppPalette.background,
    dividerColor: AppPalette.line,
    textTheme: base.textTheme.apply(
      bodyColor: AppPalette.text,
      displayColor: AppPalette.text,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xE8E8F8FF),
      labelStyle: const TextStyle(color: AppPalette.muted),
      hintStyle: const TextStyle(color: AppPalette.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(color: AppPalette.primary, width: 1.6),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: AppPalette.text,
        selectedForegroundColor: AppPalette.text,
        backgroundColor: AppPalette.surface.withValues(alpha: .72),
        selectedBackgroundColor: AppPalette.primary.withValues(alpha: .24),
        side: BorderSide(color: AppPalette.line.withValues(alpha: .92)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppPalette.surface),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppPalette.line),
          ),
        ),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: AppPalette.line),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(26)),
        side: BorderSide(color: AppPalette.line),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppPalette.surfaceRaised,
      contentTextStyle: TextStyle(color: AppPalette.text),
      behavior: SnackBarBehavior.floating,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        foregroundColor: AppPalette.primaryDark,
        minimumSize: const Size(0, 48),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ).copyWith(backgroundBuilder: _primaryLiquidButton),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppPalette.primaryDark,
        minimumSize: const Size(0, 44),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ).copyWith(backgroundBuilder: _secondaryLiquidButton),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppPalette.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ).copyWith(backgroundBuilder: _secondaryLiquidButton),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppPalette.primaryDark,
        backgroundColor: Colors.transparent,
      )
          .copyWith(backgroundBuilder: _iconLiquidButton),
    ),
  );
}

/// The night presentation is a real Material theme, not only a backdrop.
/// This keeps dialogs, exports, pickers and form controls in the same violet
/// material as the dashboard instead of falling back to the light theme.
ThemeData atelierDarkTheme({String? fontFamily}) {
  const canvas = Color(0xFF110019);
  const surface = Color(0xFF21052F);
  const raised = Color(0xFF351047);
  const text = Color(0xFFFFF3FF);
  const muted = Color(0xFFE3C5ED);
  const violet = Color(0xFFE36AFF);
  const line = Color(0xFFA650C5);
  const scheme = ColorScheme.dark(
    primary: violet,
    onPrimary: Color(0xFF260033),
    secondary: Color(0xFFFFB8ED),
    onSecondary: Color(0xFF260033),
    primaryContainer: Color(0xFF59216E),
    onPrimaryContainer: text,
    secondaryContainer: Color(0xFF4A175D),
    onSecondaryContainer: text,
    surface: surface,
    surfaceContainerHigh: raised,
    onSurface: text,
    onSurfaceVariant: muted,
    outline: line,
    error: Color(0xFFFF99A8),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: fontFamily,
  );
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: line),
  );
  return base.copyWith(
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
    dividerColor: line.withValues(alpha: .55),
    textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
    iconTheme: const IconThemeData(color: muted),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xC9280A39),
      labelStyle: const TextStyle(color: muted),
      hintStyle: const TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: const BorderSide(color: violet, width: 1.6),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF210022),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: base.textTheme.headlineSmall?.copyWith(
        color: text,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(color: muted),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(26)),
        side: BorderSide(color: line.withValues(alpha: .85)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF210022),
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF210022),
      surfaceTintColor: Colors.transparent,
      textStyle: const TextStyle(color: text),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: line),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Color(0xFF210022)),
        elevation: WidgetStatePropertyAll(8),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? violet
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Color(0xFF260033)),
      side: const BorderSide(color: muted, width: 1.5),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: muted,
        selectedForegroundColor: text,
        backgroundColor: surface,
        selectedBackgroundColor: const Color(0xFF652580),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: raised,
      contentTextStyle: TextStyle(color: text),
      behavior: SnackBarBehavior.floating,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        foregroundColor: text,
        minimumSize: const Size(0, 48),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ).copyWith(backgroundBuilder: _primaryLiquidButton),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        minimumSize: const Size(0, 44),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ).copyWith(backgroundBuilder: _secondaryLiquidButton),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: violet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ).copyWith(backgroundBuilder: _secondaryLiquidButton),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: text,
        backgroundColor: Colors.transparent,
      ).copyWith(backgroundBuilder: _iconLiquidButton),
    ),
  );
}

/// A shared select field used in every form.  The stock Material dropdown
/// differs by platform and was visually out of place in the liquid UI, so the
/// picker is rendered as a consistent blue-glass list instead.
class LiquidSelectFormField<T> extends FormField<T> {
  LiquidSelectFormField({
    super.key,
    super.initialValue,
    required this.items,
    required this.decoration,
    required this.onChanged,
    this.isExpanded = false,
    super.validator,
    super.autovalidateMode,
  }) : super(
         builder: (field) => _LiquidSelectField<T>(
           field: field,
           items: items,
           decoration: decoration,
           onChanged: onChanged,
           isExpanded: isExpanded,
         ),
       );

  final List<DropdownMenuItem<T>> items;
  final InputDecoration decoration;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
}

class _LiquidSelectField<T> extends StatelessWidget {
  const _LiquidSelectField({
    required this.field,
    required this.items,
    required this.decoration,
    required this.onChanged,
    required this.isExpanded,
  });

  final FormFieldState<T> field;
  final List<DropdownMenuItem<T>> items;
  final InputDecoration decoration;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final selected = items.where((item) => item.value == field.value).firstOrNull;
    final enabled = onChanged != null;
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : .56,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: !enabled
            ? null
            : () async {
                final selectedItem = await _showLiquidSelectMenu<T>(
                  context,
                  items: items,
                  selected: field.value,
                );
                // The item itself is returned (rather than only its value),
                // so a legitimate "Toutes les catégories" null value can be
                // selected without being confused with cancelling the dialog.
                if (selectedItem == null || !context.mounted) return;
                field.didChange(selectedItem.value);
                onChanged!(selectedItem.value);
              },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 145;
            return InputDecorator(
              isEmpty: false,
              decoration: decoration.copyWith(
                errorText: field.errorText,
                enabled: enabled,
                isDense: compact ? true : decoration.isDense,
                prefixIcon: decoration.prefixIcon ??
                    (compact ? null : Icon(Icons.sell_outlined, color: scheme.primary)),
                suffixIcon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: scheme.primary,
                ),
                suffixIconConstraints: compact
                    ? const BoxConstraints(minWidth: 30)
                    : null,
              ),
              child: selected == null
                  ? const Text('Sélectionner…')
                  : DefaultTextStyle.merge(
                      maxLines: isExpanded ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      child: selected.child,
                    ),
            );
          },
        ),
      ),
    );
  }
}

Future<DropdownMenuItem<T>?> _showLiquidSelectMenu<T>(
  BuildContext context, {
  required List<DropdownMenuItem<T>> items,
  required T? selected,
}) {
  final scheme = Theme.of(context).colorScheme;
  final fieldBox = context.findRenderObject() as RenderBox;
  final overlay = Navigator.of(context).overlay!;
  final overlayBox = overlay.context.findRenderObject() as RenderBox;
  final origin = fieldBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  final fieldRect = origin & fieldBox.size;
  final screen = Offset.zero & overlayBox.size;

  return showMenu<DropdownMenuItem<T>>(
    context: context,
    color: scheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    constraints: BoxConstraints(
      minWidth: fieldBox.size.width,
      maxWidth: max(fieldBox.size.width, 420.0),
      maxHeight: min(390.0, overlayBox.size.height * .60),
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: scheme.outline.withValues(alpha: .90)),
    ),
    position: RelativeRect.fromRect(
      Rect.fromLTWH(fieldRect.left, fieldRect.bottom + 6, fieldRect.width, 1),
      screen,
    ),
    items: [
      for (final item in items)
        PopupMenuItem<DropdownMenuItem<T>>(
          value: item,
          enabled: item.enabled,
          height: 57,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Builder(
            builder: (context) {
              final isSelected = item.value == selected;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isSelected
                      ? scheme.primary.withValues(alpha: .20)
                      : scheme.surfaceContainerHigh.withValues(alpha: .48),
                  border: Border.all(
                    color: isSelected
                        ? scheme.primary.withValues(alpha: .58)
                        : scheme.outline.withValues(alpha: .34),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.sell_rounded
                          : Icons.inventory_2_outlined,
                      size: 19,
                      color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DefaultTextStyle.merge(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        child: item.child,
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_rounded, color: scheme.primary),
                  ],
                ),
              );
            },
          ),
        ),
    ],
  );
}

class _AtelierBackdrop extends CustomPainter {
  const _AtelierBackdrop({this.dark = false, this.reflection = false});

  final bool dark;
  final bool reflection;

  List<Color> _colors(List<Color> colors) => reflection
      ? colors.map((color) => color.withValues(alpha: color.a * .55)).toList()
      : colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _colors(
            dark
                ? const [Color(0xFF0B0011), Color(0xFF21002D), Color(0xFF08000D)]
                : const [Color(0xFFEAF7FF), Color(0xFFC6E6FF), Color(0xFF8CCBFF)],
          ),
          stops: [0, .53, 1],
        ).createShader(bounds),
    );
    canvas.save();
    canvas.scale(size.width, size.height);
    _orb(
      canvas,
      const Offset(.86, .045),
      const Size(1.06, .36),
      -.21,
      dark ? const Color(0xFFB841FF) : const Color(0xFF5DA9F5),
    );
    _orb(
      canvas,
      const Offset(1.08, .77),
      const Size(.73, .51),
      .46,
      dark ? const Color(0xFFE535D5) : const Color(0xFF65D7F0),
    );
    _orb(
      canvas,
      const Offset(.42, 1.07),
      const Size(1.50, .33),
      -.31,
      dark ? const Color(0xFF8A23FF) : const Color(0xFF7C96F8),
    );
    canvas.restore();
  }

  void _orb(
    Canvas canvas,
    Offset center,
    Size size,
    double angle,
    Color light,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final shape = Rect.fromCenter(
      center: Offset.zero,
      width: size.width,
      height: size.height,
    );
    if (!reflection) {
      canvas.drawOval(
        shape.inflate(.019),
        Paint()
          ..color = light.withValues(alpha: .20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .021),
      );
    }
    canvas.drawOval(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _colors([
            light.withValues(alpha: .71),
            if (dark) ...[
              const Color(0xFF2B0843),
              const Color(0xFF4F1172),
              const Color(0xFF160020),
            ] else ...[
              const Color(0xFF9CD4FF),
              const Color(0xFFCFEAFF),
              const Color(0xFFF0FAFF),
            ],
          ]),
          stops: const [0, .20, .57, 1],
        ).createShader(shape),
    );
    canvas.drawOval(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .003
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _colors([
            light,
            dark ? const Color(0xDDF8D5FF) : const Color(0xCCFFFFFF),
            light.withValues(alpha: .11),
            Colors.transparent,
          ]),
          stops: const [0, .23, .59, 1],
        ).createShader(shape),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AtelierBackdrop oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.reflection != reflection;
}

class _AtelierIcon extends StatelessWidget {
  const _AtelierIcon(
    this.icon, {
    this.color = AppPalette.primary,
    this.size = 42,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The historic primary is blue.  In the night scene the same semantic
    // primary becomes violet, so icons never look as though they belong to
    // the light interface.
    final accent = dark && (color == AppPalette.primary || color == AppPalette.secondary)
        ? Theme.of(context).colorScheme.primary
        : color;
    final base = dark ? const Color(0xFF260633) : AppPalette.surfaceRaised;
    final lower = dark ? const Color(0xFF190022) : AppPalette.surface;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(accent.withValues(alpha: .64), base),
            Color.alphaBlend(accent.withValues(alpha: .16), lower),
          ],
        ),
        border: Border.all(
          color: (dark ? Colors.white : accent).withValues(
            alpha: dark ? .34 : .42,
          ),
        ),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .25), blurRadius: 10),
        ],
      ),
      child: Icon(
        icon,
        size: size * .54,
        color: dark ? const Color(0xFFFFF2FF) : AppPalette.text,
      ),
    );
  }
}

class _AtelierBackButton extends StatelessWidget {
  const _AtelierBackButton({this.tooltip = 'Retour'});
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: () => Navigator.maybePop(context),
      icon: const Icon(Icons.arrow_back_rounded),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: scheme.primary,
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide(color: scheme.outline),
      ),
    );
  }
}

class _DashboardHeaderButton extends StatelessWidget {
  const _DashboardHeaderButton({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      child: _LiquidTapTarget(
        radius: 24,
        accent: AppPalette.lilac,
        onTap: onTap,
        child: SizedBox.square(dimension: 44, child: Center(child: child)),
      ),
    ),
  );
}

class _DashboardGlassIcon extends StatelessWidget {
  const _DashboardGlassIcon(this.icon, this.color, {this.size = 38});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final accent = dark && color == AppPalette.lilac ? scheme.primary : color;
    final colors = dark
        ? [
            Color.lerp(accent, Colors.white, .20)!,
            Color.lerp(accent, scheme.surfaceContainerHigh, .43)!,
            Color.lerp(accent, scheme.surface, .65)!,
            Color.alphaBlend(accent.withValues(alpha: .52), scheme.surface),
          ]
        : [
            Color.lerp(accent, Colors.white, .43)!,
            Color.lerp(accent, AppPalette.soft, .43)!,
            Color.lerp(accent, AppPalette.background, .65)!,
            accent,
          ];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .31),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .31),
            blurRadius: 13,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: accent.withValues(alpha: .45), width: .65),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: const [0, .30, .72, 1],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .29),
          gradient: RadialGradient(
            center: const Alignment(-.72, -.95),
            radius: .75,
            colors: [Colors.white.withValues(alpha: .34), Colors.transparent],
          ),
        ),
        child: Icon(
          icon,
          size: size * .56,
          color: scheme.onSurface,
          shadows: [
            Shadow(
              color: dark ? const Color(0x66170025) : const Color(0x55316FA6),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopDashboardWelcome extends StatelessWidget {
  const _DesktopDashboardWelcome({required this.firstName});

  final String firstName;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 132,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned(
          right: 10,
          top: -30,
          width: 340,
          height: 190,
          child: IgnorePointer(child: _DesktopWelcomeGear()),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'VUE D’ENSEMBLE',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 11,
                letterSpacing: 2.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  firstName.isEmpty ? 'Bonjour' : 'Bonjour, $firstName',
                  style: const TextStyle(
                    fontSize: 31,
                    letterSpacing: -1.15,
                    height: 1.04,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.waving_hand_rounded,
                  color: AppPalette.amber,
                  size: 27,
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              'Voici un aperçu de votre atelier aujourd’hui.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _AtelierOverview extends StatelessWidget {
  const _AtelierOverview({
    required this.firstName,
    required this.machineCount,
    this.desktop = false,
  });
  final String firstName;
  final int machineCount;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final accent = dark ? const Color(0xFFE46AFF) : AppPalette.primary;
    final foreground = dark ? const Color(0xFFFFF3FF) : AppPalette.text;
    final muted = dark ? const Color(0xFFE3C5ED) : AppPalette.muted;
    return Glass(
      key: const ValueKey('atelier-overview'),
      radius: 30,
      accent: accent,
      frosted: true,
      child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: desktop
                  ? const _MachineArmEmblem()
                  : const _WorkshopEmblem(),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: desktop ? 176 : 208),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 17, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (desktop)
                  const _DashboardGlassIcon(
                    Icons.precision_manufacturing_outlined,
                    AppPalette.lilac,
                    size: 43,
                  )
                else ...[
                  const Glass(
                    radius: 14,
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.space_dashboard_outlined, size: 12),
                        SizedBox(width: 6),
                        Text(
                          'VUE D’ENSEMBLE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    firstName.isEmpty ? 'Bonjour' : 'Bonjour, $firstName',
                    style: TextStyle(
                      fontSize: 27,
                      height: 1.08,
                      letterSpacing: -.8,
                      fontWeight: FontWeight.w800,
                      color: foreground,
                    ),
                  ),
                ],
                SizedBox(height: desktop ? 13 : 25),
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: dark
                        ? const [Color(0xFFF0B5FF), Color(0xFFB33EE1)]
                        : const [Color(0xFF0C9BFA), Color(0xFF1260CD)],
                  ).createShader(bounds),
                  child: Text(
                    '$machineCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 58,
                      height: 1,
                      letterSpacing: -2.7,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Machines de l’atelier',
                  style: TextStyle(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }
}

class _DesktopWelcomeGear extends StatelessWidget {
  const _DesktopWelcomeGear();

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 1250),
      curve: Curves.easeOutCubic,
      builder: (_, light, _) => CustomPaint(
        painter: _DesktopWelcomeGearPainter(
          light,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    ),
  );
}

class _DesktopWelcomeGearPainter extends CustomPainter {
  const _DesktopWelcomeGearPainter(this.light, {required this.dark});
  final double light;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = min(size.width, size.height) * .40;
    if (radius < 12) return;
    final center = Offset(size.width * .67, size.height * .58);
    final halo = Rect.fromCircle(center: center, radius: radius * 1.23);
    canvas.drawOval(
      halo,
      Paint()
        ..color = dark ? const Color(0x38D059F6) : const Color(0x384B91F2)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .21),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.19 + light * .11);
    final gear = _gearPath(radius, teeth: 10);
    canvas.drawPath(
      gear.shift(const Offset(0, 7)),
      Paint()
        ..color = dark ? const Color(0x3D7721A3) : const Color(0x3D2B70A9)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(
      gear,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.48, -.75),
          radius: 1.24,
          colors: dark
              ? const [Color(0xFFFFE8FF), Color(0xFFCB80F5), Color(0xFF8636B1), Color(0x80511C75)]
              : const [Color(0xFFE8F8FF), Color(0xFF72BFFF), Color(0xFF2675CE), Color(0x8023619F)],
          stops: const [0, .22, .61, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
    canvas.drawPath(
      gear,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFFFFF1FF), Color(0x66E6A1FF), Color(0xFFAC52D8)]
              : const [Color(0xFFFFFFFF), Color(0x6685D7FF), Color(0xFF2D8EE5)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .40,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topLeft,
          colors: dark
              ? const [Color(0xEEA75ACF), Color(0x888A3FB8), Color(0x008A3FB8)]
              : const [Color(0xEE4B94CF), Color(0x8851A6E8), Color(0x0051A6E8)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .39,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..color = dark ? const Color(0xFFF6D8FF) : const Color(0xFFD7F2FF),
    );
    canvas.restore();
  }

  Path _gearPath(double radius, {required int teeth}) {
    final path = Path();
    const profile = [(.0, .79), (.18, .79), (.27, 1.0), (.61, 1.0), (.70, .79)];
    for (var tooth = 0; tooth < teeth; tooth++) {
      for (final (phase, distance) in profile) {
        final angle = (tooth + phase) * 2 * pi / teeth;
        final point = Offset(cos(angle), sin(angle)) * radius * distance;
        if (tooth == 0 && phase == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _DesktopWelcomeGearPainter oldDelegate) =>
      oldDelegate.light != light || oldDelegate.dark != dark;
}

class _MachineArmEmblem extends StatelessWidget {
  const _MachineArmEmblem();

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _MachineArmEmblemPainter(
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
    ),
  );
}

class _MachineArmEmblemPainter extends CustomPainter {
  const _MachineArmEmblemPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.width, size.height) / 210;
    if (scale <= 0) return;
    canvas.save();
    canvas.translate(size.width * .73, size.height * .83);
    canvas.scale(scale);
    canvas.rotate(-.02);
    final glow = Rect.fromCenter(
      center: const Offset(-5, -55),
      width: 175,
      height: 138,
    );
    canvas.drawOval(
      glow,
      Paint()
        ..color = dark ? const Color(0x33D059F6) : const Color(0x33167CE3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 19),
    );
    _roundedPart(canvas, const Rect.fromLTWH(-62, -4, 116, 20), 8);
    _roundedPart(canvas, const Rect.fromLTWH(-42, -22, 77, 18), 7);
    _armSegment(canvas, const Offset(-12, -26), const Offset(6, -75), 15);
    _armSegment(canvas, const Offset(6, -75), const Offset(-37, -104), 14);
    _armSegment(canvas, const Offset(-37, -104), const Offset(-3, -133), 12);
    _joint(canvas, const Offset(-12, -26), 15);
    _joint(canvas, const Offset(6, -75), 14);
    _joint(canvas, const Offset(-37, -104), 12);
    _joint(canvas, const Offset(-3, -133), 9);
    final claw = Paint()
      ..color = dark ? const Color(0xFFF8DAFF) : const Color(0xFFE6F8FF)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-3, -133), const Offset(21, -144), claw);
    canvas.drawLine(const Offset(21, -144), const Offset(30, -137), claw);
    canvas.drawLine(const Offset(21, -144), const Offset(27, -154), claw);
    canvas.restore();
  }

  void _roundedPart(Canvas canvas, Rect rect, double radius) {
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      shape.shift(const Offset(-2, 4)),
      Paint()
        ..color = dark ? const Color(0x34721D99) : const Color(0x342B6FA5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFFFFE6FF), Color(0xFFC876EF), Color(0xFF702593)]
              : const [Color(0xFFE8F8FF), Color(0xFF58AAEE), Color(0xFF1D63B6)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = dark ? const Color(0xFFF8DFFF) : const Color(0xFFE5F7FF),
    );
  }

  void _armSegment(Canvas canvas, Offset from, Offset to, double width) {
    final midpoint = Offset.lerp(from, to, .5)!;
    final angle = (to - from).direction;
    final length = (to - from).distance;
    canvas.save();
    canvas.translate(midpoint.dx, midpoint.dy);
    canvas.rotate(angle);
    _roundedPart(
      canvas,
      Rect.fromCenter(center: Offset.zero, width: length, height: width),
      width * .45,
    );
    canvas.restore();
  }

  void _joint(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.5, -.6),
          colors: dark
              ? const [Color(0xFFFFEFFF), Color(0xFFCB81EF), Color(0xFF74259B)]
              : const [Color(0xFFF0FBFF), Color(0xFF59B5F5), Color(0xFF1C67BB)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = dark ? const Color(0xFFF9E2FF) : const Color(0xFFE7F9FF),
    );
  }

  @override
  bool shouldRepaint(covariant _MachineArmEmblemPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class _WorkshopEmblem extends StatelessWidget {
  const _WorkshopEmblem();

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 1450),
        curve: Curves.easeOutCubic,
        builder: (_, progress, _) => CustomPaint(
          painter: _WorkshopEmblemPainter(progress, dark: dark),
        ),
      ),
    );
  }
}

class _WorkshopEmblemPainter extends CustomPainter {
  const _WorkshopEmblemPainter(this.light, {this.dark = false});

  final double light;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final span = min(size.width * .50, size.height * .95);
    if (span < 32) return;

    canvas.save();
    canvas.translate(size.width - span * .49, size.height * .69 - 4 * light);
    canvas.rotate(-.60 + .13 * light);
    final halo = Rect.fromCenter(
      center: Offset.zero,
      width: span * 1.20,
      height: span * .83,
    );
    canvas.drawOval(
      halo,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: dark
              ? const [
                  Color(0x80D35BFF),
                  Color(0x407B24A3),
                  Color(0x001A0027),
                ]
              : const [
                  Color(0x8052B9F3),
                  Color(0x4067BFF1),
                  Color(0x0051A6E8),
                ],
          stops: [0, .58, 1],
        ).createShader(halo),
    );
    canvas.drawOval(
      halo.deflate(span * .076).shift(Offset(-span * .05, span * .06)),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.bottomRight,
          radius: 1.1,
          colors: dark
              ? [Color(0x91ED9CFF), Color(0x415F1684), Colors.transparent]
              : [
                  Color(0x9166C6F5),
                  Color(0x4168B9EF),
                  Colors.transparent,
                ],
        ).createShader(halo),
    );
    canvas.drawOval(
      halo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: dark
              ? const [Color(0xEEFFE6FF), Color(0x50C64DFF), Colors.transparent]
              : const [
                  Color(0xEEEAFAFF),
                  Color(0x5072B9E8),
                  Colors.transparent,
                ],
        ).createShader(halo),
    );

    final tile = Rect.fromCenter(
      center: Offset.zero,
      width: span * .56,
      height: span * .53,
    );
    final shape = RRect.fromRectAndRadius(tile, Radius.circular(span * .13));
    canvas.drawRRect(
      shape.shift(Offset(-span * .035, span * .093)),
      Paint()
        ..color = dark ? const Color(0x3C691990) : const Color(0x3C215F9B)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawRRect(
      shape.shift(Offset(-span * .045, span * .050)),
      Paint()..color = dark ? const Color(0x846C2295) : const Color(0x846AB9EC),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [
                  Color(0xEDFFE7FF),
                  Color(0xC1E072FF),
                  Color(0x83641C87),
                  Color(0xE99C37C5),
                ]
              : const [
                  Color(0xEDF0FBFF),
                  Color(0xC170BAF2),
                  Color(0x83529CDD),
                  Color(0xE961B8F5),
                ],
          stops: [0, .28, .72, 1],
        ).createShader(tile),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(-.94 + .57 * light, -1.06),
          radius: .91,
          colors: dark
              ? const [Color(0xBAFFF1FF), Color(0x67C651F4), Colors.transparent]
              : const [
                  Color(0xBAF2FBFF),
                  Color(0x677DC7F5),
                  Colors.transparent,
                ],
        ).createShader(tile),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFFFFF1FF), Color(0x40D15CFF), Color(0xFFE5B4FF)]
              : const [
                  Color(0xFFF1FBFF),
                  Color(0x405FADE5),
                  Color(0xFFB9E5FF),
                ],
        ).createShader(tile),
    );
    _paintGear(canvas, span * .115);
    canvas.restore();
  }

  void _paintGear(Canvas canvas, double radius) {
    const teeth = 8;
    const toothProfile = [
      (0.0, .80),
      (.22, .80),
      (.31, 1.0),
      (.69, 1.0),
      (.78, .80),
    ];
    final gear = Path();
    for (var tooth = 0; tooth < teeth; tooth++) {
      for (final (phase, length) in toothProfile) {
        final angle = (tooth + phase) * (2 * pi / teeth);
        final point = Offset(cos(angle), sin(angle)) * (radius * length);
        if (tooth == 0 && phase == 0) {
          gear.moveTo(point.dx, point.dy);
        } else {
          gear.lineTo(point.dx, point.dy);
        }
      }
    }
    gear.close();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.7
      ..color = dark ? const Color(0xFFFFE9FF) : AppPalette.text;
    canvas.drawPath(gear, stroke);
    canvas.drawCircle(Offset.zero, radius * .30, stroke);
  }

  @override
  bool shouldRepaint(covariant _WorkshopEmblemPainter oldDelegate) =>
      oldDelegate.light != light || oldDelegate.dark != dark;
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final foreground = dark ? const Color(0xFFFFF3FF) : AppPalette.text;
    final muted = dark ? const Color(0xFFE3C5ED) : AppPalette.muted;
    final surfaceAccent = dark ? const Color(0xFFE46AFF) : accent;
    return Glass(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      radius: 25,
      accent: surfaceAccent,
      child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 57),
      child: Row(
        children: [
          _DashboardGlassIcon(icon, surfaceAccent, size: 41),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 26,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _DashboardAction extends StatelessWidget {
  const _DashboardAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.desktop = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final surfaceAccent = dark ? const Color(0xFFE46AFF) : color;
    final foreground = dark ? const Color(0xFFFFF3FF) : AppPalette.text;
    final muted = dark ? const Color(0xFFE3C5ED) : AppPalette.muted;
    return _LiquidTapTarget(
    radius: 25,
    accent: surfaceAccent,
    onTap: onTap,
    child: Container(
      constraints: BoxConstraints(minHeight: desktop ? 142 : 62),
      padding: EdgeInsets.symmetric(
        horizontal: 13,
        vertical: desktop ? 14 : 9,
      ),
      child: desktop
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _DashboardGlassIcon(icon, surfaceAccent, size: 48),
                const SizedBox(height: 12),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    color: surfaceAccent.withValues(alpha: .22),
                    shape: BoxShape.circle,
                    border: Border.all(color: surfaceAccent.withValues(alpha: .35)),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: foreground,
                    size: 15,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                _DashboardGlassIcon(icon, surfaceAccent, size: 36),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    color: foreground,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: muted,
                  size: 17,
                ),
              ],
            ),
    ),
    );
  }
}

class _LoginScene extends StatelessWidget {
  const _LoginScene({required this.wide, required this.signIn});

  final bool wide;
  final Widget signIn;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final scene = LayoutBuilder(
      builder: (context, constraints) {
        final padding = EdgeInsets.symmetric(
          horizontal: wide ? min(76, constraints.maxWidth * .047) : 16,
          vertical: wide ? 30 : 16,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            if (dark)
              RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: reducedMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 1300),
                  curve: Curves.easeOutCubic,
                  builder: (_, progress, _) => CustomPaint(
                    painter: _LoginAmbientLight(dark: dark, progress: progress),
                  ),
                ),
              ),
            if (wide && dark)
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: constraints.maxWidth * .49,
                child: const RepaintBoundary(child: _LoginArtwork(wide: true)),
              ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, safeConstraints) => SingleChildScrollView(
                  padding: padding,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: max(
                        0,
                        safeConstraints.maxHeight - padding.vertical,
                      ),
                    ),
                    child: Center(
                      child: wide
                          ? ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: dark ? double.infinity : 1060,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 10,
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        bottom: dark
                                            ? min(
                                                236,
                                                constraints.maxHeight * .26,
                                              )
                                            : 0,
                                      ),
                                      child: Center(
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 460,
                                          ),
                                          child: const SizedBox(
                                            width: double.infinity,
                                            child: _LoginIdentity(wide: true),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: dark
                                        ? constraints.maxWidth * .032
                                        : 28,
                                  ),
                                  Expanded(
                                    flex: 11,
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 600,
                                        ),
                                        child: signIn,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 464),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _LoginIdentity(wide: false),
                                  const SizedBox(height: 14),
                                  signIn,
                                ],
                              ),
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
    return dark ? Aura(child: scene) : _LoginDaylightGlass(child: scene);
  }
}

class _LoginDaylightGlass extends StatefulWidget {
  const _LoginDaylightGlass({required this.child});

  final Widget child;

  @override
  State<_LoginDaylightGlass> createState() => _LoginDaylightGlassState();
}

// Keep the daylight background and the login lenses on the same texture.
class _LoginDaylightGlassState extends State<_LoginDaylightGlass> {
  final _anchor = GlobalKey();
  ImageStream? _stream;
  ImageInfo? _wallpaper;

  late final _listener = ImageStreamListener(
    (image, synchronous) {
      final previous = _wallpaper;
      if (synchronous) {
        _wallpaper = image;
      } else {
        setState(() => _wallpaper = image);
      }
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
    },
    onError: (error, _) => debugPrint('Daylight wallpaper unavailable: $error'),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream != null) return;
    final stream = const AssetImage('assets/atelier-login-daylight.png')
        .resolve(createLocalImageConfiguration(context));
    _stream = stream;
    stream.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _wallpaper?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final program = _LiquidSceneData.maybeOf(context)?.program;
    final texture = _wallpaper?.image;
    return LayoutBuilder(
      builder: (_, constraints) => SizedBox.expand(
        key: _anchor,
        child: _LiquidSceneData(
          anchor: _anchor,
          program: program,
          wallpaper: texture,
          reflection: null,
          size: constraints.biggest,
          dark: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (texture == null)
                const ColoredBox(color: Color(0xFFE7F1F8))
              else
                const RepaintBoundary(child: _LiquidWallpaper()),
              widget.child,
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginArtwork extends StatelessWidget {
  const _LoginArtwork({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final photo = Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF171323)),
        Image.asset(
          'assets/forage-login-drill.jpg',
          fit: BoxFit.cover,
          alignment: wide ? const Alignment(.58, 0) : const Alignment(0, .27),
          excludeFromSemantics: true,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: wide ? Alignment.bottomCenter : Alignment.centerRight,
              colors: [
                wide
                    ? (dark ? const Color(0xB31E052A) : const Color(0x90142748))
                    : const Color(0xE410071D),
                wide ? Colors.transparent : const Color(0x8E10071D),
                wide ? const Color(0x2E140525) : Colors.transparent,
              ],
              stops: const [0, .54, 1],
            ),
          ),
        ),
      ],
    );
    if (!wide) return photo;
    return CustomPaint(
      foregroundPainter: _LoginArtworkEdge(dark: dark),
      child: ClipPath(clipper: const _LoginArtworkClipper(), child: photo),
    );
  }
}

// The same contour clips the photo and carries the glass rim.
class _LoginArtworkClipper extends CustomClipper<Path> {
  const _LoginArtworkClipper();

  static Path edge(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * .72, 0)
      ..cubicTo(w * .90, h * .10, w * 1.035, h * .29, w * .974, h * .49)
      ..cubicTo(w * .935, h * .73, w * .79, h * .91, w * .60, h);
  }

  @override
  Path getClip(Size size) => edge(size)
    ..lineTo(0, size.height)
    ..lineTo(0, 0)
    ..close();

  @override
  bool shouldReclip(_LoginArtworkClipper oldClipper) => false;
}

class _LoginArtworkEdge extends CustomPainter {
  const _LoginArtworkEdge({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final edge = _LoginArtworkClipper.edge(size);
    final light = dark ? const Color(0xFFE694FF) : const Color(0xFFE5FCFF);
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        light.withValues(alpha: .40),
        light.withValues(alpha: .18),
        light,
        light.withValues(alpha: .28),
        light.withValues(alpha: .78),
      ],
      stops: const [0, .28, .48, .68, 1],
    ).createShader(Offset.zero & size);
    canvas.drawPath(
      edge,
      Paint()
        ..color = light.withValues(alpha: .32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      edge,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(_LoginArtworkEdge oldDelegate) => oldDelegate.dark != dark;
}

class _LoginAmbientLight extends CustomPainter {
  const _LoginAmbientLight({required this.dark, required this.progress});

  final bool dark;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final light = dark ? const Color(0xFFF5B2FF) : const Color(0xFFF5FDFF);
    final halo = dark ? const Color(0xFFCB2AFB) : const Color(0xFF57B7FC);
    final bounds = Offset.zero & size;

    void glow(Offset center, double radius, Color color, double alpha) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(center, radius, [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ]),
      );
    }

    glow(Offset(w * .80, h * .14), w * .53, halo, dark ? .29 : .38);
    glow(Offset(w * .79, h * .79), w * .48, halo, dark ? .20 : .24);
    final arc = Path()
      ..moveTo(w * .11, h * 1.07)
      ..cubicTo(w * .59, h * .70, w * .82, h * 1.06, w * 1.04, h * .52);
    final upperArc = Path()
      ..moveTo(w * .23, h * .32)
      ..cubicTo(w * .56, h * .16, w * .77, h * .31, w * .96, -h * .07);
    final rim = LinearGradient(
      colors: [
        Colors.transparent,
        light.withValues(alpha: .19),
        light.withValues(alpha: .82),
        halo.withValues(alpha: .43),
      ],
      stops: const [.18, .42, .79, 1],
    ).createShader(bounds);
    for (final curve in [upperArc, arc]) {
      canvas.drawPath(
        curve,
        Paint()
          ..color = halo.withValues(alpha: dark ? .43 : .30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      canvas.drawPath(
        curve,
        Paint()
          ..shader = rim
          ..style = PaintingStyle.stroke
          ..strokeWidth = dark ? 2 : 1.4,
      );
    }

    final metric = arc.computeMetrics().first;
    final edge = metric.getTangentForOffset(
      metric.length * (.48 + .35 * progress),
    );
    if (edge != null) {
      glow(edge.position, min(w * .15, 134), halo, dark ? .47 : .41);
      glow(edge.position, 24, light, .54);
    }
  }

  @override
  bool shouldRepaint(_LoginAmbientLight oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.progress != progress;
}

class _LoginGlassPanel extends StatelessWidget {
  const _LoginGlassPanel({
    required this.radius,
    required this.accent,
    required this.padding,
    required this.child,
  });

  final double radius;
  final Color accent;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final corners = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: dark ? .20 : .23),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Glass(
        radius: radius,
        accent: accent,
        frosted: true,
        depth: 1.92,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: corners,
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? .21 : .52),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: dark ? .24 : .08),
                Colors.transparent,
                accent.withValues(alpha: dark ? .13 : .14),
              ],
              stops: const [0, .37, 1],
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _LoginFeatureMark extends StatelessWidget {
  const _LoginFeatureMark(
    this.icon, {
    required this.accent,
    required this.size,
  });

  final IconData icon;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) => _LoginGlassPanel(
    radius: size * .30,
    accent: accent,
    padding: EdgeInsets.zero,
    child: SizedBox.square(
      dimension: size,
      child: Icon(icon, size: size * .55),
    ),
  );
}

Widget _loginButtonSurface(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final accent = dark ? const Color(0xFFE76AFF) : AppPalette.primary;
  final enabled = !states.contains(WidgetState.disabled);
  return _liquidButton(
    context,
    states,
    child,
    accent: accent,
    radius: 28,
    depth: 2.35,
    surfaceBuilder: enabled
        ? (pressure, child) => CustomPaint(
            painter: _LoginButtonReflection(
              dark: dark,
              accent: accent,
              pressure: pressure,
            ),
            child: child,
          )
        : null,
  );
}

class _LoginButtonReflection extends CustomPainter {
  const _LoginButtonReflection({
    required this.dark,
    required this.accent,
    required this.pressure,
  });

  final bool dark;
  final Color accent;
  final double pressure;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final capsule = RRect.fromRectAndRadius(bounds, const Radius.circular(28));
    final highlight = dark ? const Color(0xFFF5CBFF) : const Color(0xFFF4FCFF);
    final rim = dark ? const Color(0xFFE79AFF) : const Color(0xFF548FC8);

    // Keep the middle clear so the backdrop remains visible through the lens.
    canvas.drawRRect(
      capsule,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            highlight.withValues(alpha: .30 + .12 * pressure),
            accent.withValues(alpha: dark ? .18 : .10),
            Colors.transparent,
            rim.withValues(alpha: dark ? .36 : .25),
          ],
          stops: const [0, .23, .61, 1],
        ).createShader(bounds),
    );
    final glint = Alignment(.82 - .44 * pressure, .98);
    canvas.drawRRect(
      capsule,
      Paint()
        ..shader = RadialGradient(
          center: glint,
          radius: .23,
          colors: [
            highlight.withValues(alpha: .48 + .17 * pressure),
            accent.withValues(alpha: .16),
            Colors.transparent,
          ],
          stops: const [0, .42, 1],
        ).createShader(bounds),
    );
    canvas.drawRRect(
      capsule.deflate(.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            highlight.withValues(alpha: .92),
            rim.withValues(alpha: .44),
            rim.withValues(alpha: .32),
            highlight,
          ],
          stops: const [0, .31, .67, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_LoginButtonReflection oldDelegate) =>
      oldDelegate.dark != dark ||
      oldDelegate.accent != accent ||
      oldDelegate.pressure != pressure;
}

class _LoginIdentity extends StatelessWidget {
  const _LoginIdentity({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!dark) return _LoginDaylightIdentity(wide: wide);
    final accent = dark ? const Color(0xFFE46AFF) : AppPalette.primary;
    final logo = Image.asset(
      'assets/app_logo.png',
      width: wide ? 54 : 36,
      height: wide ? 54 : 36,
      excludeFromSemantics: true,
      color: dark ? const Color(0xFFF4CEFF) : null,
      colorBlendMode: BlendMode.srcIn,
    );
    final mark = _LoginGlassPanel(
      radius: wide ? 24 : 15,
      accent: accent,
      padding: EdgeInsets.all(wide ? 12 : 6),
      child: logo,
    );
    final name = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: wide
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          'FORAGE ZOUHOUR',
          textAlign: wide ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: wide ? 36 : 18,
            fontWeight: FontWeight.w900,
            height: 1.07,
            letterSpacing: wide ? -.85 : .15,
            color: wide && !dark ? AppPalette.text : const Color(0xFFFCF9FF),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Gestion d’atelier',
          style: TextStyle(
            color: wide && !dark ? AppPalette.muted : const Color(0xFFF0DBFA),
            fontWeight: FontWeight.w700,
            letterSpacing: wide ? 1.1 : 0,
            fontSize: wide ? 15 : 13,
          ),
        ),
      ],
    );
    if (wide) {
      return _LoginGlassPanel(
        radius: 32,
        accent: accent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 23),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [mark, const SizedBox(height: 18), name],
        ),
      );
    }
    return Glass(
      radius: 25,
      accent: accent,
      frosted: true,
      padding: const EdgeInsets.all(4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          children: [
            const Positioned.fill(child: _LoginArtwork(wide: false)),
            Container(
              constraints: const BoxConstraints(minHeight: 128),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  mark,
                  const SizedBox(width: 11),
                  Expanded(child: name),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginDaylightIdentity extends StatelessWidget {
  const _LoginDaylightIdentity({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final brand = Row(
      children: [
        Image.asset(
          'assets/app_logo.png',
          width: wide ? 44 : 34,
          height: wide ? 44 : 34,
          excludeFromSemantics: true,
        ),
        SizedBox(width: wide ? 13 : 9),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FORAGE ZOUHOUR',
                style: TextStyle(
                  color: AppPalette.text,
                  fontSize: wide ? 25 : 16,
                  fontWeight: FontWeight.w800,
                  height: 1.13,
                  letterSpacing: wide ? -.6 : 0,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Gestion d’atelier',
                style: TextStyle(color: AppPalette.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(wide ? 24 : 15),
      child: Image.asset(
        'assets/forage-login-daylight.jpg',
        fit: BoxFit.cover,
        alignment: const Alignment(.25, .53),
        excludeFromSemantics: true,
      ),
    );
    return Glass(
      radius: wide ? 32 : 23,
      accent: const Color(0xFF6D9CBD),
      frosted: true,
      depth: 1.16,
      padding: EdgeInsets.all(wide ? 10 : 12),
      child: wide
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: const EdgeInsets.all(12), child: brand),
                const SizedBox(height: 4),
                AspectRatio(aspectRatio: 1.38, child: photo),
              ],
            )
          : Row(
              children: [
                Expanded(child: brand),
                const SizedBox(width: 10),
                SizedBox(width: 90, height: 70, child: photo),
              ],
            ),
    );
  }
}

class _AtelierNavCapsule extends StatelessWidget {
  const _AtelierNavCapsule();

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final accent = dark ? const Color(0xFFD44DFF) : AppPalette.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(23)),
        boxShadow: [
          BoxShadow(
            color: (dark ? const Color(0xFFCB4DFF) : AppPalette.primary)
                .withValues(alpha: dark ? .55 : .34),
            blurRadius: 17,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: dark ? const Color(0x4E26002F) : const Color(0x263B6F96),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _LiquidLayer(
        radius: 23,
        depth: 1.53,
        press: .93,
        opacity: .78,
        accent: accent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(23)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [
                      Color(0xAFFFF5FF),
                      Color(0x55C84CFF),
                      Color(0x795A117A),
                    ]
                  : const [
                      Color(0xCFFFFFFF),
                      Color(0x6E8FD0FF),
                      Color(0x534A9CED),
                    ],
              stops: const [0, .52, 1],
            ),
          ),
        ),
      ),
    );
  }
}

class _AtelierNavItem extends StatelessWidget {
  const _AtelierNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final activeColor = dark ? const Color(0xFFFFFFFF) : AppPalette.text;
    final idleColor = dark ? const Color(0xFFF1D7F7) : AppPalette.muted;
    return Semantics(
    button: true,
    selected: selected,
    // The moving capsule is the only selection effect in the phone bar.
    // A second press lens used to remain visible after a fast page switch.
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? activeColor : idleColor,
              size: 22,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? activeColor : idleColor,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
        ),
      ),
    ),
    );
  }
}
