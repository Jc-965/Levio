import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import 'Recovery/exercise.dart';
import 'Main/home.dart';
import 'Main/manage.dart';
import 'Main/recovery.dart';
import 'Main/community.dart';
import 'Main/profile.dart';
import 'Manage/schedule.dart';
import 'services/tutorial_targets.dart';
import 'services/tutorial_service.dart';
import 'singleton.dart';
import 'theme/app_theme.dart';
import 'utils/app_routes.dart';
import 'utils/haptic_utils.dart';
import 'widgets/modern_input.dart';
import 'widgets/tutorial_overlay.dart';

class Navbar extends StatefulWidget {
  const Navbar({super.key});

  @override
  State<Navbar> createState() => _NavbarState();
}

class _NavbarState extends State<Navbar> with TickerProviderStateMixin {
  final singleton = Singleton();
  final tutorialService = TutorialService();
  int currentIndex = 0;
  int _previousIndex = 0;
  Timer? _tabSettleTimer;
  bool _tabTransitionMovesForward = true;
  bool button = false;
  bool addPost = false;
  bool editProfile = false;
  IconData iconButton = Icons.edit_outlined;

  late AnimationController _fabAnimationController;
  late Animation<double> _fabScaleAnimation;
  late final List<TutorialStep> _tutorialSteps;

  final GlobalKey _titleKey = GlobalKey();
  final GlobalKey _avatarKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();
  final GlobalKey _fabKey = GlobalKey();
  final GlobalKey _exerciseCardKey = GlobalKey();
  final GlobalKey _logSymptomQuickActionKey = GlobalKey();
  final GlobalKey _addMedicationQuickActionKey = GlobalKey();
  final GlobalKey _medicationsToolCardKey = GlobalKey();
  final List<GlobalKey> _navItemKeys = List<GlobalKey>.generate(
    5,
    (_) => GlobalKey(),
  );

