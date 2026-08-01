import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Copies a picked image out of the image_picker cache (which the OS purges
/// at will) into app documents storage, so the avatar survives instead of
/// silently reverting to the default.
Future<String> persistPickedImage(XFile picked) async {
  final directory = await getApplicationDocumentsDirectory();
  final avatarDir = Directory('${directory.path}/avatars');
  await avatarDir.create(recursive: true);
  final dotIndex = picked.path.lastIndexOf('.');
  final extension = dotIndex == -1
      ? 'jpg'
      : picked.path.substring(dotIndex + 1);
  final target = '${avatarDir.path}/profile.$extension';
  await picked.saveTo(target);
  return target;
}
