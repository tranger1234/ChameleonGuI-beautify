import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// iOS 26 "Liquid Glass" design language for Chameleon Ultra GUI
/// (Muse v1.1 二开改造，仅 UI 层；v1.2 增补见 [FrostedSurface] 与
/// [showFrostedDialog]).
///
/// v1.1 rework, based on a study of Apple's Liquid Glass (WWDC25 #219 and
/// published optical reconstructions — see LIQUID-GLASS-ANALYSIS.md):
/// v1 was ordinary frosted glass (uniform blur + white tint + flat border).
/// Real Liquid Glass is defined by *lensing at the rim*, a
/// saturate-before-blur colour pipeline, a rim light that varies around
/// the perimeter, layered content-aware shadows and light that moves.
///
/// v1.1 therefore provides:
/// - [liquidGlassBackdrop]: a composed backdrop filter that boosts
///   saturation *before* blurring (Apple's filter order), so colours seen
///   through the glass stay vivid instead of washing out to grey.
/// - [GlassBackground]: a more saturated, colourful backdrop — the "light
///   source" every glass surface in the app refracts.
/// - [GlassContainer]: a glass surface with a comparatively clear centre
///   and an optical rim: perimeter rim light (bright top-left, dim
///   bottom-right, like a fixed −60° light source), a soft inner
///   refraction band, a dark outer keyline, inner top/bottom bands that
///   give the pane thickness, dual ambient-tinted shadows and a slowly
///   drifting specular sheen.
/// - [LiquidGlassTheme]: restyles the stock Material components into
///   translucent glass with capsule shapes and large radii.
class GlassPalette {
  // v1.1: deeper, more saturated blob colours. The backdrop is what every
  // glass surface shows through itself, so its vibrancy caps the whole
  // app's glass look.
  static const Color blobBlue = Color(0xFF3B6DFF);
  static const Color blobPink = Color(0xFFFF5FB8);
  static const Color blobOrange = Color(0xFFFFA63D);
  static const Color blobMint = Color(0xFF2FE6A8);
  static const Color blobViolet = Color(0xFF7D5CFF);
}

/// Saturation matrix (Rec. 709 luma) with an optional constant lift,
/// as a 4x5 colour matrix for [ColorFilter.matrix].
List<double> _saturationMatrix(double saturation, {double lift = 0}) {
  const double r = 0.2126;
  const double g = 0.7152;
  const double b = 0.0722;
  final double s = saturation;
  final double ir = (1 - s) * r;
  final double ig = (1 - s) * g;
  final double ib = (1 - s) * b;
  return <double>[
    ir + s, ig, ib, 0, lift,
    ir, ig + s, ib, 0, lift,
    ir, ig, ib + s, 0, lift,
    0, 0, 0, 1, 0,
  ];
}

/// The Liquid Glass backdrop pipeline: **saturate first, then blur**
/// (with a slight lift). Gaussian blur averages chroma towards grey, so
/// boosting saturation *after* the blur — or not at all, as v1 did —
/// leaves the classic milky frosted look. Apple's material recipes use
/// this order (saturate → blur → brightness); Flutter applies the
/// `inner` filter of [ImageFilter.compose] first, hence the wiring below.
///
/// v2.13: results are memoised on the parameter triple. This function
/// is called from build methods that re-run per animation frame (the
/// navigation rail's pane and its sliding lens). Handing back the
/// *identical* [ImageFilter] for identical parameters lets
/// RenderBackdropFilter skip its repaint when only the caller's
/// rebuild changed; a fresh filter object every build reads as "the
/// filter changed" and forces the backdrop to re-rasterise even at a
/// constant size and sigma. ImageFilters are immutable, so sharing
/// instances is safe.
final Map<(double, double, double), ImageFilter> _liquidGlassBackdropCache =
    <(double, double, double), ImageFilter>{};

ImageFilter liquidGlassBackdrop({
  double blurSigma = 16,
  double saturation = 1.55,
  double lift = 4,
}) {
  final (double, double, double) key = (blurSigma, saturation, lift);
  return _liquidGlassBackdropCache.putIfAbsent(
    key,
    () => ImageFilter.compose(
      outer: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      inner: ColorFilter.matrix(_saturationMatrix(saturation, lift: lift)),
    ),
  );
}

/// Full-screen colourful background inspired by iOS 26 wallpapers seen
/// through Liquid Glass: a base gradient plus large, heavily blurred
/// colour blobs so translucent surfaces visibly refract colour.
class GlassBackground extends StatelessWidget {
  final Widget child;

  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        // Base gradient
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF0B1026),
                      Color(0xFF1B1140),
                      Color(0xFF062A3A),
                    ]
                  : const [
                      Color(0xFFD7E7FF),
                      Color(0xFFF3D8F8),
                      Color(0xFFFFEECB),
                      Color(0xFFCDF6E3),
                    ],
            ),
          ),
        ),
        // Blurred colour blobs
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
            child: Stack(
              children: [
                _blob(GlassPalette.blobBlue, -90, -60, 300, isDark ? 0.6 : 0.72),
                _blob(GlassPalette.blobPink, null, -70, 260, isDark ? 0.45 : 0.62,
                    right: -80),
                _blob(GlassPalette.blobMint, null, -70, 280, isDark ? 0.36 : 0.56,
                    bottom: -60),
                _blob(GlassPalette.blobOrange, null, null, 220, isDark ? 0.34 : 0.5,
                    right: -40, bottom: 120),
                _blob(GlassPalette.blobViolet, 260, 130, 200, isDark ? 0.4 : 0.46),
              ],
            ),
          ),
        ),
        // Subtle top light so the whole screen feels lit like glass
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [
                Colors.white.withValues(alpha: isDark ? 0.05 : 0.22),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }

  Widget _blob(Color color, double? top, double? left, double size, double opacity,
      {double? right, double? bottom}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: opacity),
        ),
      ),
    );
  }
}

