import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:parkiwell/navbar.dart';
import 'package:parkiwell/routes.dart';
import 'package:parkiwell/singleton.dart';
import 'package:parkiwell/theme/app_theme.dart';
import 'package:parkiwell/screens/onboarding_flow.dart';
import 'package:parkiwell/screens/splash_screen.dart';
import 'package:parkiwell/services/app_logger.dart';
import 'package:parkiwell/config/environment.dart';
import 'package:parkiwell/widgets/password_update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terminate_restart/terminate_restart.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Determine if running in production
  final bool isProduction = kReleaseMode || EnvironmentConfig.isProduction;

  // Initialize logger
  final logger = AppLogger();
  logger.init(isProduction: isProduction);
  logger.info(
    'App starting in ${isProduction ? "production" : "development"} mode',
  );

  // Initialize restart functionality
  TerminateRestart.instance.initialize();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize singleton services
  final singleton = Singleton();

  // Set up error handling for production
  if (isProduction) {
    FlutterError.onError = (details) {
      logger.fatal('Flutter error', details.exception, details.stack);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      logger.fatal('Platform error', error, stack);
      return true;
    };
  }

  // Cloud sync runs concurrently with the first frame; the in-app splash
  // waits for it (with a hard timeout) instead of blocking runApp on the
  // network, so launch never hangs on a flaky connection.
  final bootstrap = _bootstrap(singleton, logger, isProduction);

  runApp(MyApp(bootstrap: bootstrap));
}

Future<void> _bootstrap(
  Singleton singleton,
  AppLogger logger,
  bool isProduction,
) async {
  try {
    await singleton.initialize(isProduction: isProduction);

    await SharedPreferences.getInstance().then((prefs) async {
      if (prefs.containsKey('userID')) {
        try {
          // Load user from cloud backend
          final loaded = await singleton.loadUser();
          if (loaded && singleton.name != "[Name]") {
            // User data loaded successfully, not first time
            singleton.setFirstTime(false);
            logger.info('Existing user loaded successfully');
          } else if (singleton.hasCachedData && singleton.name != "[Name]") {
            singleton.setFirstTime(false);
            logger.info('Loaded cached user data for offline session');
          } else {
            // User data not found, clear stale userID only when cloud is online.
            if (singleton.isCloudConnected) {
              await prefs.remove('userID');
              logger.info('Stale user ID cleared');
            }
          }
        } catch (e, stackTrace) {
          // Error loading user, clear stale userID only when cloud is online.
          if (singleton.isCloudConnected) {
            await prefs.remove('userID');
          }
          logger.error('Error loading user', e, stackTrace);
        }
      } else if (singleton.hasCachedData && singleton.name != "[Name]") {
        singleton.setFirstTime(false);
      }
      // firstTime remains true by default if no valid user found

      if (prefs.containsKey('theme')) {
        singleton.switchColorTheme(await singleton.getTheme());
      } else {
        singleton.switchColorTheme(false);
      }
    });
  } catch (e, stackTrace) {
    logger.fatal('Critical initialization error', e, stackTrace);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.bootstrap});

  /// Startup work (cloud init, user load) running concurrently with the
  /// first frame. Null means there is nothing to wait for.
  final Future<void>? bootstrap;

  @override
  State<MyApp> createState() => _MyAppState();
}

enum AppScreen { splash, onboarding, home }

class _MyAppState extends State<MyApp> {
  final singleton = Singleton();
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<void>? _passwordRecoverySubscription;
  bool _passwordDialogVisible = false;
  AppScreen _currentScreen = AppScreen.splash;

  /// Cap on how long the splash may hold for startup sync; past this the
  /// app continues with locally cached data.
  static const Duration _bootstrapTimeout = Duration(seconds: 8);

  bool _splashAnimationDone = false;
  bool _bootstrapSettled = false;

  @override
  void initState() {
    super.initState();
    _lastColorMode = singleton.colorMode;
    singleton.addListener(_onSingletonChange);
    _passwordRecoverySubscription = singleton.passwordRecoveryEvents.listen(
      (_) => _showPasswordRecovery(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (singleton.isPasswordRecoveryPending) _showPasswordRecovery();
    });
    _awaitBootstrap();
  }

