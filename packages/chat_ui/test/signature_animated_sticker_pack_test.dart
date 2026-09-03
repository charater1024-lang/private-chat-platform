import 'package:chat_ui/chat_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _characterIds = <String>['mori', 'lulu', 'bobo', 'toto', 'nuri', 'duri'];

const _artworkByCharacter = <String, String>{
  'mori': 'assets/stickers/mori-hello.png',
  'lulu': 'assets/stickers/lulu-love.png',
  'bobo': 'assets/stickers/bobo-laugh.png',
  'toto': 'assets/stickers/toto-ok.png',
  'nuri': 'assets/stickers/nuri-celebrate.png',
  'duri': 'assets/stickers/duri-sorry.png',
};

const _mixedInteractions = <String, (List<String>, String, String)>{
  'high-five': (
    <String>['mori', 'bobo'],
    '하이파이브!',
    'assets/stickers/duo-01-high-five.png',
  ),
  'hug': (
    <String>['lulu', 'duri'],
    '꼬옥 안아줄게',
    'assets/stickers/duo-02-hug.png',
  ),
  'gift-exchange': (
    <String>['bobo', 'nuri'],
    '선물 받아!',
    'assets/stickers/duo-03-gift-exchange.png',
  ),
  'pat-back': (
    <String>['toto', 'duri'],
    '토닥토닥',
    'assets/stickers/duo-04-pat-back.png',
  ),
  'team-cheer': (
    <String>['mori', 'nuri'],
    '우리 팀 파이팅!',
    'assets/stickers/duo-05-team-cheer.png',
  ),
  'reconcile': (
    <String>['lulu', 'nuri'],
    '우리 화해하자',
    'assets/stickers/duo-06-reconcile.png',
  ),
  'secret-share': (
    <String>['bobo', 'lulu'],
    '비밀이야, 쉿!',
    'assets/stickers/duo-07-secret-share.png',
  ),
  'celebrate-together': (
    <String>['nuri', 'duri'],
    '같이 축하하자!',
    'assets/stickers/duo-08-celebrate-together.png',
  ),
  'help-up': (
    <String>['mori', 'toto'],
    '내 손 잡아!',
    'assets/stickers/duo-09-help-up.png',
  ),
  'share-umbrella': (
    <String>['lulu', 'duri'],
    '우산 같이 쓰자!',
    'assets/stickers/duo-10-share-umbrella.png',
  ),
  'tug-of-war': (
    <String>['bobo', 'toto'],
    '하나, 둘, 영차!',
    'assets/stickers/duo-11-tug-of-war.png',
  ),
  'group-photo': (
    <String>['mori', 'duri'],
    '같이 찰칵!',
    'assets/stickers/duo-12-group-photo.png',
  ),
};

