import 'animated_sticker_definition.dart';

const _mori = 'assets/stickers/mori-hello.png';
const _lulu = 'assets/stickers/lulu-love.png';
const _bobo = 'assets/stickers/bobo-laugh.png';
const _toto = 'assets/stickers/toto-ok.png';
const _nuri = 'assets/stickers/nuri-celebrate.png';
const _duri = 'assets/stickers/duri-sorry.png';

const _characterArtwork = <String, String>{
  'mori': _mori,
  'lulu': _lulu,
  'bobo': _bobo,
  'toto': _toto,
  'nuri': _nuri,
  'duri': _duri,
};

/// Stable wire namespace for future server envelopes.
const signatureAnimatedStickerPackId = 'signature-motion';
const signatureAnimatedStickerPackVersion = 1;

/// Picker labels for the six mascots and their shared-interaction collection.
const signatureAnimatedStickerCharacterLabels = <String, String>{
  'mori': '모리',
  'lulu': '루루',
  'bobo': '보보',
  'toto': '토토',
  'nuri': '누리',
  'duri': '두리',
  'mixed': '함께',
};

/// Exact Korean copy in the complete pack: 120 solo and 12 interactions.
///
/// Every phrase is deliberately unique so search, accessibility, analytics,
/// and future server-side sticker cataloguing can distinguish all 132 items.
final signatureAnimatedStickerUniqueExpressions = List<String>.unmodifiable(
  <String>[
    for (final seeds in _soloSeedsByCharacter.values)
      for (final seed in seeds) seed.bubbleText,
    for (final seed in _mixedSeeds) seed.bubbleText,
  ],
);

/// 132 lightweight animated stickers.
///
/// Each mascot contributes exactly 20 solo expressions. The final 12 entries
/// use purpose-built composite artwork for interactions that cannot be
/// expressed by one mascot alone. Exact Korean copy and motion remain runtime
/// data, keeping image assets reusable and accessible on older devices.
final signatureAnimatedStickerPack =
    List<AnimatedStickerDefinition>.unmodifiable(<AnimatedStickerDefinition>[
      for (final entry in _soloSeedsByCharacter.entries)
        for (var index = 0; index < entry.value.length; index += 1)
          _buildSoloSticker(entry.key, entry.value[index], index),
      for (var index = 0; index < _mixedSeeds.length; index += 1)
        _buildMixedSticker(_mixedSeeds[index], index),
    ]);

AnimatedStickerDefinition _buildSoloSticker(
  String characterId,
  _SoloStickerSeed seed,
  int index,
) {
  final characterName = signatureAnimatedStickerCharacterLabels[characterId]!;
  final artwork = _characterArtwork[characterId]!;
  return AnimatedStickerDefinition(
    id: '$signatureAnimatedStickerPackId-v$signatureAnimatedStickerPackVersion-$characterId-${seed.slug}',
    name: '$characterName ${seed.bubbleText}',
    assetSheetPath: artwork,
    semanticLabel: '$characterName의 ${seed.bubbleText} 감정을 표현하는 움직이는 이모티콘',
    characterId: characterId,
    emotionId: seed.slug,
    bubbleText: seed.bubbleText,
    spriteCellIndex: index % 6,
    motion: _motionFor(seed.effect, index),
    participants: <String>[characterId],
    usesSpriteSheet: false,
    artworkAssetPaths: <String>[artwork],
    effect: seed.effect,
  );
}

AnimatedStickerDefinition _buildMixedSticker(
  _MixedStickerSeed seed,
  int index,
) {
  final participantNames = seed.participants
      .map((id) => signatureAnimatedStickerCharacterLabels[id])
      .join('와 ');
  return AnimatedStickerDefinition(
    id: '$signatureAnimatedStickerPackId-v$signatureAnimatedStickerPackVersion-mixed-${seed.slug}',
    name: '$participantNames ${seed.bubbleText}',
    assetSheetPath: seed.assetPath,
    semanticLabel: '$participantNames가 함께 ${seed.bubbleText} 하는 상호작용 움직이는 이모티콘',
    characterId: 'mixed',
    emotionId: 'interaction-${seed.slug}',
    bubbleText: seed.bubbleText,
    spriteCellIndex: index % 6,
    motion: seed.motion,
    participants: seed.participants,
    usesSpriteSheet: false,
    artworkAssetPaths: <String>[seed.assetPath],
    effect: seed.effect,
  );
}

