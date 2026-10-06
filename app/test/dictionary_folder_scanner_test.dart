import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictionary/services/dictionary_folder_scanner.dart';

void main() {
  test('recursively discovers MDX files and ignores unrelated resources',
      () async {
    final root = await Directory.systemTemp.createTemp('lumalex-scan-');
    addTearDown(() => root.delete(recursive: true));

    final nested =
        await Directory('${root.path}/Oxford/assets').create(recursive: true);
    await File('${root.path}/Cambridge.mdx').writeAsBytes(const [1]);
    await File('${root.path}/Cambridge.mdd').writeAsBytes(const [2]);
    await File('${nested.parent.path}/Oxford.MDX').writeAsBytes(const [3]);
    await File('${nested.path}/style.css').writeAsBytes(const [4]);

    final result = await scanDictionaryFolder(root.path);

    expect(result.mdxPaths, hasLength(2));
    expect(
      result.mdxPaths.map((path) => path.toLowerCase()),
      containsAll(<String>[
        '${root.path}/Cambridge.mdx'.toLowerCase(),
        '${nested.parent.path}/Oxford.MDX'.toLowerCase(),
      ]),
    );
    expect(result.unreadableDirectoryCount, 0);
  });

  test('returns an empty result for a folder without dictionaries', () async {
    final root = await Directory.systemTemp.createTemp('lumalex-empty-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/notes.txt').writeAsString('not a dictionary');

    final result = await scanDictionaryFolder(root.path);

    expect(result.mdxPaths, isEmpty);
  });
}
