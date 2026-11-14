import 'package:flutter/material.dart';
import 'package:chameleonultragui/main.dart';

ButtonStyle customCardButtonStyle(ChameleonGUIState appState) {
  // iOS 26 Liquid Glass (Muse v1.1): the button is a small glass lens.
  // Resting: translucent theme-colour fill, soft specular rim.
  // Pressed: the material "energizes with light" like real Liquid
  // Glass — the rim lights up (brighter, slightly thicker), a white
  // illumination glows from within via the overlay, and the fill
  // deepens. Behaviour and layout stay untouched.
  //
  // v2.9 (dark-theme red-card fix): the complementary-colour table
  // (helpers/colors.dart) encodes its strength in the alpha channel —
  // the light row is near-white pastels at full alpha, the dark row is
  // saturated hues at alpha 16–50/255 (≈0.06–0.20), designed to be laid
  // over a dark surface *verbatim* (as upstream did) so only a whisper
  // of hue shows. The v1.1 rewrite above replaced that alpha with
  // 0.36/0.48/0.62 via withValues(alpha:), which is harmless for the
  // pastel row but turns the dark row's saturated RGB (e.g.
  // (202, 43, 43) for the default colour scheme) into a solid
  // wine-red block at 36–62% opacity — the owner’s dark-theme cards
  // came out saturated red regardless of the page’s dark-purple glass.
  // Fix: in dark mode the fill is a neutral dark-glass tint (white at
  // low alpha, the same family as the theme’s dark card fill and the
  // FrostedSurface tints), stepped up for hover/press; the theme hue
  // survives only in the icons/accents, never as a saturated fill.
  // The light branch below keeps the v1.1 values verbatim.
  final base = appState.sharedPreferencesProvider.getThemeComplementaryColor();
  final themeMode = appState.sharedPreferencesProvider.getTheme();
  final isDark = themeMode == ThemeMode.dark ||
      (themeMode == ThemeMode.system &&
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark);
  Color fill(double lightAlpha, double darkAlpha) => isDark
      ? Colors.white.withValues(alpha: darkAlpha)
      : base.withValues(alpha: lightAlpha);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith<Color>(
      (Set<WidgetState> states) {
        if (states.contains(WidgetState.pressed)) {
          return fill(0.62, 0.22);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return fill(0.48, 0.16);
        }
        return fill(0.36, 0.10);
      },
    ),
    // Illumination: light emitted from inside the glass on interaction.
    overlayColor: WidgetStateProperty.resolveWith<Color>(
      (Set<WidgetState> states) {
        if (states.contains(WidgetState.pressed)) {
          return Colors.white.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return Colors.white.withValues(alpha: 0.06);
        }
        return Colors.transparent;
      },
    ),
    // Specular rim: brightens and thickens under the fingertip.
    side: WidgetStateProperty.resolveWith<BorderSide>(
      (Set<WidgetState> states) {
        if (states.contains(WidgetState.pressed)) {
          return BorderSide(
            color: Colors.white.withValues(alpha: 0.95),
            width: 1.3,
          );
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return BorderSide(
            color: Colors.white.withValues(alpha: 0.75),
            width: 1.1,
          );
        }
        return BorderSide(
          color: Colors.white.withValues(alpha: 0.55),
          width: 1.0,
        );
      },
    ),
    surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
    elevation: WidgetStateProperty.all(0),
    // Ambient-tinted shadow colour (only visible if a call site raises
    // elevation): the shadow picks up the glass's own colour instead of
    // flat grey-black. v2.9: neutral in dark mode, for the same reason
    // as the fill above (a saturated-hue shadow would glow red).
    shadowColor: WidgetStateProperty.all(isDark
        ? Colors.black.withValues(alpha: 0.25)
        : base.withValues(alpha: 0.25)),
    shape: WidgetStateProperty.all<RoundedRectangleBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24.0),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.55),
          width: 1.0,
        ),
      ),
    ),
  );
}