void main() {
  group('signature animated sticker pack', () {
    test('contains exactly 120 solo and 12 mixed stickers', () {
      expect(signatureAnimatedStickerPack, hasLength(132));
      expect(
        signatureAnimatedStickerCharacterLabels.keys,
        orderedEquals(<String>[..._characterIds, 'mixed']),
      );
      expect(signatureAnimatedStickerCharacterLabels['mixed'], '함께');

      final solo = signatureAnimatedStickerPack
          .where((sticker) => !sticker.isMixed)
          .toList(growable: false);
      final mixed = signatureAnimatedStickerPack
          .where((sticker) => sticker.isMixed)
          .toList(growable: false);

      expect(solo, hasLength(120));
      expect(mixed, hasLength(12));
      expect(mixed.every((sticker) => sticker.characterId == 'mixed'), isTrue);
    });

    test('gives every mascot exactly 20 solo expressions', () {
      for (final characterId in _characterIds) {
        final characterPack = signatureAnimatedStickerPack
            .where(
              (sticker) =>
                  sticker.characterId == characterId && !sticker.isMixed,
            )
            .toList(growable: false);

        expect(characterPack, hasLength(20), reason: characterId);
        expect(
          characterPack.every(
            (sticker) =>
                sticker.participants.length == 1 &&
                sticker.participants.single == characterId,
          ),
          isTrue,
          reason: characterId,
        );
        expect(
          characterPack.map((sticker) => sticker.emotionId).toSet(),
          hasLength(20),
          reason: characterId,
        );
      }
    });

    test('all 132 exact Korean phrases are non-empty and unique', () {
      final phrases = signatureAnimatedStickerPack
          .map((sticker) => sticker.bubbleText)
          .toList(growable: false);
      final hasKorean = RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]');

      expect(signatureAnimatedStickerUniqueExpressions, hasLength(132));
      expect(signatureAnimatedStickerUniqueExpressions.toSet(), hasLength(132));
      expect(phrases, orderedEquals(signatureAnimatedStickerUniqueExpressions));
      for (final phrase in phrases) {
        expect(phrase, isNotEmpty);
        expect(phrase.trim(), phrase);
        expect(hasKorean.hasMatch(phrase), isTrue, reason: phrase);
      }
    });

    test('uses unique versioned IDs without static-pack collisions', () {
      expect(signatureAnimatedStickerPackId, 'signature-motion');
      expect(signatureAnimatedStickerPackVersion, 1);

      final animatedIds = signatureAnimatedStickerPack
          .map((sticker) => sticker.id)
          .toSet();
      final staticIds = signatureStickerPack
          .map((sticker) => sticker.id)
          .toSet();

      expect(animatedIds, hasLength(132));
      expect(
        animatedIds.every(
          (id) => id.startsWith(
            '$signatureAnimatedStickerPackId-v$signatureAnimatedStickerPackVersion-',
          ),
        ),
        isTrue,
      );
      expect(animatedIds.intersection(staticIds), isEmpty);
    });

    test('solo entries reuse only their mascot transparent cut-out', () {
      final solo = signatureAnimatedStickerPack.where(
        (sticker) => !sticker.isMixed,
      );

      for (final sticker in solo) {
        final expectedArtwork = _artworkByCharacter[sticker.characterId];
        expect(sticker.usesSpriteSheet, isFalse, reason: sticker.id);
        expect(sticker.assetSheetPath, expectedArtwork, reason: sticker.id);
        expect(
          sticker.artworkAssetPaths,
          orderedEquals(<String>[expectedArtwork!]),
          reason: sticker.id,
        );
        expect(sticker.effect, isNotNull, reason: sticker.id);
        expect(sticker.effectGlyph, isEmpty, reason: sticker.id);
      }
    });

    test('mixed entries encode only genuine two-mascot interactions', () {
      final mixed = signatureAnimatedStickerPack
          .where((sticker) => sticker.isMixed)
          .toList(growable: false);

      expect(mixed, hasLength(_mixedInteractions.length));
      for (final sticker in mixed) {
        final slug = sticker.emotionId.replaceFirst('interaction-', '');
        final expected = _mixedInteractions[slug];

        expect(expected, isNotNull, reason: sticker.id);
        expect(sticker.characterId, 'mixed', reason: sticker.id);
        expect(sticker.emotionId, startsWith('interaction-'));
        expect(sticker.participants, orderedEquals(expected!.$1));
        expect(sticker.participants.toSet(), hasLength(2), reason: sticker.id);
        expect(
          sticker.participants.every(_characterIds.contains),
          isTrue,
          reason: sticker.id,
        );
        expect(sticker.bubbleText, expected.$2, reason: sticker.id);
        expect(sticker.semanticLabel, contains('상호작용'), reason: sticker.id);
        expect(sticker.usesSpriteSheet, isFalse, reason: sticker.id);
        expect(sticker.assetSheetPath, expected.$3, reason: sticker.id);
        expect(
          sticker.artworkAssetPaths,
          orderedEquals(<String>[expected.$3]),
          reason: sticker.id,
        );
        expect(
          sticker.assetSheetPath,
          matches(r'^assets/stickers/duo-\d{2}-[a-z0-9-]+\.png$'),
          reason: sticker.id,
        );
      }
    });

    test('pack exercises every supported effect and motion', () {
      expect(
        signatureAnimatedStickerPack.map((sticker) => sticker.effect).toSet(),
        equals(StickerEffect.values.toSet()),
      );
      expect(
        signatureAnimatedStickerPack.map((sticker) => sticker.motion).toSet(),
        equals(StickerMotion.values.toSet()),
      );
    });

    test('Bobo solo expressions always use the corrected two-ear artwork', () {
      const correctedBoboArtwork = 'assets/stickers/bobo-laugh.png';
      final boboSolo = signatureAnimatedStickerPack.where(
        (sticker) => sticker.characterId == 'bobo' && !sticker.isMixed,
      );

      expect(boboSolo, hasLength(20));
      expect(
        boboSolo.every(
          (sticker) =>
              sticker.participants.single == 'bobo' &&
              sticker.artworkAssetPaths.single == correctedBoboArtwork,
        ),
        isTrue,
      );
    });

    test('exported pack and nested collections are immutable', () {
      final solo = signatureAnimatedStickerPack.first;
      final mixed = signatureAnimatedStickerPack.last;

      expect(
        () => signatureAnimatedStickerPack.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => signatureAnimatedStickerUniqueExpressions.clear(),
        throwsUnsupportedError,
      );
      expect(() => solo.participants.clear(), throwsUnsupportedError);
      expect(() => solo.artworkAssetPaths.clear(), throwsUnsupportedError);
      expect(() => mixed.participants.clear(), throwsUnsupportedError);
      expect(() => mixed.artworkAssetPaths.clear(), throwsUnsupportedError);
    });
  });
}
