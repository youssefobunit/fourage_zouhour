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
        foregroundColor: AppPalette.primary,
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
        foregroundColor: AppPalette.primary,
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
      style: IconButton.styleFrom(backgroundColor: Colors.transparent)
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
      backgroundColor: const Color(0xFFF210022),
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
      backgroundColor: Color(0xFFF210022),
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFFF210022),
      surfaceTintColor: Colors.transparent,
      textStyle: const TextStyle(color: text),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: line),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Color(0xFFF210022)),
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
      style: TextButton.styleFrom(foregroundColor: violet),
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
        child: InputDecorator(
          // Keep the label above the value.  With an empty decorator both
          // pieces of text would be painted on top of each other.
          isEmpty: false,
          decoration: decoration.copyWith(
            errorText: field.errorText,
            enabled: enabled,
            prefixIcon: decoration.prefixIcon ??
                const Icon(Icons.sell_outlined, color: AppPalette.primary),
            suffixIcon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppPalette.primaryDark,
            ),
          ),
          child: selected == null
              ? const Text('Sélectionner…')
              : DefaultTextStyle.merge(
                  maxLines: isExpanded ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  child: selected.child,
                ),
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
  final fieldBox = context.findRenderObject() as RenderBox;
  final overlay = Navigator.of(context).overlay!;
  final overlayBox = overlay.context.findRenderObject() as RenderBox;
  final origin = fieldBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  final fieldRect = origin & fieldBox.size;
  final screen = Offset.zero & overlayBox.size;

  return showMenu<DropdownMenuItem<T>>(
    context: context,
    color: AppPalette.surface,
    elevation: 0,
    constraints: BoxConstraints(
      minWidth: fieldBox.size.width,
      maxWidth: max(fieldBox.size.width, 420.0),
      maxHeight: min(390.0, overlayBox.size.height * .60),
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: AppPalette.line.withValues(alpha: .90)),
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
                      ? AppPalette.primary.withValues(alpha: .20)
                      : AppPalette.surfaceRaised.withValues(alpha: .48),
                  border: Border.all(
                    color: isSelected
                        ? AppPalette.primary.withValues(alpha: .58)
                        : AppPalette.line.withValues(alpha: .34),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.sell_rounded
                          : Icons.inventory_2_outlined,
                      size: 19,
                      color: isSelected ? AppPalette.primary : AppPalette.muted,
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
                      const Icon(Icons.check_rounded, color: AppPalette.primary),
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
  const _AtelierBackdrop({this.dark = false});

  final bool dark;

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
          colors: dark
              ? const [Color(0xFF0B0011), Color(0xFF21002D), Color(0xFF08000D)]
              : const [Color(0xFFEAF7FF), Color(0xFFC6E6FF), Color(0xFF8CCBFF)],
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
    final glow = shape.inflate(.019);
    canvas.drawOval(
      glow,
      Paint()
        ..color = light.withValues(alpha: .20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .021),
    );
    canvas.drawOval(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
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
          ],
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
          colors: [
            light,
            dark ? const Color(0xDDF8D5FF) : const Color(0xCCFFFFFF),
            light.withValues(alpha: .11),
            Colors.transparent,
          ],
          stops: const [0, .23, .59, 1],
        ).createShader(shape),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AtelierBackdrop oldDelegate) =>
      oldDelegate.dark != dark;
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
    final dark = ForageAppearanceScope.of(context).isDark;
    // The historic primary is blue.  In the night scene the same semantic
    // primary becomes violet, so icons never look as though they belong to
    // the light interface.
    final accent = dark && color == AppPalette.primary
        ? const Color(0xFFE36AFF)
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
  Widget build(BuildContext context) => IconButton(
    onPressed: () => Navigator.maybePop(context),
    icon: const Icon(Icons.arrow_back_rounded),
    tooltip: tooltip,
    style: IconButton.styleFrom(
      foregroundColor: AppPalette.primary,
      backgroundColor: AppPalette.surfaceRaised,
      side: const BorderSide(color: AppPalette.line),
    ),
  );
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
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .31),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .31),
          blurRadius: 13,
          offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(color: color.withValues(alpha: .45), width: .65),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(color, Colors.white, .43)!,
          Color.lerp(color, AppPalette.soft, .43)!,
          Color.lerp(color, AppPalette.background, .65)!,
          color,
        ],
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
        color: AppPalette.text,
        shadows: const [Shadow(color: Color(0x55316FA6), blurRadius: 4)],
      ),
    ),
  );
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
            const Text(
              'VUE D’ENSEMBLE',
              style: TextStyle(
                color: AppPalette.primary,
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
            const Text(
              'Voici un aperçu de votre atelier aujourd’hui.',
              style: TextStyle(
                color: AppPalette.muted,
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
  Widget build(BuildContext context) => Glass(
    key: const ValueKey('atelier-overview'),
    radius: 30,
    accent: AppPalette.primary,
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
                    style: const TextStyle(
                      fontSize: 27,
                      height: 1.08,
                      letterSpacing: -.8,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.text,
                    ),
                  ),
                ],
                SizedBox(height: desktop ? 13 : 25),
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0C9BFA), Color(0xFF1260CD)],
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
                const Text(
                  'Machines de l’atelier',
                  style: TextStyle(
                    color: AppPalette.muted,
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
        painter: _DesktopWelcomeGearPainter(light),
      ),
    ),
  );
}

