import 'dart:io';
import 'dart:math' as math;
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/connector/serial_macos.dart';
import 'package:chameleonultragui/gui/component/glass.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/gui/page/plugins.dart';
import 'package:chameleonultragui/helpers/font.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'connector/serial_native.dart';

// Page imports
import 'package:chameleonultragui/gui/page/home.dart';
import 'package:chameleonultragui/gui/page/saved_cards.dart';
import 'package:chameleonultragui/gui/page/settings.dart';
import 'package:chameleonultragui/gui/page/connect.dart';
import 'package:chameleonultragui/gui/page/debug.dart';
import 'package:chameleonultragui/gui/page/slot_manager.dart';
import 'package:chameleonultragui/gui/page/flashing.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/gui/page/pending_connection.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Shared Preferences Provider
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Logger
import 'package:logger/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferencesProvider = SharedPreferencesProvider();
  await sharedPreferencesProvider.load();
  runApp(ChameleonGUI(sharedPreferencesProvider));
}

class ChameleonGUI extends StatelessWidget {
  // Root Widget
  final SharedPreferencesProvider _sharedPreferencesProvider;
  const ChameleonGUI(this._sharedPreferencesProvider, {super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _sharedPreferencesProvider),
        ChangeNotifierProvider(
          create: (context) => ChameleonGUIState(_sharedPreferencesProvider),
        ),
      ],
      child: MainPage(sharedPreferencesProvider: _sharedPreferencesProvider),
    );
  }
}

class ChameleonGUIState extends ChangeNotifier {
  final SharedPreferencesProvider sharedPreferencesProvider;
  ChameleonGUIState(this.sharedPreferencesProvider);

  SharedPreferencesProvider? _sharedPreferencesProvider;
  Logger? log; // Logger

  // Android uses AndroidSerial, iOS can only use BLESerial
  // The rest (desktops?) can use NativeSerial
  AbstractSerial? connector;
  ChameleonCommunicator? communicator;

  bool devMode = false;
  double? progress; // DFU

  // Flashing easter egg
  bool easterEgg = false;
  dynamic _suppressedAutoReconnectPort;

  GlobalKey navigationRailKey = GlobalKey();
  Size? navigationRailSize;

  void changesMade() {
    notifyListeners();
  }

  void onConnectorStateChanged() {
    if (connector == null || !connector!.connected) {
      communicator = null;
      progress = null;
    }
    notifyListeners();
  }

  bool isAutoReconnectSuppressed(dynamic devicePort) {
    return _suppressedAutoReconnectPort == devicePort;
  }

  void clearAutoReconnectSuppression([dynamic devicePort]) {
    if (devicePort == null || _suppressedAutoReconnectPort == devicePort) {
      _suppressedAutoReconnectPort = null;
    }
  }

  void syncAutoReconnectSuppression(Iterable<dynamic> visiblePorts) {
    if (_suppressedAutoReconnectPort == null) {
      return;
    }

    for (final port in visiblePorts) {
      if (port == _suppressedAutoReconnectPort) {
        return;
      }
    }

    _suppressedAutoReconnectPort = null;
  }

  Future<void> disconnect({bool manual = false}) async {
    final suppressedPort = manual ? connector?.activeDevicePort : null;
    await connector?.performDisconnect();
    if (manual && suppressedPort != null) {
      _suppressedAutoReconnectPort = suppressedPort;
    }
    communicator = null;
    progress = null;
    notifyListeners();
  }

