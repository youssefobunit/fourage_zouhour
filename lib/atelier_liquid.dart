part of 'main.dart';

/// A single wallpaper texture keeps the liquid lenses aligned with the
/// original backdrop, including on renderers without shader image filters.
class AtelierLiquidStage extends StatefulWidget {
  const AtelierLiquidStage({super.key, required this.child, this.dark = false});
  final Widget child;
  final bool dark;

  @override
  State<AtelierLiquidStage> createState() => _AtelierLiquidStageState();
}

class _AtelierLiquidStageState extends State<AtelierLiquidStage> {
  final anchor = GlobalKey();
  Size sceneSize = Size.zero;
  ui.Image? wallpaper;
  ui.FragmentProgram? program;
  bool _renderingWallpaper = false;

  @override
  void initState() {
    super.initState();
    loadProgram();
  }

  Future<void> loadProgram() async {
    try {
      final loaded = await ui.FragmentProgram.fromAsset(
        'shaders/atelier_liquid.frag',
      );
      if (mounted) setState(() => program = loaded);
    } catch (error) {
      debugPrint('FORAGE liquid shader unavailable: $error');
    }
  }

  void updateWallpaper(Size size, double pixelRatio) {
    if (size.isEmpty || !size.isFinite) return;
    final scale = min(pixelRatio, 1440 / size.longestSide);
    final width = max(1, (size.width * scale).ceil());
    final height = max(1, (size.height * scale).ceil());
    if (size == sceneSize &&
        wallpaper?.width == width &&
        wallpaper?.height == height &&
        _wallpaperWasDark == widget.dark) {
      return;
    }
    // Picture.toImageSync blocks the Windows raster thread.  Switching the
    // appearance used to rebuild this bitmap during build, which made the
    // native window report "not responding".  Defer the work and let the
    // previous wallpaper (or painted fallback) remain visible meanwhile.
    if (_renderingWallpaper) return;
    _renderingWallpaper = true;
    final dark = widget.dark;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_renderWallpaper(size, width, height, dark));
    });
  }

  Future<void> _renderWallpaper(
    Size size,
    int width,
    int height,
    bool dark,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(width / size.width, height / size.height);
    _AtelierBackdrop(dark: dark).paint(canvas, size);
    final picture = recorder.endRecording();
    late final ui.Image next;
    try {
      next = await picture.toImage(width, height);
    } catch (error) {
      debugPrint('FORAGE liquid wallpaper unavailable: $error');
      _renderingWallpaper = false;
      return;
    } finally {
      picture.dispose();
    }
    if (!mounted || widget.dark != dark) {
      next.dispose();
      _renderingWallpaper = false;
      if (mounted) setState(() {});
      return;
    }
    final previous = wallpaper;
    setState(() {
      wallpaper = next;
      sceneSize = size;
      _wallpaperWasDark = dark;
      _renderingWallpaper = false;
    });
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  bool? _wallpaperWasDark;

  @override
  void dispose() {
    wallpaper?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Rendering a scene bitmap through Picture.toImage blocks the Windows
      // graphics driver on some machines (especially while the authenticated
      // workspace is opening).  Desktop therefore uses the lightweight,
      // direct liquid fallback; mobile retains the refracting scene texture.
      final useSceneTexture =
          !(Platform.isWindows || Platform.isLinux || Platform.isMacOS);
      if (useSceneTexture) {
        updateWallpaper(
          constraints.biggest,
          MediaQuery.devicePixelRatioOf(context),
        );
      }
      return SizedBox.expand(
        key: anchor,
        child: _LiquidSceneData(
          anchor: anchor,
          program: program,
          wallpaper: wallpaper,
          size: sceneSize,
          dark: widget.dark,
          child: widget.child,
        ),
      );
    },
  );
}

class _LiquidSceneData extends InheritedWidget {
  const _LiquidSceneData({
    required this.anchor,
    required this.program,
    required this.wallpaper,
    required this.size,
    required this.dark,
    required super.child,
  });

  final GlobalKey anchor;
  final ui.FragmentProgram? program;
  final ui.Image? wallpaper;
  final Size size;
  final bool dark;

  static _LiquidSceneData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiquidSceneData>();

  Offset originOf(RenderBox box) {
    final root = anchor.currentContext?.findRenderObject();
    if (root is! RenderBox || !root.attached || !box.attached) {
      return Offset.zero;
    }
    final offset = box.localToGlobal(Offset.zero, ancestor: root);
    return offset.isFinite ? offset : Offset.zero;
  }

  @override
  bool updateShouldNotify(_LiquidSceneData oldWidget) =>
      oldWidget.program != program ||
      oldWidget.wallpaper != wallpaper ||
      oldWidget.size != size ||
      oldWidget.dark != dark;
}

