import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum LegalDocumentType { termsOfService, privacyPolicy }

class LegalDocumentScreen extends StatelessWidget {
  final LegalDocumentType type;

  const LegalDocumentScreen({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sections = _sectionsFor(type);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          type == LegalDocumentType.termsOfService
              ? 'Terms of Service'
              : 'Privacy Policy',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Container(
        color: colors.background,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          itemBuilder: (context, index) {
            final section = sections[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  section.body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.55,
                  ),
                ),
              ],
            );
          },
          separatorBuilder: (_, _) => const SizedBox(height: 18),
          itemCount: sections.length,
        ),
      ),
    );
  }

  List<_LegalSection> _sectionsFor(LegalDocumentType type) {
    if (type == LegalDocumentType.termsOfService) {
      return const [
        _LegalSection(title: 'Effective Date', body: 'July 18, 2026'),
        _LegalSection(
          title: 'Agreement to These Terms',
          body:
              'These Terms of Service are a binding agreement between you and ParkiWell governing your use of the app. By creating an account, completing setup, or using the app, you agree to these Terms and to the Privacy Policy. If you do not agree, please do not use the app.',
        ),
        _LegalSection(
          title: 'Medical Disclaimer',
          body:
              'ParkiWell is an organizational and educational tool. It is not a medical device and does not provide medical advice, diagnosis, monitoring, or treatment. Trends, insights, charts, guided videos, and optional camera-based movement observations are for general information only and are not a substitute for the judgment of a qualified healthcare professional. Never disregard, delay, or change medical care because of anything recorded in or shown by the app. Decisions about medications, therapy, and exercise belong with you and your care team.',
        ),
        _LegalSection(
          title: 'Emergencies',
          body:
              'The app is not designed for emergencies, and no one monitors the information you enter. If you believe you are experiencing a medical emergency, call your local emergency number immediately.',
        ),
        _LegalSection(
          title: 'Exercise and Speech Practice Safety',
          body:
              'Guided speech and movement content is educational and general in nature. Consult your healthcare provider before starting any exercise program, especially regarding balance, freezing of gait, or fall risk. Practice in a safe environment, use support such as a sturdy chair where shown, and stop immediately if you feel pain, dizziness, chest discomfort, shortness of breath, or distress. You are responsible for exercising within your own limits.',
        ),
        _LegalSection(
          title: 'Eligibility',
          body:
              'You must be at least 13 years old (or the higher minimum age in your jurisdiction) to use the app. If you use ParkiWell on behalf of someone in your care, you are responsible for having their permission to record information about them.',
        ),
        _LegalSection(
          title: 'Your Account',
          body:
              'Cloud sync and community features require an account with a verified email, created with a password or Google sign-in. Keep your credentials confidential — you are responsible for activity under your account. The core of the app also works without an account; in that case your data exists only on this device and cannot be recovered if the device or app is removed.',
        ),
        _LegalSection(
          title: 'Acceptable Use',
          body:
              'You may use the app for your own personal, non-commercial care organization. You agree not to use it to provide medical services to others, attempt to access another user\'s data, bypass security controls, upload malicious code, scrape the service, or use it in violation of applicable law.',
        ),
        _LegalSection(
          title: 'Community Rules',
          body:
              'The community exists so people affected by Parkinson\'s can support each other. Be safe and kind: no harassment, hate speech, or threats. No medical misinformation — do not present unproven treatments as cures or discourage others from following professional advice. No advertising or solicitation. Do not post anyone else\'s personal or health information without permission. We may remove content and restrict or suspend accounts that break these rules. Views posted in the community belong to their authors, not to ParkiWell.',
        ),
        _LegalSection(
          title: 'Your Content',
          body:
              'You own everything you create in the app — logs, schedules, recovery history, recordings, posts, and comments. You grant ParkiWell permission to store and process this content solely to operate, secure, and improve the app for you; community posts are additionally shown to other users. This permission ends for an item when you delete it, except for copies in encrypted backups until they rotate out. Practice recordings you capture never leave your device.',
        ),
        _LegalSection(
          title: 'Third-Party Content',
          body:
              'Recovery videos are embedded from YouTube and remain the property of their creators, with attribution shown in the app. Your use of embedded players is also subject to YouTube\'s terms and Google\'s privacy policy. Videos may become unavailable if removed by their owners, and the catalog may change over time.',
        ),
        _LegalSection(
          title: 'Service Availability and Changes',
          body:
              'Features may change, be added, or be removed, and the service may occasionally be unavailable due to maintenance, updates, or third-party outages. Because ParkiWell is local-first, your recorded data stays available on your device during cloud outages and sync resumes when connectivity returns. If the service is ever discontinued, we will give reasonable notice so you can access your data and delete your account.',
        ),
        _LegalSection(
          title: 'Termination',
          body:
              'You may stop using the app at any time and can delete your account from Settings, which removes your synced records. We may suspend or terminate access for material breaches of these Terms, where required by law, or to protect users or the service.',
        ),
        _LegalSection(
          title: 'Disclaimers and Limitation of Liability',
          body:
              'The app is provided "as is" and "as available," without warranties of any kind to the maximum extent permitted by law. We do not warrant that it will be uninterrupted, error-free, or that data will never be lost — please keep independent records of critical medical information. To the maximum extent permitted by law, ParkiWell is not liable for indirect, incidental, or consequential damages, including damages arising from reliance on the app or from exercise activities. Some jurisdictions do not allow certain exclusions, so parts of this section may not apply to you.',
        ),
        _LegalSection(
          title: 'Changes to These Terms',
          body:
              'We may update these Terms as the app evolves. Material changes will be announced in the app, and continued use after the effective date of a revision constitutes acceptance.',
        ),
        _LegalSection(
          title: 'Contact',
          body:
              'Questions about these Terms can be sent to the support contact listed on the app\'s store page.',
        ),
      ];
    }

    return const [
      _LegalSection(title: 'Effective Date', body: 'July 18, 2026'),
      _LegalSection(
        title: 'Summary',
        body:
            'ParkiWell works local-first: your records live in private storage on your device and remain usable offline. Cloud sync is optional and happens only when you sign in. We do not sell personal data, show ads, track you across apps, or operate remote analytics or crash reporting. The optional motion coach analyzes camera frames on-device with Google MediaPipe, which sends API performance and utilization metrics to Google but never your camera input; when you are signed in with backup on, only derived movement scores and repetition counts sync to your account. Practice recordings and camera data never leave your device, and you can delete your account, your movement history, and synced data in-app at any time.',
      ),
      _LegalSection(
        title: 'Information You Provide',
        body:
            'Account and profile data for synced accounts (name, email, optional profile image); symptom logs with severity and time; medication names, dose details, schedules, and adherence events; weekly recovery goals and completed session history; and community posts, comments, and likes if you use the community.',
      ),
      _LegalSection(
        title: 'What Stays on Your Device',
        body:
            'Practice videos you record (up to three minutes, using the camera and microphone) are stored only on your device and are never uploaded. During an optional motion check, camera images and pose landmarks are processed on-device; the temporary landmark stream is discarded after analysis and is not uploaded or stored. Trends, streaks, pattern insights, and motion observations are computed locally from your own records. Routine diagnostic logs stay on the device and are not sent to any remote service.',
      ),
      _LegalSection(
        title: 'What We Do Not Collect',
        body:
            'No location data, contacts, files, or browsing history. No advertising identifiers and no cross-app tracking. We do not use camera images or pose landmarks to identify you. No data from HealthKit, Health Connect, or wearables. No background recording of any kind.',
      ),
      _LegalSection(
        title: 'How We Use Data',
        body:
            'Only to provide app features (tracking, schedules, charts, streaks, community, and optional on-device motion observations), sync your records across devices when you use an account, authenticate you and process email verification and password resets, moderate the community for safety, and respond to support requests. Your content and health records are not used for advertising, marketing profiles, or model training, and they are never sold.',
      ),
      _LegalSection(
        title: 'Where Data Is Stored',
        body:
            'Before you sign in, everything is stored in the app\'s private on-device storage. With a synced account, records are also stored in a Supabase-hosted database protected by encryption in transit (HTTPS) and at rest, with row-level security so each account can only access its own records. Changes made offline are queued on-device and replayed safely when connectivity returns.',
      ),
      _LegalSection(
        title: 'Sharing',
        body:
            'We do not sell personal data or share it with advertisers or data brokers. Service providers include Supabase for hosting and authentication, Google when you choose Google sign-in or use MediaPipe motion check, and Anthropic only if you turn on the optional AI session summary. MediaPipe processes camera input on-device and sends Google API performance and utilization metrics, not images, video, or pose landmarks. With the AI summary enabled, the derived scores and repetition counts of a backed-up motion session (never your name, camera images, video, or pose data) are sent to Anthropic\'s Claude API to write a short summary; it is off by default and can be disabled any time in Motion coach settings. Recovery videos are embedded from YouTube, which may collect data under its own policy when a video loads. We may disclose information if required by law.',
      ),
      _LegalSection(
        title: 'Community Visibility',
        body:
            'Posts, comments, and likes are visible to other users along with your display name and profile image. Your symptom logs, medications, recovery history, and recordings are never visible to other users. Please avoid posting private contact details or health information you want to keep private.',
      ),
      _LegalSection(
        title: 'Retention and Deletion',
        body:
            'Synced records are kept while your account exists. Deleting your account in Settings removes your account and associated synced data from the active database; residual copies in encrypted backups expire on the provider\'s rotation schedule. Local data stays on your device until you delete the account or uninstall the app.',
      ),
      _LegalSection(
        title: 'Your Rights and Controls',
        body:
            'You can edit your profile, delete individual logs, schedules, posts, and comments, and delete your account entirely from Settings. Depending on where you live (including the EEA, UK, and California), you may also have legal rights to access, correct, export, or erase your personal data and to complain to a supervisory authority. Contact the support address on the app\'s store page to exercise rights not already available in-app.',
      ),
      _LegalSection(
        title: 'Security',
        body:
            'All traffic is encrypted in transit, synced data is encrypted at rest, passwords are held only as secure hashes by the authentication provider, new accounts require email verification, and password-reset links expire. Local data lives in the operating system\'s sandboxed app container. No method of storage is perfectly secure; if a breach affects your data we will notify you as required by law.',
      ),
      _LegalSection(
        title: 'Children',
        body:
            'ParkiWell is not directed to children and is not intended for anyone under 13 (or the higher minimum age in your jurisdiction). We do not knowingly collect personal data from children and will delete it if notified.',
      ),
      _LegalSection(
        title: 'Health Information Notice',
        body:
            'Records you keep in ParkiWell are personal notes you create for yourself; they are not medical records held by a healthcare provider, and ParkiWell is not covered by HIPAA. The app provides organizational and educational features only and does not provide medical advice, diagnosis, or treatment.',
      ),
      _LegalSection(
        title: 'Device Permissions',
        body:
            'Camera (practice recordings, optional on-device motion check, and profile photos), microphone (audio in practice recordings), and photo library (profile picture) are all optional — denying a permission disables only that feature. Core local features work offline. Network access is used for optional sync, community, embedded videos, and MediaPipe API performance and utilization metrics after you choose to use motion check.',
      ),
      _LegalSection(
        title: 'Changes and Contact',
        body:
            'Material changes to this policy will be announced in the app and reflected in the effective date above. Privacy questions and requests can be sent to the support contact listed on the app\'s store page.',
      ),
    ];
  }
}

class _LegalSection {
  final String title;
  final String body;

  const _LegalSection({required this.title, required this.body});
}