  void setProgressBar(dynamic value) {
    progress = value;
    notifyListeners();
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.sharedPreferencesProvider});

  final SharedPreferencesProvider sharedPreferencesProvider;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  var selectedIndex = 0;

  // The sidebar's expansion state lives inside _LiquidRail (v2.2):
  // the rail starts collapsed (icons only), follows the finger with
  // rubber-band resistance, springs open/closed, and collapses again
  // as soon as any destination is tapped. The old persisted
  // preferences (sidebar_expanded / sidebar_auto_expanded) are no
  // longer read by the UI; the settings page offers no option either.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => updateNavigationRailWidth(context));
  }

  @override
  void reassemble() async {
    // Disconnect on reload
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    await appState.disconnect();

    super.reassemble();
  }

  AbstractSerial getConnector(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isEmulatedChameleon()) {
      return EmulatorSerial(log: appState.log!);
    }

    if (Platform.isMacOS) {
      return MacOSSerial(log: appState.log!);
    }

    if (Platform.isAndroid) {
      return AndroidSerial(log: appState.log!);
    }

    if (Platform.isIOS) {
      return BLESerial(log: appState.log!);
    }

    return NativeSerial(log: appState.log!);
  }

  Logger getLogger(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isDebugLogging() &&
        appState._sharedPreferencesProvider!.isDebugMode()) {
      return Logger(
        output: SharedPreferencesLogger(appState._sharedPreferencesProvider!),
        printer: PrettyPrinter(
          noBoxingByDefault: true,
        ),
        filter: ChameleonLogFilter(),
      );
    } else {
      return Logger();
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    appState._sharedPreferencesProvider = widget.sharedPreferencesProvider;
    appState.log ??= getLogger(appState);
    appState.connector ??= getConnector(appState);
    appState.connector!.connectionStateCallback =
        appState.onConnectorStateChanged;

    appState.devMode = appState.sharedPreferencesProvider.isDebugMode();

    Widget page; // Set Page
    if (!appState.connector!.connected &&
        selectedIndex != 0 &&
        selectedIndex != 2 &&
        selectedIndex != 5 &&
        selectedIndex != 6 &&
        selectedIndex != 7 &&
        selectedIndex != 8) {
      // Offline pages remain available without a device.
      selectedIndex = 0;
    }

    switch (selectedIndex) {
      // Sidebar Navigation
      case 0:
        if (appState.connector!.pendingConnection) {
          page = const PendingConnectionPage();
        } else {
          if (appState.connector!.connected) {
            if (appState.connector!.isDFU) {
              page = const FlashingPage();
            } else {
              page = const HomePage();
            }
          } else {
            page = const ConnectPage();
          }
        }
        break;
      case 1:
        page = const SlotManagerPage();
        break;
      case 2:
        page = const SavedCardsPage();
        break;
      case 3:
        page = const ReadCardPage();
        break;
      case 4:
        page = const WriteCardPage();
        break;
      case 5:
        page = const ToolsPage();
        break;
      case 6:
        page = const PluginsPage();
        break;
      case 7:
        page = const SettingsMainPage();
        break;
      case 8:
        page = const DebugPage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    try {
      WakelockPlus.toggle(enable: page is FlashingPage);
    } catch (_) {}

    return MaterialApp(
      title: 'Chameleon Ultra GUI', // App Name
      locale: widget.sharedPreferencesProvider.getLocale(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: widget.sharedPreferencesProvider.getThemeColor()),
        brightness: Brightness.light,
        appBarTheme: AppBarTheme(
            systemOverlayStyle: SystemUiOverlayStyle(
                // v1.2: transparent so the GlassBackground gradient
                // shows through the status bar as well — v1.1 painted
                // the solid surface colour here, which produced a
                // visible band at the top of the screen whose chroma
                // did not match the app background.
                statusBarColor: Colors.transparent,
                statusBarBrightness: Brightness.light,
                statusBarIconBrightness: Brightness.dark)),
      ).useCustomSystemFont(Brightness.light).liquidGlass(),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: widget.sharedPreferencesProvider.getThemeColor(),
            brightness: Brightness.dark),
        brightness: Brightness.dark,
        appBarTheme: AppBarTheme(
            systemOverlayStyle: SystemUiOverlayStyle(
                // v1.2: transparent, same as the light theme above.
                statusBarColor: Colors.transparent,
                statusBarBrightness: Brightness.dark,
                statusBarIconBrightness: Brightness.light)),
      ).useCustomSystemFont(Brightness.dark).liquidGlass(),
      themeMode: widget.sharedPreferencesProvider.getTheme(), // Dark Theme
      home: GlassBackground(
          child: LayoutBuilder(// Build Page
          builder: (context, constraints) {
        return SafeArea(
          left: false,
          right: false,
          top: false,
          bottom: true,
          child: Scaffold(
              backgroundColor: Colors.transparent,
              // v2.3: Stack instead of the v2.2 Row. The page layer is
              // pinned to the rail's *collapsed* footprint (its left
              // edge never moves), and the rail floats on top of it:
              // while the rail animates, the page is not laid out
              // again — v2.2 resized the page every frame of a drag,
              // which re-ran every frosted backdrop filter on the
              // page and dropped frames. At rest the geometry is
              // identical to v2.2 (see _LiquidRail.restFootprint);
              // while expanded, the rail overlays the page's left
              // strip like a drawer until a destination is picked.
              body: Stack(
                children: [
                  // v2.16: the page wash is a full-screen layer under
                  // everything in the body. Through v2.15 it lived on
                  // the page layer alone (a Container around the page),
                  // so it began abruptly at the page's left edge
                  // (x = _LiquidRail.restFootprint): the narrow strip
                  // behind/around the rail showed the raw
                  // GlassBackground while the page area showed
                  // background + wash, and the join read as a
                  // full-height colour seam beside the rail in both
                  // themes (an RGB step at x≈94, measured on the
                  // owner's screenshots). The colour expression below
                  // is identical to the old page-layer tint, so every
                  // pixel at x ≥ restFootprint composes exactly as in
                  // v2.15; only the strip left of it gains the wash,
                  // and the seam disappears. The DFU layout (page
                  // spanning the full width, rail hidden) composes
                  // identically too: wash-everywhere under an untinted
                  // full-width page equals the old full-width page
                  // carrying the wash itself.
                  Positioned.fill(
                    child: Container(
                      // Liquid Glass: let the colourful background shine
                      // through a translucent tint instead of a solid fill.
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.22),
                    ),
                  ),
                  Positioned(
                    left: (!appState.connector!.isDFU ||
                            !appState.connector!.connected)
                        ? _LiquidRail.restFootprint
                        : 0,
                    top: 0,
                    right: 0,
                    bottom: 0,
                    // v2.13: repaint isolation between the two layers.
                    // Without a boundary both layers record into the
                    // same picture, so every rail animation frame also
                    // re-rasterised the page (and vice versa). The
                    // boundary changes nothing geometrically — the
                    // rail's backdrop filters still sample the page
                    // beneath them, compositing order is unchanged —
                    // it only lets the compositor reuse the untouched
                    // layer's picture.
                    // v2.16: the boundary now wraps the page directly —
                    // the wash it used to carry lives on the full-screen
                    // layer at the bottom of this Stack (see above).
                    child: RepaintBoundary(
                      child: page,
                    ),
                  ),
                  if (!appState.connector!.isDFU ||
                      !appState.connector!.connected)
                    Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        // v2.13: the rail layer gets the matching
                        // repaint boundary (see the page layer above),
                        // so page updates don't re-rasterise the rail
                        // either.
                        child: RepaintBoundary(
                          child: SafeArea(
                          // Liquid Glass: the navigation rail floats on
                          // a real glass pane and is fully gesture-driven
                          // (see _LiquidRail): it follows the finger,
                          // rubber-bands at the ends and springs shut
                          // when a destination is picked.
                          child: _LiquidRail(
                            railKey: appState.navigationRailKey,
                            selectedIndex: selectedIndex,
                            onDestinationSelected: (value) {
                              setState(() {
                                selectedIndex = value;
                              });
                            },
                            destinations: [
                              // Sidebar Items
                              NavigationRailDestination(
                                icon: _JellyRailIcon(
                                    icon: Icons.home,
                                    selected: selectedIndex == 0),
                                label: Text(
                                    AppLocalizations.of(context)!.home,
                                    // v2.7: never wrap (see _LiquidRail).
                                    softWrap: false,
                                    overflow: TextOverflow.clip), // Home
                              ),
                              NavigationRailDestination(
                                disabled: !appState.connector!.connected,
                                icon: _JellyRailIcon(
                                    icon: Icons.widgets,
                                    selected: selectedIndex == 1),
                                label: Text(
                                    AppLocalizations.of(context)!.slot_manager,
                                    softWrap: false,
                                    overflow: TextOverflow.clip),
                              ),
                              NavigationRailDestination(
                                icon: _JellyRailIcon(
                                    icon: Icons.auto_awesome_motion,
                                    selected: selectedIndex == 2),
                                label: Text(
                                    AppLocalizations.of(context)!.saved_cards,
                                    softWrap: false,
                                    overflow: TextOverflow.clip),
                              ),
                              NavigationRailDestination(
                                disabled: !appState.connector!.connected,
                                icon: _JellyRailIcon(
                                    icon: Icons.sensors,
                                    selected: selectedIndex == 3),
                                label: Text(
                                    AppLocalizations.of(context)!.read_card,
                                    softWrap: false,
                                    overflow: TextOverflow.clip),
                              ),
                              NavigationRailDestination(
                                disabled: !appState.connector!.connected,
                                icon: _JellyRailIcon(
                                    icon: Icons.system_update_alt,
                                    selected: selectedIndex == 4),
                                label: Text(
                                    AppLocalizations.of(context)!.write_card,
                                    softWrap: false,
                                    overflow: TextOverflow.clip),
                              ),
                              NavigationRailDestination(
                                icon: _JellyRailIcon(
                                    icon: Icons.handyman,
                                    selected: selectedIndex == 5),
                                label: Text(
                                    AppLocalizations.of(context)!.tools,
                                    softWrap: false,
                                    overflow: TextOverflow.clip),
                              ),
                              NavigationRailDestination(
                                icon: _JellyRailIcon(
                                    icon: Icons.extension,
                                    selected: selectedIndex == 6),
                                label: Text(AppLocalizations.of(context)!.plugins,
                                    softWrap: false,
                                    overflow: TextOverflow.clip),
                              ),
                              NavigationRailDestination(
                                icon: _JellyRailIcon(
                                    icon: Icons.settings,
                                    selected: selectedIndex == 7),
                                label: Text(
                                    AppLocalizations.of(context)!.settings,
                                    softWrap: false,
                                    overflow: TextOverflow.clip),
                              ),
                              if (appState.devMode)
                                NavigationRailDestination(
                                  icon: _JellyRailIcon(
                                      icon: Icons.bug_report,
                                      selected: selectedIndex == 8),
                                  label: Text(
                                      '🐞 ${AppLocalizations.of(context)!.debug} 🐞',
                                      softWrap: false,
                                      overflow: TextOverflow.clip),
                                ),
                            ],
                          ),
                        ),
                        )),
                ],
              ),
              bottomNavigationBar: const BottomProgressBar()),
        );
      })),
    );
  }
}