class _LiquidWallpaper extends StatelessWidget {
  const _LiquidWallpaper();

  @override
  Widget build(BuildContext context) {
    if (_LiquidSceneData.maybeOf(context)?.wallpaper == null) {
      return CustomPaint(
        painter: _AtelierBackdrop(
          dark: _LiquidSceneData.maybeOf(context)?.dark ?? false,
        ),
      );
    }
    return const _LiquidLayer(wallpaperOnly: true, child: SizedBox.expand());
  }
}

typedef _LensStyle = ({
  double radius,
  double depth,
  double press,
  double opacity,
  Color accent,
});

class _LiquidLayer extends SingleChildRenderObjectWidget {
  const _LiquidLayer({
    super.child,
    this.radius = 18,
    this.depth = 1,
    this.press = 0,
    this.opacity = .96,
    this.accent = AppPalette.primary,
    this.wallpaperOnly = false,
  });

  final double radius;
  final double depth;
  final double press;
  final double opacity;
  final Color accent;
  final bool wallpaperOnly;

  _LensStyle get style => (
    radius: radius,
    depth: depth,
    press: press,
    opacity: opacity,
    accent: accent,
  );

  @override
  _RenderLiquidLayer createRenderObject(BuildContext context) =>
      _RenderLiquidLayer(
        _LiquidSceneData.maybeOf(context),
        wallpaperOnly ? null : Scrollable.maybeOf(context)?.position,
        style,
        wallpaperOnly,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiquidLayer renderObject,
  ) {
    renderObject.update(
      scene: _LiquidSceneData.maybeOf(context),
      viewport: wallpaperOnly ? null : Scrollable.maybeOf(context)?.position,
      style: style,
      wallpaperOnly: wallpaperOnly,
    );
  }
}

class _RenderLiquidLayer extends RenderProxyBox {
  _RenderLiquidLayer(
    this._scene,
    this._viewport,
    this._style,
    this._wallpaperOnly,
  );

  _LiquidSceneData? _scene;
  ScrollPosition? _viewport;
  _LensStyle _style;
  bool _wallpaperOnly;
  ui.FragmentShader? _shader;

  void update({
    required _LiquidSceneData? scene,
    required ScrollPosition? viewport,
    required _LensStyle style,
    required bool wallpaperOnly,
  }) {
    if (_viewport != viewport) {
      if (attached) _viewport?.removeListener(markNeedsPaint);
      _viewport = viewport;
      if (attached) _viewport?.addListener(markNeedsPaint);
    }
    if (_scene?.program != scene?.program) {
      _shader?.dispose();
      _shader = null;
    }
    if (_scene != scene || _style != style || _wallpaperOnly != wallpaperOnly) {
      _scene = scene;
      _style = style;
      _wallpaperOnly = wallpaperOnly;
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _viewport?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _viewport?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!size.isEmpty && (_wallpaperOnly || _style.opacity > 0)) {
      final canvas = context.canvas;
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      final scene = _scene;
      final texture = scene?.wallpaper;
      final bounds = Offset.zero & size;
      if (_wallpaperOnly && texture != null && scene != null) {
        canvas.clipRect(bounds);
        canvas.drawImageRect(
          texture,
          Rect.fromLTWH(
            0,
            0,
            texture.width.toDouble(),
            texture.height.toDouble(),
          ),
          -scene.originOf(this) & scene.size,
          Paint()..filterQuality = FilterQuality.low,
        );
      } else if (texture != null && scene?.program != null) {
        drawLens(canvas, bounds, scene!, texture);
      } else {
        drawFallback(canvas, bounds);
      }
      canvas.restore();
    }
    super.paint(context, offset);
  }

  void drawLens(
    Canvas canvas,
    Rect bounds,
    _LiquidSceneData scene,
    ui.Image texture,
  ) {
    final origin = scene.originOf(this);
    final shader = _shader ??= scene.program!.fragmentShader();
    final style = _style;
    final radius = min(style.radius, size.shortestSide * .5);
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, origin.dx)
      ..setFloat(3, origin.dy)
      ..setFloat(4, scene.size.width)
      ..setFloat(5, scene.size.height)
      ..setFloat(6, style.accent.r)
      ..setFloat(7, style.accent.g)
      ..setFloat(8, style.accent.b)
      ..setFloat(9, radius)
      ..setFloat(10, style.depth)
      ..setFloat(11, style.press)
      ..setFloat(12, style.opacity)
      ..setFloat(13, scene.dark ? 1 : 0)
      ..setImageSampler(0, texture);
    canvas.drawRect(bounds, Paint()..shader = shader);
  }

  void drawFallback(Canvas canvas, Rect bounds) {
    final style = _style;
    final radius = min(style.radius, size.shortestSide * .5);
    final shape = RRect.fromRectAndRadius(bounds, Radius.circular(radius));
    final dark = _scene?.dark ?? false;
    final edgeColor = (dark ? const Color(0xFFF0BBFF) : style.accent)
        .withValues(alpha: .30 + .32 * style.press);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          colors: [
            if (dark) ...[
              const Color(0xFF57147E),
              const Color(0xFF190024),
            ] else ...[
              Color.lerp(
                AppPalette.surfaceRaised,
                style.accent,
                .12 + .10 * style.press,
              )!,
              AppPalette.background,
            ],
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bounds),
    );
    canvas.drawRRect(
      shape.deflate(.6),
      Paint()
        ..color = edgeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }
}

