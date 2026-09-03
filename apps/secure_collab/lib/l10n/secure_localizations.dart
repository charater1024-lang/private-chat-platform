import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'secure_localizations_en.dart';
import 'secure_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of SecureLocalizations
/// returned by `SecureLocalizations.of(context)`.
///
/// Applications need to include `SecureLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/secure_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: SecureLocalizations.localizationsDelegates,
///   supportedLocales: SecureLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the SecureLocalizations.supportedLocales
/// property.
abstract class SecureLocalizations {
  SecureLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static SecureLocalizations of(BuildContext context) {
    return Localizations.of<SecureLocalizations>(context, SecureLocalizations)!;
  }

  static const LocalizationsDelegate<SecureLocalizations> delegate =
      _SecureLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ko'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ko, this message translates to:
  /// **'Secure Collab'**
  String get appTitle;

  /// No description provided for @search.
  ///
  /// In ko, this message translates to:
  /// **'검색'**
  String get search;

  /// No description provided for @channelInfo.
  ///
  /// In ko, this message translates to:
  /// **'채널 정보'**
  String get channelInfo;

  /// No description provided for @homeserverStatusTitle.
  ///
  /// In ko, this message translates to:
  /// **'개인 홈서버 연결'**
  String get homeserverStatusTitle;

  /// No description provided for @homeserverName.
  ///
  /// In ko, this message translates to:
  /// **'홈서버: {name}'**
  String homeserverName(Object name);

  /// No description provided for @httpsPending.
  ///
  /// In ko, this message translates to:
  /// **'HTTPS: 연결 전 · 인증서 확인 대기'**
  String get httpsPending;

  /// No description provided for @closedFederation.
  ///
  /// In ko, this message translates to:
  /// **'개인 서버 · 연합 꺼짐'**
  String get closedFederation;

  /// No description provided for @memberOnlyEncryptionMode.
  ///
  /// In ko, this message translates to:
  /// **'설계 목표: TRUE_E2EE · 참여 기기만 키 보유 · 미검증'**
  String get memberOnlyEncryptionMode;

  /// No description provided for @prototypeConnectionPending.
  ///
  /// In ko, this message translates to:
  /// **'로컬 프로토타입 · 실제 서버 연결 예정'**
  String get prototypeConnectionPending;

  /// No description provided for @transportVerificationActive.
  ///
  /// In ko, this message translates to:
  /// **'인증 통신 어댑터 · 연결 시 서버 신원 검증'**
  String get transportVerificationActive;

  /// No description provided for @syncDisconnected.
  ///
  /// In ko, this message translates to:
  /// **'동기화 구성됨 · 연결 대기'**
  String get syncDisconnected;

  /// No description provided for @syncConnecting.
  ///
  /// In ko, this message translates to:
  /// **'홈서버 연결과 신원을 확인하는 중'**
  String get syncConnecting;

  /// No description provided for @syncConnected.
  ///
  /// In ko, this message translates to:
  /// **'홈서버 연결됨 · 대기 {count}개'**
  String syncConnected(int count);

  /// No description provided for @syncBackingOff.
  ///
  /// In ko, this message translates to:
  /// **'연결 재시도 대기 · 전송 대기 {count}개'**
  String syncBackingOff(int count);

  /// No description provided for @syncBlocked.
  ///
  /// In ko, this message translates to:
  /// **'보안 확인 실패 · 서버나 인증 설정 확인 필요'**
  String get syncBlocked;

  /// No description provided for @syncFailed.
  ///
  /// In ko, this message translates to:
  /// **'로컬 동기화 오류 · 재시도 필요'**
  String get syncFailed;

  /// No description provided for @syncStopped.
  ///
  /// In ko, this message translates to:
  /// **'동기화 중지됨'**
  String get syncStopped;

  /// No description provided for @deliveryLocalOnly.
  ///
  /// In ko, this message translates to:
  /// **'이 기기에만 저장됨'**
  String get deliveryLocalOnly;

  /// No description provided for @deliveryQueued.
  ///
  /// In ko, this message translates to:
  /// **'암호화 전송 대기'**
  String get deliveryQueued;