/// Paints the optical rim of a glass pane: a rim light whose brightness
/// varies around the perimeter, as if lit by a fixed light source from
/// the top-left (Apple's ≈ −60° direction). A uniform white border is
/// the wrong *shape* for glass — brightness must follow the surface
/// normal around the shape. Beneath the crisp rim line, a wider blurred
/// stroke simulates the bright refraction band inside the bevel.
class _GlassRimPainter extends CustomPainter {
  final double radius;
  final bool isDark;

  const _GlassRimPainter({required this.radius, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Rim alpha around the perimeter, starting at angle 0 (+x axis,
    // pointing right) and increasing clockwise (y is down):
    // right → bottom-right → bottom → bottom-left → left → top-left →
    // top → top-right → right. Brightest at top-left (fraction 0.625).
    final peak = isDark ? 0.72 : 0.95;
    final alphas = <double>[
      0.45, 0.16, 0.30, 0.45, 0.62, 1.0, 0.80, 0.50, 0.45,
    ];
    final colors = alphas
        .map((a) => Colors.white.withValues(alpha: a * peak))
        .toList(growable: false);
    final gradient = SweepGradient(
      colors: colors,
      stops: const [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0],
    );

    // Soft inner refraction band: a wide, faint, blurred stroke just
    // inside the rim — the compressed bright edge a real bevel shows.
    final bandPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
          rect.deflate(4), Radius.circular(math.max(0, radius - 4))));
    canvas.drawPath(
      bandPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..shader = gradient.createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Crisp rim light line.
    final rimPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
          rect.deflate(0.7), Radius.circular(math.max(0, radius - 0.7))));
    canvas.drawPath(
      rimPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.isDark != isDark;
}

/// Public accessor for the glass rim painter (v2.11): the navigation
/// rail's sliding selection lens lives in main.dart but draws the
/// same perimeter rim light as every [GlassContainer] pane, so the
/// private painter is exposed through this factory instead of being
/// duplicated.
CustomPainter glassRimPainter({required double radius, required bool isDark}) =>
    _GlassRimPainter(radius: radius, isDark: isDark);

/// v2.10: the navigation rail's theme-following tint base for
/// [GlassContainer.tintColor] — the colour scheme's [primary]
/// blended into white at low strength (0.40 light / 0.60 dark), so
/// the result is a pastel of the scheme's hue: the hue survives
/// (within a degree or so on the schemes this app offers), the
/// saturation drops to a fraction (measured tint-base saturation
/// ≤ ≈0.26 across all eight schemes in both brightnesses — see the
/// v2.10 harness test). [GlassContainer] then lays that base down
/// through its tint gradient's own low alphas (≤ 0.34 light,
/// ≤ 0.13 dark), so over the blurred backdrop the scheme reads as a
/// whisper of hue in the glass, never as a coloured fill.
///
/// Why the restraint — the v2.9 lesson: the card-button style once
/// took a saturated theme RGB (202, 43, 43) and *replaced* the
/// alpha its colour table had tuned (≈0.06) with 0.36–0.62, which
/// produced saturated red blocks all over the dark theme. Here the
/// primary is desaturated into a pastel *before* it reaches the
/// glass, and in the dark theme the strongest hue-bearing stop is
/// that pastel at alpha 0.13 — roughly an order of magnitude
/// weaker than the v2.9 failure mode. The dark cards stay neutral
/// (v2.9), so rail and cards coexist: the rail carries a hint of
/// the current scheme, the cards stay theme-neutral glass.
Color railGlassTint(Color primary, {required bool isDark}) {
  return Color.alphaBlend(
    primary.withValues(alpha: isDark ? 0.60 : 0.40),
    Colors.white,
  );
}

/// A reusable Liquid Glass surface (v1.1).
///
/// Structure, back to front: saturation-boosted backdrop blur with a
/// light tint (centre stays comparatively clear — the effect lives at
/// the rim), inner top refraction band and bottom inner shadow that
/// give the pane thickness, the perimeter rim light, a slowly drifting
/// specular sheen, and finally the content. Outside: a dark keyline and
/// dual shadows — a tight contact shadow plus a wide ambient-tinted
/// glow, the way colourful surroundings bleed into a real glass shadow.
class GlassContainer extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blurSigma;
  final double? width;
  final double? height;

  /// Whether the specular sheen slowly drifts (living light). Static
  /// when the system asks to reduce motion.
  final bool sheen;

  /// v2.2: horizontal liquid deformation (1.0 = none). The navigation
  /// rail stretches this slightly while it is being dragged or
  /// springing, for a jelly feel. Other users leave the default and
  /// are unaffected.
  ///
  /// v2.6: the deformation applies to the glass *skin* only (backdrop,
  /// tint, rim, sheen, border, shadows) — never to [child]. Through
  /// v2.5 the transform wrapped the whole pane, content included, so
  /// the rail's icons were dragged along with the stretch: up to
  /// 40 × (deformX − 1) ≈ +2 px of sideways drift on every transition,
  /// measured on the owner's device recording. The pane's outline may
  /// stretch; the content must not move.
  final double deformX;

