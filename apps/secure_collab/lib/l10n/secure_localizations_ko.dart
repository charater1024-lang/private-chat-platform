// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'secure_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class SecureLocalizationsKo extends SecureLocalizations {
  SecureLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'Secure Collab';

  @override
  String get search => '검색';

  @override
  String get channelInfo => '채널 정보';

  @override
  String get homeserverStatusTitle => '개인 홈서버 연결';

  @override
  String homeserverName(Object name) {
    return '홈서버: $name';
  }

  @override
  String get httpsPending => 'HTTPS: 연결 전 · 인증서 확인 대기';

  @override
  String get closedFederation => '개인 서버 · 연합 꺼짐';

  @override
  String get memberOnlyEncryptionMode => '설계 목표: TRUE_E2EE · 참여 기기만 키 보유 · 미검증';

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
  String get deliveryFailed => '전송 실패';

  @override
  String profileEditTooltip(Object name) {
    return '$name 업무 프로필 편집';
  }

  @override
  String get navConversations => '대화';

  @override
  String get navTasks => '업무';

  @override
  String get navActivity => '활동';

  @override
  String get navProfile => '내 정보';

  @override
  String get addItemTitle => '추가할 항목';

  @override
  String get mediaActionTitle => '사진·동영상·파일';

  @override
  String get mediaActionSubtitle => '이 기기에서 암호화해 보낼 첨부를 선택해요';

  @override
  String get stickersActionTitle => '캐릭터 이모티콘';

  @override
  String get stickersActionSubtitle => '6개 캐릭터의 움직이는 한국어 감정 표현을 바로 보내요';

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
  String get maxAttachments => '첨부는 한 번에 최대 30개까지 보낼 수 있습니다.';

  @override
  String get fileOpenFailed => '파일을 열지 못했습니다. 다시 시도해 주세요.';

  @override
  String get imageTooLarge => '이미지는 파일당 30MB 이하여야 합니다.';

  @override
  String get videoTooLarge => '동영상은 파일당 500MB 이하여야 합니다.';

  @override
  String get genericFileTooLarge => '일반 파일은 파일당 1GB 이하여야 합니다.';

  @override
  String get mediaNotAllowed => '지원하는 이미지, 동영상 또는 파일 형식이 아닙니다.';

  @override
  String get attachmentPolicyMismatch => '선택한 첨부가 앱의 안전 한도에 맞지 않습니다.';

  @override
  String get profileSaved => '업무 프로필을 저장했습니다.';

  @override
  String get timeNow => '방금';

  @override
  String channelStart(Object name) {
    return '#$name 채널의 시작';
  }

  @override
  String get addWorkspace => '워크스페이스 추가';

  @override
  String get newMessage => '새 메시지';

  @override
  String get workspaceSearch => '워크스페이스 검색';

  @override
  String get channels => '채널';

  @override
  String get directMessages => '1:1 및 그룹 대화';

  @override
  String get newDirectMessage => '새 1:1 또는 그룹 대화';

  @override
  String get memberCanCreate => '일반 구성원 · ACTIVE · 소유자 승인 없이 대화 생성 가능';

  @override
  String get newDirectDialogTitle => '멤버와 대화 만들기';

  @override
  String get newDirectDialogInstruction =>
      '같은 홈서버의 ACTIVE 멤버를 선택하세요. 1명이면 1:1, 2명 이상이면 그룹 대화가 됩니다.';

  @override
  String get selectMembers => '멤버를 선택해 주세요';

  @override
  String get oneMemberSelected => '1명 선택 · 1:1 대화';

  @override
  String manyMembersSelected(int count) {
    return '$count명 선택 · 그룹 대화';
  }

  @override
  String get activeMember => 'ACTIVE 일반 구성원';

  @override
  String get groupConversationName => '그룹 대화 이름 (선택)';

  @override
  String groupConversationDefault(Object names) {
    return '$names 그룹';
  }

  @override
  String get groupConversationHelper => '비워 두면 선택한 멤버 이름으로 만들어요.';

  @override
  String get cancel => '취소';

  @override
  String get createConversation => '대화 만들기';

  @override
  String get directConversationCreated => '소유자 승인 없이 1:1 대화를 만들었습니다.';

  @override
  String get groupConversationCreated => '소유자 승인 없이 그룹 대화를 만들었습니다.';

  @override
  String directConversationStart(Object name) {
    return '$name 대화의 시작';
  }

  @override
  String groupConversationStart(Object name) {
    return '$name 그룹 대화의 시작';
  }

  @override
  String directMessageHint(Object name) {
    return '$name에게 메시지 보내기';
  }

  @override
  String groupMessageHint(Object name) {
    return '$name 그룹에 메시지 보내기';
  }

  @override
  String get directConversationPurpose => '같은 홈서버의 등록 멤버만 참여하는 비공개 대화';

  @override
  String get groupConversationPurpose => '같은 홈서버의 등록 멤버들이 참여하는 비공개 그룹 대화';

  @override
  String get privacySecurityActive => '개인 홈서버 · TRUE_E2EE 설계 · 로컬 시뮬레이션';

  @override
  String get channelPurpose => '오로라 출시 준비와 의사결정을 기록합니다';

  @override
  String get startHuddle => '허들 시작';

  @override
  String trueE2eeBanner(Object version) {
    return 'TRUE_E2EE 설계 목표 · 키는 참여 기기에만 · 실제 암호화·서버 연결 미구현 · v$version';
  }

  @override
  String trueE2eeTransportBanner(Object version) {
    return 'TRUE_E2EE 암호화 어댑터·내구성 동기화 경로 구성 · 외부 보안 검증 필요 · v$version';
  }

  @override
  String get viewSecurityDetails => '보안 설계 보기';

  @override
  String get reply => '답글';

  @override
  String get taskCardTitle => '출시 전 보안 점검';

  @override
  String get inProgress => '진행 중';

  @override
  String get taskCardProgress => '8개 중 6개 완료 · 오늘 오후 4시 검토';

  @override
  String get removeAttachment => '첨부 제거';

  @override
  String attachmentDescriptionLabel(Object fileName) {
    return '$fileName 접근성 설명';
  }

  @override
  String get attachmentDescriptionHint => '첨부 내용을 설명해 주세요 (선택)';

  @override
  String get genericFileLabel => '일반 파일';

  @override
  String messageChannelHint(Object channelName) {
    return '#$channelName에 메시지 보내기';
  }

  @override
  String get attachmentPolicySummary =>
      '로컬 안전 한도 · 이미지 최대 30MB · 동영상 최대 500MB · 일반 파일 최대 1GB · 최대 30개';

  @override
  String get addMenu => '추가 메뉴';

  @override
  String get createTask => '업무 만들기';

  @override
  String get send => '보내기';

  @override
  String get members => '멤버';

  @override
  String get membersDetail => '24명 · 외부 게스트 없음';

  @override
  String get sharedFiles => '공유 파일';

  @override
  String get sharedFilesDetail => '최근 30일 18개';

  @override
  String get pinnedItems => '고정된 항목';

  @override
  String get pinnedItemsDetail => '결정 사항 4개';

  @override
  String get securityStatus => '보안 상태';

  @override
  String get memberKeyCustodyStatus => '설계 목표: 대화 키는 참여 기기에만 보관 · 미검증';

  @override
  String get encryptedAttachmentStatus =>
      '설계 목표: 이미지·영상·파일 종단간 암호화 · 실제 전송 미연결';

  @override
  String get homeserverBlindStatus => '개인 홈서버는 메시지 키를 보유하지 않도록 설계';

  @override
  String get integrityAnchorStatus => '설계 목표: 원문 없는 무결성 앵커 · 블록체인 미연결';

  @override
  String accessibilityDescription(Object description) {
    return '접근성 설명: $description';
  }

  @override
  String get profileEditorClose => '프로필 편집 닫기';

  @override
  String get profileEditorTitle => '업무 프로필 편집';

  @override
  String get save => '저장';

  @override
  String get unnamed => '이름 없음';

  @override
  String get profileImagePolicyError => '지원 이미지 형식 또는 30MB 용량 한도에 맞지 않습니다.';

  @override
  String get profileImageOnly => '프로필에는 이미지만 선택할 수 있습니다.';

  @override
  String get profileImageOpenFailed => '이미지를 열지 못했습니다. 다시 시도해 주세요.';

  @override
  String get profileNameRequired => '표시 이름을 입력해 주세요.';

  @override
  String get profilePhotoSelect => '프로필 사진 선택';

  @override
  String get coverImageSelect => '커버 이미지 선택';

  @override
  String get profileLocalNotice => '이름·직책·팀은 이 기기의 프로필에서 직접 관리합니다.';

  @override
  String get name => '이름';

  @override
  String get jobTitle => '직책';

  @override
  String get team => '팀';

  @override
  String get statusMessage => '상태 메시지';

  @override
  String get timezone => '시간대';

  @override
  String get timezoneHint => '예: 서울 · UTC+9';

  @override
  String get profileTheme => '프로필 테마';

  @override
  String get profileThemeDescription => '업무 화면에 어울리는 차분한 색상입니다.';

  @override
  String profileThemeSemantics(int number) {
    return '차분한 테마 색상 $number';
  }

  @override
  String get localEditAvailable => '이 기기에서 편집';
}
