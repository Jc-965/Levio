import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../singleton.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../utils/profile_image_store.dart';
import '../widgets/modern_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final singleton = Singleton();
  final picker = ImagePicker();
  bool? _emailVerified;

  void _onSingletonUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> updateImage() async {
    HapticUtils.lightImpact();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (!mounted) return;

    if (pickedFile != null) {
      final previousImage = singleton.image;
      final storedPath = await persistPickedImage(pickedFile);
      if (!mounted) return;
      singleton.setImage(storedPath);

      final updated = await singleton.updateUser(profileImage: storedPath);
      if (!mounted) return;
      if (!updated) {
        singleton.setImage(previousImage);
        HapticUtils.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not save profile image'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        return;
      }

      HapticUtils.success();
    }
  }

  @override
  void initState() {
    super.initState();
    singleton.addListener(_onSingletonUpdate);
    _refreshEmailVerificationStatus();
  }

  @override
  void dispose() {
    singleton.removeListener(_onSingletonUpdate);
    super.dispose();
  }

  bool _hasCustomImage() {
    return singleton.image.isNotEmpty &&
        singleton.image != 'images/711128.png' &&
        !singleton.image.contains('711128');
  }

  Future<void> _refreshEmailVerificationStatus() async {
    final verified = await singleton.isCurrentUserEmailVerified();
    if (!mounted) return;
    setState(() => _emailVerified = verified);
  }

  Future<void> _resendVerificationEmail() async {
    final currentEmail = singleton.email.trim();
    if (currentEmail.isEmpty || !currentEmail.contains('@')) return;
    final sent = await singleton.resendEmailVerification(currentEmail);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'Verification email sent. Please check your inbox.'
              : 'Could not send verification email right now.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildProfileImage(AppColors colors) {
    if (!_hasCustomImage()) {
      return _buildInitialsAvatar(colors);
    }

    if (singleton.image.startsWith('images/')) {
      return Image.asset(
        singleton.image,
        fit: BoxFit.cover,
        width: 86,
        height: 86,
        errorBuilder: (context, error, stackTrace) {
          return _buildInitialsAvatar(colors);
        },
      );
    } else {
      return Image.file(
        // Decode at display size, not photo size.
        cacheWidth: 384,
        File(singleton.image),
        fit: BoxFit.cover,
        width: 86,
        height: 86,
        errorBuilder: (context, error, stackTrace) {
          return _buildInitialsAvatar(colors);
        },
      );
    }
  }

  Widget _buildInitialsAvatar(AppColors colors) {
    final displayName = singleton.name != '[Name]' && singleton.name.isNotEmpty
        ? singleton.name
        : 'User';
    final initials = displayName
        .split(' ')
        .take(2)
        .map((s) => s.isNotEmpty ? s[0].toUpperCase() : '')
        .join();

    return Container(
      width: 86,
      height: 86,
      decoration: BoxDecoration(color: colors.surfaceVariant),
      child: Center(
        child: Text(
          initials.isNotEmpty ? initials : 'U',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (_emailVerified == false) ...[
            ModernCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: colors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Email not verified',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Please verify your email before posting in community features.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: _resendVerificationEmail,
                          child: const Text('Resend verification email'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Profile header
          _buildProfileHeader(colors),
          const SizedBox(height: 24),

          // Stats section
          _buildStatsSection(colors),
          const SizedBox(height: 24),

          // Activity section
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Activity',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 12),

          _ActivityItem(
            icon: Icons.favorite_outline,
            title: 'Symptoms',
            value: '${singleton.log.length}',
          ),
          const SizedBox(height: 8),

          _ActivityItem(
            icon: Icons.medication_outlined,
            title: 'Medications Tracked',
            value: '${singleton.schedule.length}',
          ),
          const SizedBox(height: 8),

          _ActivityItem(
            icon: Icons.fitness_center_outlined,
            title: 'Therapy Sessions',
            value: '${singleton.exerNum}',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(AppColors colors) {
    return Column(
      children: [
        // Profile image
        GestureDetector(
          onTap: updateImage,
          child: Stack(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.border, width: 1),
                ),
                child: ClipOval(
                  child: SizedBox(
                    width: 86,
                    height: 86,
                    child: _buildProfileImage(colors),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border, width: 1),
                  ),
                  child: Icon(
                    Icons.camera_alt_outlined,
                    color: colors.textSecondary,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Name
        Text(
          singleton.name == "[Name]" ? "Your Name" : singleton.name,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),

        // Email
        Text(
          singleton.email,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }

  Widget _buildStatsSection(AppColors colors) {
    return ModernCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(value: '${singleton.postNum}', label: 'Posts'),
          Container(width: 1, height: 32, color: colors.divider),
          _StatItem(value: '${singleton.exerNum}', label: 'Sessions'),
          Container(width: 1, height: 32, color: colors.divider),
          _StatItem(
            value: '${singleton.log.length + singleton.schedule.length}',
            label: 'Total Logs',
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _ActivityItem({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ModernCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: colors.textSecondary, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