  /// Anchor for [deformX]; the rail uses centre-left so the pane
  /// grows from the screen edge.
  final AlignmentGeometry deformAlignment;

  /// v2.2: extra offset added to the specular sheen position, so the
  /// light can lean with motion (rail opening, fling direction).
  final double sheenShift;

  /// v2.2: extra sheen intensity while in motion (0 = unchanged);
  /// the sheen alpha is multiplied by (1 + sheenBoost).
  final double sheenBoost;

  /// v2.3: cheap-motion mode. While true, the specular sheen's slow
  /// drift animation is paused — the layer freezes at whatever
  /// position the drift had reached — so a caller that rebuilds the
  /// pane every frame (the navigation rail while it is dragged or
  /// springing) does not pay for a second, independent per-frame
  /// repaint driver. The caller's own [sheenShift]/[sheenBoost]
  /// still apply, and lowering [blurSigma] during motion is the
  /// caller's side of the same deal. Defaults to false (the v2.2
  /// behaviour); only the rail opts in, nobody else is affected.
  final bool motionReduced;

  /// v2.10: optional base colour for the pane's backdrop tint
  /// gradient. Null (the default) keeps the neutral white base every
  /// version through v2.9 used, so existing panes are unchanged.
  /// When set, the gradient keeps its exact per-stop alphas and only
  /// the base colour changes — the pane takes on a hue without any
  /// change to the glass optics (blur pipeline, rim, sheen, bands,
  /// shadows all stay as they are). The passed colour's own alpha is
  /// replaced per stop via withValues, so pass an opaque colour; the
  /// navigation rail passes [railGlassTint], a pastel blend of the
  /// colour scheme's primary.
  final Color? tintColor;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 28,
    this.blurSigma = 16,
    this.width,
    this.height,
    this.sheen = true,
    this.deformX = 1.0,
    this.deformAlignment = Alignment.center,
    this.sheenShift = 0,
    this.sheenBoost = 0,
    this.motionReduced = false,
    this.tintColor,
  });

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer>
    with SingleTickerProviderStateMixin {
  AnimationController? _sheenController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.sheen &&
        _sheenController == null &&
        !MediaQuery.disableAnimationsOf(context)) {
      _sheenController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 9),
      );
      _syncSheenDrift();
    }
  }

  @override
  void didUpdateWidget(GlassContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motionReduced != widget.motionReduced) {
      _syncSheenDrift();
    }
  }

  /// v2.3: runs the sheen drift unless [GlassContainer.motionReduced]
  /// asks for a frozen sheen. Stopping (rather than disposing) keeps
  /// the drift value, so the layer resumes from the exact position
  /// it froze at — no visible jump when motion ends.
  void _syncSheenDrift() {
    final controller = _sheenController;
    if (controller == null) {
      return;
    }
    if (widget.motionReduced) {
      controller.stop();
    } else if (!controller.isAnimating) {
      controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _sheenController?.dispose();
    super.dispose();
  }

  Widget _sheenLayer(bool isDark, double shift, double boost) {
    final midAlpha = (isDark ? 0.05 : 0.09) * (1 + boost);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(shift - 0.55, -1),
            end: Alignment(shift + 0.55, 1),
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: midAlpha),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.3, 0.5, 0.7],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ambient = Theme.of(context).colorScheme.primary;
    final radius = BorderRadius.circular(widget.borderRadius);
    // v2.10: the backdrop tint gradient's base colour — neutral
    // white unless a caller tints the pane (see [GlassContainer.tintColor]).
    final tintBase = widget.tintColor ?? Colors.white;
    // v2.6: the pane is built as two layers — a glass *skin* (every
    // optical layer plus the keyline border and the shadows that
    // outline the pane) and the content on top of it. Only the skin
    // is ever deformed (see [GlassContainer.deformX]); through v2.5 a
    // single Transform wrapped skin and content together, which moved
    // the content — the rail's icons — sideways on every transition.
    final skin = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        // Dark outer keyline: separates the pane from light content,
        // the way a real glass edge catches a dark contour.
        border: Border.all(
          color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.10),
          width: 0.8,
        ),
        boxShadow: [
          // Wide ambient-tinted glow: surrounding colour bleeding into
          // the shadow.
          BoxShadow(
            color: ambient.withValues(alpha: isDark ? 0.16 : 0.14),
            blurRadius: 36,
            offset: const Offset(0, 18),
            spreadRadius: -6,
          ),
          // Tight contact shadow for grounding.
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.16),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Backdrop: saturate → blur, then a light tint. The centre
            // stays comparatively clear; v1's heavy white wash (up to
            // alpha 0.55) is gone.
            Positioned.fill(
              child: BackdropFilter(
                filter: liquidGlassBackdrop(blurSigma: widget.blurSigma),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              tintBase.withValues(alpha: 0.13),
                              tintBase.withValues(alpha: 0.04),
                              tintBase.withValues(alpha: 0.08),
                            ]
                          : [
                              tintBase.withValues(alpha: 0.34),
                              tintBase.withValues(alpha: 0.13),
                              tintBase.withValues(alpha: 0.24),
                            ],
                    ),
                  ),
                ),
              ),
            ),
            // Inner top refraction band: light entering the bevel.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.10 : 0.18),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom inner shadow: the far side of the pane's thickness.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // Perimeter rim light.
            Positioned.fill(
              child: CustomPaint(
                painter: _GlassRimPainter(
                    radius: widget.borderRadius, isDark: isDark),
              ),
            ),
            // Specular line hugging the top edge, stronger towards the
            // left where the light source sits.
            Positioned(
              top: 0,
              left: 10,
              right: 10,
              child: Container(
                height: 1.6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: isDark ? 0.6 : 0.95),
                      Colors.white.withValues(alpha: isDark ? 0.25 : 0.45),
                      Colors.white.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.35, 0.75, 1.0],
                  ),
                ),
              ),
            ),
            // Living specular sheen: a broad diagonal gloss that drifts
            // very slowly, like light moving when the device tilts.
            if (widget.sheen)
              Positioned.fill(
                child: RepaintBoundary(
                  child: _sheenController == null
                      ? _sheenLayer(
                          isDark, -0.2 + widget.sheenShift, widget.sheenBoost)
                      : AnimatedBuilder(
                          animation: _sheenController!,
                          builder: (context, _) {
                            final t = Curves.easeInOutSine
                                .transform(_sheenController!.value);
                            return _sheenLayer(
                                isDark,
                                -0.35 + 0.5 * t + widget.sheenShift,
                                widget.sheenBoost);
                          },
                        ),
                ),
              ),
          ],
        ),
      ),
    );
    // v2.2: liquid deformation of the skin. Inert (no extra layer)
    // unless a caller drives deformX away from 1.0. v2.6: the
    // transform wraps the skin only — the content layer below is
    // never part of it, so content cannot be dragged by the stretch.
    final Widget skinLayer = widget.deformX == 1.0
        ? skin
        : Transform(
            transform: Matrix4.diagonal3Values(widget.deformX, 1, 1),
            alignment: widget.deformAlignment,
            child: skin,
          );
    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      child: Stack(
        // The skin's shadows paint outside the pane's rect; the old
        // single-container structure never clipped them, so don't
        // clip here either.
        clipBehavior: Clip.none,
        children: [
          // The skin fills the pane exactly (the pane sizes to the
          // content, as before) and ignores pointers — all input
          // belongs to the content.
          Positioned.fill(child: IgnorePointer(child: skinLayer)),
          // Content: unscaled, undeformed, exactly where the old
          // structure's padding put it.
          Padding(
            padding: widget.padding ?? EdgeInsets.zero,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// A plain frosted-glass surface (v1.2): real backdrop blur plus a
/// translucent tint and a fine border — deliberately *without* the
/// Liquid Glass optics (rim light, sheen, refraction bands) of
/// [GlassContainer]. The owner asked for cards and secondary surfaces
/// to be honest frosted glass, not liquid glass, so this stays simple:
/// blur + tint + border, nothing else.
class FrostedSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final Color? tintColor;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const FrostedSurface({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blurSigma = 14,
    this.tintColor,
    this.margin,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius);
    final tint = tintColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.18));
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Real frost: blur whatever is behind the surface, then a
            // translucent tint on top of the blurred backdrop.
            Positioned.fill(
              child: BackdropFilter(
                filter:
                    ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: Container(color: tint),
              ),
            ),
            if (padding != null)
              Padding(padding: padding!, child: child)
            else
              child,
            // Fine border, drawn above the content so the edge stays
            // defined even where the content is transparent.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: Colors.white
                          .withValues(alpha: isDark ? 0.22 : 0.45),
                      width: 0.8,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a dialog the frosted way (v1.2): the page behind the dialog
/// is blurred with the saturate → blur pipeline while the dialog
/// itself uses the translucent [DialogTheme] from [LiquidGlassTheme],
/// so the panel reads as frosted glass floating over a blurred page
/// instead of the near-opaque white slab it was before.
///
/// Drop-in replacement for [showDialog] covering the parameter subset
/// this app uses (context / builder / barrierDismissible). Wrapping
/// the [AlertDialog] itself in a [BackdropFilter] is not possible —
/// the framework's [Dialog] expands to fill the route and centres its
/// material inside, so any external frost layer would cover the whole
/// screen at the wrong size; blurring the backdrop and making the
/// dialog translucent achieves the same frosted read robustly for
/// every dialog size and shape.
Future<T?> showFrostedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext dialogContext) {
      return _FrostedDialogBackdrop(child: builder(dialogContext));
    },
  );
}

