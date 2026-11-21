/// The phone's own Photos (iOS) or gallery (Android), where catches live.
///
/// A catch goes into a "LookUp" album, and Photos gives back its id. The
/// Log keeps that id and a small thumbnail, and shows the picture from
/// Photos: the full picture is stored once, in the user's own library
/// (and their iCloud if they use it), not again inside LookUp.
///
/// On iPhone that needs read access, and LookUp recommends **Limited**:
/// LookUp only ever looks at the pictures it saved, in its own album.
/// Pictures an app saves stay visible to it under Limited access, and since
/// iOS 15 an app can create and read its own album there too. Without read
/// access a catch still goes into the Log with LookUp's own full copy, as
/// before.
///
/// On Android 10 and later an app can save to and read back its own
/// pictures without any permission (they go in Pictures/LookUp).
///
/// Every picture also carries its words in the file (`CatchTag`), and its
/// place and time are set on the Photos item, so it shows on the Photos map.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';

import '../domain/log/restore.dart' show FoundCatch;
import '../domain/photo/catch_tag.dart';

/// What LookUp may do with Photos.
enum PhotosAccess {
  /// Not asked yet (iPhone): LookUp explains before iOS asks.
  unasked,

  /// Limited (recommended): LookUp sees what it saved.
  limited,

  /// Full access (LookUp still only looks at its own album).
  full,

  /// Refused or restricted: catches stay in LookUp only.
  denied,
}

/// Where a picture went.
class SavedPicture {
  const SavedPicture({required this.toPhotos, this.assetId});

  /// Whether it reached Photos at all.
  final bool toPhotos;

  /// Its Photos id, when LookUp can find it again from there. Null means
  /// keep LookUp's own full copy.
  final String? assetId;

  static const none = SavedPicture(toPhotos: false);
}

abstract class PhotoLibrary {
  const PhotoLibrary();

  /// The album catches go in.
  static const album = 'LookUp';

  Future<PhotosAccess> access();

  /// Asks the phone (iPhone shows its prompt once).
  Future<PhotosAccess> ask();

  /// Saves a caught picture to the LookUp album, with [tag] in the file and
  /// on the Photos item.
  Future<SavedPicture> save(Uint8List png, {required String name, CatchTag? tag, double? lat, double? lon});

  /// Saves the video at [path] (a timelapse) to the LookUp album.
  Future<SavedPicture> saveVideo(String path, {String? title, DateTime? at, double? lat, double? lon});

  /// The picture with [assetId], about [px] on its long side; null when
  /// it's gone from Photos or out of reach.
  Future<Uint8List?> picture(String assetId, {int px = 1600});

  /// Opens iOS's picker to change a Limited selection.
  Future<void> manageLimited();

  /// LookUp's own pictures in the album that carry a catch's details
  /// (`CatchTag`), newest first, at most [max]: for bringing the Log back
  /// on a new phone.
  Future<List<FoundCatch>> albumCatches({int max = 300});

  /// Opens LookUp's page in the phone's Settings (to change Photos access).
  Future<void> openSettings();

  /// Whether the phone asks about Photos at all (iPhone does; Android
  /// needs nothing for LookUp's own pictures).
  bool get asks;
}

class DevicePhotoLibrary extends PhotoLibrary {
  DevicePhotoLibrary();

  static const _ask = PermissionRequestOption(iosAccessLevel: IosAccessLevel.readWrite);
  AssetPathEntity? _album;

  static PhotosAccess _of(PermissionState s) => switch (s) {
        PermissionState.notDetermined => PhotosAccess.unasked,
        PermissionState.limited => PhotosAccess.limited,
        PermissionState.authorized => PhotosAccess.full,
        PermissionState.denied || PermissionState.restricted => PhotosAccess.denied,
      };

  @override
  Future<PhotosAccess> access() async {
    // Android 10+ needs no permission for LookUp's own pictures.
    if (!Platform.isIOS) return PhotosAccess.full;
    try {
      return _of(await PhotoManager.getPermissionState(requestOption: _ask));
    } catch (_) {
      return PhotosAccess.denied;
    }
  }

  @override
  Future<PhotosAccess> ask() async {
    if (!Platform.isIOS) return PhotosAccess.full;
    try {
      return _of(await PhotoManager.requestPermissionExtend(requestOption: _ask));
    } catch (_) {
      return PhotosAccess.denied;
    }
  }

  Future<bool> _ready() async {
    if (Platform.isIOS) {
      final a = await access();
      return a == PhotosAccess.limited || a == PhotosAccess.full;
    }
    // On Android LookUp only touches its own pictures, which needs no read
    // permission; the plugin would otherwise ask for one.
    await PhotoManager.setIgnorePermissionCheck(true);
    return true;
  }

