import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:io';

import '../services/cloud_backend_service.dart';
import '../services/tutorial_service.dart';
import '../singleton.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/modern_button.dart';
import '../widgets/stage_transition_switcher.dart';
import '../legal/legal_document_screen.dart';

class EditProfileScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  final bool startInSignIn;
  final VoidCallback? onBack;

  const EditProfileScreen({
    super.key,
    this.onComplete,
    this.startInSignIn = false,
    this.onBack,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

enum _AuthMode { signUp, signIn }

enum _EntryStage { auth, profileSetup, goals }

class _EditProfileScreenState extends State<EditProfileScreen> {
  final singleton = Singleton();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  _AuthMode _mode = _AuthMode.signUp;
  _EntryStage _stage = _EntryStage.auth;
  bool _stageReverse = false;
  final int _modeTransitionDirection = 1;
  bool _isLoading = false;
  bool _replayTutorialAfterEntry = false;
  bool _awaitingEmailVerification = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  int _speechGoal = 4;
  int _physicalGoal = 4;
  String _imagePath = 'images/711128.png';
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _firstNameError;
  String? _lastNameError;
  String? _stageErrorMessage;
  CloudAuthProfile? _pendingAuthProfile;
  StreamSubscription<CloudAuthProfile>? _verifiedSignInSubscription;

  @override
  void initState() {
    super.initState();
    _mode = widget.startInSignIn ? _AuthMode.signIn : _AuthMode.signUp;
    _stage = widget.startInSignIn ? _EntryStage.auth : _EntryStage.profileSetup;
    _speechGoal = singleton.weeklySpeechExerciseGoal;
    _physicalGoal = singleton.weeklyPhysicalExerciseGoal;
    if (singleton.isCloudConfigured) {
      _verifiedSignInSubscription = singleton.cloudVerifiedSignIns.listen(
        _onVerifiedSignIn,
      );
    }
  }

  void _onVerifiedSignIn(CloudAuthProfile profile) {
    if (!mounted || !_awaitingEmailVerification) return;
    _awaitingEmailVerification = false;
    HapticUtils.success();
    final email = profile.email?.trim();
    if (email != null && email.isNotEmpty) {
      _emailController.text = email;
    }
    setState(() {
      _pendingAuthProfile = profile;
      _replayTutorialAfterEntry = true;
      _isLoading = true;
    });
    final colors = context.colors;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          content: Text(
            'Email verified! Finishing setup.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: colors.surface.blend(colors.success, 0.18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.border.blend(colors.success, 0.58)),
          ),
        ),
      );
    _finishVerifiedEmailSetup();
  }

  @override
  void dispose() {
    _verifiedSignInSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _finishEntry() async {
    if (_replayTutorialAfterEntry) {
      await TutorialService().resetTutorial();
    }
    singleton.setFirstTime(false);
    singleton.setPage(0);
    HapticUtils.success();
    widget.onComplete?.call();
    if (!mounted || widget.onComplete != null) return;
    // Never push a second Navbar over the app root; the root already hosts
    // it and duplicate trees collide on GlobalKeys.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  bool _validateAccountFields() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final emailError = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
        ? null
        : 'Enter a valid email address.';
    // New accounts guard health data: require 8+. Sign-in keeps the legacy
    // floor so existing shorter passwords still work.
    final minPasswordLength = _mode == _AuthMode.signUp ? 8 : 6;
    final passwordError = password.length >= minPasswordLength
        ? null
        : 'Use at least $minPasswordLength characters.';
    final confirmPasswordError =
        _mode == _AuthMode.signUp && _confirmPasswordController.text != password
        ? 'Passwords do not match.'
        : null;

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmPasswordError = confirmPasswordError;
      _stageErrorMessage = null;
    });
    return emailError == null &&
        passwordError == null &&
        confirmPasswordError == null;
  }

  void _openLegalDocument(LegalDocumentType type) {
    HapticUtils.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LegalDocumentScreen(type: type)),
    );
  }

  String _friendlyAuthMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('cancelled') || text.contains('canceled')) {
      return 'Sign in was cancelled.';
    }
    if (text.contains('invalid login') ||
        text.contains('invalid credentials') ||
        text.contains('wrong password')) {
      return 'Email or password is incorrect.';
    }
    if (text.contains('already registered') ||
        text.contains('already exists')) {
      return 'This email is already registered. Try signing in.';
    }
    if (text.contains('verification link') ||
        text.contains('check your email') ||
        text.contains('email confirmation')) {
      return 'Check your email for a verification link, then sign in.';
    }
    if (text.contains('network') || text.contains('connection')) {
      return 'No internet connection. Please try again.';
    }
    if (text.contains('cloud') && text.contains('config')) {
      return 'Sign in is not available right now. Please try again later.';
    }
    return 'Authentication failed. Please try again.';
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _stageErrorMessage = message);
    final colors = context.colors;
    HapticUtils.error();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          content: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: colors.surface.blend(colors.error, 0.18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.border.blend(colors.error, 0.58)),
          ),
        ),
      );
  }

  void _showNotice(String message) {
    if (!mounted) return;
    final colors = context.colors;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          content: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: colors.surface.blend(colors.info, 0.14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.border.blend(colors.info, 0.5)),
          ),
        ),
      );
  }

  Future<void> _resendVerification() async {
    if (_isLoading) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _isLoading = true;
      _stageErrorMessage = null;
    });
    final sent = await singleton.resendEmailVerification(email);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (sent) {
      _showNotice('A new verification link was sent to $email.');
    } else {
      _showError(
        'We could not resend the link. Check your connection and try again.',
      );
    }
  }

  Future<void> _requestPasswordReset() async {
    if (_isLoading) return;
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _emailError = 'Enter your email to reset your password.');
      HapticUtils.error();
      return;
    }
    if (!singleton.isCloudConfigured) {
      _showError('Password recovery is not available right now.');
      return;
    }

    setState(() {
      _isLoading = true;
      _stageErrorMessage = null;
      _emailError = null;
    });
    final sent = await singleton.requestPasswordReset(email);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (sent) {
      _showNotice(
        'If an account exists for $email, a password recovery link is on its way.',
      );
    } else {
      _showError(
        'We could not send a recovery link. Check your connection and try again.',
      );
    }
  }

  /// Sign in with Apple is shown only on Apple platforms, where App Store
  /// Guideline 4.8 requires it whenever a third-party login is offered.
  bool get _supportsAppleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _signInWithApple() async {
    if (_isLoading) return;
    if (!singleton.isCloudConfigured) {
      _showError('Apple sign in is not available right now.');
      return;
    }

    setState(() {
      _isLoading = true;
      _stageErrorMessage = null;
    });
    HapticUtils.mediumImpact();
    try {
      final profile = await singleton.signInWithApple();
      if (profile == null) {
        // Null also covers the user dismissing the Apple sheet.
        return;
      }

      final resolvedEmail = profile.email?.trim();
      final fallbackName =
          (resolvedEmail != null && resolvedEmail.contains('@'))
          ? resolvedEmail.split('@').first
          : 'User';
      final resolvedName =
          (profile.fullName != null && profile.fullName!.trim().isNotEmpty)
          ? profile.fullName!.trim()
          : fallbackName;

      if (_mode == _AuthMode.signIn) {
        final synced = await singleton.createOrSyncAuthenticatedUser(
          displayName: resolvedName,
          userEmail: resolvedEmail,
          profileImage: _imagePath,
          preferExistingName: true,
        );
        if (!synced) {
          throw Exception('Unable to complete account sync.');
        }
        await _finishEntry();
        return;
      }

      if (!mounted) return;
      _replayTutorialAfterEntry = true;
      _pendingAuthProfile = profile;
      _emailController.text = resolvedEmail ?? _emailController.text;
      await _saveProfileAndFinish();
    } catch (e) {
      _showError(_friendlyAuthMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    if (!singleton.isCloudConfigured) {
      _showError('Google sign in is not available right now.');
      return;
    }

    setState(() {
      _isLoading = true;
      _stageErrorMessage = null;
    });
    HapticUtils.mediumImpact();
    try {
      final profile = await singleton.signInWithGoogle();
      if (profile == null) {
        throw Exception('Google sign in could not complete.');
      }

      final resolvedEmail = profile.email?.trim();
      final fallbackName =
          (resolvedEmail != null && resolvedEmail.contains('@'))
          ? resolvedEmail.split('@').first
          : 'User';
      final resolvedName =
          (profile.fullName != null && profile.fullName!.trim().isNotEmpty)
          ? profile.fullName!.trim()
          : fallbackName;

      if (_mode == _AuthMode.signIn) {
        final synced = await singleton.createOrSyncAuthenticatedUser(
          displayName: resolvedName,
          userEmail: resolvedEmail,
          profileImage: _imagePath,
          preferExistingName: true,
        );
        if (!synced) {
          throw Exception('Unable to complete account sync.');
        }
        await _finishEntry();
        return;
      }

      if (!mounted) return;
      _replayTutorialAfterEntry = true;
      _pendingAuthProfile = profile;
      _emailController.text = resolvedEmail ?? _emailController.text;
      await _saveProfileAndFinish();
    } catch (e) {
      _showError(_friendlyAuthMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _continueWithEmail() async {
    if (_isLoading) return;
    if (!_validateAccountFields()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isLoading = true;
      _stageErrorMessage = null;
    });
    HapticUtils.mediumImpact();
    try {
      if (_mode == _AuthMode.signIn) {
        if (!singleton.isCloudConfigured) {
          _showError(
            'Sign in is not available right now. Please try again later.',
          );
          return;
        }
        final profile = await singleton.signInWithEmailPassword(
          email: email,
          password: password,
        );
        if (profile == null) {
          _showError(
            _friendlyAuthMessage(singleton.lastCloudError ?? 'Sign in failed.'),
          );
          return;
        }
        final displayName =
            (profile.fullName != null && profile.fullName!.trim().isNotEmpty)
            ? profile.fullName!.trim()
            : email.split('@').first;
        final synced = await singleton.createOrSyncAuthenticatedUser(
          displayName: displayName,
          userEmail: profile.email ?? email,
          profileImage: _imagePath,
          preferExistingName: true,
        );
        if (!synced) {
          throw Exception('Unable to complete account sync.');
        }
        await _finishEntry();
        return;
      }

      // Sign up
      if (singleton.isCloudConfigured) {
        final profile = await singleton.signUpWithEmailPassword(
          email: email,
          password: password,
        );
        if (profile == null) {
          final error = singleton.lastCloudError ?? 'Sign up failed.';
          _awaitingEmailVerification = error.toLowerCase().contains(
            'verification link',
          );
          if (_awaitingEmailVerification) {
            if (mounted) setState(() => _stageErrorMessage = null);
            _showNotice(
              'Check your inbox and open the verification link to finish setup.',
            );
          } else {
            _showError(_friendlyAuthMessage(error));
          }
          return;
        }
        _pendingAuthProfile = profile;
      } else {
        // No cloud: create account locally and go to profile setup
        _pendingAuthProfile = CloudAuthProfile(
          userId: '',
          email: email,
          fullName: null,
          avatarUrl: null,
        );
      }
      _replayTutorialAfterEntry = true;
      await _saveProfileAndFinish();
    } catch (e) {
      _showError(_friendlyAuthMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickProfileImage() async {
    HapticUtils.lightImpact();
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted || picked == null) return;
    setState(() => _imagePath = picked.path);
  }

  void _continueFromProfileSetup() {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    final firstNameError = first.isEmpty ? 'Enter your first name.' : null;
    final lastNameError = last.isEmpty ? 'Enter your last name.' : null;
    setState(() {
      _firstNameError = firstNameError;
      _lastNameError = lastNameError;
      _stageErrorMessage = null;
    });
    if (firstNameError != null || lastNameError != null) {
      HapticUtils.error();
      return;
    }

    HapticUtils.selectionClick();
    setState(() {
      _stage = _EntryStage.goals;
      _stageReverse = false;
    });
  }

  void _continueFromGoals() {
    singleton.setTherapyGoals(
      weeklySpeech: _speechGoal,
      weeklyPhysical: _physicalGoal,
    );
    HapticUtils.selectionClick();
    setState(() {
      _stage = _EntryStage.auth;
      _stageReverse = false;
      _stageErrorMessage = null;
    });
  }

  Future<void> _saveProfileAndFinish() async {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    if (first.isEmpty || last.isEmpty) {
      throw Exception('Enter both first and last name.');
    }

    final email = _pendingAuthProfile?.email?.trim().isNotEmpty == true
        ? _pendingAuthProfile!.email!.trim()
        : _emailController.text.trim();

    singleton.setTherapyGoals(
      weeklySpeech: _speechGoal,
      weeklyPhysical: _physicalGoal,
    );

    final synced = singleton.isCloudConfigured
        ? await singleton.createOrSyncAuthenticatedUser(
            displayName: '$first $last',
            userEmail: email,
            profileImage: _imagePath,
          )
        : await singleton.createLocalOnlyUser(
            displayName: '$first $last',
            userEmail: email,
            profileImage: _imagePath,
          );
    if (!synced) {
      throw Exception('Unable to save your profile.');
    }
    await _finishEntry();
  }

  Future<void> _finishVerifiedEmailSetup() async {
    try {
      await _saveProfileAndFinish();
    } catch (e) {
      _showError(_friendlyAuthMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _initialsPreview() {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    final fallback = _emailController.text.trim();
    final a = first.isNotEmpty
        ? first[0]
        : (fallback.isNotEmpty ? fallback[0] : 'U');
    final b = last.isNotEmpty ? last[0] : '';
    return '${a.toUpperCase()}${b.toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.background.blend(colors.primaryLight, 0.18),
              colors.background.blend(colors.secondaryLight, 0.07),
              colors.background,
            ],
            stops: const [0.0, 0.38, 1.0],
          ),
        ),
        child: StageTransitionSwitcher(
          reverse: _stageReverse,
          child: switch (_stage) {
            _EntryStage.auth => KeyedSubtree(
              key: const ValueKey<String>('stage-auth'),
              child: _buildAuthStage(colors),
            ),
            _EntryStage.profileSetup => KeyedSubtree(
              key: const ValueKey<String>('stage-profile'),
              child: _buildProfileSetupStage(colors),
            ),
            _EntryStage.goals => KeyedSubtree(
              key: const ValueKey<String>('stage-goals'),
              child: _buildGoalsStage(colors),
            ),
          },
        ),
      ),
    );
  }

  Widget _buildJourneyHeader({
    required AppColors colors,
    required VoidCallback onBack,
    int? step,
  }) {
    final isSetup = step != null;
    return Semantics(
      container: true,
      label: isSetup ? 'Setup step ${step + 1} of 3' : 'Sign in',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _buildTopActionButton(
                colors: colors,
                icon: Icons.arrow_back_rounded,
                tooltip: 'Go back',
                onTap: onBack,
              ),
              const Spacer(),
              if (isSetup)
                Text(
                  'STEP ${step + 1} OF 3',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
            ],
          ),
          if (isSetup) ...<Widget>[
            const SizedBox(height: 16),
            Row(
              children: List<Widget>.generate(5, (index) {
                if (index.isOdd) return const SizedBox(width: 8);
                final segment = index ~/ 2;
                final active = segment <= step;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 5,
                    decoration: BoxDecoration(
                      color: active ? colors.primary : colors.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInlineAlert(AppColors colors, String message) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface.blend(colors.error, 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border.blend(colors.error, 0.42)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, color: colors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textPrimary,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudAvailabilityNote(AppColors colors) {
    final message = _mode == _AuthMode.signIn
        ? 'Account sign in is temporarily unavailable. Check your connection or try again later.'
        : 'Cloud sync is unavailable right now. You can finish setup on this device and keep using core tracking offline.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface.blend(colors.warning, 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border.blend(colors.warning, 0.34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.cloud_off_outlined, color: colors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textPrimary,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Interior padding for a full-bleed stage scroll view: content is inset
  /// past the notch and home indicator, but scrolls edge to edge.
  EdgeInsets _stagePadding(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return EdgeInsets.fromLTRB(20, safe.top + 12, 20, safe.bottom + 20);
  }

  BoxConstraints _stageMinHeight(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    return BoxConstraints(
      minHeight: (constraints.maxHeight - _stagePadding(context).vertical)
          .clamp(0.0, double.infinity),
    );
  }

  Widget _buildAuthStage(AppColors colors) {
    final cloudReady = singleton.isCloudConfigured;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: _stagePadding(context),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: _stageMinHeight(context, constraints),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildJourneyHeader(
                colors: colors,
                step: _mode == _AuthMode.signUp ? 2 : null,
                onBack: () {
                  if (_mode == _AuthMode.signUp) {
                    setState(() {
                      _stage = _EntryStage.goals;
                      _stageReverse = true;
                      _stageErrorMessage = null;
                    });
                  } else {
                    widget.onBack?.call();
                  }
                },
              ),
              const SizedBox(height: 20),
              _buildModeAnimatedSwitcher(
                child: Column(
                  key: ValueKey<String>('auth-copy-${_mode.name}'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _mode == _AuthMode.signUp
                          ? 'Create your account'
                          : 'Welcome back',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _mode == _AuthMode.signUp
                          ? 'Add an email and password to save your profile and therapy goals.'
                          : 'Sign in to continue where you left off.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (_stageErrorMessage != null) ...[
                _buildInlineAlert(colors, _stageErrorMessage!),
                const SizedBox(height: 14),
              ],
              if (!cloudReady) ...[
                _buildCloudAvailabilityNote(colors),
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: AutofillGroup(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildFieldLabel('Email'),
                        _buildInputField(
                          controller: _emailController,
                          hintText: 'you@example.com',
                          icon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          errorText: _emailError,
                          autocorrect: false,
                          enableSuggestions: false,
                          onChanged: (_) {
                            if (_emailError != null ||
                                _stageErrorMessage != null ||
                                _awaitingEmailVerification) {
                              setState(() {
                                _emailError = null;
                                _stageErrorMessage = null;
                                _awaitingEmailVerification = false;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        _buildFieldLabel('Password'),
                        _buildInputField(
                          controller: _passwordController,
                          hintText: _mode == _AuthMode.signUp
                              ? 'At least 8 characters'
                              : 'Enter your password',
                          icon: Icons.lock_outline_rounded,
                          obscureText: !_passwordVisible,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: _mode == _AuthMode.signUp
                              ? TextInputAction.next
                              : TextInputAction.done,
                          errorText: _passwordError,
                          autocorrect: false,
                          enableSuggestions: false,
                          onChanged: (_) {
                            if (_passwordError != null ||
                                _stageErrorMessage != null) {
                              setState(() {
                                _passwordError = null;
                                _stageErrorMessage = null;
                              });
                            }
                          },
                          onSubmitted: _mode == _AuthMode.signIn
                              ? (_) => _continueWithEmail()
                              : null,
                          suffixIcon: IconButton(
                            tooltip: _passwordVisible
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: () => setState(
                              () => _passwordVisible = !_passwordVisible,
                            ),
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        if (_mode == _AuthMode.signIn)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : _requestPasswordReset,
                              child: const Text('Forgot password?'),
                            ),
                          ),
                        ClipRect(
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: _mode == _AuthMode.signUp
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const SizedBox(height: 14),
                                      _buildFieldLabel('Confirm Password'),
                                      _buildInputField(
                                        controller: _confirmPasswordController,
                                        hintText: 'Retype your password',
                                        icon: Icons.verified_user_outlined,
                                        obscureText: !_confirmPasswordVisible,
                                        textInputAction: TextInputAction.done,
                                        errorText: _confirmPasswordError,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        onChanged: (_) {
                                          if (_confirmPasswordError != null ||
                                              _stageErrorMessage != null) {
                                            setState(() {
                                              _confirmPasswordError = null;
                                              _stageErrorMessage = null;
                                            });
                                          }
                                        },
                                        onSubmitted: (_) =>
                                            _continueWithEmail(),
                                        suffixIcon: IconButton(
                                          tooltip: _confirmPasswordVisible
                                              ? 'Hide password'
                                              : 'Show password',
                                          onPressed: () => setState(
                                            () => _confirmPasswordVisible =
                                                !_confirmPasswordVisible,
                                          ),
                                          icon: Icon(
                                            _confirmPasswordVisible
                                                ? Icons.visibility_off_outlined
                                                : Icons.visibility_outlined,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _continueWithEmail,
                            icon: _isLoading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.textOnPrimary,
                                    ),
                                  )
                                : Icon(
                                    Icons.mail_outline_rounded,
                                    size: 18,
                                    color: colors.textOnPrimary,
                                  ),
                            label: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeOutCubic,
                              layoutBuilder: (currentChild, previousChildren) {
                                // widthFactor keeps the label hugging its text
                                // so the icon sits beside it instead of being
                                // pushed to the button's edge.
                                return ClipRect(
                                  child: Align(
                                    alignment: Alignment.center,
                                    widthFactor: 1,
                                    child:
                                        currentChild ?? const SizedBox.shrink(),
                                  ),
                                );
                              },
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: Offset(
                                          _modeTransitionDirection * 0.02,
                                          0,
                                        ),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: Text(
                                _isLoading
                                    ? 'Please wait...'
                                    : _mode == _AuthMode.signUp
                                    ? 'Create Account'
                                    : 'Sign In with Email',
                                key: ValueKey<String>(
                                  'email-cta-${_mode.name}-$_isLoading',
                                ),
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              elevation: 0,
                              backgroundColor: colors.primaryDark.blend(
                                colors.primary,
                                0.22,
                              ),
                              foregroundColor: colors.textOnPrimary,
                              disabledBackgroundColor: colors.surface.blend(
                                colors.primary,
                                0.16,
                              ),
                              disabledForegroundColor: colors.textSecondary
                                  .blend(colors.surface, 0.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ),
                        if (cloudReady && _supportsAppleSignIn) ...[
                          const SizedBox(height: 12),
                          _buildAppleButton(colors),
                        ],
                        if (cloudReady) ...[
                          const SizedBox(height: 12),
                          _buildGoogleButton(colors),
                        ],
                        if (_awaitingEmailVerification) ...[
                          const SizedBox(height: 14),
                          _buildVerificationPanel(colors),
                        ],
                        const SizedBox(height: 14),
                        _buildLegalConsent(colors),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeAnimatedSwitcher({required Widget child}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            child: currentChild ?? const SizedBox.shrink(),
          ),
        );
      },
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(_modeTransitionDirection * 0.03, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildTopActionButton({
    required AppColors colors,
    required IconData icon,
    required VoidCallback onTap,
    String tooltip = 'Go back',
  }) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, color: colors.textPrimary, size: 21),
        style: IconButton.styleFrom(
          backgroundColor: colors.surface,
          shape: CircleBorder(side: BorderSide(color: colors.border)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    List<String>? autofillHints,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    TextInputAction? textInputAction,
    String? errorText,
    Widget? suffixIcon,
    bool autocorrect = true,
    bool enableSuggestions = true,
  }) {
    final colors = context.colors;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autofillHints: autofillHints,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        errorText: errorText,
        prefixIcon: Icon(icon, size: 20, color: colors.textTertiary),
        suffixIcon: suffixIcon,
        fillColor: colors.surface.blend(colors.background, 0.4),
        filled: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
    );
  }

  Widget _buildAppleButton(AppColors colors) {
    // Apple's guidelines: black button in light mode, white in dark mode,
    // matching the size and prominence of other sign-in options.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? Colors.white : Colors.black;
    final foreground = isDark ? Colors.black : Colors.white;

    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: _isLoading ? null : _signInWithApple,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: background,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.apple, size: 26, color: foreground),
            const SizedBox(width: 10),
            Text(
              _mode == _AuthMode.signUp
                  ? 'Sign up with Apple'
                  : 'Sign in with Apple',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleButton(AppColors colors) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          elevation: 0,
          backgroundColor: colors.surface,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CustomPaint(
              size: Size.square(22),
              painter: _GoogleGPainter(),
            ),
            const SizedBox(width: 12),
            Text(
              _mode == _AuthMode.signUp
                  ? 'Create with Google'
                  : 'Sign In with Google',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationPanel(AppColors colors) {
    final email = _emailController.text.trim();
    return Semantics(
      liveRegion: true,
      container: true,
      label: 'Verification email sent to $email',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface.blend(colors.info, 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border.blend(colors.info, 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.mark_email_read_outlined,
                  color: colors.info,
                  size: 21,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Check your inbox',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Open the link sent to $email. ParkiWell will finish setup when you return.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isLoading ? null : _resendVerification,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Resend verification email'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegalConsent(AppColors colors) {
    return Column(
      children: <Widget>[
        Text(
          'By continuing, you agree to ParkiWell\'s',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            TextButton(
              onPressed: () =>
                  _openLegalDocument(LegalDocumentType.termsOfService),
              child: const Text('Terms of Service'),
            ),
            Text(
              'and',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            TextButton(
              onPressed: () =>
                  _openLegalDocument(LegalDocumentType.privacyPolicy),
              child: const Text('Privacy Policy'),
            ),
          ],
        ),
        Text(
          'ParkiWell supports tracking and education; it does not replace medical advice.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.textTertiary,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSetupStage(AppColors colors) {
    final hasCustomImage =
        _imagePath.isNotEmpty &&
        !_imagePath.contains('711128') &&
        !_imagePath.startsWith('images/');
    final emailSummary = _pendingAuthProfile?.email?.trim().isNotEmpty == true
        ? _pendingAuthProfile!.email!.trim()
        : _emailController.text.trim();

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: _stagePadding(context),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: _stageMinHeight(context, constraints),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildJourneyHeader(
                colors: colors,
                step: 0,
                onBack: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else {
                    setState(() {
                      _stage = _EntryStage.auth;
                      _stageReverse = true;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              if (_stageErrorMessage != null) ...[
                _buildInlineAlert(colors, _stageErrorMessage!),
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildAvatarPreview(colors, hasCustomImage),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Set up your profile',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Add your name. A profile photo is optional.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: colors.textSecondary),
                              ),
                              if (emailSummary.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: colors.border),
                                  ),
                                  child: Text(
                                    emailSummary,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colors.textSecondary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextButton.icon(
                      onPressed: _isLoading ? null : _pickProfileImage,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: const Text('Choose profile picture'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: colors.surfaceVariant,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildFieldLabel('First Name'),
                    _buildInputField(
                      controller: _firstNameController,
                      hintText: 'First name',
                      icon: Icons.person_outline_rounded,
                      textInputAction: TextInputAction.next,
                      errorText: _firstNameError,
                      onChanged: (_) => setState(() {
                        _firstNameError = null;
                        _stageErrorMessage = null;
                      }),
                    ),
                    const SizedBox(height: 14),
                    _buildFieldLabel('Last Name'),
                    _buildInputField(
                      controller: _lastNameController,
                      hintText: 'Last name',
                      icon: Icons.badge_outlined,
                      textInputAction: TextInputAction.done,
                      errorText: _lastNameError,
                      onChanged: (_) => setState(() {
                        _lastNameError = null;
                        _stageErrorMessage = null;
                      }),
                      onSubmitted: (_) => _continueFromProfileSetup(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ModernButton(
                        text: 'Continue to Goals',
                        icon: Icons.arrow_forward_rounded,
                        backgroundColor: colors.primaryDark.blend(
                          colors.primary,
                          0.22,
                        ),
                        onPressed: _continueFromProfileSetup,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoalsStage(AppColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: _stagePadding(context),
        child: ConstrainedBox(
          constraints: _stageMinHeight(context, constraints),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildJourneyHeader(
                colors: colors,
                step: 1,
                onBack: () => setState(() {
                  _stage = _EntryStage.profileSetup;
                  _stageReverse = true;
                  _stageErrorMessage = null;
                }),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: colors.border),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Set therapy goals',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose a comfortable weekly target for speech and movement. Start small—you can change this anytime.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _GoalSetupRow(
                      colors: colors,
                      icon: Icons.record_voice_over_rounded,
                      title: 'Speech exercises',
                      subtitle: 'Voice, clarity, and breath practice',
                      accent: colors.primary,
                      value: _speechGoal,
                      onDecrease: () => setState(
                        () => _speechGoal = (_speechGoal - 1)
                            .clamp(0, 99)
                            .toInt(),
                      ),
                      onIncrease: () => setState(
                        () => _speechGoal = (_speechGoal + 1)
                            .clamp(0, 99)
                            .toInt(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _GoalSetupRow(
                      colors: colors,
                      icon: Icons.fitness_center_rounded,
                      title: 'Physical exercises',
                      subtitle: 'Mobility, balance, and strength sessions',
                      accent: colors.secondary,
                      value: _physicalGoal,
                      onDecrease: () => setState(
                        () => _physicalGoal = (_physicalGoal - 1)
                            .clamp(0, 99)
                            .toInt(),
                      ),
                      onIncrease: () => setState(
                        () => _physicalGoal = (_physicalGoal + 1)
                            .clamp(0, 99)
                            .toInt(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ModernButton(
                        text: 'Continue to Account',
                        icon: Icons.arrow_forward_rounded,
                        backgroundColor: colors.primaryDark.blend(
                          colors.primary,
                          0.22,
                        ),
                        onPressed: _continueFromGoals,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPreview(AppColors colors, bool hasCustomImage) {
    return Semantics(
      button: true,
      label: hasCustomImage
          ? 'Change profile picture'
          : 'Choose an optional profile picture',
      child: GestureDetector(
        onTap: _isLoading ? null : _pickProfileImage,
        child: Container(
          width: 94,
          height: 94,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.border, width: 1.5),
            color: colors.surfaceVariant,
          ),
          child: ClipOval(
            child: hasCustomImage
                ? Image.file(
                    File(_imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildAvatarFallback(colors),
                  )
                : _buildAvatarFallback(colors),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(AppColors colors) {
    return Center(
      child: Text(
        _initialsPreview(),
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: colors.primary,
        ),
      ),
    );
  }
}

class _GoalSetupRow extends StatelessWidget {
  final AppColors colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final int value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _GoalSetupRow({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 23),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Weekly target',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _GoalSetupButton(
                colors: colors,
                icon: Icons.remove_rounded,
                tooltip: 'Decrease $title weekly goal',
                enabled: value > 0,
                onTap: onDecrease,
              ),
              Semantics(
                label: '$value $title per week',
                child: SizedBox(
                  width: 48,
                  child: Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              _GoalSetupButton(
                colors: colors,
                icon: Icons.add_rounded,
                tooltip: 'Increase $title weekly goal',
                enabled: value < 99,
                onTap: onIncrease,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalSetupButton extends StatelessWidget {
  final AppColors colors;
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool enabled;

  const _GoalSetupButton({
    required this.colors,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: enabled
            ? () {
                HapticUtils.selectionClick();
                onTap();
              }
            : null,
        style: IconButton.styleFrom(
          backgroundColor: colors.surface,
          disabledBackgroundColor: colors.surfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colors.border),
          ),
        ),
        icon: Icon(icon, size: 20, color: colors.textPrimary),
      ),
    );
  }
}

/// Official multicolor Google "G", drawn from the brand's 18x18 vector paths
/// so the sign-in button follows Google's branding guidelines.
class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 18;
    canvas.drawPath(
      Path()
        ..moveTo(17.64 * s, 9.20 * s)
        ..cubicTo(17.64 * s, 8.56 * s, 17.58 * s, 7.95 * s, 17.48 * s, 7.36 * s)
        ..lineTo(9.00 * s, 7.36 * s)
        ..lineTo(9.00 * s, 10.84 * s)
        ..lineTo(13.84 * s, 10.84 * s)
        ..cubicTo(
          13.63 * s,
          11.97 * s,
          13.00 * s,
          12.92 * s,
          12.04 * s,
          13.56 * s,
        )
        ..lineTo(12.04 * s, 15.82 * s)
        ..lineTo(14.96 * s, 15.82 * s)
        ..cubicTo(
          16.67 * s,
          14.25 * s,
          17.64 * s,
          11.94 * s,
          17.64 * s,
          9.20 * s,
        )
        ..close(),
      Paint()..color = const Color(0xFF4285F4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(9.00 * s, 18.00 * s)
        ..cubicTo(
          11.43 * s,
          18.00 * s,
          13.47 * s,
          17.20 * s,
          14.96 * s,
          15.82 * s,
        )
        ..lineTo(12.04 * s, 13.56 * s)
        ..cubicTo(
          11.24 * s,
          14.10 * s,
          10.20 * s,
          14.42 * s,
          9.00 * s,
          14.42 * s,
        )
        ..cubicTo(6.66 * s, 14.42 * s, 4.68 * s, 12.84 * s, 3.97 * s, 10.72 * s)
        ..lineTo(0.96 * s, 10.72 * s)
        ..lineTo(0.96 * s, 13.05 * s)
        ..cubicTo(2.44 * s, 15.98 * s, 5.48 * s, 18.00 * s, 9.00 * s, 18.00 * s)
        ..close(),
      Paint()..color = const Color(0xFF34A853),
    );
    canvas.drawPath(
      Path()
        ..moveTo(3.97 * s, 10.72 * s)
        ..cubicTo(3.79 * s, 10.18 * s, 3.69 * s, 9.60 * s, 3.69 * s, 9.00 * s)
        ..cubicTo(3.69 * s, 8.40 * s, 3.79 * s, 7.82 * s, 3.97 * s, 7.28 * s)
        ..lineTo(3.97 * s, 4.95 * s)
        ..lineTo(0.96 * s, 4.95 * s)
        ..cubicTo(0.35 * s, 6.17 * s, 0.00 * s, 7.55 * s, 0.00 * s, 9.00 * s)
        ..cubicTo(0.00 * s, 10.45 * s, 0.35 * s, 11.83 * s, 0.96 * s, 13.05 * s)
        ..lineTo(3.97 * s, 10.72 * s)
        ..close(),
      Paint()..color = const Color(0xFFFBBC05),
    );
    canvas.drawPath(
      Path()
        ..moveTo(9.00 * s, 3.58 * s)
        ..cubicTo(10.32 * s, 3.58 * s, 11.50 * s, 4.03 * s, 12.44 * s, 4.93 * s)
        ..lineTo(15.02 * s, 2.35 * s)
        ..cubicTo(13.46 * s, 0.90 * s, 11.42 * s, 0.00 * s, 9.00 * s, 0.00 * s)
        ..cubicTo(5.48 * s, 0.00 * s, 2.44 * s, 2.02 * s, 0.96 * s, 4.95 * s)
        ..lineTo(3.97 * s, 7.28 * s)
        ..cubicTo(4.68 * s, 5.16 * s, 6.66 * s, 3.58 * s, 9.00 * s, 3.58 * s)
        ..close(),
      Paint()..color = const Color(0xFFEA4335),
    );
  }

  @override
  bool shouldRepaint(covariant _GoogleGPainter oldDelegate) => false;
}
