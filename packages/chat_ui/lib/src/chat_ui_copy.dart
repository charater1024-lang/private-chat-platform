import 'package:flutter/widgets.dart';

import 'media_types.dart';

/// Small locale-aware fallback copy for shared accessibility semantics.
///
/// Product-visible copy still belongs in each app's ARB catalog. These strings
/// cover defaults owned by shared widgets so a Korean app never falls back to
/// English screen-reader output. English is used for every non-Korean locale.
final class ChatUiCopy {
  const ChatUiCopy._(this.isKorean);

  factory ChatUiCopy.of(BuildContext context) {
    return ChatUiCopy._(
      Localizations.maybeLocaleOf(context)?.languageCode == 'ko',
    );
  }

  final bool isKorean;

  String get image => isKorean ? '이미지' : 'Image';
  String get video => isKorean ? '동영상' : 'Video';
  String get file => isKorean ? '파일' : 'File';
  String get removeAttachment => isKorean ? '첨부 파일 제거' : 'Remove attachment';
  String get sending => isKorean ? '전송 중' : 'Sending';
  String get failedToSend => isKorean ? '전송 실패' : 'Failed to send';
  String get ownMessage => isKorean ? '내 메시지' : 'Me';
  String get message => isKorean ? '메시지' : 'Message';

  String attachment({
    required ChatMediaKind kind,
    required String fileName,
    required String sizeLabel,
  }) {
    final kindLabel = mediaKindLabel(kind);
    return isKorean
        ? '$kindLabel 첨부. $fileName. $sizeLabel'
        : '$kindLabel attachment. $fileName. $sizeLabel';
  }

  String mediaKindLabel(ChatMediaKind kind) => switch (kind) {
    ChatMediaKind.image => image,
    ChatMediaKind.video => video,
    ChatMediaKind.file => file,
  };

  String attachmentsReady(int count) {
    return isKorean
        ? '$count개의 첨부 파일 전송 준비됨'
        : '$count attachments ready to send';
  }

  String profile(String displayName, String status) {
    return isKorean
        ? '$displayName의 프로필. $status'
        : 'Profile for $displayName. $status';
  }

  String avatar(String label, {required bool isOnline}) {
    if (isKorean) {
      return '$label 아바타${isOnline ? ', 온라인' : ''}';
    }
    return '$label avatar${isOnline ? ', online' : ''}';
  }
}