/// The liquid navigation rail (v2.2, gesture fixes in v2.3).
///
/// Interaction model (all state is local to this widget; rebuilds are
/// scoped to the rail subtree via [AnimatedBuilder]):
/// - One unbounded [AnimationController] holds the *display progress*
///   (0 = collapsed at 80 px, 1 = extended at 256 px — the framework's
///   M3 rail widths). Rubber-banding and spring overshoot may push it
///   slightly outside [0, 1] while moving.
/// - Dragging drives the value directly from the accumulated finger
///   displacement, so the capsule follows the finger. Past either end
///   the value is rubber-banded (resistance grows as you pull), and
///   the glass pane stretches a little — the liquid pull.
/// - On release, a [SpringSimulation] (stiffness 175, damping 24.5,
///   ζ ≈ 0.93 → a decisive settle with only a sub-pixel overshoot;
///   damping was 20.5 / ζ ≈ 0.77 through v2.13 — see the v2.14 note
///   below) carries it to a stable state; tapping any destination
///   springs it shut the same way.
/// - The framework rail is kept stock and (v2.15) *permanently
///   extended*: it always lays out at the fixed 256 px width, and
///   the outer [SizedBox] + clip alone decide how much of it is
///   visible — collapse and expansion are pure clipping of a layout
///   that never changes. (Through v2.14 `extended` flipped with
///   hysteresis past the midpoint and the layout stepped between
///   80 and 256; see the v2.15 note below.) The default selection
///   indicator is unchanged; the tapped icon adds a jelly pulse (see
///   [_JellyRailIcon]).
/// - With system reduce-motion on, springs are skipped and the rail
///   jumps straight to the settled state.
///
/// v2.3 changes (real-device feedback on v2.2: swipes often failed to
/// open the rail, and dragging stuttered):
/// - Release decisions are made against the stable state the drag
///   started from, with a wider commit zone: from collapsed, p ≥ 0.30
///   or an effective fling ≥ 0.7 progress/s opens; from expanded,
///   p ≤ 0.70 or ≤ −0.7 closes. v2.2 demanded p ≥ 0.5 or > 1.4/s.
/// - The release velocity no longer trusts the framework's
///   primaryVelocity alone (it reads ≈0 for short flicks): the drag
///   keeps its own samples of the last ~100 ms of finger travel and
///   the larger same-direction value wins, for both the decision and
///   the spring's initial velocity.
/// - The rail floats over the page (Stack in [_MainPageState])
///   instead of resizing it, so a drag no longer re-lays-out the
///   whole page every frame. While the rail moves, its glass runs
///   cheap: sheen drift paused, blur sigma 16 → 10.
/// - The gesture detector wraps the pane *including* its margins,
///   so a finger landing on the margin strip still grabs the rail.
///
/// v2.4 changes (owner asked for asymmetric gestures):
/// - Closing is threshold-free: while the rail is not fully
///   collapsed, a drag whose net travel reaches the arena slop
///   (≈18 px) leftwards springs it shut *immediately*, mid-drag —
///   no release decision and no minimum distance or speed beyond
///   the arena's own. Once committed, the rest of that drag is
///   ignored, and a release that still ends net-leftwards closes
///   too; only net-rightward drags return to open.
/// - Opening keeps the v2.3 thresholds untouched (p ≥ 0.30 or an
///   effective fling ≥ 0.7 progress/s on release).
///
/// v2.5 changes (owner: label layout must stay fixed during the
/// transition — at intermediate widths "已保存的卡片" wrapped to two
/// lines and labels drifted sideways):
/// - The framework rail now lays out at a *fixed* width per latch
///   state (80 collapsed / 256 extended, stepped by the latch); only
///   the outer glass width animates with p, and the clip reveals or
///   hides the already-laid-out labels. Text is never re-measured,
///   re-wrapped or re-positioned per frame. (This supersedes the
///   "destinations stay centred while collapsed" behaviour above:
///   the destinations no longer drift with the pane width.)
/// - Geometry, checked against this SDK's NavigationRail source:
///   in both rest layouts the destination group spans the full rail
///   width and the icon sits at x = 40 (collapsed: centred in the
///   80 px group; extended: first cell of the destination row,
///   indicator offset = minWidth/2). During the framework's own
///   200 ms extended transition, though, the group is still
///   narrower than 256 (its min-width lerps 80 → 256) and is
///   *centred* in the 256 px rail, which would swing the icon out
///   to x = 128 and back. A replica of that animation (same
///   200 ms, same easeInOut, driven by the same latch flips)
///   translates the inner rail left by (256 − groupWidth)/2 while
///   the latch is extended, pinning the icon at x = 40 for the
///   whole transition. Collapsing needs no compensation: stepping
///   back to the tight 80 px width clamps the group to 80, so the
///   icon stays at 40 and the labels clip to a zero-width slot
///   instead of rewrapping.
///
/// v2.7 changes (owner's recording of v2.6: icons still moved on
/// collapse — vertically this time):
/// - The zero-width slot was not harmless: during the framework's
///   200 ms reverse transition in the tight 80 px layout, each
///   destination's label gets zero flex width and wraps to one
///   character per line; the label sits in an Align with
///   heightFactor 1.0 inside the destination's Row, so the wrapped
///   stack inflates the destination's height (卡槽管理 4 chars →
///   +20 px, 已保存的卡片 6 chars → +52 px) and every icon below
///   is pushed down cumulatively — measured +10/+46/+72 px on the
///   recording, constant for the whole transition, then a snap
///   back when t reaches 0. The wide layout therefore now outlives
///   the latch on the way down: it steps to 80 only once the
///   transition replica reaches 0, in the same frame the framework
///   switches to its t == 0 branch (identical icon geometry), and
///   the centring compensation runs whenever the layout is wide.
/// - Backstop: the destinations' label Texts are built with
///   softWrap: false + overflow: clip (in _MainPageState), so a
///   label can never wrap — and never inflate a destination — in
///   any layout width. Rest-state appearance is unchanged (the
///   labels are single-line at 256 px either way).
/// - Verified by a widget test driving this exact code (see
///   CHANGES-GUI-v2.7.md): the v2.6 code reproduces the measured
///   +10/+46/+72 px drift; with these changes the drift is 0.
///
/// v2.11 changes (owner: the selection capsule should behave like
/// the iOS 26 tab-bar lens in the reference video — a real sliding
/// liquid-glass lens; this is the self-drawn indicator v2.2 deferred):
/// - The framework's per-destination indicator is switched off in
///   the theme (glass.dart: indicatorColor is transparent — it only
///   ever cross-faded in place). A single self-drawn glass lens now
///   lives in the same Stack as the framework rail, *under* it, so
///   it inherits the fixed-width layout, the clip and the centring
///   compensation, and its backdrop blur samples the pane and the
///   page — never the destinations painted above it.
/// - The lens *slides*: an unbounded controller holds its centre Y
///   in px and the same 175/24.5 spring carries it between
///   destination centres (30 + 44·i, derived from the SDK's rail
///   metrics and verified by measurement in the test harness).
///   While it moves fast it stretches along Y (skin-only Transform,
///   capped at +30%) and narrows slightly, like the video.
/// - Its width follows the extended replica: a 60 px stadium over
///   the icon when collapsed, growing to a full-row pill (12 px
///   insets of the 256 layout) when extended.
/// - The selected icon is magnified ×1.2 on the same spring (see
///   [_JellyRailIcon]); the jelly pulse still handles the tap
///   instant. Selected icon/label colours were already the theme
///   primary via the rail theme.
/// - A vertical drag on the rail scrubs the lens with the finger
///   (the framework gesture arena decides the axis first, so the
///   horizontal expand/collapse gestures keep priority on
///   horizontal drags); on release the lens springs to the nearest
///   enabled destination and selects it through the same
///   [_handleSelected] path as a tap.
///
/// v2.13 changes (owner: the expand animation stuttered — width
/// advancing in visible steps on the device recording):
/// - Pure performance; every behaviour and every resting pixel is
///   unchanged. A frame-cost audit (see CHANGES-GUI-v2.13.md) found
///   the merged AnimatedBuilder reconstructing the framework rail
///   and its whole destination cascade on every tick of any of its
///   three controllers (harness count: 119 rail constructions over
///   one 349-frame expand), while two saturate→blur backdrop
///   filters (pane + lens) re-ran per frame over areas that *grow*
///   during an expand — the asymmetry the owner felt.
/// - The framework rail is now cached (see [_railWidget]) and only
///   rebuilt when the latch, the destinations or the selection
///   change; the in-motion backdrop sigmas drop further (pane
///   10 → 8, lens 8 → 0 — saturation pass only), the resting values
///   are untouched; liquidGlassBackdrop memoises its filters so a
///   rebuild alone no longer forces a backdrop repaint; and the
///   page/rail layers in _MainPageState each got a RepaintBoundary
///   so one layer's animation no longer re-rasterises the other.
///
/// v2.14 changes (owner: v2.13 felt identical — the rail still
/// hitched once per transition, and the owner located the hitch at
/// the *tail* of the motion, just before it stops):
/// - The v2.14 audit (AUDIT-v2.14.md) measured the owner's v2.13
///   recording frame by frame (678 frames): the pane width never
///   froze at any deterministic event — latch flips, the layout
///   step and even the framework's destination remount frame all
///   passed inside the frame budget — and v2.13's steady-state
///   cost cuts changed nothing the owner could feel. The one
///   phenomenon present in *every* transition, matching the
///   owner's tail localisation exactly, was the spring itself:
///   at ζ ≈ 0.77 every expand overshot to p ≈ 1.033 and then
///   spent ~0.5 s visibly crawling back over the last ~6 px
///   (collapse symmetric). That slow reverse crawl at the tail
///   is the "hitch".
/// - The only change in this version: spring damping 20.5 → 24.5
///   (ζ ≈ 0.77 → ≈0.93), stiffness 175 untouched, applied to
///   both [_spring] and [_JellyRailIcon]'s copy of it. The
///   theoretical overshoot drops to ≈0.04% of the travel
///   (sub-pixel), so the crawl-back disappears with it; the main
///   travel keeps its speed (time to 99% is essentially
///   unchanged — see the numeric check in CHANGES-GUI-v2.14.md).
///   The spring is still under-damped, so the settle stays
///   decisive rather than fading out critically-damped style.
/// - Trade-off, taken deliberately: the visible overshoot was a
///   v2.2 liquid-design feature; at the owner's direction this
///   version gives it up in favour of a clean stop. Everything
///   else — gestures, thresholds, geometry, the lens, v2.13's
///   optimisations — is untouched, so the tail feel can be
///   judged in isolation. (The audit's always-wide-layout
///   prototype, proven frame-equivalent, is deliberately *not*
///   merged here for the same one-variable-at-a-time reason.)
///
/// v2.15 changes (owner: v2.14 fixed the start and the tail, but
/// the *middle* of the transition still stuttered — the expand
/// especially; asked for one more version):
/// - The middle is exactly where the old structure did all of its
///   discrete work: at p ≈ 0.55 the latch flipped, the inner
///   layout stepped 80 → 256, the framework rail switched its
///   `extended` branch (its own 200 ms transition, destination
///   group drifting to centre and back under a replica-compensation
///   translation), and — one framework tick later — every
///   destination's content subtree was unmounted and remounted as
///   the framework's per-destination branch flipped with its
///   transition value (the audit's probe counted 108 element
///   remounts and the single most expensive frame of the cycle).
///   At a 60 fps capture those frames mostly fit the budget; on
///   the owner's high-refresh device the mid-transition is where
///   they stop fitting.
/// - The decisive restructure: the framework rail is now
///   *permanently* `extended: true` and the inner layout is
///   permanently 256 wide. Nothing flips, steps, or remounts
///   mid-transition any more: collapse/expansion is the pane's
///   visible width (unchanged formula) clipping a constant
///   layout, exactly like the glass has always pretended to work.
///   Retired with it: the hysteresis latch, the transition
///   replica and its centring compensation (the destination group
///   never moves, so there is nothing to compensate), and the
///   layout step itself. Rest geometry is unchanged — the SDK
///   puts the extended rail's icon at x = 40, y = 30 + 44·i, the
///   same values the two old rest layouts shared (verified
///   against this SDK's source and by the harness).
/// - The lens's horizontal extent was driven by the retired
///   replica's curve value; it is now driven directly by the
///   clamped progress (t := p clamped to [0, 1]), so mid-flight
///   the lens width tracks the pane's progress exactly instead of
///   the framework's 200 ms easeInOut. The two rest geometries
///   are identical (60 px stadium at [10, 70] collapsed, full-row
///   pill at [12, 244] extended); only the mid-flight timing of a
///   decoration layer differs. Lens Y, sliding, stretch,
///   magnification and scrubbing are untouched (scrubbing only
///   ever used Y).
/// - A side benefit: destination states (including each
///   [_JellyRailIcon]'s jelly/magnification controllers) now
///   survive transitions instead of being destroyed and recreated
///   by the framework's branch remount.
/// - Splash check (SDK source): the destinations' ink well wraps
///   the whole content row in both framework branches, but its
///   splash/highlight rect comes from a rect callback that pins
///   it to the 56×32 indicator rect centred at x = 40 in *both*
///   branches (t == 0 centres it in the 80 px box; t > 0 uses the
///   indicator offset, also 40), clipped by the theme's
///   indicatorShape — so the visible splash is unchanged. What
///   does grow is the ink well's own hit bounds (the full row
///   instead of the icon cell); points beyond the pane's visible
///   width are rejected by the pane's ClipRect before they can
///   reach it, so no clipped-away label area can be tapped.
class _LiquidRail extends StatefulWidget {
  final GlobalKey railKey;
  final List<NavigationRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _LiquidRail({
    required this.railKey,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  /// Total width the rail occupies at rest: the pane's horizontal
  /// margins (10 left + 4 right, see _LiquidRailState._paneMargin)
  /// around the 80 px collapsed pane. [_MainPageState] pins the page
  /// layer's left edge to this so the page keeps the exact position
  /// it had in the v2.2 Row layout while the rail floats over it.
  static const double restFootprint = 10 + 80 + 4;

  @override
  State<_LiquidRail> createState() => _LiquidRailState();
}

/// One sample of the finger's accumulated travel during a drag,
/// used by _LiquidRailState's own velocity estimate (v2.3).
class _DragSample {
  final Duration time;
  final double px;

  const _DragSample(this.time, this.px);
}

class _LiquidRailState extends State<_LiquidRail>
    with TickerProviderStateMixin {
  // NavigationRail M3 default widths in this SDK.
  static const double _collapsedWidth = 80;
  static const double _extendedWidth = 256;
  static const double _range = _extendedWidth - _collapsedWidth;

  // The pane's margin, formerly GlassContainer.margin (v2.2). In
  // v2.3 it is a Padding *inside* the gesture detector, so the drag
  // hot zone covers the full capsule footprint (see restFootprint)
  // while the pane itself sits at exactly the same position.
  static const EdgeInsets _paneMargin = EdgeInsets.fromLTRB(10, 10, 4, 10);

  // Still under-damped but only just (v2.14): damping 24.5 gives
  // ζ ≈ 0.93, so the theoretical overshoot is ≈0.04% of the travel
  // (sub-pixel) and there is no visible crawl-back at the end of a
  // transition. Through v2.13 the damping was 20.5 (ζ ≈ 0.77,
  // ≈2% theoretical overshoot); the owner's recordings measured
  // ≈3.3% followed by a ~0.5 s slow crawl over the last few px,
  // which read as a hitch right at the tail of every transition.
  // Stiffness is unchanged, so the main travel keeps its speed.
  static const SpringDescription _spring =
      SpringDescription(mass: 1, stiffness: 175, damping: 24.5);

  // Release thresholds for *opening* (progress units / progress per
  // second). v2.3 widened them; v2.4 keeps them unchanged — opening
  // stays a thresholded, finger-followed gesture.
  static const double _openPosition = 0.30;
  static const double _flingVelocity = 0.7;

  // v2.4: closing has *no* business threshold. A drag whose net
  // travel reaches this far leftwards commits the close mid-drag.
  // The value is the framework's touch-slop magnitude (kTouchSlop):
  // the smallest displacement the gesture arena itself needs before
  // it will call anything a horizontal drag at all, so it is the
  // floor of "a leftward slide happened", not a tuned threshold.
  static const double _leftCommitPx = 18.0;

  /// How much finger history the rail's own velocity estimate uses.
  static const Duration _velocityWindow = Duration(milliseconds: 100);

  // v2.11 lens geometry, derived from this SDK's NavigationRail
  // source (labelType none, M3) and confirmed by harness
  // measurement of the resting icon centres (pitch 44, first
  // centre 30, in rail coordinates):
  // - the rail's destination group starts below an 8 px
  //   `_verticalSpacer`;
  // - each destination is 6 px spacing + 32 px indicator height
  //   (`_kIndicatorHeight`; it dominates the 24/26 px icon) + 6 px
  //   spacing = a 44 px pitch, so destination i's icon centre sits
  //   at 8 + 6 + 16 + 44·i = 30 + 44·i, horizontally at x = 40 in
  //   both rest layouts (the invariant v2.5/v2.7 rely on).
  static const double _destinationPitch = 44;
  static const double _firstDestinationCenter = 30;

  /// v2.11: the sliding lens is a 48 px-tall stadium (radius 24),
  /// chunkier than the framework's old 56×32 indicator so it reads
  /// as a liquid lens like the reference video, not a flat pill.
  static const double _lensHeight = 48;

  /// Display progress: 0 = collapsed, 1 = extended.
  late final AnimationController _progress =
      AnimationController.unbounded(vsync: this, value: 0);

  // v2.15: the v2.5 transition replica (`_extendedReplica` /
  // `_extendedReplicaCurve`) and the hysteresis latch
  // (`_extendedLatch`) are retired — the framework rail is
  // permanently extended now, so there is no framework transition
  // to mirror and no group drift to compensate (see the v2.15
  // section of the _LiquidRail doc comment).

  /// Accumulated finger travel (px) mapped from the drag start.
  double _dragBasePx = 0;

  /// Extra glass stretch from fast finger movement during a drag.
  double _dragStretch = 0;

  /// v2.3: the last *settled* state (0 = collapsed, 1 = expanded).
  /// Updated when a settle spring completes (or jumps, with
  /// reduce-motion). Release decisions are made against this, not
  /// against the raw midpoint.
  double _lastStable = 0;

  /// Stable state the current drag started from (snapshot of
  /// [_lastStable] taken in onHorizontalDragStart).
  double _dragFromStable = 0;

  /// Target of the in-flight settle spring, if any; promoted to
  /// [_lastStable] when the spring completes.
  double? _pendingTarget;

  /// True between drag start and drag end/cancel.
  bool _dragging = false;

  /// Net horizontal finger travel (px) of the current drag,
  /// accumulated from the drag's own deltas; negative = leftwards.
  double _dragNetPx = 0;

  /// v2.4: true once the current drag has committed an instant
  /// close (net leftward travel reached [_leftCommitPx] while the
  /// rail was not fully collapsed). A committed drag stops
  /// following the finger, and its end/cancel performs no settle
  /// decision, so the finger cannot re-open the rail by wandering
  /// right again within the same drag.
  bool _closeCommitted = false;

  /// Monotonic clock for the rail's own velocity samples.
  final Stopwatch _dragClock = Stopwatch();

  /// Recent finger-travel samples (see [_velocityWindow]).
  final List<_DragSample> _dragSamples = [];

  /// v2.11: the sliding lens's centre Y (px, rail coordinates),
  /// carried by an unbounded controller like [_progress] so the
  /// 175/24.5 spring gives it the same liquid settle as the pane.
  /// Initialised in [initState] directly on the selected
  /// destination's centre — no entry animation.
  late final AnimationController _lensY;

  /// v2.11: true while a vertical scrub drag owns the lens.
  bool _scrubbing = false;

  /// Scrub bookkeeping: the pointer's local Y at pointer-down (see
  /// [_onVerticalDragDown]) and the lens centre when the scrub
  /// started, and a smoothed finger velocity (px/s) used for the
  /// lens's stretch and its release spring.
  double _scrubStartLocalY = 0;
  double _scrubStartCenter = 0;
  double _scrubVelocity = 0;
  final Stopwatch _scrubClock = Stopwatch();
  Duration _scrubLastTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _lensY = AnimationController.unbounded(
      vsync: this,
      value: _destinationCenter(widget.selectedIndex),
    );
    _progress.addStatusListener((status) {
      if (status == AnimationStatus.completed && _pendingTarget != null) {
        _lastStable = _pendingTarget!;
        _pendingTarget = null;
      }
    });
  }

  @override
  void didUpdateWidget(_LiquidRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.destinations.length != oldWidget.destinations.length) {
      // Destination count changed (the debug destination comes and
      // goes): the framework resets its own rail state in the same
      // situation, so the lens snaps to the (clamped) selected
      // centre instead of sliding across a changed geometry.
      _lensY.stop();
      _lensY.value = _destinationCenter(widget.selectedIndex);
      return;
    }
    if (widget.selectedIndex != oldWidget.selectedIndex && !_scrubbing) {
      _springLensTo(
        _destinationCenter(widget.selectedIndex),
        _lensY.velocity,
      );
    }
  }