  /// No description provided for @deliveryAcknowledged.
  ///
  /// In ko, this message translates to:
  /// **'홈서버에 전달됨'**
  String get deliveryAcknowledged;

  /// No description provided for @deliveryRetryScheduled.
  ///
  /// In ko, this message translates to:
  /// **'재전송 대기'**
  String get deliveryRetryScheduled;

  /// No description provided for @deliveryBlocked.
  ///
  /// In ko, this message translates to:
  /// **'보안 확인 필요'**
  String get deliveryBlocked;

  /// No description provided for @deliveryFailed.
  ///
  /// In ko, this message translates to:
  /// **'전송 실패'**
  String get deliveryFailed;

  /// No description provided for @profileEditTooltip.
  ///
  /// In ko, this message translates to:
  /// **'{name} 업무 프로필 편집'**
  String profileEditTooltip(Object name);

  /// No description provided for @navConversations.
  ///
  /// In ko, this message translates to:
  /// **'대화'**
  String get navConversations;

  /// No description provided for @navTasks.
  ///
  /// In ko, this message translates to:
  /// **'업무'**
  String get navTasks;

  /// No description provided for @navActivity.
  ///
  /// In ko, this message translates to:
  /// **'활동'**
  String get navActivity;

  /// No description provided for @navProfile.
  ///
  /// In ko, this message translates to:
  /// **'내 정보'**
  String get navProfile;

  /// No description provided for @addItemTitle.
  ///
  /// In ko, this message translates to:
  /// **'추가할 항목'**
  String get addItemTitle;

  /// No description provided for @mediaActionTitle.
  ///
  /// In ko, this message translates to:
  /// **'사진·동영상·파일'**
  String get mediaActionTitle;

  /// No description provided for @mediaActionSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'이 기기에서 암호화해 보낼 첨부를 선택해요'**
  String get mediaActionSubtitle;

  /// No description provided for @stickersActionTitle.
  ///
  /// In ko, this message translates to:
  /// **'캐릭터 이모티콘'**
  String get stickersActionTitle;

  /// No description provided for @stickersActionSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'6개 캐릭터의 움직이는 한국어 감정 표현을 바로 보내요'**
  String get stickersActionSubtitle;

  /// No description provided for @stickerEmpty.
  ///
  /// In ko, this message translates to:
  /// **'사용할 수 있는 이모티콘이 없어요'**
  String get stickerEmpty;

  /// No description provided for @stickerPreviousPage.
  ///
  /// In ko, this message translates to:
  /// **'이전 이모티콘'**
  String get stickerPreviousPage;

  /// No description provided for @stickerNextPage.
  ///
  /// In ko, this message translates to:
  /// **'다음 이모티콘'**
  String get stickerNextPage;

  /// No description provided for @stickerPageSemantics.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘 {page}페이지, 전체 {total}페이지'**
  String stickerPageSemantics(int page, int total);

  /// No description provided for @stickerAccessibility.
  ///
  /// In ko, this message translates to:
  /// **'{character} 캐릭터, {meaning}. 한국어 표현: {koreanPhrase}'**
  String stickerAccessibility(
    Object character,
    Object meaning,
    Object koreanPhrase,
  );

  /// No description provided for @stickerMeaningGreeting.
  ///
  /// In ko, this message translates to:
  /// **'인사'**
  String get stickerMeaningGreeting;

  /// No description provided for @stickerMeaningWelcome.
  ///
  /// In ko, this message translates to:
  /// **'환영'**
  String get stickerMeaningWelcome;

  /// No description provided for @stickerMeaningAgreement.
  ///
  /// In ko, this message translates to:
  /// **'동의'**
  String get stickerMeaningAgreement;

  /// No description provided for @stickerMeaningUnderstood.
  ///
  /// In ko, this message translates to:
  /// **'이해함'**
  String get stickerMeaningUnderstood;

  /// No description provided for @stickerMeaningSleep.
  ///
  /// In ko, this message translates to:
  /// **'잠'**
  String get stickerMeaningSleep;

