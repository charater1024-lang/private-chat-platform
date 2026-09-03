// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'everyday_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class EverydayLocalizationsKo extends EverydayLocalizations {
  EverydayLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'Everyday Chat';

  @override
  String get brandTitle => 'Everyday';

  @override
  String get brandTagline => '소중한 사람들과 편안하게';

  @override
  String get navFriends => '친구';

  @override
  String get navChats => '대화';

  @override
  String get navCalls => '통화';

  @override
  String get navMore => '더보기';

  @override
  String get newChat => '새 대화';

  @override
  String get searchChats => '대화 검색';

  @override
  String get trueE2ee => '목표 정책: 종단간 암호화 · 미검증';

  @override
  String get homeserverStatusTitle => '내 홈서버 연결';

  @override
  String homeserverName(Object name) {
    return '홈서버: $name';
  }

  @override
  String get httpsPending => 'HTTPS: 연결 전 · 인증서 확인 대기';

  @override
  String get closedFederation => '닫힌 서버 · 연합 꺼짐';

  @override
  String get privacyEncryptionMode => '목표: 종단간 암호화 · 서버 복호화 불가 · 미검증';

  @override
  String get prototypeConnectionPending => '로컬 프로토타입 · 실제 서버 연결 예정';

  @override
  String get transportVerificationActive => '인증 통신 어댑터 · 연결 시 서버 신원 검증';

  @override
  String get syncDisconnected => '동기화 구성됨 · 연결 대기';

  @override
  String get syncConnecting => '홈서버 연결과 신원을 확인하는 중';

  @override
  String syncConnected(int count) {
    return '홈서버 연결됨 · 대기 $count개';
  }

  @override
  String syncBackingOff(int count) {
    return '연결 재시도 대기 · 전송 대기 $count개';
  }

  @override
  String get syncBlocked => '보안 확인 실패 · 서버나 인증 설정 확인 필요';

  @override
  String get syncFailed => '로컬 동기화 오류 · 재시도 필요';

  @override
  String get syncStopped => '동기화 중지됨';

  @override
  String get deliveryLocalOnly => '이 기기에만 저장됨';

  @override
  String get deliveryQueued => '암호화 전송 대기';

  @override
  String get deliveryAcknowledged => '홈서버에 전달됨';

  @override
  String get deliveryRetryScheduled => '재전송 대기';

  @override
  String get deliveryBlocked => '보안 확인 필요';

  @override
  String get activeMemberCanCreate =>
      'ACTIVE 일반 구성원 · 소유자 승인 없이 1:1/그룹 대화 생성 가능';

  @override
  String get noSearchResults => '검색 결과가 없어요';

  @override
  String get conversationList => '대화 목록';

  @override
  String get voiceCall => '음성 통화';

  @override
  String get conversationInfo => '대화 정보';

  @override
  String get directConversationPrivacy => '1:1 대화 · 참여자의 기기에서만 열립니다';

  @override
  String groupConversationPrivacy(int count) {
    return '단체 대화 · $count명 · 참여자의 기기에서만 열립니다';
  }

  @override
  String get conversationEncrypted => '목표 정책: 종단간 암호화 · 현재 로컬 프로토타입';

  @override
  String get sending => '보내는 중';

  @override
  String get sendFailed => '전송 실패';

  @override
  String get sent => '전송됨';

  @override
  String get timeNow => '방금';

  @override
  String get chooseItemTitle => '보낼 항목 선택';

  @override
  String get mediaActionTitle => '사진·동영상·파일';

  @override
  String get mediaActionSubtitle => '기기에서 사진, 동영상 또는 파일을 골라요';

  @override
  String get stickersActionTitle => '캐릭터 이모티콘';

  @override
  String get stickersActionSubtitle => '움직이는 캐릭터와 한국어 감정 표현을 보내요';

  @override
  String get stickerPickerClose => '이모티콘 선택기 닫기';

  @override
  String get stickerPickerInstruction => '이모티콘을 고르면 현재 대화방에 바로 보내요.';

  @override
  String get stickerEmpty => '사용할 수 있는 이모티콘이 없어요';

  @override
  String get stickerPreviousPage => '이전 이모티콘';

  @override
  String get stickerNextPage => '다음 이모티콘';

  @override
  String stickerPageSemantics(int page, int total) {
    return '이모티콘 $page페이지, 전체 $total페이지';
  }

  @override
  String stickerAccessibility(
    Object character,
    Object meaning,
    Object koreanPhrase,
  ) {
    return '$character 캐릭터, $meaning. 한국어 표현: $koreanPhrase';
  }

  @override
  String get stickerMeaningGreeting => '인사';

  @override
  String get stickerMeaningWelcome => '환영';

  @override
  String get stickerMeaningAgreement => '동의';

  @override
  String get stickerMeaningUnderstood => '이해함';

  @override
  String get stickerMeaningSleep => '잠';

  @override
  String get stickerMeaningSuccess => '성공';

  @override
  String get stickerMeaningLove => '사랑';

  @override
  String get stickerMeaningMissing => '그리움';

  @override
  String get stickerMeaningThanks => '감사';

  @override
  String get stickerMeaningSorry => '사과';

  @override
  String get stickerMeaningPlease => '부탁';

  @override
  String get stickerMeaningComfort => '위로';

  @override
  String get stickerMeaningLaugh => '웃음';

  @override
  String get stickerMeaningMusic => '음악';

  @override
  String get stickerMeaningSurprise => '놀람';

  @override
  String get stickerMeaningShock => '충격';

  @override
  String get stickerMeaningLike => '좋아요';

  @override
  String get stickerMeaningCelebrate => '축하';

  @override
  String get stickerMeaningCheer => '응원';

  @override
  String get stickerMeaningClap => '박수';

  @override
  String get stickerMeaningAngry => '화남';

  @override
  String get stickerMeaningSad => '슬픔';

  @override
  String get stickerMeaningCry => '울음';

  @override
  String get stickerMeaningTired => '피곤함';

  @override
  String get characterMori => '모리';

  @override
  String get characterLulu => '루루';

  @override
  String get characterBobo => '보보';

  @override
  String get characterToto => '토토';

  @override
  String get characterNuri => '누리';

  @override
  String get characterDuri => '두리';

  @override
  String get characterTogether => '함께';

  @override
  String get profileCustomize => '프로필 꾸미기';

  @override
  String get save => '저장';

  @override
  String get unnamed => '이름 없음';

  @override
  String get statusPrompt => '상태 메시지를 입력해 보세요';

  @override
  String get profilePhotoSelect => '프로필 사진 선택';

  @override
  String get profileBackgroundSelect => '배경 이미지 선택';

  @override
  String get myInfo => '내 정보';

  @override
  String get displayName => '표시 이름';

  @override
  String get statusMessage => '상태 메시지';

  @override
  String get profileTheme => '프로필 테마';

  @override
  String get themeSprout => '새싹';

  @override
  String get themePurple => '보라';

  @override
  String get themeLilac => '라일락';

  @override
  String get themeOlive => '올리브';

  @override
  String profileThemeSemantics(Object name) {
    return '$name 프로필 테마';
  }

  @override
  String themeTooltip(Object name) {
    return '$name 테마';
  }

  @override
  String get profileLocalPreviewTitle => '현재 사진은 이 기기에서만 미리 보여요';

  @override
  String get profileLocalPreviewSubtitle => '서버 저장·동기화·암호화 업로드는 다음 단계에서 연결합니다.';

  @override
  String get profileSave => '프로필 저장';

  @override
  String get profileNameRequired => '표시 이름을 입력해 주세요.';

  @override
  String get profileSaved => '프로필이 저장되었어요.';

  @override
  String get removeSelection => '선택 항목 제거';

  @override
  String get mediaDescriptionSemantics => '선택한 첨부 파일의 접근성 설명';

  @override
  String get mediaDescriptionLabel => '첨부 파일 설명 (선택)';

  @override
  String get mediaDescriptionHint => '화면을 보지 못하는 사람도 내용을 이해할 수 있게 설명해 주세요';

  @override
  String get composerAddTooltip => '사진·동영상·파일 또는 캐릭터 이모티콘 보내기';

  @override
  String get messageHint => '메시지를 입력하세요';

  @override
  String get send => '보내기';

  @override
  String get placeholderDescription => '다음 개발 단계에서 실제 데이터와 연결됩니다.';

  @override
  String get welcomeHint => '대화를 선택하면 이곳에서 이어갈 수 있어요.';

  @override
  String get newConversationTitle => '새 대화 만들기';

  @override
  String get newConversationInstruction =>
      '친구 1명을 고르면 1:1 대화, 2명 이상을 고르면 단체방으로 만들어져요.';

  @override
  String get selectFriend => '친구를 선택해 주세요';

  @override
  String get oneFriendSelected => '1명 선택 · 1:1 대화';

  @override
  String manyFriendsSelected(int count) {
    return '$count명 선택 · 단체 대화';
  }

  @override
  String get friend => '친구';

  @override
  String get groupNameOptional => '단체방 이름 (선택)';

  @override
  String get groupNameHelper => '비워 두면 선택한 친구 이름으로 만들어요.';

  @override
  String get cancel => '취소';

  @override
  String get createGroup => '단체방 만들기';

  @override
  String get startDirect => '1:1 대화 시작';

  @override
  String groupNameDefault(Object names) {
    return '$names 모임';
  }

  @override
  String newGroupPreview(int count) {
    return '$count명이 함께하는 새 단체방';
  }

  @override
  String get newDirectPreview => '새로운 1:1 대화가 시작되었어요';

  @override
  String maxFiles(int count) {
    return '한 번에 최대 $count개까지 보낼 수 있어요.';
  }

  @override
  String get mediaPickFailed => '첨부 파일을 선택하지 못했어요. 다시 시도해 주세요.';

  @override
  String get imagePickFailed => '이미지를 선택하지 못했어요. 다시 시도해 주세요.';

  @override
  String get profileImageOnly => '프로필에는 이미지 파일만 사용할 수 있어요.';

  @override
  String get imageTooLarge => '이미지는 30MB 이하만 보낼 수 있어요.';

  @override
  String get videoTooLarge => '동영상은 500MB 이하만 보낼 수 있어요.';

  @override
  String get fileTooLarge => '파일은 1GB 이하만 보낼 수 있어요.';

  @override
  String get unsupportedMedia => '지원하지 않는 첨부 파일 형식이에요.';

  @override
  String get unusableFile => '선택한 파일을 사용할 수 없어요.';
}