  @override
  void dispose() {
    _lensY.dispose();
    _progress.dispose();
    super.dispose();
  }

  // v2.13: the cached framework rail handed to the tree by the
  // per-frame builder (see [_railWidget]).
  NavigationRail? _cachedRail;
  List<NavigationRailDestination>? _cachedRailDestinations;
  int? _cachedRailSelectedIndex;

  /// v2.13: the framework rail, (re)built only when one of its real
  /// inputs changes — the destination list, or the selection.
  /// (Through v2.14 the extended latch was a third input; v2.15
  /// retired it — `extended` is permanently true, see below.) The
  /// per-frame [AnimatedBuilder] below passes the *identical*
  /// widget instance on every animation tick, and Flutter's
  /// element update short-circuits on identical widgets, so during
  /// a drag or spring neither [NavigationRail.build] nor the
  /// destination cascade beneath it (destination rows, ink
  /// responses, indicator/label stacks) re-runs per frame. Through
  /// v2.12 the merged builder reconstructed the rail on every tick
  /// of any of its three controllers — the widget-test harness
  /// counted 119 rail constructions over one 349-frame expand;
  /// with this cache the same expand constructs it twice through
  /// v2.14 (initial build + the latch flip) and once in v2.15.
  /// The cached instance's callback is [_handleSelected], which
  /// reads the *current* widget at call time, so keeping the
  /// instance never serves a stale callback.
  NavigationRail _railWidget() {
    if (_cachedRail == null ||
        !identical(_cachedRailDestinations, widget.destinations) ||
        _cachedRailSelectedIndex != widget.selectedIndex) {
      _cachedRailDestinations = widget.destinations;
      _cachedRailSelectedIndex = widget.selectedIndex;
      _cachedRail = NavigationRail(
        key: widget.railKey,
        // v2.15: permanently extended. The framework's own
        // transition controller initialises at 1.0 for an
        // initially-extended rail and never runs, so the
        // destinations stay in their extended (row) branch for
        // the rail's whole life — no branch switch, no remount,
        // no 200 ms framework transition riding on top of ours.
        // Collapse is purely our pane width + clip (see build).
        extended: true,
        destinations: widget.destinations,
        selectedIndex: widget.selectedIndex,
        onDestinationSelected: _handleSelected,
      );
    }
    return _cachedRail!;
  }