  /// No description provided for @stickerMeaningSuccess.
  ///
  /// In ko, this message translates to:
  /// **'성공'**
  String get stickerMeaningSuccess;

  /// No description provided for @stickerMeaningLove.
  ///
  /// In ko, this message translates to:
  /// **'사랑'**
  String get stickerMeaningLove;

  /// No description provided for @stickerMeaningMissing.
  ///
  /// In ko, this message translates to:
  /// **'그리움'**
  String get stickerMeaningMissing;

  /// No description provided for @stickerMeaningThanks.
  ///
  /// In ko, this message translates to:
  /// **'감사'**
  String get stickerMeaningThanks;

  /// No description provided for @stickerMeaningSorry.
  ///
  /// In ko, this message translates to:
  /// **'사과'**
  String get stickerMeaningSorry;

  /// No description provided for @stickerMeaningPlease.
  ///
  /// In ko, this message translates to:
  /// **'부탁'**
  String get stickerMeaningPlease;

  /// No description provided for @stickerMeaningComfort.
  ///
  /// In ko, this message translates to:
  /// **'위로'**
  String get stickerMeaningComfort;

  /// No description provided for @stickerMeaningLaugh.
  ///
  /// In ko, this message translates to:
  /// **'웃음'**
  String get stickerMeaningLaugh;

  /// No description provided for @stickerMeaningMusic.
  ///
  /// In ko, this message translates to:
  /// **'음악'**
  String get stickerMeaningMusic;

  /// No description provided for @stickerMeaningSurprise.
  ///
  /// In ko, this message translates to:
  /// **'놀람'**
  String get stickerMeaningSurprise;

  /// No description provided for @stickerMeaningShock.
  ///
  /// In ko, this message translates to:
  /// **'충격'**
  String get stickerMeaningShock;

  /// No description provided for @stickerMeaningLike.
  ///
  /// In ko, this message translates to:
  /// **'좋아요'**
  String get stickerMeaningLike;

  /// No description provided for @stickerMeaningCelebrate.
  ///
  /// In ko, this message translates to:
  /// **'축하'**
  String get stickerMeaningCelebrate;

  /// No description provided for @stickerMeaningCheer.
  ///
  /// In ko, this message translates to:
  /// **'응원'**
  String get stickerMeaningCheer;

  /// No description provided for @stickerMeaningClap.
  ///
  /// In ko, this message translates to:
  /// **'박수'**
  String get stickerMeaningClap;

  /// No description provided for @stickerMeaningAngry.
  ///
  /// In ko, this message translates to:
  /// **'화남'**
  String get stickerMeaningAngry;

  /// No description provided for @stickerMeaningSad.
  ///
  /// In ko, this message translates to:
  /// **'슬픔'**
  String get stickerMeaningSad;

  /// No description provided for @stickerMeaningCry.
  ///
  /// In ko, this message translates to:
  /// **'울음'**
  String get stickerMeaningCry;

  /// No description provided for @stickerMeaningTired.
  ///
  /// In ko, this message translates to:
  /// **'피곤함'**
  String get stickerMeaningTired;

  /// No description provided for @characterMori.
  ///
  /// In ko, this message translates to:
  /// **'모리'**
  String get characterMori;

  /// No description provided for @characterLulu.
  ///
  /// In ko, this message translates to:
  /// **'루루'**
  String get characterLulu;

  /// No description provided for @characterBobo.
  ///
  /// In ko, this message translates to:
  /// **'보보'**
  String get characterBobo;

  /// No description provided for @characterToto.
  ///
  /// In ko, this message translates to:
  /// **'토토'**
  String get characterToto;

  /// No description provided for @characterNuri.
  ///
  /// In ko, this message translates to:
  /// **'누리'**
  String get characterNuri;

  /// No description provided for @characterDuri.
  ///
  /// In ko, this message translates to:
  /// **'두리'**
  String get characterDuri;

  /// No description provided for @characterTogether.
  ///
  /// In ko, this message translates to:
  /// **'함께'**
  String get characterTogether;