class _FrostedDialogBackdrop extends StatelessWidget {
  final Widget child;

  const _FrostedDialogBackdrop({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: liquidGlassBackdrop(blurSigma: 14, saturation: 1.3),
            child: Container(color: Colors.transparent),
          ),
        ),
        child,
      ],
    );
  }
}

/// Stronger frosted menu colour for the settings page dropdowns (v1.3).
///
/// Everywhere else, dropdown menus take the theme's translucent
/// canvasColor (white α0.80 / #262939 α0.88). On the settings page the
/// owner found that too see-through: the rows behind the open menu
/// stayed legible through it. Dropdown routes are painted by the
/// framework and accept no BackdropFilter, so "more frosted" for a
/// dropdown means a denser tint — near-opaque, with just a hint of the
/// backdrop still coming through. Only the settings page opts into
/// this, via DropdownButton.dropdownColor.
///
/// v2.8: the settings page no longer uses this — its two dropdowns
/// are [FrostedDropdown]s with a real backdrop-blur panel now. Kept
/// for any framework-painted menu that still wants the dense tint.
Color frostedDropdownColor(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark
      ? const Color(0xFF262939).withValues(alpha: 0.95)
      : Colors.white.withValues(alpha: 0.93);
}

/// A drop-in replacement for [DropdownButton] whose menu is a real
/// frosted-glass panel instead of the framework's painted menu route
/// (v2.8, built for the settings page).
///
/// The framework's dropdown menu is drawn by the framework in its own
/// route and accepts no [BackdropFilter], so through v2.7 the
/// settings menus could only be *tinted* (see
/// [frostedDropdownColor]) — and at the α0.93/α0.95 density the owner
/// asked for in v1.3 they read as near-solid slabs that clash with
/// the rest of the glass UI. This widget keeps the closed field
/// metric-identical to [DropdownButton] (same item stack sized by the
/// widest item, same titleMedium text style, same 24 px dropdown
/// icon in the framework's own icon colour, same 48 px item height,
/// same ink splash with the same corner radius) but opens a
/// self-drawn anchored panel with the optics of the card dialogs
/// (see [showFrostedDialog]): the saturate → blur backdrop pipeline
/// ([liquidGlassBackdrop], blur 14 / saturate 1.3) behind a
/// translucent panel tint in the dialog theme's own values (white
/// α0.55 light / #2A2D3E α0.66 dark), a 28 px radius and the dialog
/// shape's fine bright border.
///
/// Behaviour mirrors the framework dropdown: the entries are the
/// very same [DropdownMenuItem]s (an item's `onTap` fires before the
/// value callback, a disabled item cannot be chosen), the selected
/// row is highlighted with the theme's focus colour — what the
/// framework paints behind the selected item in touch highlight
/// mode — tapping outside dismisses without a callback, and the
/// back button dismisses too (it is a [PopupRoute], like the
/// framework's own menu route).
///
/// Panel geometry: width is the field width widened to fit the
/// widest item's text (measured, plus the framework's 16 px item
/// padding on both sides), clamped to the screen minus 16 px margins
/// on both sides; the panel hangs 4 px below the field, or above it
/// when the space below is the smaller one; height is capped at 60%
/// of the screen height, with the list scrolling inside and starting
/// scrolled so the selected item is visible with one item of context
/// above it.
class FrostedDropdown<T> extends StatefulWidget {
  /// The currently selected value, shown in the closed field.
  final T? value;