class _DesktopWelcomeGearPainter extends CustomPainter {
  const _DesktopWelcomeGearPainter(this.light);
  final double light;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = min(size.width, size.height) * .40;
    if (radius < 12) return;
    final center = Offset(size.width * .67, size.height * .58);
    final halo = Rect.fromCircle(center: center, radius: radius * 1.23);
    canvas.drawOval(
      halo,
      Paint()
        ..color = AppPalette.secondary.withValues(alpha: .22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .21),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-.19 + light * .11);
    final gear = _gearPath(radius, teeth: 10);
    canvas.drawPath(
      gear.shift(const Offset(0, 7)),
      Paint()
        ..color = const Color(0x3D2B70A9)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(
      gear,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.48, -.75),
          radius: 1.24,
          colors: [
            Color(0xFFE8F8FF),
            Color(0xFF72BFFF),
            Color(0xFF2675CE),
            Color(0x8023619F),
          ],
          stops: [0, .22, .61, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
    canvas.drawPath(
      gear,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0x6685D7FF), Color(0xFF2D8EE5)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .40,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.topLeft,
          colors: [Color(0xEE4B94CF), Color(0x8851A6E8), Color(0x0051A6E8)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
    canvas.drawCircle(
      Offset.zero,
      radius * .39,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..color = const Color(0xFFD7F2FF),
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
      oldDelegate.light != light;
}

class _MachineArmEmblem extends StatelessWidget {
  const _MachineArmEmblem();

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: const _MachineArmEmblemPainter()),
  );
}

class _MachineArmEmblemPainter extends CustomPainter {
  const _MachineArmEmblemPainter();

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
        ..color = AppPalette.primary.withValues(alpha: .20)
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
      ..color = const Color(0xFFE6F8FF)
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
        ..color = const Color(0x342B6FA5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8F8FF), Color(0xFF58AAEE), Color(0xFF1D63B6)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = const Color(0xFFE5F7FF),
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
          colors: const [Color(0xFFF0FBFF), Color(0xFF59B5F5), Color(0xFF1C67BB)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFE7F9FF),
    );
  }

  @override
  bool shouldRepaint(covariant _MachineArmEmblemPainter oldDelegate) => false;
}

class _WorkshopEmblem extends StatelessWidget {
  const _WorkshopEmblem();

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 1450),
      curve: Curves.easeOutCubic,
      builder: (_, progress, _) =>
          CustomPaint(painter: _WorkshopEmblemPainter(progress)),
    ),
  );
}

class _WorkshopEmblemPainter extends CustomPainter {
  const _WorkshopEmblemPainter(this.light);