  /// No description provided for @maxAttachments.
  ///
  /// In ko, this message translates to:
  /// **'첨부는 한 번에 최대 30개까지 보낼 수 있습니다.'**
  String get maxAttachments;

  /// No description provided for @fileOpenFailed.
  ///
  /// In ko, this message translates to:
  /// **'파일을 열지 못했습니다. 다시 시도해 주세요.'**
  String get fileOpenFailed;

  /// No description provided for @imageTooLarge.
  ///
  /// In ko, this message translates to:
  /// **'이미지는 파일당 30MB 이하여야 합니다.'**
  String get imageTooLarge;

  /// No description provided for @videoTooLarge.
  ///
  /// In ko, this message translates to:
  /// **'동영상은 파일당 500MB 이하여야 합니다.'**
  String get videoTooLarge;

  /// No description provided for @genericFileTooLarge.
  ///
  /// In ko, this message translates to:
  /// **'일반 파일은 파일당 1GB 이하여야 합니다.'**
  String get genericFileTooLarge;

  /// No description provided for @mediaNotAllowed.
  ///
  /// In ko, this message translates to:
  /// **'지원하는 이미지, 동영상 또는 파일 형식이 아닙니다.'**
  String get mediaNotAllowed;

  /// No description provided for @attachmentPolicyMismatch.
  ///
  /// In ko, this message translates to:
  /// **'선택한 첨부가 앱의 안전 한도에 맞지 않습니다.'**
  String get attachmentPolicyMismatch;

  /// No description provided for @profileSaved.
  ///
  /// In ko, this message translates to:
  /// **'업무 프로필을 저장했습니다.'**
  String get profileSaved;

  /// No description provided for @timeNow.
  ///
  /// In ko, this message translates to:
  /// **'방금'**
  String get timeNow;

  /// No description provided for @channelStart.
  ///
  /// In ko, this message translates to:
  /// **'#{name} 채널의 시작'**
  String channelStart(Object name);

  /// No description provided for @addWorkspace.
  ///
  /// In ko, this message translates to:
  /// **'워크스페이스 추가'**
  String get addWorkspace;

  /// No description provided for @newMessage.
  ///
  /// In ko, this message translates to:
  /// **'새 메시지'**
  String get newMessage;

  /// No description provided for @workspaceSearch.
  ///
  /// In ko, this message translates to:
  /// **'워크스페이스 검색'**
  String get workspaceSearch;

  /// No description provided for @channels.
  ///
  /// In ko, this message translates to:
  /// **'채널'**
  String get channels;

  /// No description provided for @directMessages.
  ///
  /// In ko, this message translates to:
  /// **'1:1 및 그룹 대화'**
  String get directMessages;

  /// No description provided for @newDirectMessage.
  ///
  /// In ko, this message translates to:
  /// **'새 1:1 또는 그룹 대화'**
  String get newDirectMessage;

  /// No description provided for @memberCanCreate.
  ///
  /// In ko, this message translates to:
  /// **'일반 구성원 · ACTIVE · 소유자 승인 없이 대화 생성 가능'**
  String get memberCanCreate;

  /// No description provided for @newDirectDialogTitle.
  ///
  /// In ko, this message translates to:
  /// **'멤버와 대화 만들기'**
  String get newDirectDialogTitle;

  /// No description provided for @newDirectDialogInstruction.
  ///
  /// In ko, this message translates to:
  /// **'같은 홈서버의 ACTIVE 멤버를 선택하세요. 1명이면 1:1, 2명 이상이면 그룹 대화가 됩니다.'**
  String get newDirectDialogInstruction;

  /// No description provided for @selectMembers.
  ///
  /// In ko, this message translates to:
  /// **'멤버를 선택해 주세요'**
  String get selectMembers;

  /// No description provided for @oneMemberSelected.
  ///
  /// In ko, this message translates to:
  /// **'1명 선택 · 1:1 대화'**
  String get oneMemberSelected;

  /// No description provided for @manyMembersSelected.
  ///
  /// In ko, this message translates to:
  /// **'{count}명 선택 · 그룹 대화'**
  String manyMembersSelected(int count);