  /// The entries, exactly as for [DropdownButton.items].
  final List<DropdownMenuItem<T>> items;

  /// Called with the chosen value when the user picks an item.
  /// Dismissing the menu (outside tap, back button) never calls it.
  final ValueChanged<T?>? onChanged;

  /// The field's trailing icon; defaults to [Icons.arrow_drop_down],
  /// like [DropdownButton].
  final Widget? icon;

  /// Icon size; 24 like [DropdownButton.iconSize].
  final double iconSize;

  /// Text style for the field and the menu rows; defaults to
  /// [TextTheme.titleMedium], like [DropdownButton].
  final TextStyle? style;

  /// Corner radius of the field's ink splash; the settings page
  /// passes the same 20 px radius it passed to [DropdownButton].
  final BorderRadius? borderRadius;

  /// Height of one menu row; 48 like the framework's menu items.
  final double itemHeight;

  const FrostedDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
    this.iconSize = 24,
    this.style,
    this.borderRadius,
    this.itemHeight = kMinInteractiveDimension,
  });

  @override
  State<FrostedDropdown<T>> createState() => _FrostedDropdownState<T>();
}

class _FrostedDropdownState<T> extends State<FrostedDropdown<T>> {
  final GlobalKey _fieldKey = GlobalKey();
  bool _menuOpen = false;

  // Same enabled rule as DropdownButton: items present and a
  // callback to deliver the choice to.
  bool get _enabled => widget.items.isNotEmpty && widget.onChanged != null;

  int get _selectedIndex =>
      widget.items.indexWhere((item) => item.value == widget.value);

