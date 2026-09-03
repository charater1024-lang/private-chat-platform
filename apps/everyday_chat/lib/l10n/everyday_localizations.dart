import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'everyday_localizations_en.dart';
import 'everyday_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of EverydayLocalizations
/// returned by `EverydayLocalizations.of(context)`.
///
/// Applications need to include `EverydayLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/everyday_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: EverydayLocalizations.localizationsDelegates,
///   supportedLocales: EverydayLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the EverydayLocalizations.supportedLocales
/// property.
abstract class EverydayLocalizations {
  EverydayLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static EverydayLocalizations of(BuildContext context) {
    return Localizations.of<EverydayLocalizations>(
      context,
      EverydayLocalizations,
    )!;
  }

  static const LocalizationsDelegate<EverydayLocalizations> delegate =
      _EverydayLocalizationsDelegate();

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
  /// **'Everyday Chat'**
  String get appTitle;

  /// No description provided for @brandTitle.
  ///
  /// In ko, this message translates to:
  /// **'Everyday'**
  String get brandTitle;

  /// No description provided for @brandTagline.
  ///
  /// In ko, this message translates to:
  /// **'소중한 사람들과 편안하게'**
  String get brandTagline;

  /// No description provided for @navFriends.
  ///
  /// In ko, this message translates to:
  /// **'친구'**
  String get navFriends;

  /// No description provided for @navChats.
  ///
  /// In ko, this message translates to:
  /// **'대화'**
  String get navChats;

  /// No description provided for @navCalls.
  ///
  /// In ko, this message translates to:
  /// **'통화'**
  String get navCalls;

  /// No description provided for @navMore.
  ///
  /// In ko, this message translates to:
  /// **'더보기'**
  String get navMore;

  /// No description provided for @newChat.
  ///
  /// In ko, this message translates to:
  /// **'새 대화'**
  String get newChat;

  /// No description provided for @searchChats.
  ///
  /// In ko, this message translates to:
  /// **'대화 검색'**
  String get searchChats;

  /// No description provided for @trueE2ee.
  ///
  /// In ko, this message translates to:
  /// **'목표 정책: 종단간 암호화 · 미검증'**
  String get trueE2ee;

  /// No description provided for @homeserverStatusTitle.
  ///
  /// In ko, this message translates to:
  /// **'내 홈서버 연결'**
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
  /// **'닫힌 서버 · 연합 꺼짐'**
  String get closedFederation;

  /// No description provided for @privacyEncryptionMode.
  ///
  /// In ko, this message translates to:
  /// **'목표: 종단간 암호화 · 서버 복호화 불가 · 미검증'**
  String get privacyEncryptionMode;

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

  /// No description provided for @activeMemberCanCreate.
  ///
  /// In ko, this message translates to:
  /// **'ACTIVE 일반 구성원 · 소유자 승인 없이 1:1/그룹 대화 생성 가능'**
  String get activeMemberCanCreate;

  /// No description provided for @noSearchResults.
  ///
  /// In ko, this message translates to:
  /// **'검색 결과가 없어요'**
  String get noSearchResults;

  /// No description provided for @conversationList.
  ///
  /// In ko, this message translates to:
  /// **'대화 목록'**
  String get conversationList;

  /// No description provided for @voiceCall.
  ///
  /// In ko, this message translates to:
  /// **'음성 통화'**
  String get voiceCall;

  /// No description provided for @conversationInfo.
  ///
  /// In ko, this message translates to:
  /// **'대화 정보'**
  String get conversationInfo;

  /// No description provided for @directConversationPrivacy.
  ///
  /// In ko, this message translates to:
  /// **'1:1 대화 · 참여자의 기기에서만 열립니다'**
  String get directConversationPrivacy;

  /// No description provided for @groupConversationPrivacy.
  ///
  /// In ko, this message translates to:
  /// **'단체 대화 · {count}명 · 참여자의 기기에서만 열립니다'**
  String groupConversationPrivacy(int count);

  /// No description provided for @conversationEncrypted.
  ///
  /// In ko, this message translates to:
  /// **'목표 정책: 종단간 암호화 · 현재 로컬 프로토타입'**
  String get conversationEncrypted;

  /// No description provided for @sending.
  ///
  /// In ko, this message translates to:
  /// **'보내는 중'**
  String get sending;

  /// No description provided for @sendFailed.
  ///
  /// In ko, this message translates to:
  /// **'전송 실패'**
  String get sendFailed;

  /// No description provided for @sent.
  ///
  /// In ko, this message translates to:
  /// **'전송됨'**
  String get sent;

  /// No description provided for @timeNow.
  ///
  /// In ko, this message translates to:
  /// **'방금'**
  String get timeNow;

  /// No description provided for @chooseItemTitle.
  ///
  /// In ko, this message translates to:
  /// **'보낼 항목 선택'**
  String get chooseItemTitle;

  /// No description provided for @mediaActionTitle.
  ///
  /// In ko, this message translates to:
  /// **'사진·동영상·파일'**
  String get mediaActionTitle;