  /// Centre Y (rail coordinates) of destination [index]'s icon;
  /// the index is clamped so a transiently out-of-range selection
  /// (destination removed while selected) cannot throw the lens
  /// off the rail.
  double _destinationCenter(int index) {
    final last = widget.destinations.length - 1;
    final i = last < 0 ? 0 : index.clamp(0, last);
    return _firstDestinationCenter + _destinationPitch * i;
  }

  /// Spring (or jump, with reduce-motion) the lens centre to
  /// [center], carrying [velocity] (px/s) in as the spring's
  /// initial velocity — the same 175/24.5 spring as the pane, whose
  /// settle time is distance-independent, so the lens and the
  /// selected icon's magnification (same spring) stay in step.
  void _springLensTo(double center, double velocity) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _lensY.value = center;
      return;
    }
    _lensY.animateWith(SpringSimulation(
      _spring,
      _lensY.value,
      center,
      velocity.clamp(-4000.0, 4000.0).toDouble(),
    ));
  }

  /// The enabled destination nearest to centre Y [center] — the
  /// scrub's snap target. Disabled destinations (greyed out while
  /// no device is connected) are skipped, exactly as their taps are
  /// ignored by the framework.
  int _nearestEnabledIndex(double center) {
    final n = widget.destinations.length;
    if (n == 0) {
      return widget.selectedIndex;
    }
    final raw = ((center - _firstDestinationCenter) / _destinationPitch)
        .round()
        .clamp(0, n - 1);
    if (!widget.destinations[raw].disabled) {
      return raw;
    }
    for (int d = 1; d < n; d++) {
      if (raw - d >= 0 && !widget.destinations[raw - d].disabled) {
        return raw - d;
      }
      if (raw + d < n && !widget.destinations[raw + d].disabled) {
        return raw + d;
      }
    }
    return widget.selectedIndex;
  }

  /// v2.11: records where the finger went down. The scrub follows
  /// the finger by *offset from the down point*, and the drag-start
  /// details cannot supply that anchor: by the time the arena
  /// resolves, DragStartDetails.localPosition is the position where
  /// the drag was *accepted* (past touch slop), which would silently
  /// drop the first stretch of travel from the follow math.
  void _onVerticalDragDown(DragDownDetails details) {
    _scrubStartLocalY = details.localPosition.dy;
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _lensY.stop();
    _scrubbing = true;
    _scrubStartCenter = _lensY.value;
    _scrubVelocity = 0;
    _scrubClock
      ..reset()
      ..start();
    _scrubLastTime = Duration.zero;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_scrubbing) {
      return;
    }
    final now = _scrubClock.elapsed;
    final dtSeconds =
        (now - _scrubLastTime).inMicroseconds / Duration.microsecondsPerSecond;
    if (dtSeconds > 0) {
      final v = details.delta.dy / dtSeconds;
      _scrubVelocity = _scrubVelocity * 0.6 + v * 0.4;
    }
    _scrubLastTime = now;
    // Delta-based follow (no coordinate conversion needed): the
    // lens tracks the finger 1:1, clamped to the first/last
    // destination centres.
    _lensY.value = (_scrubStartCenter +
            (details.localPosition.dy - _scrubStartLocalY))
        .clamp(
          _firstDestinationCenter,
          _destinationCenter(widget.destinations.length - 1),
        )
        .toDouble();
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_scrubbing) {
      return;
    }
    _scrubbing = false;
    final target = _nearestEnabledIndex(_lensY.value);
    // Spring first, select second: the selection change rebuilds
    // this rail and didUpdateWidget re-springs towards the same
    // centre from the spring's current velocity, so the handover
    // is seamless.
    _springLensTo(
      _destinationCenter(target),
      details.primaryVelocity ?? _scrubVelocity,
    );
    if (target != widget.selectedIndex) {
      _handleSelected(target);
    }
  }

  void _onVerticalDragCancel() {
    if (!_scrubbing) {
      return;
    }
    _scrubbing = false;
    _springLensTo(
      _destinationCenter(widget.selectedIndex),
      _scrubVelocity,
    );
  }

  /// Rubber-band transform for drag positions outside [0, 1]:
  /// resistance grows the further you pull; the asymptote is about
  /// 8.5% of the travel range (≈15 px).
  double _rubberize(double raw) {
    if (raw >= 0 && raw <= 1) {
      return raw;
    }
    final bound = raw < 0 ? 0.0 : 1.0;
    final over = raw - bound;
    final damped = (1 - 1 / (over.abs() * 4 + 1)) * 0.085;
    return bound + damped * over.sign;
  }

  /// The rail's own release velocity (px/s), from the finger travel
  /// sampled over the last [_velocityWindow] of the drag. Returns 0
  /// when there is not enough trustworthy history (a single sample,
  /// or sub-4 px of travel, which is jitter rather than a flick).
  double get _selfVelocityPx {
    if (_dragSamples.length < 2) {
      return 0;
    }
    final first = _dragSamples.first;
    final last = _dragSamples.last;
    final travel = last.px - first.px;
    final seconds =
        (last.time - first.time).inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0 || travel.abs() < 4) {
      return 0;
    }
    return travel / seconds;
  }

  /// Effective release velocity (progress/s): the framework's
  /// primaryVelocity is unreliable for short flicks (it can read 0),
  /// so combine it with the rail's own estimate — when both agree in
  /// direction, the larger magnitude wins; when they disagree (the
  /// finger reversed right at the lift), the rail's samples describe
  /// the motion that actually just happened, so they win.
  double _effectiveVelocity(double primaryPx) {
    final primary = primaryPx / _range;
    final self = _selfVelocityPx / _range;
    if (self == 0) {
      return primary;
    }
    if (primary == 0) {
      return self;
    }
    if (primary.sign == self.sign) {
      return primary.abs() >= self.abs() ? primary : self;
    }
    return self;
  }

  /// Spring (or jump, with reduce-motion) to [target], feeding
  /// [velocity] (progress/s) in as the spring's initial velocity.
  /// Bookkeeping: [target] becomes [_lastStable] once the motion
  /// completes, so the *next* drag decides against it.
  void _springTo(double target, double velocity) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pendingTarget = null;
      _progress.value = target;
      _lastStable = target;
      return;
    }
    _pendingTarget = target;
    _progress.animateWith(SpringSimulation(
      _spring,
      _progress.value,
      target,
      velocity.clamp(-6.0, 6.0).toDouble(),
    ));
  }

  /// Release decision, judged against the stable state the drag
  /// started from:
  /// - From collapsed (v2.3, unchanged in v2.4): opening keeps its
  ///   thresholds — a 30% drag or a modest fling opens, anything
  ///   weaker falls back shut.
  /// - From expanded (v2.4): the v2.3 release thresholds for closing
  ///   (p ≤ 0.70 or a −0.7 fling) are gone. Leftward drags of arena
  ///   size already committed mid-drag in [_onDragUpdate]; a release
  ///   that still ends net-leftwards closes too, and only a drag
  ///   that netted rightwards (a rubber-band peek past fully open)
  ///   returns to open. There is no "drag left a bit, let go, bounce
  ///   back open" any more.
  void _settle(double velocity) {
    final p = _progress.value;
    final double target;
    if (_dragFromStable < 0.5) {
      target = (p >= _openPosition || velocity >= _flingVelocity) ? 1 : 0;
    } else {
      target = _dragNetPx < 0 ? 0 : 1;
    }
    _springTo(target, velocity);
  }

  /// Tap-to-collapse, through the same spring as a drag release.
  void _collapse() {
    if (_progress.value <= 0.001 && !_progress.isAnimating) {
      _lastStable = 0;
      return;
    }
    _springTo(0, math.min(_progress.velocity, 0).toDouble());
  }

  void _handleSelected(int index) {
    widget.onDestinationSelected(index);
    _collapse();
  }

  void _onDragStart(DragStartDetails details) {
    _progress.stop();
    _pendingTarget = null;
    _dragFromStable = _lastStable;
    _dragBasePx = _progress.value.clamp(0.0, 1.0) * _range;
    _dragStretch = 0;
    _dragNetPx = 0;
    _closeCommitted = false;
    _dragging = true;
    if (!_dragClock.isRunning) {
      _dragClock.start();
    }
    _dragSamples
      ..clear()
      ..add(_DragSample(_dragClock.elapsed, _dragBasePx));
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // v2.4: a drag that already committed its instant close ignores
    // the finger for the rest of its travel.
    if (_closeCommitted) {
      return;
    }
    _dragBasePx += details.delta.dx;
    _dragNetPx += details.delta.dx;
    final now = _dragClock.elapsed;
    _dragSamples.add(_DragSample(now, _dragBasePx));
    // Keep only the velocity window (but never drop the newest
    // sample, which anchors the estimate's end point).
    while (_dragSamples.length > 1 &&
        now - _dragSamples.first.time > _velocityWindow) {
      _dragSamples.removeAt(0);
    }
    _dragStretch = math.max(
      _dragStretch * 0.7,
      math.min(details.delta.dx.abs() * 0.005, 0.02),
    );
    _progress.value = _rubberize(_dragBasePx / _range);
    // v2.4: instant close — no business threshold, no waiting for
    // the release. While the rail is not fully collapsed, net
    // leftward travel reaching the gesture arena's own slop
    // distance springs it shut right now, fed with the finger's
    // current effective velocity. (Fully collapsed, p ≈ 0, a
    // leftward drag just rubber-bands against the lower bound,
    // exactly as before.)
    if (_progress.value > 0.02 && _dragNetPx <= -_leftCommitPx) {
      _closeCommitted = true;
      _springTo(0, _effectiveVelocity(0));
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    _dragStretch = 0;
    // v2.4: a committed close is final for this drag — no settle
    // decision, whatever the finger did after committing.
    if (_closeCommitted) {
      return;
    }
    _settle(_effectiveVelocity(details.primaryVelocity ?? 0));
  }

  void _onDragCancel() {
    _dragging = false;
    _dragStretch = 0;
    if (_closeCommitted) {
      return;
    }
    // No framework velocity on a cancel; the rail's own samples are
    // all we have.
    _settle(_effectiveVelocity(0));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_progress, _lensY]),
      builder: (context, _) {
        final p = _progress.value;
        final width =
            (_collapsedWidth + p * _range).clamp(56.0, 300.0).toDouble();
        // v2.15: the inner layout width is a constant. Through
        // v2.14 it stepped between 80 and 256 per latch state
        // (v2.5), stayed wide until the framework transition ran
        // out on the way down (v2.7), and a replica of that
        // transition translated the rail to cancel the destination
        // group's centring drift. With the framework rail
        // permanently extended (see [_railWidget]) there is no
        // step, no drift and nothing to compensate: the group is
        // laid out once, at 256, and the clip below reveals or
        // hides it. Labels are measured exactly once, at their
        // natural single line (and still never wrap — softWrap:
        // false where the destinations are built, the v2.7
        // backstop, kept).
        const layoutWidth = _extendedWidth;
        final overshoot = (p - p.clamp(0.0, 1.0)).abs().toDouble();
        final speed = _progress.isAnimating ? _progress.velocity.abs() : 0.0;
        // Liquid cues, all deliberately small: the pane stretches with
        // overshoot/speed (≤ +5%), the sheen leans into the motion and
        // brightens while things move.
        final deformX = 1.0 +
            math.min(overshoot * 0.5 + speed * 0.010 + _dragStretch, 0.05);
        final sheenShift = (p.clamp(-0.1, 1.1) * 0.30 -
                (_progress.isAnimating ? _progress.velocity : 0.0) * 0.05)
            .clamp(-0.12, 0.45)
            .toDouble();
        final sheenBoost =
            math.min(overshoot * 2.0 + speed * 0.08, 0.85).toDouble();
        // v2.3: while the rail is being dragged or is springing, run
        // the glass cheap — sheen drift frozen and a lighter blur —
        // and restore both the moment it settles.
        final inMotion = _dragging || _progress.isAnimating;

        // v2.10: the pane is a rounded rectangle now (radius 24,
        // was 28 — at the collapsed 80 px width the old radius left
        // only a 24 px flat segment at each end, so the pane read
        // as a capsule; 24 lengthens the flats to 32 px and sits in
        // the app's radius family: inputs 24, cards 28, dialogs 32)
        // and its glass tint follows the theme: railGlassTint
        // blends the colour scheme's primary into the tint base as
        // a pastel, so the pane's hue tracks the selected colour
        // scheme and the light/dark brightness while every other
        // optic (blur pipeline, rim, sheen, deform skin) is the
        // unchanged GlassContainer behaviour.
        final railTheme = Theme.of(context);
        final railTint = railGlassTint(
          railTheme.colorScheme.primary,
          isDark: railTheme.brightness == Brightness.dark,
        );

        // v2.11: the sliding lens. Its centre Y comes from _lensY;
        // its horizontal extent is a 60 px stadium centred on the
        // icon (x = 40) when collapsed, growing rightwards into a
        // full-row pill with 12 px insets when extended. Through
        // v2.14 the extent followed the framework-transition
        // replica's curve value (a 200 ms easeInOut once the latch
        // flipped); v2.15 drives it directly from the clamped
        // display progress instead, so mid-flight the lens width
        // tracks the pane's own progress exactly. Both rest
        // geometries are unchanged. While the lens moves fast it
        // stretches along Y (skin-only Transform, like the pane's
        // deform): +0.035% per px/s of lens velocity, capped at
        // +30%, narrowing slightly to conserve volume.
        // Reduce-motion kills the stretch.
        final lensT = p.clamp(0.0, 1.0).toDouble();
        final lensCenterY = _lensY.value;
        final lensLeft = 10 + 2 * lensT;
        final lensWidth = 60 + 172 * lensT;
        final lensVelocity =
            _scrubbing ? _scrubVelocity : _lensY.velocity;
        final lensStretch = MediaQuery.disableAnimationsOf(context)
            ? 0.0
            : math.min(lensVelocity.abs() * 0.00035, 0.30);
        final lensScaleY = 1 + lensStretch;
        final lensScaleX = 1 - lensStretch * 0.35;
        // The lens's backdrop blur runs cheap while anything is in
        // motion — the pane's own motion-reduction precedent.
        final lensInMotion = inMotion || _lensY.isAnimating || _scrubbing;
        final isDark = railTheme.brightness == Brightness.dark;
        final lensTint = railGlassTint(
          railTheme.colorScheme.primary,
          isDark: isDark,
        ).withValues(alpha: isDark ? 0.42 : 0.50);

        // The detector wraps the pane *and* its margins (the margin
        // is a Padding inside the detector now), so the drag hot
        // zone is the capsule's full footprint — no wider, so it
        // never competes with horizontal gestures in the page.
        // v2.11: it also takes vertical drags (lens scrubbing). The
        // gesture arena resolves the axis before either recogniser
        // fires, so horizontal expand/collapse keeps exactly its
        // old priority on horizontal drags.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          onVerticalDragDown: _onVerticalDragDown,
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          onVerticalDragCancel: _onVerticalDragCancel,
          child: Padding(
            padding: _paneMargin,
            child: GlassContainer(
              borderRadius: 24,
              tintColor: railTint,
              // v2.13: the in-motion sigma drops one more step
              // (10 → 8; v2.3 set 10). The pane's backdrop filter
              // re-runs every frame of an expand at a growing width,
              // and mid-motion the eye cannot resolve the difference;
              // the resting sigma (16) is untouched.
              blurSigma: inMotion ? 8 : 16,
              motionReduced: inMotion,
              deformX: deformX,
              deformAlignment: Alignment.centerLeft,
              sheenShift: sheenShift,
              sheenBoost: sheenBoost,
              child: SizedBox(
                width: width,
                child: ClipRect(
                  // The OverflowBox breaks the animated width's
                  // tight constraint, so the rail always lays out at
                  // layoutWidth and is merely clipped by the visible
                  // width above it — labels are revealed/hidden,
                  // never reflowed. Through v2.14 layoutWidth stepped
                  // between 80 and 256 per latch state (v2.5/v2.7)
                  // and a translate compensated the framework
                  // transition's group-centring; v2.15 made the
                  // layout a constant 256 (see layoutWidth above),
                  // so neither the step nor the translate exists.
                  // The clip is also the hit-test gate: points
                  // outside the visible width never reach the
                  // destinations laid out beyond it.
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: layoutWidth,
                    maxWidth: layoutWidth,
                    child: SizedBox(
                      width: layoutWidth,
                      // v2.11: the lens shares the rail's Stack so
                      // it inherits this fixed layout and the clip
                      // above — expansion, collapse and scrubbing
                      // can never detach it from the destinations.
                      // It is painted *under* the rail: its backdrop
                      // blur then samples the pane and the page
                      // behind (never the destinations, which are
                      // painted after it and stay crisp), and the
                      // destinations' ink splashes paint over it.
                      // Pure decoration: IgnorePointer, and being
                      // Positioned it never affects layout.
                      child: Stack(
                        children: <Widget>[
                          Positioned(
                            left: lensLeft,
                            top: lensCenterY - _lensHeight / 2,
                            width: lensWidth,
                            height: _lensHeight,
                            child: IgnorePointer(
                              child: Transform(
                                key: const ValueKey<String>(
                                    'railLensTransform'),
                                alignment: Alignment.center,
                                transform: Matrix4.diagonal3Values(
                                    lensScaleX, lensScaleY, 1),
                                child: Container(
                                  key: const ValueKey<String>('railLens'),
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(24),
                                    boxShadow: <BoxShadow>[
                                      // Ambient glow in the scheme's
                                      // own colour — the pane shadow's
                                      // language, and the lens's hint
                                      // of a coloured edge.
                                      BoxShadow(
                                        color: railTheme.colorScheme.primary
                                            .withValues(
                                                alpha: isDark ? 0.20 : 0.16),
                                        blurRadius: 18,
                                        offset: const Offset(0, 6),
                                        spreadRadius: -4,
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                            alpha: isDark ? 0.30 : 0.14),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(24),
                                    child: Stack(
                                      children: <Widget>[
                                        // Real glass: the pane's own
                                        // saturate → blur pipeline,
                                        // then the pastel theme tint.
                                        Positioned.fill(
                                          child: BackdropFilter(
                                            filter: liquidGlassBackdrop(
                                                // v2.13: no blur at
                                                // all while anything is
                                                // in motion (was 8) —
                                                // only the saturate
                                                // pass runs. The lens
                                                // mostly samples the
                                                // pane's own already-
                                                // blurred glass, and
                                                // mid-flight the eye
                                                // tracks position, not
                                                // sharpness; the full
                                                // σ14 returns the frame
                                                // motion stops.
                                                blurSigma:
                                                    lensInMotion ? 0 : 14),
                                            child: Container(
                                                color: lensTint),
                                          ),
                                        ),
                                        // Dome highlight: light pooled
                                        // at the top of the lens.
                                        Positioned.fill(
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.center,
                                                colors: <Color>[
                                                  Colors.white.withValues(
                                                      alpha: isDark
                                                          ? 0.14
                                                          : 0.28),
                                                  Colors.white
                                                      .withValues(alpha: 0),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        // The pane's perimeter rim
                                        // light, same painter.
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: glassRimPainter(
                                                radius: 24,
                                                isDark: isDark),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // v2.13: the cached instance — see
                          // _railWidget. Passing the identical
                          // widget every frame keeps the whole
                          // framework rail subtree out of the
                          // per-frame rebuild.
                          _railWidget(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A rail destination icon with a jelly pulse: when it becomes the
/// selected destination it stretches out, squashes back and settles —
/// the liquid tap feedback.
///
/// v2.11: the icon also carries the sliding lens's magnification —
/// while its destination is the selected one (i.e. the glass lens
/// rests on it) it is scaled by [selectedMagnification] on the
/// rail's 175/24.5 spring, so it grows as the lens arrives and
/// shrinks as the lens leaves, like the reference video. The two
/// transforms multiply: the jelly owns the tap instant, the
/// magnification owns the "lens in place" state. Both are
/// transform-only — layout, and with it every resting icon
/// position, is untouched.
class _JellyRailIcon extends StatefulWidget {
  final IconData icon;
  final bool selected;

  /// v2.11: resting scale of the icon under the lens.
  static const double selectedMagnification = 1.2;

  const _JellyRailIcon({required this.icon, required this.selected});

  @override
  State<_JellyRailIcon> createState() => _JellyRailIconState();
}

class _JellyRailIconState extends State<_JellyRailIcon>
    with TickerProviderStateMixin {
  /// The rail's spring (see [_LiquidRailState._spring]) — the icon's
  /// magnification and the lens slide share it and stay in step.
  /// Kept in sync with it (v2.14: damping 24.5, ζ ≈ 0.93).
  static const SpringDescription _magSpring =
      SpringDescription(mass: 1, stiffness: 175, damping: 24.5);

  late final AnimationController _jelly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1, // rest state: scale curve evaluates to 1.0 at t = 1
  );

  /// v2.11: current magnification — 1.0 while unselected,
  /// [_JellyRailIcon.selectedMagnification] while the lens rests on
  /// this destination; spring-driven, starts at the resting value.
  late final AnimationController _mag = AnimationController.unbounded(
    vsync: this,
    value: widget.selected ? _JellyRailIcon.selectedMagnification : 1.0,
  );

  @override
  void didUpdateWidget(_JellyRailIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected &&
        !oldWidget.selected &&
        !MediaQuery.disableAnimationsOf(context)) {
      _jelly.forward(from: 0);
    }
    if (widget.selected != oldWidget.selected) {
      final target =
          widget.selected ? _JellyRailIcon.selectedMagnification : 1.0;
      if (MediaQuery.disableAnimationsOf(context)) {
        _mag.value = target;
      } else {
        _mag.animateWith(SpringSimulation(
          _magSpring,
          _mag.value,
          target,
          _mag.velocity.clamp(-4.0, 4.0).toDouble(),
        ));
      }
    }
  }

  @override
  void dispose() {
    _mag.dispose();
    _jelly.dispose();
    super.dispose();
  }

  /// Jelly keyframes: stretch to 1.16, squash to 0.94, settle at 1.0
  /// with the faintest overshoot (easeOutBack on the last segment).
  double _jellyScaleX(double t) {
    if (t <= 0) {
      return 1;
    }
    if (t < 0.3) {
      return 1 + 0.16 * Curves.easeOut.transform(t / 0.3);
    }
    if (t < 0.6) {
      return 1.16 - 0.22 * Curves.easeInOut.transform((t - 0.3) / 0.3);
    }
    return 0.94 + 0.06 * Curves.easeOutBack.transform((t - 0.6) / 0.4);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_jelly, _mag]),
      builder: (context, child) {
        final sx = _jellyScaleX(_jelly.value);
        final mag = _mag.value;
        // Conserve "volume": as the icon stretches wide it squashes a
        // little vertically, and vice versa. The v2.11 magnification
        // multiplies both axes on top of the jelly pulse.
        return Transform.scale(
          scaleX: sx * mag,
          scaleY: (1 - (sx - 1) * 0.55) * mag,
          child: child,
        );
      },
      child: Icon(widget.icon),
    );
  }
}

class BottomProgressBar extends StatelessWidget {
  const BottomProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    return (appState.connector!.connected && appState.connector!.isDFU)
        ? LinearProgressIndicator(
            value: appState.progress,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          )
        : const SizedBox();
  }
}
