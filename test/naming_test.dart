import 'package:flutter_test/flutter_test.dart';
import 'package:sappari_sheet/core/naming.dart';

void main() {
  test('accepts only supported extensions', () {
    expect(isAccepted('/x/a.JPG'), isTrue);
    expect(isAccepted('/x/a.png'), isTrue);
    expect(isAccepted('/x/a.jpeg'), isTrue);
    expect(isAccepted('/x/a.tiff'), isFalse);
    expect(isAccepted('/x/noext'), isFalse);
    expect(isAccepted(r'C:\photos\roll.JPEG'), isTrue);
  });

  test('sanitize replaces reserved characters and falls back', () {
    expect(sanitizeFileName('a<b>c/d'), 'a_b_c_d');
    expect(sanitizeFileName('  name..  '), 'name');
    expect(sanitizeFileName('   '), 'index_sheet');
    expect(sanitizeFileName('holiday 2024'), 'holiday 2024');
    expect(sanitizeFileName('a:b"c|d?e*f'), 'a_b_c_d_e_f');
    expect(sanitizeFileName('a\u0001b'), 'a_b');
    expect(sanitizeFileName('ロール 2024'), 'ロール 2024');
  });

  test('build output path picks the separator', () {
    expect(buildOutputPath('/a/b', 'roll'), '/a/b/roll.jpg');
    expect(buildOutputPath(r'C:\photos', 'roll'), r'C:\photos\roll.jpg');
    expect(buildOutputPath('/a/b', 'bad*name'), '/a/b/bad_name.jpg');
  });

  test('natural comparison is numeric aware', () {
    expect(naturalCmp('img2.jpg', 'img10.jpg'), lessThan(0));
    expect(naturalCmp('img10.jpg', 'img2.jpg'), greaterThan(0));
    expect(naturalCmp('IMG_001.jpg', 'img_001.jpg'), 0);
    expect(naturalCmp('a.jpg', 'b.jpg'), lessThan(0));
  });

  test('natural comparison handles zero padding and equal widths', () {
    expect(naturalCmp('img007.jpg', 'img7.jpg'), 0);
    expect(naturalCmp('img08.jpg', 'img9.jpg'), lessThan(0));
    expect(naturalCmp('a1b2.jpg', 'a1b10.jpg'), lessThan(0));
  });

  test('natural sort orders a roll the way a file manager does', () {
    final names = [
      'IMG_10.jpg',
      'IMG_2.jpg',
      'IMG_1.jpg',
      'IMG_20.jpg',
      'IMG_3.jpg',
    ]..sort(naturalCmp);
    expect(names, [
      'IMG_1.jpg',
      'IMG_2.jpg',
      'IMG_3.jpg',
      'IMG_10.jpg',
      'IMG_20.jpg',
    ]);
  });

  test('file name extraction handles both separators', () {
    expect(fileNameOf(r'C:\photos\roll\IMG_001.jpg'), 'IMG_001.jpg');
    expect(fileNameOf('/home/u/IMG_001.jpg'), 'IMG_001.jpg');
    expect(fileNameOf('IMG_001.jpg'), 'IMG_001.jpg');
  });
}