  /// No description provided for @mediaActionSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'기기에서 사진, 동영상 또는 파일을 골라요'**
  String get mediaActionSubtitle;

  /// No description provided for @stickersActionTitle.
  ///
  /// In ko, this message translates to:
  /// **'캐릭터 이모티콘'**
  String get stickersActionTitle;

  /// No description provided for @stickersActionSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'움직이는 캐릭터와 한국어 감정 표현을 보내요'**
  String get stickersActionSubtitle;

  /// No description provided for @stickerPickerClose.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘 선택기 닫기'**
  String get stickerPickerClose;

  /// No description provided for @stickerPickerInstruction.
  ///
  /// In ko, this message translates to:
  /// **'이모티콘을 고르면 현재 대화방에 바로 보내요.'**
  String get stickerPickerInstruction;

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

  /// No description provided for @profileCustomize.
  ///
  /// In ko, this message translates to:
  /// **'프로필 꾸미기'**
  String get profileCustomize;

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

  /// No description provided for @statusPrompt.
  ///
  /// In ko, this message translates to:
  /// **'상태 메시지를 입력해 보세요'**
  String get statusPrompt;

  /// No description provided for @profilePhotoSelect.
  ///
  /// In ko, this message translates to:
  /// **'프로필 사진 선택'**
  String get profilePhotoSelect;

  /// No description provided for @profileBackgroundSelect.
  ///
  /// In ko, this message translates to:
  /// **'배경 이미지 선택'**
  String get profileBackgroundSelect;

  /// No description provided for @myInfo.
  ///
  /// In ko, this message translates to:
  /// **'내 정보'**
  String get myInfo;

  /// No description provided for @displayName.
  ///
  /// In ko, this message translates to:
  /// **'표시 이름'**
  String get displayName;

  /// No description provided for @statusMessage.
  ///
  /// In ko, this message translates to:
  /// **'상태 메시지'**
  String get statusMessage;

  /// No description provided for @profileTheme.
  ///
  /// In ko, this message translates to:
  /// **'프로필 테마'**
  String get profileTheme;

  /// No description provided for @themeSprout.
  ///
  /// In ko, this message translates to:
  /// **'새싹'**
  String get themeSprout;

  /// No description provided for @themePurple.
  ///
  /// In ko, this message translates to:
  /// **'보라'**
  String get themePurple;

  /// No description provided for @themeLilac.
  ///
  /// In ko, this message translates to:
  /// **'라일락'**
  String get themeLilac;

  /// No description provided for @themeOlive.
  ///
  /// In ko, this message translates to:
  /// **'올리브'**
  String get themeOlive;

  /// No description provided for @profileThemeSemantics.
  ///
  /// In ko, this message translates to:
  /// **'{name} 프로필 테마'**
  String profileThemeSemantics(Object name);

  /// No description provided for @themeTooltip.
  ///
  /// In ko, this message translates to:
  /// **'{name} 테마'**
  String themeTooltip(Object name);

  /// No description provided for @profileLocalPreviewTitle.
  ///
  /// In ko, this message translates to:
  /// **'현재 사진은 이 기기에서만 미리 보여요'**
  String get profileLocalPreviewTitle;

  /// No description provided for @profileLocalPreviewSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'서버 저장·동기화·암호화 업로드는 다음 단계에서 연결합니다.'**
  String get profileLocalPreviewSubtitle;

  /// No description provided for @profileSave.
  ///
  /// In ko, this message translates to:
  /// **'프로필 저장'**
  String get profileSave;

  /// No description provided for @profileNameRequired.
  ///
  /// In ko, this message translates to:
  /// **'표시 이름을 입력해 주세요.'**
  String get profileNameRequired;

  /// No description provided for @profileSaved.
  ///
  /// In ko, this message translates to:
  /// **'프로필이 저장되었어요.'**
  String get profileSaved;

  /// No description provided for @removeSelection.
  ///
  /// In ko, this message translates to:
  /// **'선택 항목 제거'**
  String get removeSelection;

  /// No description provided for @mediaDescriptionSemantics.
  ///
  /// In ko, this message translates to:
  /// **'선택한 첨부 파일의 접근성 설명'**
  String get mediaDescriptionSemantics;

  /// No description provided for @mediaDescriptionLabel.
  ///
  /// In ko, this message translates to:
  /// **'첨부 파일 설명 (선택)'**
  String get mediaDescriptionLabel;

  /// No description provided for @mediaDescriptionHint.
  ///
  /// In ko, this message translates to:
  /// **'화면을 보지 못하는 사람도 내용을 이해할 수 있게 설명해 주세요'**
  String get mediaDescriptionHint;

  /// No description provided for @composerAddTooltip.
  ///
  /// In ko, this message translates to:
  /// **'사진·동영상·파일 또는 캐릭터 이모티콘 보내기'**
  String get composerAddTooltip;

  /// No description provided for @messageHint.
  ///
  /// In ko, this message translates to:
  /// **'메시지를 입력하세요'**
  String get messageHint;

  /// No description provided for @send.
  ///
  /// In ko, this message translates to:
  /// **'보내기'**
  String get send;