Widget _primaryLiquidButton(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => _liquidButton(
  states,
  child,
  accent: AppPalette.primary,
  radius: 16,
  depth: 1.32,
);

Widget _secondaryLiquidButton(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => _liquidButton(
  states,
  child,
  accent: AppPalette.secondary,
  radius: 16,
  depth: 1.1,
);

Widget _iconLiquidButton(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => _liquidButton(
  states,
  child,
  accent: AppPalette.primary,
  radius: 50,
  depth: 1.29,
);

Widget _criticalLiquidButton(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => _liquidButton(
  states,
  child,
  accent: AppPalette.coral,
  radius: 16,
  depth: 1.21,
);

final _criticalActionStyle = FilledButton.styleFrom(
  foregroundColor: AppPalette.coral,
).copyWith(backgroundBuilder: _criticalLiquidButton);

Widget _liquidButton(
  Set<WidgetState> states,
  Widget? child, {
  required Color accent,
  required double radius,
  required double depth,
}) {
  final enabled = !states.contains(WidgetState.disabled);
  final pressure = states.contains(WidgetState.pressed)
      ? 1.0
      : states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)
      ? .35
      : 0.0;
  return TweenAnimationBuilder<double>(
    tween: Tween(end: pressure),
    duration: const Duration(milliseconds: 170),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (_, value, child) => _LiquidLayer(
      radius: radius,
      depth: enabled ? depth : .38,
      press: enabled ? value : 0,
      opacity: enabled ? .97 : .48,
      accent: enabled ? accent : AppPalette.muted,
      child: child,
    ),
  );
}

class _LiquidTapTarget extends StatefulWidget {
  const _LiquidTapTarget({
    required this.onTap,
    required this.child,
    required this.accent,
    this.radius = 21,
    this.selected = false,
    this.idleOpacity = .91,
    this.selectedOpacity = 1,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color accent;
  final double radius;
  final bool selected;
  final double idleOpacity;
  final double selectedOpacity;

  @override
  State<_LiquidTapTarget> createState() => _LiquidTapTargetState();
}

class _LiquidTapTargetState extends State<_LiquidTapTarget>
    with SingleTickerProviderStateMixin {
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 410,
    ratio: .72,
  );

  bool _pressed = false;
  double get _restingPressure => widget.selected ? .61 : 0;
  late final _pressure = AnimationController.unbounded(
    vsync: this,
    value: _restingPressure,
  );

  @override
  void didUpdateWidget(covariant _LiquidTapTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected && !_pressed) {
      _settleAt(_restingPressure);
    }
  }

  void _settleAt(double target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pressure.value = target;
      return;
    }
    _pressure.animateWith(
      SpringSimulation(
        _spring,
        _pressure.value,
        target,
        _pressure.velocity,
        tolerance: const Tolerance(distance: .002, velocity: .02),
      ),
    );
  }

  void _onHighlightChanged(bool pressed) {
    if (!mounted || pressed == _pressed) return;
    _pressed = pressed;
    _settleAt(pressed ? 1.0 : _restingPressure);
  }

  @override
  void dispose() {
    _pressure.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pressure,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: _onHighlightChanged,
        borderRadius: BorderRadius.circular(widget.radius),
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return widget.accent.withValues(alpha: .20);
          }
          return Colors.transparent;
        }),
        child: widget.child,
      ),
    ),
    builder: (context, child) {
      final pressure = _pressure.value.clamp(0.0, 1.0);
      final compression = (_pressure.value - _restingPressure).clamp(-.15, 1.0);
      return Transform.scale(
        scale: 1 - .028 * compression,
        transformHitTests: false,
        child: _LiquidLayer(
          radius: widget.radius,
          depth: widget.selected ? 1.36 : 1.16,
          press: pressure,
          accent: widget.accent,
          opacity: widget.selected
              ? widget.selectedOpacity
              : ui.lerpDouble(widget.idleOpacity, 1, pressure)!,
          child: child,
        ),
      );
    },
  );
}