  final double light;

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
        ..shader = const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0x8052B9F3), Color(0x4067BFF1), Color(0x0051A6E8)],
          stops: [0, .58, 1],
        ).createShader(halo),
    );
    canvas.drawOval(
      halo.deflate(span * .076).shift(Offset(-span * .05, span * .06)),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.bottomRight,
          radius: 1.1,
          colors: [Color(0x9166C6F5), Color(0x4168B9EF), Colors.transparent],
        ).createShader(halo),
    );
    canvas.drawOval(
      halo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..shader = const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xEEEAFAFF), Color(0x5072B9E8), Colors.transparent],
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
        ..color = const Color(0x3C215F9B)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawRRect(
      shape.shift(Offset(-span * .045, span * .050)),
      Paint()..color = const Color(0x846AB9EC),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
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
          colors: const [
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
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1FBFF), Color(0x405FADE5), Color(0xFFB9E5FF)],
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
      ..color = AppPalette.text;
    canvas.drawPath(gear, stroke);
    canvas.drawCircle(Offset.zero, radius * .30, stroke);
  }

  @override
  bool shouldRepaint(covariant _WorkshopEmblemPainter oldDelegate) =>
      oldDelegate.light != light;
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
  Widget build(BuildContext context) => Glass(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    radius: 25,
    accent: accent,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 57),
      child: Row(
        children: [
          _DashboardGlassIcon(icon, accent, size: 41),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    color: AppPalette.text,
                    fontSize: 26,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppPalette.muted,
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
  Widget build(BuildContext context) => _LiquidTapTarget(
    radius: 25,
    accent: color,
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
                _DashboardGlassIcon(icon, color, size: 48),
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
                    color: color.withValues(alpha: .22),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: .35)),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppPalette.text,
                    size: 15,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                _DashboardGlassIcon(icon, color, size: 36),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppPalette.muted,
                  size: 17,
                ),
              ],
            ),
    ),
  );
}

class _LoginIdentity extends StatelessWidget {
  const _LoginIdentity({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    final accent = dark ? const Color(0xFFE46AFF) : AppPalette.primary;
    final mark = Glass(
      accent: accent,
      radius: wide ? 23 : 19,
      padding: EdgeInsets.all(wide ? 12 : 8),
      child: dark
          ? ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0xFFE46AFF),
                BlendMode.srcIn,
              ),
              child: Image.asset(
                'assets/app_logo.png',
                width: wide ? 57 : 39,
                height: wide ? 57 : 39,
                excludeFromSemantics: true,
              ),
            )
          : Image.asset(
              'assets/app_logo.png',
              width: wide ? 57 : 39,
              height: wide ? 57 : 39,
              excludeFromSemantics: true,
            ),
    );
    if (!wide) {
      return Row(
        children: [
          mark,
          const SizedBox(width: 13),
          const Expanded(child: _LoginBrandName()),
        ],
      );
    }
    return Glass(
      radius: 30,
      accent: accent,
      frosted: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _WorkshopEmblemPainter(dark ? .72 : 1)),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 350),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  mark,
                  const SizedBox(height: 23),
                  const _LoginBrandName(large: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBrandName extends StatelessWidget {
  const _LoginBrandName({this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context) {
    final dark = ForageAppearanceScope.of(context).isDark;
    return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'FORAGE ZOUHOUR',
        style: TextStyle(
          fontSize: large ? 32 : 20,
          fontWeight: FontWeight.w900,
          height: 1.04,
          letterSpacing: large ? -1 : .15,
          color: dark ? const Color(0xFFFFF4FF) : null,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Gestion d’atelier',
        style: TextStyle(
          color: dark ? const Color(0xFFE67BFF) : AppPalette.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ],
  );
  }
}

class _AtelierNavCapsule extends StatelessWidget {
  const _AtelierNavCapsule();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      borderRadius: BorderRadius.all(Radius.circular(23)),
      boxShadow: [
        BoxShadow(color: Color(0x8CCB4DFF), blurRadius: 17, spreadRadius: 1),
        BoxShadow(
          color: Color(0x4E26002F),
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: _LiquidLayer(
      radius: 23,
      depth: 1.53,
      press: .93,
      opacity: .78,
      accent: const Color(0xFFD44DFF),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(23)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xAFFFF5FF), Color(0x55C84CFF), Color(0x795A117A)],
            stops: [0, .52, 1],
          ),
        ),
      ),
    ),
  );
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
