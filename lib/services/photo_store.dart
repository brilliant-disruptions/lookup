/// Photos attached to sightings: picked from the library, copied into the
/// app's own folder so they survive the user tidying their camera roll.
library;

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class PhotoStore {
  const PhotoStore();

  static Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/sightings');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Lets the user pick a photo; returns the stored file name, or null.
  Future<String?> pickFor(String eventId) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 88);
    if (picked == null) return null;
    final safe = eventId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final ext = picked.path.contains('.') ? picked.path.substring(picked.path.lastIndexOf('.')) : '.jpg';
    final name = '$safe-${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(picked.path).copy('${(await _dir()).path}/$name');
    return name;
  }

  Future<File?> fileFor(String? name) async {
    if (name == null) return null;
    final f = File('${(await _dir()).path}/$name');
    return await f.exists() ? f : null;
  }

  Future<void> delete(String? name) async {
    final f = await fileFor(name);
    if (f != null) await f.delete();
  }
}