  /// No description provided for @activeMember.
  ///
  /// In ko, this message translates to:
  /// **'ACTIVE 일반 구성원'**
  String get activeMember;

  /// No description provided for @groupConversationName.
  ///
  /// In ko, this message translates to:
  /// **'그룹 대화 이름 (선택)'**
  String get groupConversationName;

  /// No description provided for @groupConversationDefault.
  ///
  /// In ko, this message translates to:
  /// **'{names} 그룹'**
  String groupConversationDefault(Object names);

  /// No description provided for @groupConversationHelper.
  ///
  /// In ko, this message translates to:
  /// **'비워 두면 선택한 멤버 이름으로 만들어요.'**
  String get groupConversationHelper;

  /// No description provided for @cancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get cancel;

  /// No description provided for @createConversation.
  ///
  /// In ko, this message translates to:
  /// **'대화 만들기'**
  String get createConversation;

  /// No description provided for @directConversationCreated.
  ///
  /// In ko, this message translates to:
  /// **'소유자 승인 없이 1:1 대화를 만들었습니다.'**
  String get directConversationCreated;

  /// No description provided for @groupConversationCreated.
  ///
  /// In ko, this message translates to:
  /// **'소유자 승인 없이 그룹 대화를 만들었습니다.'**
  String get groupConversationCreated;

  /// No description provided for @directConversationStart.
  ///
  /// In ko, this message translates to:
  /// **'{name} 대화의 시작'**
  String directConversationStart(Object name);

  /// No description provided for @groupConversationStart.
  ///
  /// In ko, this message translates to:
  /// **'{name} 그룹 대화의 시작'**
  String groupConversationStart(Object name);

  /// No description provided for @directMessageHint.
  ///
  /// In ko, this message translates to:
  /// **'{name}에게 메시지 보내기'**
  String directMessageHint(Object name);

  /// No description provided for @groupMessageHint.
  ///
  /// In ko, this message translates to:
  /// **'{name} 그룹에 메시지 보내기'**
  String groupMessageHint(Object name);

  /// No description provided for @directConversationPurpose.
  ///
  /// In ko, this message translates to:
  /// **'같은 홈서버의 등록 멤버만 참여하는 비공개 대화'**
  String get directConversationPurpose;

  /// No description provided for @groupConversationPurpose.
  ///
  /// In ko, this message translates to:
  /// **'같은 홈서버의 등록 멤버들이 참여하는 비공개 그룹 대화'**
  String get groupConversationPurpose;

  /// No description provided for @privacySecurityActive.
  ///
  /// In ko, this message translates to:
  /// **'개인 홈서버 · TRUE_E2EE 설계 · 로컬 시뮬레이션'**
  String get privacySecurityActive;

  /// No description provided for @channelPurpose.
  ///
  /// In ko, this message translates to:
  /// **'오로라 출시 준비와 의사결정을 기록합니다'**
  String get channelPurpose;

  /// No description provided for @startHuddle.
  ///
  /// In ko, this message translates to:
  /// **'허들 시작'**
  String get startHuddle;

  /// No description provided for @trueE2eeBanner.
  ///
  /// In ko, this message translates to:
  /// **'TRUE_E2EE 설계 목표 · 키는 참여 기기에만 · 실제 암호화·서버 연결 미구현 · v{version}'**
  String trueE2eeBanner(Object version);

  /// No description provided for @trueE2eeTransportBanner.
  ///
  /// In ko, this message translates to:
  /// **'TRUE_E2EE 암호화 어댑터·내구성 동기화 경로 구성 · 외부 보안 검증 필요 · v{version}'**
  String trueE2eeTransportBanner(Object version);

  /// No description provided for @viewSecurityDetails.
  ///
  /// In ko, this message translates to:
  /// **'보안 설계 보기'**
  String get viewSecurityDetails;

  /// No description provided for @reply.
  ///
  /// In ko, this message translates to:
  /// **'답글'**
  String get reply;

  /// No description provided for @taskCardTitle.
  ///
  /// In ko, this message translates to:
  /// **'출시 전 보안 점검'**
  String get taskCardTitle;