  Future<void> _awaitBootstrap() async {
    final bootstrap = widget.bootstrap;
    if (bootstrap != null) {
      try {
        await bootstrap.timeout(_bootstrapTimeout);
      } on TimeoutException {
        AppLogger().warning(
          'Startup sync timed out; continuing with local data',
        );
      } catch (_) {
        // Bootstrap errors are already logged at the source.
      }
    }
    if (!mounted) return;
    _bootstrapSettled = true;
    _maybeLeaveSplash();
  }

  @override
  void dispose() {
    singleton.removeListener(_onSingletonChange);
    _passwordRecoverySubscription?.cancel();
    super.dispose();
  }

  Future<void> _showPasswordRecovery() async {
    if (_passwordDialogVisible) return;
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPasswordRecovery();
      });
      return;
    }

    _passwordDialogVisible = true;
    final updated = await showPasswordUpdateDialog(dialogContext);
    _passwordDialogVisible = false;
    if (updated != true || !mounted) return;

    final messengerContext = _navigatorKey.currentContext;
    if (messengerContext == null || !messengerContext.mounted) return;
    ScaffoldMessenger.of(messengerContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Your password has been updated.')),
      );
  }

  int _lastColorMode = 0;

  void _onSingletonChange() {
    if (!mounted) return;
    // The root build only depends on colorMode (theme) and the sign-out
    // transition; skipping every other notification keeps the whole app
    // from rebuilding on unrelated state changes.
    final colorModeChanged = singleton.colorMode != _lastColorMode;
    final needsOnboarding =
        singleton.firstTime && _currentScreen == AppScreen.home;
    if (!colorModeChanged && !needsOnboarding) return;
    setState(() {
      _lastColorMode = singleton.colorMode;
      // Sign-out clears the session and flips firstTime back on; return the
      // user to the onboarding entry instead of leaving a stale Navbar.
      if (needsOnboarding) {
        _currentScreen = AppScreen.onboarding;
      }
    });
  }

  void _onSplashComplete() {
    if (!mounted) return;
    _splashAnimationDone = true;
    _maybeLeaveSplash();
  }

  void _maybeLeaveSplash() {
    // Leave the splash only when the animation has finished AND startup
    // sync has settled (completed, failed, or timed out), so routing sees
    // the loaded firstTime state.
    if (!_splashAnimationDone || !_bootstrapSettled) return;
    if (_currentScreen != AppScreen.splash) return;
    setState(() {
      _currentScreen = singleton.firstTime
          ? AppScreen.onboarding
          : AppScreen.home;
    });
  }

  void _onOnboardingComplete() {
    if (mounted) {
      setState(() {
        _currentScreen = AppScreen.home;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    // Update system UI overlay style based on theme
    SystemChrome.setSystemUIOverlayStyle(
      singleton.colorMode == 0
          ? SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: AppTheme.lightColors.background,
              systemNavigationBarColor: AppTheme.lightColors.navBackground,
            )
          : SystemUiOverlayStyle.light.copyWith(
              statusBarColor: AppTheme.darkColors.background,
              systemNavigationBarColor: AppTheme.darkColors.navBackground,
            ),
    );

    final Widget home = switch (_currentScreen) {
      AppScreen.splash => SplashScreen(onComplete: _onSplashComplete),
      AppScreen.onboarding => OnboardingFlowScreen(
        onComplete: _onOnboardingComplete,
      ),
      AppScreen.home => const Navbar(),
    };

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'ParkiWell',
      routes: namedRoutes,
      onGenerateRoute: onGenerateAppRoute,
      home: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 500),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
          key: ValueKey<AppScreen>(_currentScreen),
          child: home,
        ),
      ),
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: singleton.colorMode == 0 ? ThemeMode.light : ThemeMode.dark,
      debugShowCheckedModeBanner: false,
    );
  }
}
