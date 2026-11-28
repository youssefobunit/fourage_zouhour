part of 'main.dart';

/// The lenses share the backdrop's coordinates and drawing resources.
class AtelierLiquidStage extends StatefulWidget {
  const AtelierLiquidStage({super.key, required this.child, this.dark = false});
  final Widget child;
  final bool dark;

  @override
  State<AtelierLiquidStage> createState() => _AtelierLiquidStageState();
}

class _AtelierLiquidStageState extends State<AtelierLiquidStage> {
  final anchor = GlobalKey();
  final _wallpapers = <bool, ImageInfo>{};
  final _wallpaperListeners = <(ImageStream, ImageStreamListener)>[];
  ui.FragmentProgram? program;
  ui.Picture? _reflection;
  Size _reflectionSize = Size.zero;
  bool? _reflectionWasDark;
  @override
  void initState() {
    super.initState();
    unawaited(loadProgram());
    _loadWallpaper(dark: false);
    _loadWallpaper(dark: true);
  }

  void _loadWallpaper({required bool dark}) {
    final mode = dark ? 'dark' : 'light';
    // The two static textures are decoded once. The shader needs no
    // framebuffer readback when the window changes size or theme.
    final stream = AssetImage('assets/atelier-wallpaper-$mode.png')
        .resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (image, synchronousCall) {
        final previous = _wallpapers[dark];
        if (synchronousCall) {
          _wallpapers[dark] = image;
        } else {
          setState(() => _wallpapers[dark] = image);
        }
        if (previous != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => previous.dispose(),
          );
        }
      },
      onError: (error, _) => debugPrint('FORAGE wallpaper unavailable: $error'),
    );
    _wallpaperListeners.add((stream, listener));
    stream.addListener(listener);
  }

  ui.Picture? _reflectionAt(Size size) {
    if (size.isEmpty || !size.isFinite) return null;
    if (_reflectionSize == size && _reflectionWasDark == widget.dark) {
      return _reflection;
    }
    final recorder = ui.PictureRecorder();
    _AtelierBackdrop(
      dark: widget.dark,
      reflection: true,
    ).paint(Canvas(recorder), size);
    final previous = _reflection;
    _reflection = recorder.endRecording();
    _reflectionSize = size;
    _reflectionWasDark = widget.dark;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
    return _reflection;
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

  @override
  void dispose() {
    for (final (stream, listener) in _wallpaperListeners) {
      stream.removeListener(listener);
    }
    for (final image in _wallpapers.values) {
      image.dispose();
    }
    _reflection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final texture = _wallpapers[widget.dark]?.image;
      final opticsReady = texture != null && program != null;
      return SizedBox.expand(
        key: anchor,
        child: _LiquidSceneData(
          anchor: anchor,
          program: program,
          wallpaper: opticsReady ? texture : null,
          reflection: opticsReady ? null : _reflectionAt(size),
          size: size,
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
    required this.reflection,
    required this.size,
    required this.dark,
    required super.child,
  });

  final GlobalKey anchor;
  final ui.FragmentProgram? program;
  final ui.Image? wallpaper;
  final ui.Picture? reflection;
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
      oldWidget.reflection != reflection ||
      oldWidget.size != size ||
      oldWidget.dark != dark;
}

class _LiquidWallpaper extends StatelessWidget {
  const _LiquidWallpaper();

  @override
  Widget build(BuildContext context) {
    final scene = _LiquidSceneData.maybeOf(context);
    if (scene?.wallpaper == null) {
      return CustomPaint(
        painter: _AtelierBackdrop(
          dark: scene?.dark ?? Theme.of(context).brightness == Brightness.dark,
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
  bool dark,
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

  _LensStyle _style(BuildContext context, _LiquidSceneData? scene) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scene?.dark ?? scheme.brightness == Brightness.dark;
    final useDarkAccent =
        dark &&
        (accent == AppPalette.primary ||
            accent == AppPalette.secondary ||
            accent == AppPalette.lilac ||
            accent == AppPalette.muted);
    return (
      radius: radius,
      depth: depth,
      press: press,
      opacity: opacity,
      accent: useDarkAccent ? const Color(0xFFE36AFF) : accent,
      dark: dark,
    );
  }

  @override
  _RenderLiquidLayer createRenderObject(BuildContext context) {
    final scene = _LiquidSceneData.maybeOf(context);
    return _RenderLiquidLayer(
      scene,
      wallpaperOnly ? null : Scrollable.maybeOf(context)?.position,
      _style(context, scene),
      wallpaperOnly,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiquidLayer renderObject,
  ) {
    final scene = _LiquidSceneData.maybeOf(context);
    renderObject.update(
      scene: scene,
      viewport: wallpaperOnly ? null : Scrollable.maybeOf(context)?.position,
      style: _style(context, scene),
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
      ..setFloat(13, style.dark ? 1 : 0)
      ..setImageSampler(0, texture);
    canvas.drawRect(bounds, Paint()..shader = shader);
  }

  void drawFallback(Canvas canvas, Rect bounds) {
    final style = _style;
    final radius = min(style.radius, size.shortestSide * .5);
    final shape = RRect.fromRectAndRadius(bounds, Radius.circular(radius));
    final opacity = style.opacity.clamp(0.0, 1.0);
    final depth = style.depth * (1 + .36 * style.press);
    final scene = _scene;
    final reflection = scene?.reflection;
    if (reflection != null && scene != null) {
      final origin = scene.originOf(this);
      final center = bounds.center;
      final lift = min(size.shortestSide * .12, 8.0) * depth;
      canvas.save();
      canvas.clipRRect(shape);
      canvas.translate(center.dx + 1.4 * depth, center.dy - lift * .42);
      canvas.scale(1 + 2 * lift / size.width, 1 + 2 * lift / size.height);
      canvas.translate(-origin.dx - center.dx, -origin.dy - center.dy);
      canvas.drawPicture(reflection);
      canvas.restore();
    }

    Color tint(Color color, double amount, double alpha) => Color.lerp(
      color,
      style.accent,
      amount,
    )!.withValues(alpha: alpha * opacity);
    final tintStrength = .10 + .14 * style.press;
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          colors: [
            tint(
              style.dark ? const Color(0xFF45165D) : const Color(0xFFF1FAFF),
              tintStrength,
              style.dark ? .66 : .56,
            ),
            tint(
              style.dark ? const Color(0xFF1D062C) : AppPalette.background,
              tintStrength * .48,
              style.dark ? .50 : .59,
            ),
            tint(
              style.dark ? const Color(0xFF341045) : AppPalette.surfaceRaised,
              tintStrength,
              style.dark ? .60 : .64,
            ),
          ],
          stops: const [0, .58, 1],
          begin: const Alignment(-.85, -1),
          end: const Alignment(.9, 1),
        ).createShader(bounds),
    );

    final light = style.dark ? const Color(0xFFF4CFFF) : Colors.white;
    final edge = style.dark ? const Color(0xFFDF94F7) : const Color(0xFF79BAE8);
    final shine = (opacity * (.66 + .22 * style.press)).clamp(0.0, 1.0);
    final sheen = min(.32, (9.0 + depth * 4) / size.height);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            light.withValues(alpha: shine * .29),
            light.withValues(alpha: 0),
            edge.withValues(alpha: 0),
            edge.withValues(alpha: shine * .21),
          ],
          stops: [0, sheen, 1 - sheen, 1],
        ).createShader(bounds),
    );
    final highlightRadius = min(
      size.longestSide * .46,
      max(radius * 2.6, 24.0),
    );
    final upperGlint = Offset(radius * (.70 + .36 * style.press), 0);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = ui.Gradient.radial(
          upperGlint,
          highlightRadius,
          [
            light.withValues(alpha: shine * .62),
            light.withValues(alpha: shine * .15),
            light.withValues(alpha: 0),
          ],
          const [0, .36, 1],
        ),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width - radius * .68, size.height),
          highlightRadius,
          [light.withValues(alpha: shine * .43), edge.withValues(alpha: 0)],
        ),
    );
    canvas.drawDRRect(
      shape,
      shape.deflate(min(.9, size.shortestSide * .20)),
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-.9, -1),
          end: const Alignment(.72, 1),
          colors: [
            light.withValues(alpha: shine * .95),
            edge.withValues(alpha: shine * .35),
            edge.withValues(alpha: shine * .30),
            light.withValues(alpha: shine * .76),
          ],
          stops: const [0, .32, .68, 1],
        ).createShader(bounds),
    );
  }
}