StickerMotion _motionFor(StickerEffect effect, int index) => switch (effect) {
  StickerEffect.wave ||
  StickerEffect.welcome ||
  StickerEffect.music ||
  StickerEffect.clap => StickerMotion.wiggle,
  StickerEffect.yes ||
  StickerEffect.gotIt ||
  StickerEffect.thanks ||
  StickerEffect.sorry => StickerMotion.nod,
  StickerEffect.sleep ||
  StickerEffect.miss ||
  StickerEffect.comfort ||
  StickerEffect.sad ||
  StickerEffect.tired => StickerMotion.float,
  StickerEffect.love ||
  StickerEffect.please ||
  StickerEffect.wow ||
  StickerEffect.like => StickerMotion.pulse,
  StickerEffect.angry || StickerEffect.cry => StickerMotion.shake,
  StickerEffect.trophy ||
  StickerEffect.celebrate ||
  StickerEffect.cheer ||
  StickerEffect.shock ||
  StickerEffect.laugh =>
    index.isEven ? StickerMotion.bounce : StickerMotion.shake,
};

class _SoloStickerSeed {
  const _SoloStickerSeed(this.slug, this.bubbleText, this.effect);

  final String slug;
  final String bubbleText;
  final StickerEffect effect;
}

class _MixedStickerSeed {
  const _MixedStickerSeed({
    required this.slug,
    required this.bubbleText,
    required this.assetPath,
    required this.participants,
    required this.motion,
    required this.effect,
  });

  final String slug;
  final String bubbleText;
  final String assetPath;
  final List<String> participants;
  final StickerMotion motion;
  final StickerEffect effect;
}

