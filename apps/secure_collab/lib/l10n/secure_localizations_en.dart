// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'secure_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SecureLocalizationsEn extends SecureLocalizations {
  SecureLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Secure Collab';

  @override
  String get search => 'Search';

  @override
  String get channelInfo => 'Channel information';

  @override
  String get homeserverStatusTitle => 'Personal homeserver connection';

  @override
  String homeserverName(Object name) {
    return 'Homeserver: $name';
  }

  @override
  String get httpsPending => 'HTTPS: Not connected · Certificate check pending';

  @override
  String get closedFederation => 'Personal server · Federation off';

  @override
  String get memberOnlyEncryptionMode =>
      'Design target: TRUE_E2EE · Keys stay on member devices · Not verified';

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
  String get deliveryFailed => 'Failed to send';

  @override
  String profileEditTooltip(Object name) {
    return 'Edit $name’s work profile';
  }

  @override
  String get navConversations => 'Chats';

  @override
  String get navTasks => 'Tasks';

  @override
  String get navActivity => 'Activity';

  @override
  String get navProfile => 'Profile';

  @override
  String get addItemTitle => 'Add an item';

  @override
  String get mediaActionTitle => 'Photos, videos, and files';

  @override
  String get mediaActionSubtitle =>
      'Choose attachments to encrypt on this device';

  @override
  String get stickersActionTitle => 'Character stickers';

  @override
  String get stickersActionSubtitle =>
      'Send animated Korean expressions from six characters';

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
  String get maxAttachments => 'You can send up to 30 attachments at once.';

  @override
  String get fileOpenFailed => 'Couldn’t open the file. Try again.';

  @override
  String get imageTooLarge => 'Each image must be 30 MB or smaller.';

  @override
  String get videoTooLarge => 'Each video must be 500 MB or smaller.';

  @override
  String get genericFileTooLarge =>
      'Each general file must be 1 GB or smaller.';

  @override
  String get mediaNotAllowed =>
      'This image, video, or file format isn’t supported.';

  @override
  String get attachmentPolicyMismatch =>
      'The selected attachment exceeds the app’s safety limits.';

  @override
  String get profileSaved => 'Work profile saved.';

  @override
  String get timeNow => 'Just now';

  @override
  String channelStart(Object name) {
    return 'Start of #$name';
  }

  @override
  String get addWorkspace => 'Add workspace';

  @override
  String get newMessage => 'New message';

  @override
  String get workspaceSearch => 'Search workspace';

  @override
  String get channels => 'Channels';

  @override
  String get directMessages => 'Direct messages & groups';

  @override
  String get newDirectMessage => 'New direct or group chat';

  @override
  String get memberCanCreate =>
      'Regular member · ACTIVE · Can create chats without owner approval';

  @override
  String get newDirectDialogTitle => 'Start a member conversation';

  @override
  String get newDirectDialogInstruction =>
      'Select ACTIVE members of this homeserver. Choose one for a direct chat or two or more for a group chat.';

  @override
  String get selectMembers => 'Choose members';

  @override
  String get oneMemberSelected => '1 selected · Direct chat';

  @override
  String manyMembersSelected(int count) {
    return '$count selected · Group chat';
  }

  @override
  String get activeMember => 'ACTIVE regular member';

  @override
  String get groupConversationName => 'Group chat name (optional)';

  @override
  String groupConversationDefault(Object names) {
    return '$names group';
  }

  @override
  String get groupConversationHelper =>
      'Leave blank to use the selected members’ names.';

  @override
  String get cancel => 'Cancel';

  @override
  String get createConversation => 'Create chat';

  @override
  String get directConversationCreated =>
      'Direct chat created without owner approval.';

  @override
  String get groupConversationCreated =>
      'Group chat created without owner approval.';

  @override
  String directConversationStart(Object name) {
    return 'Start of the $name conversation';
  }

  @override
  String groupConversationStart(Object name) {
    return 'Start of the $name group conversation';
  }

  @override
  String directMessageHint(Object name) {
    return 'Message $name';
  }

  @override
  String groupMessageHint(Object name) {
    return 'Message the $name group';
  }

  @override
  String get directConversationPurpose =>
      'A private chat for registered members of this homeserver';

  @override
  String get groupConversationPurpose =>
      'A private group chat for registered members of this homeserver';

  @override
  String get privacySecurityActive =>
      'Personal homeserver · TRUE_E2EE design · Local simulation';

  @override
  String get channelPurpose =>
      'A record of Aurora launch preparation and decisions';

  @override
  String get startHuddle => 'Start huddle';

  @override
  String trueE2eeBanner(Object version) {
    return 'TRUE_E2EE design target · Keys stay on member devices · Crypto and server not connected · v$version';
  }

  @override
  String trueE2eeTransportBanner(Object version) {
    return 'TRUE_E2EE crypto adapter and durable sync path configured · External security review required · v$version';
  }

  @override
  String get viewSecurityDetails => 'View security design';

  @override
  String get reply => 'Reply';

  @override
  String get taskCardTitle => 'Pre-launch security review';

  @override
  String get inProgress => 'In progress';

  @override
  String get taskCardProgress => '6 of 8 complete · Review today at 4 PM';

  @override
  String get removeAttachment => 'Remove attachment';

  @override
  String attachmentDescriptionLabel(Object fileName) {
    return 'Accessibility description for $fileName';
  }

  @override
  String get attachmentDescriptionHint => 'Describe the attachment (optional)';

  @override
  String get genericFileLabel => 'General file';

  @override
  String messageChannelHint(Object channelName) {
    return 'Message #$channelName';
  }

  @override
  String get attachmentPolicySummary =>
      'Local safety limits · Images up to 30 MB · Videos up to 500 MB · General files up to 1 GB · Up to 30 attachments';

  @override
  String get addMenu => 'Add menu';

  @override
  String get createTask => 'Create task';

  @override
  String get send => 'Send';

  @override
  String get members => 'Members';

  @override
  String get membersDetail => '24 members · No external guests';

  @override
  String get sharedFiles => 'Shared files';

  @override
  String get sharedFilesDetail => '18 in the last 30 days';

  @override
  String get pinnedItems => 'Pinned items';

  @override
  String get pinnedItemsDetail => '4 decisions';

  @override
  String get securityStatus => 'Security status';

  @override
  String get memberKeyCustodyStatus =>
      'Design target: Conversation keys stay on member devices · Not verified';

  @override
  String get encryptedAttachmentStatus =>
      'Design target: End-to-end encrypted images, videos, and files · Transfer not connected';

  @override
  String get homeserverBlindStatus =>
      'The personal homeserver is designed to hold no message keys';

  @override
  String get integrityAnchorStatus =>
      'Design target: Content-free integrity anchor · Blockchain not connected';

  @override
  String accessibilityDescription(Object description) {
    return 'Accessibility description: $description';
  }

  @override
  String get profileEditorClose => 'Close profile editor';

  @override
  String get profileEditorTitle => 'Edit work profile';

  @override
  String get save => 'Save';

  @override
  String get unnamed => 'Unnamed';

  @override
  String get profileImagePolicyError =>
      'The image format isn’t supported or exceeds 30 MB.';

  @override
  String get profileImageOnly => 'Only images can be selected for a profile.';

  @override
  String get profileImageOpenFailed => 'Couldn’t open the image. Try again.';

  @override
  String get profileNameRequired => 'Enter a display name.';

  @override
  String get profilePhotoSelect => 'Choose profile photo';

  @override
  String get coverImageSelect => 'Choose cover image';

  @override
  String get profileLocalNotice =>
      'Manage your name, title, and team directly in this device profile.';

  @override
  String get name => 'Name';

  @override
  String get jobTitle => 'Job title';

  @override
  String get team => 'Team';

  @override
  String get statusMessage => 'Status message';

  @override
  String get timezone => 'Time zone';

  @override
  String get timezoneHint => 'Example: Seoul · UTC+9';

  @override
  String get profileTheme => 'Profile theme';

  @override
  String get profileThemeDescription =>
      'Calm colors designed for the work interface.';

  @override
  String profileThemeSemantics(int number) {
    return 'Calm theme color $number';
  }

  @override
  String get localEditAvailable => 'Edit on this device';
}