Widget _primaryLiquidButton(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => _liquidButton(
  context,
  states,
  child,
  accent: AppPalette.primary,
  radius: 16,
  depth: 1.52,
);

Widget _secondaryLiquidButton(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => _liquidButton(
  context,
  states,
  child,
  accent: AppPalette.secondary,
  radius: 16,
  depth: 1.29,
);

Widget _iconLiquidButton(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => _liquidButton(
  context,
  states,
  child,
  accent: AppPalette.primary,
  radius: 50,
  depth: 1.48,
);

Widget _criticalLiquidButton(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => _liquidButton(
  context,
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
  BuildContext context,
  Set<WidgetState> states,
  Widget? child, {
  required Color accent,
  required double radius,
  required double depth,
  Widget Function(double pressure, Widget? child)? surfaceBuilder,
}) {
  final enabled = !states.contains(WidgetState.disabled);
  final pressure = states.contains(WidgetState.pressed)
      ? 1.0
      : states.contains(WidgetState.selected)
      ? .50
      : states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)
      ? .35
      : 0.0;
  return TweenAnimationBuilder<double>(
    tween: Tween(end: pressure),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 170),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (_, value, child) => _LiquidLayer(
      radius: radius,
      depth: enabled ? depth : .38,
      press: enabled ? value : 0,
      opacity: enabled ? .90 + .08 * value : .42,
      accent: enabled ? accent : AppPalette.muted,
      child: surfaceBuilder?.call(value, child) ?? child,
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
  bool _hovered = false;
  double get _restingPressure => widget.selected ? .61 : 0;
  double get _idlePressure =>
      _hovered ? (widget.selected ? .76 : .30) : _restingPressure;
  late final _pressure = AnimationController.unbounded(
    vsync: this,
    value: _restingPressure,
  );

  @override
  void didUpdateWidget(covariant _LiquidTapTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected && !_pressed) {
      _settleAt(_idlePressure);
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
    _settleAt(pressed ? 1.0 : _idlePressure);
  }

  void _onHoverChanged(bool hovered) {
    if (!mounted || _hovered == hovered) return;
    _hovered = hovered;
    if (!_pressed) _settleAt(_idlePressure);
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
        onHover: _onHoverChanged,
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
          depth: widget.selected ? 1.58 : 1.31,
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