const _soloSeedsByCharacter = <String, List<_SoloStickerSeed>>{
  'mori': <_SoloStickerSeed>[
    _SoloStickerSeed('hello', '안녕!', StickerEffect.wave),
    _SoloStickerSeed('welcome', '반가워!', StickerEffect.welcome),
    _SoloStickerSeed('good-morning', '좋은 아침!', StickerEffect.welcome),
    _SoloStickerSeed('good-night', '잘 자~', StickerEffect.sleep),
    _SoloStickerSeed('going-out', '다녀올게!', StickerEffect.wave),
    _SoloStickerSeed('im-back', '다녀왔어!', StickerEffect.welcome),
    _SoloStickerSeed('yes', '네!', StickerEffect.yes),
    _SoloStickerSeed('got-it', '알겠어!', StickerEffect.gotIt),
    _SoloStickerSeed('okay', '오케이!', StickerEffect.yes),
    _SoloStickerSeed('wait', '잠깐만!', StickerEffect.gotIt),
    _SoloStickerSeed('on-my-way', '지금 가는 중!', StickerEffect.wave),
    _SoloStickerSeed('arrived', '도착했어!', StickerEffect.celebrate),
    _SoloStickerSeed('did-you-eat', '밥 먹었어?', StickerEffect.please),
    _SoloStickerSeed('what-doing', '뭐 해?', StickerEffect.welcome),
    _SoloStickerSeed('call-me', '연락 줘!', StickerEffect.please),
    _SoloStickerSeed('see-you', '이따 봐!', StickerEffect.wave),
    _SoloStickerSeed('take-care', '조심히 가!', StickerEffect.comfort),
    _SoloStickerSeed('cheer-today', '오늘도 힘내!', StickerEffect.cheer),
    _SoloStickerSeed('rooting-for-you', '응원할게!', StickerEffect.cheer),
    _SoloStickerSeed('good-work', '수고했어!', StickerEffect.clap),
  ],
  'lulu': <_SoloStickerSeed>[
    _SoloStickerSeed('love', '사랑해', StickerEffect.love),
    _SoloStickerSeed('miss-you', '보고 싶어', StickerEffect.miss),
    _SoloStickerSeed('thanks', '고마워!', StickerEffect.thanks),
    _SoloStickerSeed('big-thanks', '정말 고마워!', StickerEffect.thanks),
    _SoloStickerSeed('sorry', '미안해', StickerEffect.sorry),
    _SoloStickerSeed('very-sorry', '진짜 미안해', StickerEffect.sorry),
    _SoloStickerSeed('please', '부탁해~', StickerEffect.please),
    _SoloStickerSeed('stay-together', '같이 있자', StickerEffect.love),
    _SoloStickerSeed('thought-of-me', '내 생각 했어?', StickerEffect.miss),
    _SoloStickerSeed('how-have-you-been', '잘 지냈어?', StickerEffect.welcome),
    _SoloStickerSeed('love-it', '너무 좋아!', StickerEffect.like),
    _SoloStickerSeed('happy', '행복해', StickerEffect.love),
    _SoloStickerSeed('touched', '감동이야', StickerEffect.love),
    _SoloStickerSeed('warm-heart', '마음이 몽글몽글', StickerEffect.love),
    _SoloStickerSeed('rest-well', '푹 쉬어', StickerEffect.comfort),
    _SoloStickerSeed('sweet-dreams', '좋은 꿈 꿔', StickerEffect.sleep),
    _SoloStickerSeed('dress-warm', '따뜻하게 입어', StickerEffect.comfort),
    _SoloStickerSeed('eat-well', '밥 꼭 챙겨 먹어', StickerEffect.comfort),
    _SoloStickerSeed('dont-worry', '걱정 마', StickerEffect.comfort),
    _SoloStickerSeed('im-here', '내가 있잖아', StickerEffect.comfort),
  ],
  'bobo': <_SoloStickerSeed>[
    _SoloStickerSeed('lol', 'ㅋㅋㅋ', StickerEffect.laugh),
    _SoloStickerSeed('hehe', 'ㅎㅎㅎ', StickerEffect.laugh),
    _SoloStickerSeed('excited', '신난다!', StickerEffect.music),
    _SoloStickerSeed('awesome', '대박!', StickerEffect.wow),
    _SoloStickerSeed('gasp', '헉!', StickerEffect.shock),
    _SoloStickerSeed('what-is-it', '뭐야 뭐야!', StickerEffect.shock),
    _SoloStickerSeed('fun', '재밌다!', StickerEffect.laugh),
    _SoloStickerSeed('lets-go', '가보자고!', StickerEffect.cheer),
    _SoloStickerSeed('deal', '콜!', StickerEffect.yes),
    _SoloStickerSeed('agreed', '인정!', StickerEffect.yes),
    _SoloStickerSeed('really-like', '완전 좋아!', StickerEffect.like),
    _SoloStickerSeed('cute', '귀여워!', StickerEffect.love),
    _SoloStickerSeed('heart-flutter', '심쿵!', StickerEffect.love),
    _SoloStickerSeed('burst-laughing', '빵 터졌어', StickerEffect.laugh),
    _SoloStickerSeed('kidding', '장난이지?', StickerEffect.shock),
    _SoloStickerSeed('let-me-join', '나도 끼워 줘!', StickerEffect.please),
    _SoloStickerSeed('play', '놀자!', StickerEffect.music),
    _SoloStickerSeed('looks-delicious', '맛있겠다!', StickerEffect.wow),
    _SoloStickerSeed('hungry', '배고파!', StickerEffect.please),
    _SoloStickerSeed('the-best', '최고다!', StickerEffect.trophy),
  ],
  'toto': <_SoloStickerSeed>[
    _SoloStickerSeed('like', '좋아!', StickerEffect.like),
    _SoloStickerSeed('best', '최고야!', StickerEffect.trophy),
    _SoloStickerSeed('cheer-up', '힘내!', StickerEffect.cheer),
    _SoloStickerSeed('fighting', '파이팅!', StickerEffect.cheer),
    _SoloStickerSeed('well-done', '잘했어!', StickerEffect.clap),
    _SoloStickerSeed('its-okay', '괜찮아', StickerEffect.comfort),
    _SoloStickerSeed('no-problem', '문제없어!', StickerEffect.yes),
    _SoloStickerSeed('you-can', '할 수 있어!', StickerEffect.cheer),
    _SoloStickerSeed('take-it-slow', '천천히 해', StickerEffect.comfort),
    _SoloStickerSeed('no-rush', '급할 것 없어', StickerEffect.comfort),
    _SoloStickerSeed('ill-help', '내가 도와줄게', StickerEffect.welcome),
    _SoloStickerSeed('believe-you', '믿고 있어', StickerEffect.cheer),
    _SoloStickerSeed('cool', '멋지다!', StickerEffect.trophy),
    _SoloStickerSeed('worked-hard', '고생 많았어', StickerEffect.thanks),
    _SoloStickerSeed('thank-you-work', '수고했어요', StickerEffect.thanks),
    _SoloStickerSeed('confirmed', '확인했어!', StickerEffect.gotIt),
    _SoloStickerSeed('go-ahead', '진행해 줘', StickerEffect.gotIt),
    _SoloStickerSeed('agree', '찬성이야', StickerEffect.yes),
    _SoloStickerSeed('good-idea', '좋은 생각이야', StickerEffect.like),
    _SoloStickerSeed('perfect', '완벽해!', StickerEffect.trophy),
  ],
  'nuri': <_SoloStickerSeed>[
    _SoloStickerSeed('congrats', '축하해!', StickerEffect.celebrate),
    _SoloStickerSeed('big-news', '대박 사건!', StickerEffect.wow),
    _SoloStickerSeed('omg', '헐!', StickerEffect.shock),
    _SoloStickerSeed('really', '진짜?', StickerEffect.shock),
    _SoloStickerSeed('for-real', '실화야?', StickerEffect.shock),
    _SoloStickerSeed('angry', '화났어!', StickerEffect.angry),
    _SoloStickerSeed('too-much', '너무해!', StickerEffect.angry),
    _SoloStickerSeed('no', '안 돼!', StickerEffect.angry),
    _SoloStickerSeed('surprised', '깜짝이야!', StickerEffect.shock),
    _SoloStickerSeed('scared', '무서워!', StickerEffect.shock),
    _SoloStickerSeed('shy', '부끄러워', StickerEffect.love),
    _SoloStickerSeed('flutter', '설렌다!', StickerEffect.love),
    _SoloStickerSeed('looking-forward', '기대돼!', StickerEffect.celebrate),
    _SoloStickerSeed('success', '성공했다!', StickerEffect.trophy),
    _SoloStickerSeed('did-it', '해냈다!', StickerEffect.trophy),
    _SoloStickerSeed('on-fire', '불타오른다!', StickerEffect.angry),
    _SoloStickerSeed('energy-up', '텐션 업!', StickerEffect.music),
    _SoloStickerSeed('depart', '출발!', StickerEffect.cheer),
    _SoloStickerSeed('focus', '집중!', StickerEffect.gotIt),
    _SoloStickerSeed('cant-resist', '이건 못 참지!', StickerEffect.wow),
  ],
  'duri': <_SoloStickerSeed>[
    _SoloStickerSeed('upset', '속상해…', StickerEffect.sad),
    _SoloStickerSeed('sob', '엉엉', StickerEffect.cry),
    _SoloStickerSeed('sad', '슬퍼', StickerEffect.sad),
    _SoloStickerSeed('tears', '눈물 나', StickerEffect.cry),
    _SoloStickerSeed('tired', '피곤해…', StickerEffect.tired),
    _SoloStickerSeed('sleepy', '졸려…', StickerEffect.sleep),
    _SoloStickerSeed('exhausted', '지쳤어', StickerEffect.tired),
    _SoloStickerSeed('need-rest', '쉬고 싶어', StickerEffect.tired),
    _SoloStickerSeed('full', '배불러', StickerEffect.comfort),
    _SoloStickerSeed('bored', '심심해', StickerEffect.tired),
    _SoloStickerSeed('lonely', '외로워', StickerEffect.sad),
    _SoloStickerSeed('hurt', '아파…', StickerEffect.sad),
    _SoloStickerSeed('too-bad', '아쉽다', StickerEffect.sad),
    _SoloStickerSeed('regret', '후회돼', StickerEffect.sorry),
    _SoloStickerSeed('overwhelmed', '멘붕이야', StickerEffect.shock),
    _SoloStickerSeed('what-now', '어떡해', StickerEffect.shock),
    _SoloStickerSeed('ruined', '망했다…', StickerEffect.cry),
    _SoloStickerSeed('shouldnt-have', '괜히 그랬어', StickerEffect.sorry),
    _SoloStickerSeed('forgive-me', '용서해 줘', StickerEffect.sorry),
    _SoloStickerSeed('comfort-me', '위로해 줘', StickerEffect.please),
  ],
};