  /// No description provided for @placeholderDescription.
  ///
  /// In ko, this message translates to:
  /// **'다음 개발 단계에서 실제 데이터와 연결됩니다.'**
  String get placeholderDescription;

  /// No description provided for @welcomeHint.
  ///
  /// In ko, this message translates to:
  /// **'대화를 선택하면 이곳에서 이어갈 수 있어요.'**
  String get welcomeHint;

  /// No description provided for @newConversationTitle.
  ///
  /// In ko, this message translates to:
  /// **'새 대화 만들기'**
  String get newConversationTitle;

  /// No description provided for @newConversationInstruction.
  ///
  /// In ko, this message translates to:
  /// **'친구 1명을 고르면 1:1 대화, 2명 이상을 고르면 단체방으로 만들어져요.'**
  String get newConversationInstruction;

  /// No description provided for @selectFriend.
  ///
  /// In ko, this message translates to:
  /// **'친구를 선택해 주세요'**
  String get selectFriend;

  /// No description provided for @oneFriendSelected.
  ///
  /// In ko, this message translates to:
  /// **'1명 선택 · 1:1 대화'**
  String get oneFriendSelected;

  /// No description provided for @manyFriendsSelected.
  ///
  /// In ko, this message translates to:
  /// **'{count}명 선택 · 단체 대화'**
  String manyFriendsSelected(int count);

  /// No description provided for @friend.
  ///
  /// In ko, this message translates to:
  /// **'친구'**
  String get friend;

  /// No description provided for @groupNameOptional.
  ///
  /// In ko, this message translates to:
  /// **'단체방 이름 (선택)'**
  String get groupNameOptional;

  /// No description provided for @groupNameHelper.
  ///
  /// In ko, this message translates to:
  /// **'비워 두면 선택한 친구 이름으로 만들어요.'**
  String get groupNameHelper;

  /// No description provided for @cancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get cancel;

  /// No description provided for @createGroup.
  ///
  /// In ko, this message translates to:
  /// **'단체방 만들기'**
  String get createGroup;

  /// No description provided for @startDirect.
  ///
  /// In ko, this message translates to:
  /// **'1:1 대화 시작'**
  String get startDirect;

  /// No description provided for @groupNameDefault.
  ///
  /// In ko, this message translates to:
  /// **'{names} 모임'**
  String groupNameDefault(Object names);

  /// No description provided for @newGroupPreview.
  ///
  /// In ko, this message translates to:
  /// **'{count}명이 함께하는 새 단체방'**
  String newGroupPreview(int count);

  /// No description provided for @newDirectPreview.
  ///
  /// In ko, this message translates to:
  /// **'새로운 1:1 대화가 시작되었어요'**
  String get newDirectPreview;

  /// No description provided for @maxFiles.
  ///
  /// In ko, this message translates to:
  /// **'한 번에 최대 {count}개까지 보낼 수 있어요.'**
  String maxFiles(int count);

  /// No description provided for @mediaPickFailed.
  ///
  /// In ko, this message translates to:
  /// **'첨부 파일을 선택하지 못했어요. 다시 시도해 주세요.'**
  String get mediaPickFailed;

  /// No description provided for @imagePickFailed.
  ///
  /// In ko, this message translates to:
  /// **'이미지를 선택하지 못했어요. 다시 시도해 주세요.'**
  String get imagePickFailed;

  /// No description provided for @profileImageOnly.
  ///
  /// In ko, this message translates to:
  /// **'프로필에는 이미지 파일만 사용할 수 있어요.'**
  String get profileImageOnly;

  /// No description provided for @imageTooLarge.
  ///
  /// In ko, this message translates to:
  /// **'이미지는 30MB 이하만 보낼 수 있어요.'**
  String get imageTooLarge;

  /// No description provided for @videoTooLarge.
  ///
  /// In ko, this message translates to:
  /// **'동영상은 500MB 이하만 보낼 수 있어요.'**
  String get videoTooLarge;

  /// No description provided for @fileTooLarge.
  ///
  /// In ko, this message translates to:
  /// **'파일은 1GB 이하만 보낼 수 있어요.'**
  String get fileTooLarge;

  /// No description provided for @unsupportedMedia.
  ///
  /// In ko, this message translates to:
  /// **'지원하지 않는 첨부 파일 형식이에요.'**
  String get unsupportedMedia;

  /// No description provided for @unusableFile.
  ///
  /// In ko, this message translates to:
  /// **'선택한 파일을 사용할 수 없어요.'**
  String get unusableFile;
}

class _EverydayLocalizationsDelegate
    extends LocalizationsDelegate<EverydayLocalizations> {
  const _EverydayLocalizationsDelegate();

  @override
  Future<EverydayLocalizations> load(Locale locale) {
    return SynchronousFuture<EverydayLocalizations>(
      lookupEverydayLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_EverydayLocalizationsDelegate old) => false;
}

EverydayLocalizations lookupEverydayLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return EverydayLocalizationsEn();
    case 'ko':
      return EverydayLocalizationsKo();
  }

  throw FlutterError(
    'EverydayLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