  /// The LookUp album on iPhone, made the first time (Android files them
  /// by folder instead).
  Future<AssetPathEntity?> _lookUpAlbum({bool create = true}) async {
    if (!Platform.isIOS) return null;
    if (_album != null) return _album;
    final paths = await PhotoManager.getAssetPathList(type: RequestType.common, hasAll: false);
    _album = paths.where((p) => p.name == PhotoLibrary.album).firstOrNull ??
        (create ? await PhotoManager.editor.darwin.createAlbum(PhotoLibrary.album) : null);
    return _album;
  }

  @override
  Future<List<FoundCatch>> albumCatches({int max = 300}) async {
    try {
      if (!await _ready()) return const [];
      // iPhone: the album; Android: the Pictures/LookUp folder, which the
      // gallery lists by its name too.
      final album = Platform.isIOS
          ? await _lookUpAlbum(create: false)
          : (await PhotoManager.getAssetPathList(type: RequestType.image, hasAll: false))
              .where((p) => p.name == PhotoLibrary.album)
              .firstOrNull;
      if (album == null) return const [];
      final out = <FoundCatch>[];
      for (final a in await album.getAssetListPaged(page: 0, size: max)) {
        if (a.type != AssetType.image) continue;
        final bytes = await a.originBytes;
        final tag = bytes == null ? null : catchTagOf(bytes);
        if (tag != null) out.add((assetId: a.id, tag: tag));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _file(AssetEntity a) async {
    try {
      final album = await _lookUpAlbum();
      if (album != null) await PhotoManager.editor.copyAssetToPath(asset: a, pathEntity: album);
    } catch (_) {
      // Still in Photos, just not in the album.
    }
  }

  @override
  Future<SavedPicture> save(Uint8List png, {required String name, CatchTag? tag, double? lat, double? lon}) async {
    final bytes = tag == null ? png : pngWithCatchTag(png, tag);
    try {
      if (await _ready()) {
        final a = await PhotoManager.editor.saveImage(
          bytes,
          filename: '$name.png',
          title: tag?.title ?? name,
          desc: tag?.description,
          relativePath: 'Pictures/${PhotoLibrary.album}',
          latitude: lat,
          longitude: lon,
          creationDate: tag?.at.toLocal(),
        );
        await _file(a);
        // Only lean on Photos if LookUp can really find it again.
        final back = await AssetEntity.fromId(a.id);
        return SavedPicture(toPhotos: true, assetId: back == null ? null : a.id);
      }
    } catch (_) {
      // Fall through to add-only saving.
    }
    return _addOnly(() => Gal.putImageBytes(bytes, name: name));
  }

  @override
  Future<SavedPicture> saveVideo(String path, {String? title, DateTime? at, double? lat, double? lon}) async {
    try {
      if (await _ready()) {
        final a = await PhotoManager.editor.saveVideo(
          File(path),
          title: title,
          relativePath: 'Movies/${PhotoLibrary.album}',
          latitude: lat,
          longitude: lon,
          creationDate: at?.toLocal(),
        );
        await _file(a);
        return SavedPicture(toPhotos: true, assetId: a.id);
      }
    } catch (_) {
      // Fall through.
    }
    return _addOnly(() => Gal.putVideo(path));
  }

  /// Without read access (or on an old Android), still put it in Photos
  /// if allowed to add, but keep LookUp's own copy.
  Future<SavedPicture> _addOnly(Future<void> Function() put) async {
    if (Platform.isIOS && await access() == PhotosAccess.denied) return SavedPicture.none;
    try {
      if (!await Gal.hasPermission() && !await Gal.requestPermission()) return SavedPicture.none;
      await put();
      return const SavedPicture(toPhotos: true);
    } catch (_) {
      return SavedPicture.none;
    }
  }

  @override
  Future<Uint8List?> picture(String assetId, {int px = 1600}) async {
    try {
      if (!await _ready()) return null;
      final a = await AssetEntity.fromId(assetId);
      if (a == null) return null;
      final long = a.width >= a.height;
      final w = long ? px : (px * a.width / (a.height == 0 ? 1 : a.height)).round();
      final h = long ? (px * a.height / (a.width == 0 ? 1 : a.width)).round() : px;
      // Fetches from iCloud when the phone has offloaded the original.
      return await a.thumbnailDataWithSize(ThumbnailSize(w.clamp(1, px), h.clamp(1, px)), quality: 90);
    } catch (_) {
      return null;
    }
  }

  @override
  bool get asks => Platform.isIOS;

  @override
  Future<void> openSettings() async {
    try {
      await PhotoManager.openSetting();
    } catch (_) {}
  }

  @override
  Future<void> manageLimited() async {
    try {
      await PhotoManager.presentLimited();
    } catch (_) {}
  }
}