  final List<_NavItem> navItems = [
    _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
    _NavItem(
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      label: 'Manage',
    ),
    _NavItem(
      icon: Icons.favorite_outline,
      activeIcon: Icons.favorite,
      label: 'Recovery',
    ),
    _NavItem(
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      label: 'Community',
    ),
    _NavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
    ),
  ];

  void checkTab() {
    if (currentIndex == 4) {
      button = true;
      addPost = false;
      editProfile = true;
      iconButton = Icons.edit;
    } else {
      button = false;
      addPost = false;
      editProfile = false;
    }
  }

  @override
  void initState() {
    super.initState();
    currentIndex = singleton.page;
    _previousIndex = currentIndex;
    singleton.addListener(_onSingletonPageChange);
    if (currentIndex == 3 || currentIndex == 4) checkTab();

    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fabScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fabAnimationController, curve: Curves.easeOut),
    );
    if (button) {
      _fabAnimationController.forward();
    }

    _tutorialSteps = _buildTutorialSteps();
  }

  @override
  void dispose() {
    _tabSettleTimer?.cancel();
    singleton.removeListener(_onSingletonPageChange);
    _fabAnimationController.dispose();
    super.dispose();
  }

  Future<void> updateAccount({
    required String rawName,
    required String rawEmail,
  }) async {
    final updatedName = rawName.trim().isEmpty
        ? singleton.name
        : rawName.trim();
    final updatedEmail = rawEmail.trim().isEmpty
        ? singleton.email
        : rawEmail.trim();

    singleton.setEmail(updatedEmail);
    singleton.setName(updatedName);

    final updated = await singleton.updateUser(
      userName: updatedName,
      userEmail: updatedEmail,
    );
    if (!updated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to update profile right now'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _onTabTapped(int index) {
    HapticUtils.selectionClick();
    _setCurrentIndex(index, syncSingleton: true);
  }

  void _switchTabForTutorial(int index) {
    if (!mounted) return;
    _setCurrentIndex(index, syncSingleton: true);
  }

  void _onSingletonPageChange() {
    if (!mounted) return;
    final targetIndex = singleton.page;
    if (targetIndex != currentIndex) {
      _setCurrentIndex(targetIndex, syncSingleton: false);
    } else {
      // Data-only change (e.g. profile name/avatar updated): refresh the
      // app bar without a tab transition.
      setState(() {});
    }
  }

  String _appBarTitle() {
    if (currentIndex != 0) return navItems[currentIndex].label;
    final raw = singleton.name.trim();
    final firstName = (raw.isEmpty || raw == '[Name]')
        ? null
        : raw.split(' ').first;
    return _timeGreeting(firstName);
  }

  String _timeGreeting(String? name) {
    final now = DateTime.now();
    final hour = now.hour;

    final List<String> pool;
    if (hour >= 5 && hour < 12) {
      pool = const [
        'Good morning',
        'Morning',
        'Welcome back',
        'Have a great day',
      ];
    } else if (hour >= 12 && hour < 17) {
      pool = const [
        'Good afternoon',
        'Welcome back',
        'Great to see you',
        'Hope you\'re well',
      ];
    } else if (hour >= 17 && hour < 21) {
      pool = const [
        'Good evening',
        'Welcome back',
        'Great to see you',
        'Evening',
      ];
    } else {
      pool = const [
        'Good evening',
        'Welcome back',
        'Winding down',
        'Rest well',
      ];
    }

    // Stable for the whole day so the header doesn't flicker between
    // rebuilds, but rotates day to day.
    final seed = now.year * 400 + now.month * 31 + now.day;
    final greeting = pool[seed % pool.length];
    return name == null ? greeting : '$greeting, $name';
  }

  void _setCurrentIndex(int index, {required bool syncSingleton}) {
    if (index == currentIndex) return;

    setState(() {
      _previousIndex = currentIndex;
      _tabTransitionMovesForward = index > currentIndex;
      currentIndex = index;
      if (syncSingleton) {
        singleton.setPage(index);
      }
      button = false;
      if (currentIndex == 3 || currentIndex == 4) {
        checkTab();
        _fabAnimationController.forward(from: 0);
      } else {
        _fabAnimationController.reverse();
      }
    });

    // Unmount the outgoing tab once the slide transition settles; keeping it
    // mounted indefinitely leaks state and risks duplicate GlobalKeys.
    _tabSettleTimer?.cancel();
    _tabSettleTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _previousIndex = currentIndex);
    });
  }

  void _popToNavbarRoot() {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
  }

  List<TutorialStep> _buildTutorialSteps() {
    return <TutorialStep>[
      TutorialStep(
        targetKey: _navItemKeys[0],
        title: 'Home Dashboard',
        description:
            'Home shows your symptom and medication trend graphs at a glance.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(0);
        },
      ),
      TutorialStep(
        targetKey: _navItemKeys[1],
        title: 'Manage',
        description:
            'Manage is where you create symptom and medication entries.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(1);
        },
      ),
      TutorialStep(
        targetKey: _logSymptomQuickActionKey,
        title: 'Start Symptom Entry',
        description:
            'Tap Log Symptom to open the symptom form and capture what you felt.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(1);
        },
      ),
      TutorialStep(
        targetKey: TutorialTargets.symptomInputKey,
        title: 'Describe the Symptom',
        description:
            'Enter the symptom details here, then choose severity and time.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(1);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushNamed('/editLogScreen');
          });
        },
      ),
      TutorialStep(
        targetKey: TutorialTargets.saveSymptomButtonKey,
        title: 'Save Symptom',
        description:
            'When details are ready, save the entry to track symptom trends.',
      ),
      TutorialStep(
        targetKey: _addMedicationQuickActionKey,
        title: 'Start Medication Entry',
        description:
            'Next, open Add Medication to create a medication schedule.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(1);
        },
      ),
      TutorialStep(
        targetKey: TutorialTargets.medicationNameInputKey,
        title: 'Medication Details',
        description:
            'Enter medication name, then choose templates or select specific days.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(1);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushNamed('/editScheduleScreen');
          });
        },
      ),
      TutorialStep(
        targetKey: TutorialTargets.saveMedicationButtonKey,
        title: 'Save Medication',
        description:
            'Save to add this medication schedule to your weekly plan.',
      ),
      TutorialStep(
        targetKey: _medicationsToolCardKey,
        title: 'Open Medication List',
        description:
            'Open Medications to review saved schedules and details in one place.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(1);
        },
      ),
      TutorialStep(
        targetKey: TutorialTargets.scheduleAddMedicationKey,
        title: 'Add from Medication View',
        description:
            'Use this button in Medications to quickly add another schedule.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(1);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(
              context,
            ).push(buildSubtleFadeRoute(page: const ScheduleScreen()));
          });
        },
      ),
      TutorialStep(
        targetKey: _navItemKeys[2],
        title: 'Recovery',
        description:
            'Recovery has guided speech and exercise videos. Tap the tab to open it.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(2);
        },
      ),
      TutorialStep(
        targetKey: _exerciseCardKey,
        title: 'Open Physical Exercises',
        description:
            'Open Physical Exercises to view official guided recovery lessons.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(2);
        },
      ),
      TutorialStep(
        targetKey: TutorialTargets.firstExerciseCardKey,
        title: 'Choose an Exercise Video',
        description:
            'Pick a lesson card to open its guided exercise video player.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(2);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(
              context,
            ).push(buildSubtleFadeRoute(page: const ExerciseScreen()));
          });
        },
      ),
      TutorialStep(
        targetKey: TutorialTargets.exerciseVideoPlayerKey,
        title: 'Practice in Video Mode',
        description:
            'Use this player to follow the movement routine step by step.',
        onStepStarted: () {
          _popToNavbarRoot();
          final firstExerciseId = singleton.exercises.keys.isNotEmpty
              ? singleton.exercises.keys.first
              : '';
          if (firstExerciseId.isEmpty) return;
          singleton.setCurrentUrl(firstExerciseId);
          _switchTabForTutorial(2);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushNamed('/exerciseVideoScreen');
          });
        },
      ),
      TutorialStep(
        targetKey: _navItemKeys[3],
        title: 'Community',
        description:
            'Share and read posts in the community feed. Tap Feed or Resources in the tabs.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(3);
        },
      ),
      TutorialStep(
        targetKey: _navItemKeys[4],
        title: 'Profile',
        description:
            'Your profile and progress summary. Tap the tab to open it.',
        onStepStarted: () {
          _popToNavbarRoot();
          _switchTabForTutorial(4);
        },
      ),
      TutorialStep(
        targetKey: _avatarKey,
        title: 'Quick Profile',
        description: 'Tap your avatar anytime to jump to profile.',
        onStepStarted: () => _switchTabForTutorial(4),
        tooltipPosition: TutorialTooltipPosition.above,
      ),
      TutorialStep(
        targetKey: _settingsKey,
        title: 'Settings',
        description: 'Theme, legal docs, replay this tutorial, or sign out.',
        onStepStarted: () => _switchTabForTutorial(4),
        tooltipPosition: TutorialTooltipPosition.above,
      ),
      TutorialStep(
        targetKey: _fabKey,
        title: 'Quick Edit',
        description: 'On Profile, this button opens edit profile.',
        onStepStarted: () => _switchTabForTutorial(4),
        tooltipPosition: TutorialTooltipPosition.above,
      ),
    ];
  }

  bool _hasCustomImage() {
    return singleton.image.isNotEmpty &&
        singleton.image != 'images/711128.png' &&
        !singleton.image.contains('711128');
  }

  Widget _buildNavbarAvatar(AppColors colors) {
    if (_hasCustomImage()) {
      if (singleton.image.startsWith('images/')) {
        return Image.asset(
          singleton.image,
          fit: BoxFit.cover,
          width: 36,
          height: 36,
          errorBuilder: (_, _, _) => _buildInitialsAvatar(colors),
        );
      }
      return Image.file(
        // Decode at display size, not photo size.
        cacheWidth: 108,
        File(singleton.image),
        fit: BoxFit.cover,
        width: 36,
        height: 36,
        errorBuilder: (_, _, _) => _buildInitialsAvatar(colors),
      );
    }
    return _buildInitialsAvatar(colors);
  }

  Widget _buildInitialsAvatar(AppColors colors) {
    final displayName = singleton.name != '[Name]' && singleton.name.isNotEmpty
        ? singleton.name
        : 'User';
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Container(
      width: 36,
      height: 36,
      color: colors.surface.blend(colors.primary, 0.14),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colors.primary,
          ),
        ),
      ),
    );
  }

  void _showEditProfileDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (BuildContext c) {
        return _EditProfileSheet(
          initialName: singleton.name == '[Name]' ? '' : singleton.name,
          initialEmail: singleton.email == '[Email]' ? '' : singleton.email,
          onSave: (name, email) =>
              updateAccount(rawName: name, rawEmail: email),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TutorialOverlay(
      steps: _tutorialSteps,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: colors.background,
        appBar: _buildAppBar(colors),
        body: Column(
          children: [
            ListenableBuilder(
              listenable: singleton,
              builder: (context, _) {
                if (!singleton.localPersistenceFailed) {
                  return const SizedBox.shrink();
                }
                return Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    // Fixed pair (not theme tokens): 6.4:1 in both themes,
                    // where error-on-textOnPrimary dips below AA at 13px.
                    color: const Color(0xFFB91C1C),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: const Text(
                      'Your data is not being saved on this device right '
                      'now. Restart the app; if this keeps happening, '
                      'contact support.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
            Expanded(child: _buildAnimatedTabBody()),
          ],
        ),
        bottomNavigationBar: _buildBottomNavBar(colors),
        floatingActionButton: _buildFAB(colors),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppColors colors) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colors.background,
      toolbarHeight: 46,
      leadingWidth: 280,
      leading: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Row(
          children: [
            Flexible(
              child: ClipRect(
                child: Container(
                  key: _titleKey,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: <Widget>[...previousChildren, ?currentChild],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      // Sequence the swap: the outgoing title finishes
                      // fading out in the first half before the incoming
                      // one fades in, so the two never overlap.
                      final fade = CurvedAnimation(
                        parent: animation,
                        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
                      );
                      return FadeTransition(
                        opacity: fade,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(fade),
                          child: child,
                        ),
                      );
                    },
                    // Ellipsize rather than scale down: shrinking the
                    // greeting under large accessibility text settings gave
                    // low-vision users SMALLER text exactly when they asked
                    // for bigger.
                    child: Text(
                      _appBarTitle(),
                      key: ValueKey<int>(currentIndex),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        // User avatar: 34px visual inside a 48px tap target
        Semantics(
          button: true,
          selected: currentIndex == 4,
          label: 'Profile',
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: () => _onTabTapped(4),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Container(
                    key: _avatarKey,
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: currentIndex == 4
                            ? colors.primary
                            : colors.border,
                        width: 1.5,
                      ),
                    ),
                    child: ClipOval(child: _buildNavbarAvatar(colors)),
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          key: _settingsKey,
          iconSize: 19,
          tooltip: 'Settings',
          icon: Icon(Icons.settings_outlined, color: colors.textSecondary),
          onPressed: () {
            HapticUtils.lightImpact();
            Navigator.pushNamed(context, '/settingsScreen');
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBottomNavBar(AppColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(navItems.length, (index) {
              final isSelected = currentIndex == index;
              // Expanded so five items share width instead of overflowing
              // at large accessibility text scales.
              return Expanded(
                child: _buildNavItem(
                  navItems[index],
                  isSelected,
                  colors,
                  _navItemKeys[index],
                  () => _onTabTapped(index),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedTabBody() {
    final colors = context.colors;
    // Honor the OS reduce-motion setting for the tab slide/fade.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final transitionDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final visibleIndices = <int>[
      if (_previousIndex != currentIndex) _previousIndex,
      currentIndex,
    ];

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: visibleIndices.map((index) {
          final isCurrent = index == currentIndex;

          Offset targetOffset;
          if (isCurrent) {
            targetOffset = Offset.zero;
          } else {
            targetOffset = _tabTransitionMovesForward
                ? const Offset(-0.025, 0)
                : const Offset(0.025, 0);
          }

          return TickerMode(
            key: ValueKey<int>(index),
            enabled: true,
            child: IgnorePointer(
              ignoring: !isCurrent,
              child: AnimatedSlide(
                duration: transitionDuration,
                curve: Curves.easeOutCubic,
                offset: targetOffset,
                child: AnimatedOpacity(
                  duration: transitionDuration,
                  curve: Curves.easeOutCubic,
                  opacity: isCurrent ? 1.0 : 0.0,
                  child: RepaintBoundary(
                    child: ColoredBox(
                      color: colors.background,
                      child: _buildTab(index),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTab(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return ManageScreen(
          logSymptomQuickActionKey: _logSymptomQuickActionKey,
          addMedicationQuickActionKey: _addMedicationQuickActionKey,
          medicationsToolCardKey: _medicationsToolCardKey,
        );
      case 2:
        return RecoveryScreen(exerciseCardKey: _exerciseCardKey);
      case 3:
        return const CommunityScreen();
      case 4:
        return const ProfileScreen();
      default:
        return const HomeScreen();
    }
  }

  Widget _buildNavItem(
    _NavItem item,
    bool isSelected,
    AppColors colors,
    GlobalKey itemKey,
    VoidCallback onTap,
  ) {
    // Tremor-friendly: at least a 48x48 tap target per nav item, with a
    // semantic tab role so screen readers announce label and selection.
    return Semantics(
      button: true,
      selected: isSelected,
      label: item.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
            child: Container(
              key: itemKey,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    scale: isSelected ? 1.06 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        isSelected ? item.activeIcon : item.icon,
                        key: ValueKey(isSelected),
                        color: isSelected
                            ? colors.primary
                            : colors.navUnselected,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style:
                        (Theme.of(context).textTheme.labelSmall ??
                                const TextStyle())
                            .copyWith(
                              color: isSelected
                                  ? colors.navSelected
                                  : colors.navUnselected,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              fontSize: 11,
                            ),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildFAB(AppColors colors) {
    if (!button) return null;

    return ScaleTransition(
      scale: _fabScaleAnimation,
      child: FloatingActionButton(
        key: _fabKey,
        onPressed: () {
          HapticUtils.lightImpact();
          if (addPost) {
            // Add post functionality
          }
          if (editProfile) {
            _showEditProfileDialog();
          }
        },
        elevation: 2,
        child: Icon(iconButton, size: 22),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  _NavItem({required this.icon, required this.activeIcon, required this.label});
}

class _EditProfileSheet extends StatefulWidget {
  final String initialName;
  final String initialEmail;
  final Future<void> Function(String name, String email) onSave;

  const _EditProfileSheet({
    required this.initialName,
    required this.initialEmail,
    required this.onSave,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _save() {
    HapticUtils.lightImpact();
    final name = _nameController.text;
    final email = _emailController.text;
    Navigator.pop(context);
    widget.onSave(name, email);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Edit Profile',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            ModernTextField(
              controller: _nameController,
              label: 'Name',
              hint: 'Enter your name',
              prefixIcon: Icons.person_outline,
            ),
            const SizedBox(height: 12),
            ModernTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'Enter your email',
              prefixIcon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      HapticUtils.lightImpact();
                      Navigator.pop(context);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(color: colors.border),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
