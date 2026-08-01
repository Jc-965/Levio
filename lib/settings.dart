import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:terminate_restart/terminate_restart.dart';

import 'legal/legal_document_screen.dart';
import 'services/medication_reminder_service.dart';
import 'services/tutorial_service.dart';
import 'singleton.dart';
import 'theme/app_theme.dart';
import 'utils/app_routes.dart';
import 'utils/haptic_utils.dart';
import 'widgets/modern_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final singleton = Singleton();
  final tutorialService = TutorialService();
  bool theme = false;
  String _appVersion = 'Loading...';
  bool _isSyncing = false;
  bool _useRealNameInCommunity = false;
  final _reminders = MedicationReminderService();
  bool _remindersEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    theme = singleton.colorMode == 1;
    _loadAppVersion();
    _loadCommunityIdentityPreference();
    _loadReminderPreferences();
  }

  Future<void> _loadReminderPreferences() async {
    final enabled = await _reminders.remindersEnabled();
    final time = await _reminders.reminderTime();
    if (!mounted) return;
    setState(() {
      _remindersEnabled = enabled;
      _reminderTime = time;
    });
  }

  Future<void> _toggleReminders(bool value) async {
    HapticUtils.selectionClick();
    if (value) {
      final granted = await _reminders.requestPermission();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications are turned off for ParkiWell in system '
              'settings. Enable them to receive reminders.',
            ),
          ),
        );
        return;
      }
    }
    await _reminders.setRemindersEnabled(value);
    await _reminders.syncFromSchedule(singleton.schedule);
    if (!mounted) return;
    setState(() => _remindersEnabled = value);
  }

  Future<void> _pickReminderTime() async {
    HapticUtils.lightImpact();
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
      helpText: 'Medication reminder time',
    );
    if (picked == null) return;
    await _reminders.setReminderTime(picked);
    await _reminders.syncFromSchedule(singleton.schedule);
    if (!mounted) return;
    setState(() => _reminderTime = picked);
  }

  Future<void> _loadCommunityIdentityPreference() async {
    final useRealName = await singleton.getCommunityUseRealName();
    if (!mounted) return;
    setState(() => _useRealNameInCommunity = useRealName);
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = '${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appVersion = 'Unknown';
      });
    }
  }

  void _showDeleteAccountDialog() {
    final colors = context.colors;

    showDialog(
      context: context,
      builder: (BuildContext c) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: Text(
            'Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently lost.',
            style: Theme.of(
              c,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                HapticUtils.lightImpact();
                Navigator.pop(c);
                await _showDeletingDialog();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showSignOutDialog() {
    final colors = context.colors;
    showDialog(
      context: context,
      builder: (BuildContext c) {
        return AlertDialog(
          title: const Text('Sign Out'),
          content: Text(
            'Sign out of your account on this device?',
            style: Theme.of(
              c,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(c);
                await _signOut();
              },
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _signOut() async {
    HapticUtils.lightImpact();
    await singleton.signOut();
    if (!mounted) return;
    // Pop back to the root; MyApp reacts to the cleared session and swaps
    // the Navbar for the onboarding flow. Pushing a nested MyApp here used
    // to mount duplicate widget trees (and duplicate GlobalKeys).
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _restartTutorial() async {
    HapticUtils.lightImpact();
    await tutorialService.resetTutorial();
    singleton.setPage(0);
    if (!mounted) return;
    // Return to the existing Navbar instead of pushing a nested app copy;
    // the Navbar's TutorialOverlay restarts in place.
    Navigator.of(context).popUntil((route) => route.isFirst);
    tutorialService.requestRestart();
  }

  Future<void> _syncNow() async {
    if (_isSyncing || singleton.isSyncInProgress) return;
    setState(() => _isSyncing = true);
    final synced = await singleton.syncNow();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(synced ? 'Sync complete' : 'Unable to sync right now.'),
      ),
    );
  }

  Future<void> _exportBackup() async {
    // Confirm first: the backup contains the full health record.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Export Health Data'),
        content: const Text(
          'The backup file contains your full health record: symptoms, '
          'medications, and profile details. Only share it with apps and '
          'people you trust.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final payload = singleton.exportBackupJson();
    try {
      // Share as a file, not raw text: text payloads land in clipboard
      // histories and message previews.
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/parkiwell-backup.json');
      await file.writeAsString(payload);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'ParkiWell backup'),
      );
      await file.delete();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to export backup right now.')),
      );
    }
  }

  Future<void> _showImportBackupDialog() async {
    final colors = context.colors;
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (c) {
        return AlertDialog(
          title: const Text('Import Backup'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(c).size.width * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste backup JSON below to restore local data.',
                  style: Theme.of(
                    c,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: '{"backup_version":1,...}',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final success = await singleton.importBackupJson(
                  controller.text.trim(),
                );
                if (!c.mounted || !mounted) return;
                Navigator.pop(c);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Backup imported into local cache'
                          : 'Backup import failed',
                    ),
                  ),
                );
              },
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  Future<void> _showDeletingDialog() async {
    final colors = context.colors;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // The dialog builder must stay side-effect free: builders can rerun on
    // rebuild, which would fire the deletion more than once.
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext c) => _buildDeletingDialog(c, colors),
      ),
    );

    final deleted = await singleton.deleteAccount();
    if (!mounted) return;
    navigator.pop();

    if (deleted) {
      HapticUtils.lightImpact();
      await TerminateRestart.instance.restartApp(
        options: const TerminateRestartOptions(terminate: false),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Account deletion failed. Your data has NOT been removed. '
          'Please check your connection and try again.',
        ),
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Widget _buildDeletingDialog(BuildContext c, AppColors colors) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          CircularProgressIndicator(color: colors.primary, strokeWidth: 2),
          const SizedBox(height: 20),
          Text('Deleting Account...', style: Theme.of(c).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Please wait while we remove your data',
            style: Theme.of(
              c,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: colors.textPrimary,
            size: 22,
          ),
          onPressed: () {
            HapticUtils.lightImpact();
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Container(
        color: colors.background,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Appearance section
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              _SettingsTile(
                icon: theme
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                title: 'Theme',
                subtitle: theme ? 'Dark mode' : 'Light mode',
                trailing: _buildThemeSwitch(colors),
              ),
              const SizedBox(height: 24),

              Text(
                'Data & Sync',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              _SettingsTile(
                icon: singleton.isOnline
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                title: 'Sync Status',
                subtitle:
                    '${singleton.lastSyncStatus} • ${singleton.lastSyncDisplay}',
              ),
              const SizedBox(height: 8),

              _SettingsTile(
                icon: Icons.sync_rounded,
                title: 'Sync Now',
                subtitle: _isSyncing || singleton.isSyncInProgress
                    ? 'Syncing...'
                    : 'Refresh cloud data',
                trailing: _isSyncing || singleton.isSyncInProgress
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      )
                    : null,
                onTap: _isSyncing ? null : _syncNow,
              ),
              const SizedBox(height: 8),

              _SettingsTile(
                icon: Icons.upload_file_outlined,
                title: 'Export Backup',
                subtitle: 'Share JSON backup of your local data',
                onTap: _exportBackup,
              ),
              const SizedBox(height: 8),

              _SettingsTile(
                icon: Icons.download_for_offline_outlined,
                title: 'Import Backup',
                subtitle: 'Restore from backup JSON',
                onTap: _showImportBackupDialog,
              ),
              const SizedBox(height: 24),

              Text(
                'Reminders',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              _SettingsTile(
                icon: Icons.notifications_active_outlined,
                title: 'Medication Reminders',
                subtitle: _remindersEnabled
                    ? 'On, at scheduled days'
                    : 'Get notified on medication days',
                trailing: Switch(
                  value: _remindersEnabled,
                  activeThumbColor: colors.primary,
                  onChanged: _toggleReminders,
                ),
              ),
              if (_remindersEnabled) ...[
                const SizedBox(height: 8),
                _SettingsTile(
                  icon: Icons.schedule_outlined,
                  title: 'Reminder Time',
                  subtitle: _reminderTime.format(context),
                  onTap: _pickReminderTime,
                ),
              ],
              const SizedBox(height: 24),

              Text(
                'Privacy',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              _SettingsTile(
                icon: Icons.badge_outlined,
                title: 'Use Real Name in Community',
                subtitle: _useRealNameInCommunity
                    ? 'Posts show your profile name'
                    : 'Posts show a private alias',
                trailing: Switch(
                  value: _useRealNameInCommunity,
                  activeThumbColor: colors.primary,
                  onChanged: (value) async {
                    HapticUtils.selectionClick();
                    setState(() => _useRealNameInCommunity = value);
                    await singleton.setCommunityUseRealName(value);
                  },
                ),
              ),
              const SizedBox(height: 24),

              // About section
              Text(
                'About',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              _SettingsTile(
                icon: Icons.info_outlined,
                title: 'App Version',
                subtitle: _appVersion,
              ),
              const SizedBox(height: 8),

              _SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms of Service',
                trailing: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.textTertiary,
                ),
                onTap: () {
                  HapticUtils.lightImpact();
                  Navigator.of(context).push(
                    buildSubtleFadeRoute(
                      page: const LegalDocumentScreen(
                        type: LegalDocumentType.termsOfService,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),

              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                trailing: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.textTertiary,
                ),
                onTap: () {
                  HapticUtils.lightImpact();
                  Navigator.of(context).push(
                    buildSubtleFadeRoute(
                      page: const LegalDocumentScreen(
                        type: LegalDocumentType.privacyPolicy,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Account section
              Text(
                'Account',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              _SettingsTile(
                icon: Icons.tour_outlined,
                title: 'Replay Tutorial',
                subtitle: 'Show the guided app walkthrough again',
                onTap: _restartTutorial,
              ),
              const SizedBox(height: 8),

              _SettingsTile(
                icon: Icons.logout_rounded,
                title: 'Sign Out',
                subtitle: 'Sign out from this device',
                onTap: _showSignOutDialog,
              ),
              const SizedBox(height: 24),

              // Danger zone
              Text(
                'Danger Zone',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),

              _SettingsTile(
                icon: Icons.delete_outline,
                title: 'Delete Account',
                subtitle: 'Permanently delete all your data',
                iconColor: colors.error,
                onTap: _showDeleteAccountDialog,
              ),
              const SizedBox(height: 48),

              // Footer
              Center(
                child: Column(
                  children: [
                    Text(
                      'ParkiWell',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Parkinson\'s Care Management',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeSwitch(AppColors colors) {
    return GestureDetector(
      onTap: () {
        HapticUtils.lightImpact();
        setState(() {
          theme = !theme;
          singleton.switchColorTheme(theme);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: theme ? colors.primary : colors.border,
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: theme ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.iconColor,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ModernCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: iconColor ?? colors.textSecondary, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