const _mixedSeeds = <_MixedStickerSeed>[
  _MixedStickerSeed(
    slug: 'high-five',
    bubbleText: '하이파이브!',
    assetPath: 'assets/stickers/duo-01-high-five.png',
    participants: <String>['mori', 'bobo'],
    motion: StickerMotion.bounce,
    effect: StickerEffect.clap,
  ),
  _MixedStickerSeed(
    slug: 'hug',
    bubbleText: '꼬옥 안아줄게',
    assetPath: 'assets/stickers/duo-02-hug.png',
    participants: <String>['lulu', 'duri'],
    motion: StickerMotion.pulse,
    effect: StickerEffect.love,
  ),
  _MixedStickerSeed(
    slug: 'gift-exchange',
    bubbleText: '선물 받아!',
    assetPath: 'assets/stickers/duo-03-gift-exchange.png',
    participants: <String>['bobo', 'nuri'],
    motion: StickerMotion.bounce,
    effect: StickerEffect.celebrate,
  ),
  _MixedStickerSeed(
    slug: 'pat-back',
    bubbleText: '토닥토닥',
    assetPath: 'assets/stickers/duo-04-pat-back.png',
    participants: <String>['toto', 'duri'],
    motion: StickerMotion.nod,
    effect: StickerEffect.comfort,
  ),
  _MixedStickerSeed(
    slug: 'team-cheer',
    bubbleText: '우리 팀 파이팅!',
    assetPath: 'assets/stickers/duo-05-team-cheer.png',
    participants: <String>['mori', 'nuri'],
    motion: StickerMotion.bounce,
    effect: StickerEffect.cheer,
  ),
  _MixedStickerSeed(
    slug: 'reconcile',
    bubbleText: '우리 화해하자',
    assetPath: 'assets/stickers/duo-06-reconcile.png',
    participants: <String>['lulu', 'nuri'],
    motion: StickerMotion.nod,
    effect: StickerEffect.sorry,
  ),
  _MixedStickerSeed(
    slug: 'secret-share',
    bubbleText: '비밀이야, 쉿!',
    assetPath: 'assets/stickers/duo-07-secret-share.png',
    participants: <String>['bobo', 'lulu'],
    motion: StickerMotion.wiggle,
    effect: StickerEffect.gotIt,
  ),
  _MixedStickerSeed(
    slug: 'celebrate-together',
    bubbleText: '같이 축하하자!',
    assetPath: 'assets/stickers/duo-08-celebrate-together.png',
    participants: <String>['nuri', 'duri'],
    motion: StickerMotion.bounce,
    effect: StickerEffect.celebrate,
  ),
  _MixedStickerSeed(
    slug: 'help-up',
    bubbleText: '내 손 잡아!',
    assetPath: 'assets/stickers/duo-09-help-up.png',
    participants: <String>['mori', 'toto'],
    motion: StickerMotion.bounce,
    effect: StickerEffect.welcome,
  ),
  _MixedStickerSeed(
    slug: 'share-umbrella',
    bubbleText: '우산 같이 쓰자!',
    assetPath: 'assets/stickers/duo-10-share-umbrella.png',
    participants: <String>['lulu', 'duri'],
    motion: StickerMotion.float,
    effect: StickerEffect.comfort,
  ),
  _MixedStickerSeed(
    slug: 'tug-of-war',
    bubbleText: '하나, 둘, 영차!',
    assetPath: 'assets/stickers/duo-11-tug-of-war.png',
    participants: <String>['bobo', 'toto'],
    motion: StickerMotion.shake,
    effect: StickerEffect.cheer,
  ),
  _MixedStickerSeed(
    slug: 'group-photo',
    bubbleText: '같이 찰칵!',
    assetPath: 'assets/stickers/duo-12-group-photo.png',
    participants: <String>['mori', 'duri'],
    motion: StickerMotion.wiggle,
    effect: StickerEffect.wow,
  ),
];
