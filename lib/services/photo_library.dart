/// Saving a caught picture to the phone's own Photos (iOS) or gallery
/// (Android), as well as LookUp's own copy for the Log.
///
/// Only "add" access is asked for on iOS, never read access: LookUp can put
/// pictures into Photos but can't look through them. That's also why the
/// Log shows LookUp's own copy ([PhotoStore]) rather than finding the
/// picture again in Photos. Third-party apps can't tag a picture in Photos,
/// so the picture itself carries the words (what, when, where, "LookUp")
/// along its foot.
library;

import 'dart:typed_data';

import 'package:gal/gal.dart';

abstract class PhotoLibrary {
  const PhotoLibrary();

  /// Saves [png] to the phone's photos. False when access was refused or
  /// saving failed; the caller still keeps LookUp's own copy.
  Future<bool> save(Uint8List png, {required String name});

  /// Saves the video at [path] (a timelapse) to the phone's photos.
  Future<bool> saveVideo(String path);
}

class GalPhotoLibrary extends PhotoLibrary {
  const GalPhotoLibrary();

  @override
  Future<bool> save(Uint8List png, {required String name}) async {
    try {
      if (!await Gal.hasPermission() && !await Gal.requestPermission()) return false;
      await Gal.putImageBytes(png, name: name);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> saveVideo(String path) async {
    try {
      if (!await Gal.hasPermission() && !await Gal.requestPermission()) return false;
      await Gal.putVideo(path);
      return true;
    } catch (_) {
      return false;
    }
  }
}
