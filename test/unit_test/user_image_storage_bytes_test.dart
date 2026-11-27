import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';

/// The browser has no file system, so there photos are bytes in a Hive box.
void main() {
  late Directory tempRoot;
  late LazyBox<Uint8List> box;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('ont_user_img_bytes_');
    Hive.init(tempRoot.path);
    box = await Hive.openLazyBox<Uint8List>('UserImageBox');
    UserImageStorage.useBytesStore(box);
  });

  tearDown(() async {
    UserImageStorage.useBytesStore(null);
    await Hive.close();
    await tempRoot.delete(recursive: true);
  });

  Future<String> pick(List<int> bytes) => UserImageStorage.importPicked(
    kind: UserImageKind.recipe,
    ownerId: 'abc',
    picked: XFile.fromData(Uint8List.fromList(bytes)),
  );

  test('a picked photo is stored and can be shown', () async {
    final relative = await pick([1, 2, 3]);

    expect(relative, 'recipe_images/abc.webp');
    expect(await UserImageStorage.readBytes(relative), [1, 2, 3]);
    expect(await UserImageStorage.imageProvider(relative), isA<MemoryImage>());
  });

  test('a stored photo survives the app being reopened', () async {
    final relative = await pick([1, 2, 3]);

    UserImageStorage.useBytesStore(box); // drops the in-memory cache

    expect(await UserImageStorage.readBytes(relative), [1, 2, 3]);
  });

  test('replacing a photo keeps the slug and announces the change', () async {
    final relative = await pick([1]);
    final before = UserImageStorage.revision.value;

    expect(await pick([2]), relative);

    expect(await UserImageStorage.readBytes(relative), [2]);
    expect(UserImageStorage.revision.value, greaterThan(before));
  });

  test('the same photo gives an equal provider, so it is not decoded again',
      () async {
    final relative = await pick([1]);

    expect(
      await UserImageStorage.imageProvider(relative),
      await UserImageStorage.imageProvider(relative),
    );
  });

  test('delete removes the photo and its credit', () async {
    final relative = await pick([1]);
    await UserImageStorage.writeCredit(relative, name: 'A', profileUrl: 'u');
    expect((await UserImageStorage.readCredit(relative))?.name, 'A');

    await UserImageStorage.delete(relative);

    expect(await UserImageStorage.imageProvider(relative), isNull);
    expect(await UserImageStorage.readCredit(relative), isNull);
    expect(box.keys, isEmpty);
  });

  test('a path outside the image folders is not stored', () async {
    await UserImageStorage.writeBytes('../evil.webp', [1]);

    expect(box.keys, isEmpty);
  });
}