  /// Width of the widest item's text, measured the way it will be
  /// drawn (the menu rows wrap the same [DropdownMenuItem]s in the
  /// same text style). Non-[Text] children contribute nothing; the
  /// field width is the floor in that case.
  double _widestItemTextWidth(BuildContext context) {
    final TextStyle baseStyle =
        widget.style ?? Theme.of(context).textTheme.titleMedium!;
    final TextDirection direction = Directionality.of(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    double widest = 0;
    for (final DropdownMenuItem<T> item in widget.items) {
      final Widget child = item.child;
      if (child is! Text) {
        continue;
      }
      final String? data = child.data ?? child.textSpan?.toPlainText();
      if (data == null || data.isEmpty) {
        continue;
      }
      final TextPainter painter = TextPainter(
        text: TextSpan(text: data, style: baseStyle.merge(child.style)),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }

  Future<void> _showMenu() async {
    if (!_enabled || _menuOpen) {
      return;
    }
    final RenderBox button =
        _fieldKey.currentContext!.findRenderObject()! as RenderBox;
    final Rect buttonRect = button.localToGlobal(Offset.zero) & button.size;
    final Size screenSize = MediaQuery.sizeOf(context);
    // Panel width: the field width, widened to the widest item's
    // text plus the framework's 16 px item padding per side, clamped
    // so the panel always keeps a 16 px margin to the screen edges.
    final double panelWidth = math.min(
      math.max(buttonRect.width, _widestItemTextWidth(context) + 32),
      math.max(0.0, screenSize.width - 32),
    );
    _menuOpen = true;
    final _FrostedDropdownResult<T>? result =
        await Navigator.of(context).push<_FrostedDropdownResult<T>>(
      _FrostedDropdownRoute<T>(
        items: widget.items,
        selectedIndex: _selectedIndex,
        buttonRect: buttonRect,
        panelWidth: panelWidth,
        itemHeight: widget.itemHeight,
        textStyle:
            widget.style ?? Theme.of(context).textTheme.titleMedium!,
        textDirection: Directionality.of(context),
        barrierLabel:
            MaterialLocalizations.of(context).modalBarrierDismissLabel,
      ),
    );
    _menuOpen = false;
    // A dismissal returns no result object at all; picking an item —
    // even one whose value is null — returns one (the framework
    // boxes its route result the same way, for the same reason).
    if (result != null) {
      widget.onChanged!(result.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    // Framework metrics (checked against this SDK's dropdown.dart):
    // the field is the item stack plus the icon, no padding, in
    // titleMedium; the icon takes grey.shade700 / white70 when
    // enabled (grey.shade400 / white10 when disabled), and a
    // disabled field dims its text to the theme's disabled colour.
    final TextStyle textStyle =
        (widget.style ?? theme.textTheme.titleMedium!).copyWith(
      color: _enabled ? null : theme.disabledColor,
    );
    final Color iconColor = _enabled
        ? (isDark ? Colors.white70 : Colors.grey.shade700)
        : (isDark ? Colors.white10 : Colors.grey.shade400);
    final int selectedIndex = _selectedIndex;
    return Semantics(
      button: true,
      child: InkWell(
        key: _fieldKey,
        onTap: _enabled ? _showMenu : null,
        borderRadius: widget.borderRadius,
        child: DefaultTextStyle(
          style: textStyle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IndexedStack(
                index: selectedIndex < 0 ? 0 : selectedIndex,
                alignment: AlignmentDirectional.centerStart,
                // Each item is boxed to itemHeight exactly like the
                // framework does: a bare DropdownMenuItem contains an
                // Align that would otherwise stretch the field to
                // the full height a bounded parent offers.
                children: widget.items
                    .map((DropdownMenuItem<T> item) =>
                        SizedBox(height: widget.itemHeight, child: item))
                    .toList(),
              ),
              IconTheme(
                data: IconThemeData(color: iconColor, size: widget.iconSize),
                child: widget.icon ?? const Icon(Icons.arrow_drop_down),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Boxes the menu's return value so that dismissing the route (no
/// result) can be told apart from picking an item whose value is
/// null — the same trick the framework's dropdown route uses.
@immutable
class _FrostedDropdownResult<T> {
  const _FrostedDropdownResult(this.value);

  final T? value;

  @override
  bool operator ==(Object other) =>
      other is _FrostedDropdownResult<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class _FrostedDropdownRoute<T> extends PopupRoute<_FrostedDropdownResult<T>> {
  _FrostedDropdownRoute({
    required this.items,
    required this.selectedIndex,
    required this.buttonRect,
    required this.panelWidth,
    required this.itemHeight,
    required this.textStyle,
    required this.textDirection,
    required this.barrierLabel,
  });

  final List<DropdownMenuItem<T>> items;
  final int selectedIndex;
  final Rect buttonRect;
  final double panelWidth;
  final double itemHeight;
  final TextStyle textStyle;
  final TextDirection textDirection;

  @override
  final String? barrierLabel;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 100);

  @override
  bool get barrierDismissible => true;

  // No coloured scrim: like the framework's dropdown route, the
  // route still gets a (transparent) modal barrier that dismisses
  // on an outside tap, and the glass panel itself carries the look.
  @override
  Color? get barrierColor => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return _FrostedDropdownPage<T>(
          items: items,
          selectedIndex: selectedIndex,
          buttonRect: buttonRect,
          panelWidth: panelWidth,
          itemHeight: itemHeight,
          textStyle: textStyle,
          textDirection: textDirection,
          screenSize: Size(constraints.maxWidth, constraints.maxHeight),
        );
      },
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}

class _FrostedDropdownPage<T> extends StatefulWidget {
  const _FrostedDropdownPage({
    required this.items,
    required this.selectedIndex,
    required this.buttonRect,
    required this.panelWidth,
    required this.itemHeight,
    required this.textStyle,
    required this.textDirection,
    required this.screenSize,
  });

  final List<DropdownMenuItem<T>> items;
  final int selectedIndex;
  final Rect buttonRect;
  final double panelWidth;
  final double itemHeight;
  final TextStyle textStyle;
  final TextDirection textDirection;
  final Size screenSize;

  @override
  State<_FrostedDropdownPage<T>> createState() =>
      _FrostedDropdownPageState<T>();
}

class _FrostedDropdownPageState<T> extends State<_FrostedDropdownPage<T>> {
  /// Vertical padding inside the panel, above and below the rows —
  /// the framework menu's kMaterialListPadding (8 + 8).
  static const double _listVerticalPadding = 8;

  /// Gap between the field and the panel.
  static const double _gap = 4;

  /// Screen margins the panel never crosses.
  static const double _screenMarginX = 16;
  static const double _screenMarginY = 8;

  late final ScrollController _scrollController;
  late final Rect _panelRect;

  @override
  void initState() {
    super.initState();
    final Size screen = widget.screenSize;
    final double contentHeight =
        widget.items.length * widget.itemHeight + _listVerticalPadding * 2;
    final double maxPanelHeight = screen.height * 0.6;
    final double belowSpace = screen.height -
        _screenMarginY -
        (widget.buttonRect.bottom + _gap);
    final double aboveSpace =
        widget.buttonRect.top - _gap - _screenMarginY;
    final double height;
    final double top;
    if (contentHeight <= belowSpace) {
      height = contentHeight;
      top = widget.buttonRect.bottom + _gap;
    } else if (aboveSpace > belowSpace) {
      height = math.min(
          contentHeight, math.min(maxPanelHeight, math.max(aboveSpace, 0)));
      top = widget.buttonRect.top - _gap - height;
    } else {
      height = math.min(
          contentHeight, math.min(maxPanelHeight, math.max(belowSpace, 0)));
      top = widget.buttonRect.bottom + _gap;
    }
    // Horizontal: anchored at the field (its left edge, or its right
    // edge in RTL), clamped into the screen margins.
    final double anchoredLeft = widget.textDirection == TextDirection.rtl
        ? widget.buttonRect.right - widget.panelWidth
        : widget.buttonRect.left;
    final double left = anchoredLeft.clamp(
      _screenMarginX,
      math.max(_screenMarginX, screen.width - _screenMarginX - widget.panelWidth),
    );
    _panelRect = Rect.fromLTWH(left, top, widget.panelWidth, height);
    // Start scrolled so the selected row is visible with one row of
    // context above it (the framework aligns the selected row with
    // the field instead; with the panel offset below/above the field
    // that alignment is impossible, so proximity is what is kept).
    final double maxExtent = math.max(0.0, contentHeight - height);
    final double initialOffset = widget.selectedIndex <= 0
        ? 0.0
        : (_listVerticalPadding +
                (widget.selectedIndex - 1) * widget.itemHeight)
            .clamp(0.0, maxExtent);
    _scrollController = ScrollController(initialScrollOffset: initialOffset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildRow(BuildContext context, int index) {
    final DropdownMenuItem<T> item = widget.items[index];
    final bool selected = index == widget.selectedIndex;
    // Framework menu-item metrics: the item in a 48 px row with
    // 16 px horizontal padding (the item itself aligns its child).
    Widget row = SizedBox(
      height: widget.itemHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: item,
      ),
    );
    if (selected) {
      // What the framework paints behind the selected item in touch
      // highlight mode: an Ink in the theme's focus colour.
      row = Ink(color: Theme.of(context).focusColor, child: row);
    }
    if (item.enabled) {
      row = InkWell(
        onTap: () {
          item.onTap?.call();
          Navigator.of(context).pop(_FrostedDropdownResult<T>(item.value));
        },
        child: row,
      );
    }
    return row;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    // The card dialog's own panel values (see LiquidGlassTheme's
    // dialogTheme and _FrostedDialogBackdrop): the saturate → blur
    // pipeline at blur 14 / saturate 1.3, the translucent dialog
    // tint, and the dialog shape's fine bright border (white α0.60
    // light / α0.26 dark, 1 px). The radius is 28 — the dialog's 32
    // scaled to the smaller panel, inside the same family.
    final BorderRadius radius = BorderRadius.circular(28);
    final Color tint = isDark
        ? const Color(0xFF2A2D3E).withValues(alpha: 0.66)
        : Colors.white.withValues(alpha: 0.55);
    final Color borderColor =
        Colors.white.withValues(alpha: isDark ? 0.26 : 0.60);
    return Stack(
      children: <Widget>[
        Positioned.fromRect(
          rect: _panelRect,
          child: Container(
            key: const ValueKey<String>('frostedDropdownPanel'),
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color:
                      Colors.black.withValues(alpha: isDark ? 0.45 : 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  children: <Widget>[
                    // Real frost: the dialog backdrop pipeline, then
                    // the dialog tint over the blurred backdrop.
                    Positioned.fill(
                      child: BackdropFilter(
                        filter: liquidGlassBackdrop(
                            blurSigma: 14, saturation: 1.3),
                        child: Container(color: tint),
                      ),
                    ),
                    DefaultTextStyle(
                      style: widget.textStyle,
                      child: Scrollbar(
                        controller: _scrollController,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              vertical: _listVerticalPadding),
                          itemExtent: widget.itemHeight,
                          itemCount: widget.items.length,
                          itemBuilder: _buildRow,
                        ),
                      ),
                    ),
                    // Fine bright border, drawn above the rows like
                    // FrostedSurface's, so the edge stays defined.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: radius,
                            border: Border.all(color: borderColor, width: 1),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Restyles a Material 3 [ThemeData] into iOS 26 Liquid Glass:
/// transparent scaffolds (so [GlassBackground] shows through), glassy
/// cards/app bars/dialogs/sheets, capsule buttons and navigation,
/// enlarged corner radii, highlight borders and soft shadows.
extension LiquidGlassTheme on ThemeData {
  ThemeData liquidGlass() {
    final isDark = brightness == Brightness.dark;
    final glassFill =
        isDark ? Colors.white.withValues(alpha: 0.09) : Colors.white.withValues(alpha: 0.34);
    final glassStrong =
        isDark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.55);
    final glassBorder = Colors.white.withValues(alpha: isDark ? 0.26 : 0.60);
    final capsule = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
    );
    final bigRadius = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
    );

    return copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      // v1.2: DropdownButton menus are painted by the framework with
      // ThemeData.canvasColor (checked in the SDK source), so a
      // translucent canvas colour is what makes every dropdown menu in
      // the app frosted-tinted instead of an opaque slab. The menu
      // route paints itself and accepts no BackdropFilter, so this is
      // a tint, not a real blur — see CHANGES-GUI-v1.2.md.
      canvasColor: isDark
          ? const Color(0xFF262939).withValues(alpha: 0.88)
          : Colors.white.withValues(alpha: 0.80),
      appBarTheme: appBarTheme.copyWith(
        // v1.2: fully transparent so the GlassBackground gradient runs
        // uninterrupted from the status bar through the app bar into
        // the body (v1.1 painted a white α0.20 strip here, which read
        // as a visible band with a different chroma than the body).
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      cardTheme: cardTheme.copyWith(
        color: glassFill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: glassBorder, width: 1),
        ),
      ),
      dialogTheme: dialogTheme.copyWith(
        // v1.2: properly translucent — dialogs are shown through
        // showFrostedDialog, which blurs the page behind them, so the
        // panel only needs to tint the blurred backdrop (frosted
        // glass). v1.1's α0.86 white read as a solid slab and hid the
        // blur entirely.
        backgroundColor: isDark
            ? const Color(0xFF2A2D3E).withValues(alpha: 0.66)
            : Colors.white.withValues(alpha: 0.55),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
          side: BorderSide(color: glassBorder, width: 1),
        ),
      ),
      bottomSheetTheme: bottomSheetTheme.copyWith(
        backgroundColor:
            isDark ? const Color(0xE62A2D3E) : Colors.white.withValues(alpha: 0.88),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      popupMenuTheme: popupMenuTheme.copyWith(
        color: isDark
            ? const Color(0xFF2A2D3E).withValues(alpha: 0.84)
            : Colors.white.withValues(alpha: 0.80),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: glassBorder, width: 1),
        ),
      ),
      // v1.2: MenuAnchor menus (e.g. the "+" create menus on the saved
      // cards page) get the same frosted tint, a rounded shape and a
      // fine border instead of the stock opaque surface.
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(
            isDark
                ? const Color(0xFF262939).withValues(alpha: 0.88)
                : Colors.white.withValues(alpha: 0.80),
          ),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shadowColor: WidgetStateProperty.all(
              Colors.black.withValues(alpha: isDark ? 0.35 : 0.15)),
          elevation: WidgetStateProperty.all(10),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: glassBorder, width: 1),
            ),
          ),
        ),
      ),
      navigationRailTheme: navigationRailTheme.copyWith(
        // Transparent: in main.dart the rail now sits inside a real
        // GlassContainer, which provides the glass surface itself.
        backgroundColor: Colors.transparent,
        elevation: 0,
        // v2.11: the framework's per-destination indicator is no
        // longer painted — main.dart draws a single sliding glass
        // lens over the selected destination instead. The colour is
        // transparent (the indicator widget still runs its scale /
        // fade animation, invisibly); the shape below still serves
        // as the destinations' ink-splash clip, so tap ripples keep
        // their capsule outline. (NavigationBar below keeps its own
        // visible indicator — it has no lens.)
        //
        // v2.12: the shape must carry NO side. ShapeDecoration
        // paints a shape's border independently of its fill colour,
        // so the v2.11 shape's 1 px glassBorder side kept drawing
        // the old 56×32 capsule outline *inside* the lens even with
        // the fill transparent — the owner's screenshot showed
        // exactly that double outline. The splash clip uses only
        // the shape's outer path (its borderRadius), never the
        // side, so dropping the side changes nothing about the
        // ripples.
        indicatorColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        selectedIconTheme: IconThemeData(color: colorScheme.primary, size: 26),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: navigationBarTheme.copyWith(
        backgroundColor: Colors.white.withValues(alpha: isDark ? 0.08 : 0.25),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.30),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: glassBorder, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: capsule,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: glassStrong,
          foregroundColor: colorScheme.onSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: glassBorder, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          elevation: 0,
          shadowColor: Colors.black.withValues(alpha: 0.10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: capsule,
          side: BorderSide(color: glassBorder, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          backgroundColor: Colors.white.withValues(alpha: isDark ? 0.05 : 0.18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: capsule),
      ),
      floatingActionButtonTheme: floatingActionButtonTheme.copyWith(
        backgroundColor: colorScheme.primary.withValues(alpha: 0.85),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: glassBorder, width: 1),
        ),
      ),
      chipTheme: chipTheme.copyWith(
        backgroundColor: glassFill,
        selectedColor: colorScheme.primary.withValues(alpha: 0.28),
        surfaceTintColor: Colors.transparent,
        side: BorderSide(color: glassBorder, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      inputDecorationTheme: inputDecorationTheme.copyWith(
        filled: true,
        fillColor: Colors.white.withValues(alpha: isDark ? 0.07 : 0.30),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      listTileTheme: listTileTheme.copyWith(
        shape: bigRadius,
        tileColor: Colors.transparent,
      ),
      dividerTheme: dividerTheme.copyWith(
        color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.45),
        thickness: 1,
      ),
      snackBarTheme: snackBarTheme.copyWith(
        backgroundColor:
            isDark ? const Color(0xE62A2D3E) : Colors.white.withValues(alpha: 0.9),
        contentTextStyle: TextStyle(color: colorScheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: glassBorder, width: 1),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
    );
  }
}