  /// No description provided for @inProgress.
  ///
  /// In ko, this message translates to:
  /// **'진행 중'**
  String get inProgress;

  /// No description provided for @taskCardProgress.
  ///
  /// In ko, this message translates to:
  /// **'8개 중 6개 완료 · 오늘 오후 4시 검토'**
  String get taskCardProgress;

  /// No description provided for @removeAttachment.
  ///
  /// In ko, this message translates to:
  /// **'첨부 제거'**
  String get removeAttachment;

  /// No description provided for @attachmentDescriptionLabel.
  ///
  /// In ko, this message translates to:
  /// **'{fileName} 접근성 설명'**
  String attachmentDescriptionLabel(Object fileName);

  /// No description provided for @attachmentDescriptionHint.
  ///
  /// In ko, this message translates to:
  /// **'첨부 내용을 설명해 주세요 (선택)'**
  String get attachmentDescriptionHint;

  /// No description provided for @genericFileLabel.
  ///
  /// In ko, this message translates to:
  /// **'일반 파일'**
  String get genericFileLabel;

  /// No description provided for @messageChannelHint.
  ///
  /// In ko, this message translates to:
  /// **'#{channelName}에 메시지 보내기'**
  String messageChannelHint(Object channelName);

  /// No description provided for @attachmentPolicySummary.
  ///
  /// In ko, this message translates to:
  /// **'로컬 안전 한도 · 이미지 최대 30MB · 동영상 최대 500MB · 일반 파일 최대 1GB · 최대 30개'**
  String get attachmentPolicySummary;

  /// No description provided for @addMenu.
  ///
  /// In ko, this message translates to:
  /// **'추가 메뉴'**
  String get addMenu;

  /// No description provided for @createTask.
  ///
  /// In ko, this message translates to:
  /// **'업무 만들기'**
  String get createTask;

  /// No description provided for @send.
  ///
  /// In ko, this message translates to:
  /// **'보내기'**
  String get send;

  /// No description provided for @members.
  ///
  /// In ko, this message translates to:
  /// **'멤버'**
  String get members;

  /// No description provided for @membersDetail.
  ///
  /// In ko, this message translates to:
  /// **'24명 · 외부 게스트 없음'**
  String get membersDetail;

  /// No description provided for @sharedFiles.
  ///
  /// In ko, this message translates to:
  /// **'공유 파일'**
  String get sharedFiles;

  /// No description provided for @sharedFilesDetail.
  ///
  /// In ko, this message translates to:
  /// **'최근 30일 18개'**
  String get sharedFilesDetail;

  /// No description provided for @pinnedItems.
  ///
  /// In ko, this message translates to:
  /// **'고정된 항목'**
  String get pinnedItems;

  /// No description provided for @pinnedItemsDetail.
  ///
  /// In ko, this message translates to:
  /// **'결정 사항 4개'**
  String get pinnedItemsDetail;

  /// No description provided for @securityStatus.
  ///
  /// In ko, this message translates to:
  /// **'보안 상태'**
  String get securityStatus;

  /// No description provided for @memberKeyCustodyStatus.
  ///
  /// In ko, this message translates to:
  /// **'설계 목표: 대화 키는 참여 기기에만 보관 · 미검증'**
  String get memberKeyCustodyStatus;

  /// No description provided for @encryptedAttachmentStatus.
  ///
  /// In ko, this message translates to:
  /// **'설계 목표: 이미지·영상·파일 종단간 암호화 · 실제 전송 미연결'**
  String get encryptedAttachmentStatus;

  /// No description provided for @homeserverBlindStatus.
  ///
  /// In ko, this message translates to:
  /// **'개인 홈서버는 메시지 키를 보유하지 않도록 설계'**
  String get homeserverBlindStatus;

  /// No description provided for @integrityAnchorStatus.
  ///
  /// In ko, this message translates to:
  /// **'설계 목표: 원문 없는 무결성 앵커 · 블록체인 미연결'**
  String get integrityAnchorStatus;

