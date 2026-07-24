import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/motion_coach/motion_cue_speaker.dart';

void main() {
  test('prefers an offline US English voice', () {
    final Map<String, String>? selected = selectOfflineEnglishVoice(<Object?>[
      <Object?, Object?>{
        'name': 'Online US',
        'locale': 'en-US',
        'network_required': '1',
      },
      <Object?, Object?>{
        'name': 'Local UK',
        'locale': 'en-GB',
        'network_required': '0',
      },
      <Object?, Object?>{
        'name': 'Local US',
        'locale': 'en-US',
        'network_required': '0',
      },
    ]);

    expect(selected, <String, String>{'locale': 'en-US', 'name': 'Local US'});
  });

  test('fails closed when only network voices are available', () {
    final Map<String, String>? selected = selectOfflineEnglishVoice(<Object?>[
      <Object?, Object?>{
        'name': 'Online US',
        'locale': 'en-US',
        'network_required': 'true',
      },
    ]);

    expect(selected, isNull);
  });
}
