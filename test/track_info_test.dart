import 'package:flutter_test/flutter_test.dart';

import 'package:salu_remote/core/models.dart';

void main() {
  test('generic track names use a readable language label without duplication', () {
    final TrackInfo track = TrackInfo.from(<String, Object?>{
      'trackId': 4,
      'title': 'Track 4',
      'language': 'es',
      'codec': 'AAC',
      'channels': '2.0',
      'isExternal': true,
      'isSelected': true,
    });

    expect(track.id, '4');
    expect(track.displayTitle, 'Spanish');
    expect(track.detail, '2.0 · AAC · external');
    expect(track.selected, isTrue);
    expect(track.external, isTrue);
  });

  test('human language names and common codes are displayed as track names', () {
    final TrackInfo hindi = TrackInfo.from(<String, Object?>{
      'id': 'sid:2',
      'title': 'Track',
      'languageName': 'Hindi',
    });
    final TrackInfo english = TrackInfo.from(<String, Object?>{
      'id': 'aid:3',
      'title': 'Audio Track 3',
      'language_code': 'eng',
    });
    final TrackInfo mandarin = TrackInfo.from(<String, Object?>{
      'id': 'aid:4',
      'title': 'Track 4',
      'lang': 'cmn',
    });

    expect(hindi.displayTitle, 'Hindi');
    expect(hindi.detail, isEmpty);
    expect(english.displayTitle, 'English');
    expect(mandarin.displayTitle, 'Mandarin');
  });

  test('keeps a specific PC-provided title and adds language only as detail', () {
    final TrackInfo track = TrackInfo.from(<String, Object?>{
      'id': '5',
      'title': 'Commentary',
      'language': 'en',
      'codecName': 'AC3',
      'channelLayout': '5.1',
    });

    expect(track.displayTitle, 'Commentary');
    expect(track.detail, 'English · 5.1 · AC3');
  });
}