  /// No description provided for @accessibilityDescription.
  ///
  /// In ko, this message translates to:
  /// **'접근성 설명: {description}'**
  String accessibilityDescription(Object description);

  /// No description provided for @profileEditorClose.
  ///
  /// In ko, this message translates to:
  /// **'프로필 편집 닫기'**
  String get profileEditorClose;

  /// No description provided for @profileEditorTitle.
  ///
  /// In ko, this message translates to:
  /// **'업무 프로필 편집'**
  String get profileEditorTitle;

  /// No description provided for @save.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get save;

  /// No description provided for @unnamed.
  ///
  /// In ko, this message translates to:
  /// **'이름 없음'**
  String get unnamed;

  /// No description provided for @profileImagePolicyError.
  ///
  /// In ko, this message translates to:
  /// **'지원 이미지 형식 또는 30MB 용량 한도에 맞지 않습니다.'**
  String get profileImagePolicyError;

  /// No description provided for @profileImageOnly.
  ///
  /// In ko, this message translates to:
  /// **'프로필에는 이미지만 선택할 수 있습니다.'**
  String get profileImageOnly;

  /// No description provided for @profileImageOpenFailed.
  ///
  /// In ko, this message translates to:
  /// **'이미지를 열지 못했습니다. 다시 시도해 주세요.'**
  String get profileImageOpenFailed;

  /// No description provided for @profileNameRequired.
  ///
  /// In ko, this message translates to:
  /// **'표시 이름을 입력해 주세요.'**
  String get profileNameRequired;

  /// No description provided for @profilePhotoSelect.
  ///
  /// In ko, this message translates to:
  /// **'프로필 사진 선택'**
  String get profilePhotoSelect;

  /// No description provided for @coverImageSelect.
  ///
  /// In ko, this message translates to:
  /// **'커버 이미지 선택'**
  String get coverImageSelect;

  /// No description provided for @profileLocalNotice.
  ///
  /// In ko, this message translates to:
  /// **'이름·직책·팀은 이 기기의 프로필에서 직접 관리합니다.'**
  String get profileLocalNotice;

  /// No description provided for @name.
  ///
  /// In ko, this message translates to:
  /// **'이름'**
  String get name;

  /// No description provided for @jobTitle.
  ///
  /// In ko, this message translates to:
  /// **'직책'**
  String get jobTitle;

  /// No description provided for @team.
  ///
  /// In ko, this message translates to:
  /// **'팀'**
  String get team;

  /// No description provided for @statusMessage.
  ///
  /// In ko, this message translates to:
  /// **'상태 메시지'**
  String get statusMessage;

  /// No description provided for @timezone.
  ///
  /// In ko, this message translates to:
  /// **'시간대'**
  String get timezone;

  /// No description provided for @timezoneHint.
  ///
  /// In ko, this message translates to:
  /// **'예: 서울 · UTC+9'**
  String get timezoneHint;

  /// No description provided for @profileTheme.
  ///
  /// In ko, this message translates to:
  /// **'프로필 테마'**
  String get profileTheme;

  /// No description provided for @profileThemeDescription.
  ///
  /// In ko, this message translates to:
  /// **'업무 화면에 어울리는 차분한 색상입니다.'**
  String get profileThemeDescription;

  /// No description provided for @profileThemeSemantics.
  ///
  /// In ko, this message translates to:
  /// **'차분한 테마 색상 {number}'**
  String profileThemeSemantics(int number);

  /// No description provided for @localEditAvailable.
  ///
  /// In ko, this message translates to:
  /// **'이 기기에서 편집'**
  String get localEditAvailable;
}

class _SecureLocalizationsDelegate
    extends LocalizationsDelegate<SecureLocalizations> {
  const _SecureLocalizationsDelegate();

  @override
  Future<SecureLocalizations> load(Locale locale) {
    return SynchronousFuture<SecureLocalizations>(
      lookupSecureLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_SecureLocalizationsDelegate old) => false;
}

SecureLocalizations lookupSecureLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return SecureLocalizationsEn();
    case 'ko':
      return SecureLocalizationsKo();
  }

  throw FlutterError(
    'SecureLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
