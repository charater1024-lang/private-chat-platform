// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'everyday_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class EverydayLocalizationsEn extends EverydayLocalizations {
  EverydayLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Everyday Chat';

  @override
  String get brandTitle => 'Everyday';

  @override
  String get brandTagline => 'A comfortable place for the people who matter';

  @override
  String get navFriends => 'Friends';

  @override
  String get navChats => 'Chats';

  @override
  String get navCalls => 'Calls';

  @override
  String get navMore => 'More';

  @override
  String get newChat => 'New chat';

  @override
  String get searchChats => 'Search chats';

  @override
  String get trueE2ee => 'Target policy: E2EE · Not verified';

  @override
  String get homeserverStatusTitle => 'My homeserver connection';

  @override
  String homeserverName(Object name) {
    return 'Homeserver: $name';
  }

  @override
  String get httpsPending => 'HTTPS: Not connected · Certificate check pending';

  @override
  String get closedFederation => 'Closed server · Federation off';

  @override
  String get privacyEncryptionMode =>
      'Target: E2EE · Server cannot decrypt · Not verified';

  @override
  String get prototypeConnectionPending =>
      'Local prototype · Real server connection pending';

  @override
  String get transportVerificationActive =>
      'Authenticated transport adapter · Server identity checked on connection';

  @override
  String get syncDisconnected => 'Sync configured · Waiting to connect';

  @override
  String get syncConnecting => 'Checking homeserver connection and identity';

  @override
  String syncConnected(int count) {
    return 'Homeserver connected · $count queued';
  }

  @override
  String syncBackingOff(int count) {
    return 'Waiting to reconnect · $count queued';
  }

  @override
  String get syncBlocked =>
      'Security check failed · Review server or credentials';

  @override
  String get syncFailed => 'Local sync error · Retry required';

  @override
  String get syncStopped => 'Sync stopped';

  @override
  String get deliveryLocalOnly => 'Saved only on this device';

  @override
  String get deliveryQueued => 'Waiting for encrypted delivery';

  @override
  String get deliveryAcknowledged => 'Delivered to homeserver';

  @override
  String get deliveryRetryScheduled => 'Waiting to retry';

  @override
  String get deliveryBlocked => 'Security check required';

  @override
  String get activeMemberCanCreate =>
      'ACTIVE regular member · Can create direct/group chats without owner approval';

  @override
  String get noSearchResults => 'No results found';

  @override
  String get conversationList => 'Chat list';

  @override
  String get voiceCall => 'Voice call';

  @override
  String get conversationInfo => 'Chat information';

  @override
  String get directConversationPrivacy =>
      'Direct chat · Opens only on participants’ devices';

  @override
  String groupConversationPrivacy(int count) {
    return 'Group chat · $count members · Opens only on participants’ devices';
  }

  @override
  String get conversationEncrypted =>
      'Target policy: E2EE · Currently a local prototype';

  @override
  String get sending => 'Sending';

  @override
  String get sendFailed => 'Failed to send';

  @override
  String get sent => 'Sent';

  @override
  String get timeNow => 'Just now';

  @override
  String get chooseItemTitle => 'Choose what to send';

  @override
  String get mediaActionTitle => 'Photos, videos, and files';

  @override
  String get mediaActionSubtitle =>
      'Choose photos, videos, or files from this device';

  @override
  String get stickersActionTitle => 'Character stickers';

  @override
  String get stickersActionSubtitle =>
      'Send animated characters with Korean expressions';

  @override
  String get stickerPickerClose => 'Close sticker picker';

  @override
  String get stickerPickerInstruction =>
      'Choose a sticker to send it to this chat immediately. Speech bubbles remain in Korean.';

  @override
  String get stickerEmpty => 'No stickers are available';

  @override
  String get stickerPreviousPage => 'Previous stickers';

  @override
  String get stickerNextPage => 'Next stickers';

  @override
  String stickerPageSemantics(int page, int total) {
    return 'Sticker page $page of $total';
  }

  @override
  String stickerAccessibility(
    Object character,
    Object meaning,
    Object koreanPhrase,
  ) {
    return '$character character, $meaning. Korean phrase: $koreanPhrase';
  }

  @override
  String get stickerMeaningGreeting => 'Greeting';

  @override
  String get stickerMeaningWelcome => 'Welcome';

  @override
  String get stickerMeaningAgreement => 'Agreement';

  @override
  String get stickerMeaningUnderstood => 'Understood';

  @override
  String get stickerMeaningSleep => 'Sleep';

  @override
  String get stickerMeaningSuccess => 'Success';

  @override
  String get stickerMeaningLove => 'Love';

  @override
  String get stickerMeaningMissing => 'Missing someone';

  @override
  String get stickerMeaningThanks => 'Thanks';

  @override
  String get stickerMeaningSorry => 'Apology';

  @override
  String get stickerMeaningPlease => 'Request';

  @override
  String get stickerMeaningComfort => 'Comfort';

  @override
  String get stickerMeaningLaugh => 'Laughter';

  @override
  String get stickerMeaningMusic => 'Music';

  @override
  String get stickerMeaningSurprise => 'Surprise';

  @override
  String get stickerMeaningShock => 'Shock';

  @override
  String get stickerMeaningLike => 'Like';

  @override
  String get stickerMeaningCelebrate => 'Celebration';

  @override
  String get stickerMeaningCheer => 'Cheering';

  @override
  String get stickerMeaningClap => 'Applause';

  @override
  String get stickerMeaningAngry => 'Anger';

  @override
  String get stickerMeaningSad => 'Sadness';

  @override
  String get stickerMeaningCry => 'Crying';

  @override
  String get stickerMeaningTired => 'Tiredness';

  @override
  String get characterMori => 'Mori';

  @override
  String get characterLulu => 'Lulu';

  @override
  String get characterBobo => 'Bobo';

  @override
  String get characterToto => 'Toto';

  @override
  String get characterNuri => 'Nuri';

  @override
  String get characterDuri => 'Duri';

  @override
  String get characterTogether => 'Together';

  @override
  String get profileCustomize => 'Customize profile';

  @override
  String get save => 'Save';

  @override
  String get unnamed => 'Unnamed';

  @override
  String get statusPrompt => 'Add a status message';

  @override
  String get profilePhotoSelect => 'Choose profile photo';

  @override
  String get profileBackgroundSelect => 'Choose background image';

  @override
  String get myInfo => 'My profile';

  @override
  String get displayName => 'Display name';

  @override
  String get statusMessage => 'Status message';

  @override
  String get profileTheme => 'Profile theme';

  @override
  String get themeSprout => 'Sprout';

  @override
  String get themePurple => 'Purple';

  @override
  String get themeLilac => 'Lilac';

  @override
  String get themeOlive => 'Olive';

  @override
  String profileThemeSemantics(Object name) {
    return '$name profile theme';
  }

  @override
  String themeTooltip(Object name) {
    return '$name theme';
  }

  @override
  String get profileLocalPreviewTitle =>
      'These images are currently previewed only on this device';

  @override
  String get profileLocalPreviewSubtitle =>
      'Server storage, synchronization, and encrypted upload will be connected in the next stage.';

  @override
  String get profileSave => 'Save profile';

  @override
  String get profileNameRequired => 'Enter a display name.';

  @override
  String get profileSaved => 'Profile saved.';

  @override
  String get removeSelection => 'Remove selected item';

  @override
  String get mediaDescriptionSemantics =>
      'Accessibility description for selected attachments';

  @override
  String get mediaDescriptionLabel => 'Attachment description (optional)';

  @override
  String get mediaDescriptionHint =>
      'Describe the content for people who cannot see the screen';

  @override
  String get composerAddTooltip =>
      'Send photos, videos, files, or a character sticker';

  @override
  String get messageHint => 'Enter a message';

  @override
  String get send => 'Send';

  @override
  String get placeholderDescription =>
      'Real data will be connected in the next development stage.';

  @override
  String get welcomeHint => 'Choose a chat to continue here.';

  @override
  String get newConversationTitle => 'Create a new chat';

  @override
  String get newConversationInstruction =>
      'Choose one friend for a direct chat, or two or more for a group chat.';

  @override
  String get selectFriend => 'Choose a friend';

  @override
  String get oneFriendSelected => '1 selected · Direct chat';

  @override
  String manyFriendsSelected(int count) {
    return '$count selected · Group chat';
  }

  @override
  String get friend => 'Friend';

  @override
  String get groupNameOptional => 'Group name (optional)';

  @override
  String get groupNameHelper =>
      'Leave blank to use the selected friends’ names.';

  @override
  String get cancel => 'Cancel';

  @override
  String get createGroup => 'Create group';

  @override
  String get startDirect => 'Start direct chat';

  @override
  String groupNameDefault(Object names) {
    return '$names group';
  }

  @override
  String newGroupPreview(int count) {
    return 'A new group with $count members';
  }

  @override
  String get newDirectPreview => 'A new direct chat has started';

  @override
  String maxFiles(int count) {
    return 'You can send up to $count files at once.';
  }

  @override
  String get mediaPickFailed => 'Couldn’t choose attachments. Try again.';

  @override
  String get imagePickFailed => 'Couldn’t choose an image. Try again.';

  @override
  String get profileImageOnly => 'Only image files can be used for a profile.';

  @override
  String get imageTooLarge => 'Images must be 30 MB or smaller.';

  @override
  String get videoTooLarge => 'Videos must be 500 MB or smaller.';

  @override
  String get fileTooLarge => 'Files must be 1 GB or smaller.';

  @override
  String get unsupportedMedia => 'This attachment format isn’t supported.';

  @override
  String get unusableFile => 'The selected file can’t be used.';
}
