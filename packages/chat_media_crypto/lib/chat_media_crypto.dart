/// Client-side, chunked attachment encryption.
///
/// This package defines an attachment cipher format. It does **not** implement
/// identity authentication, key agreement, a ratchet, MLS, or messaging E2EE.
/// The caller must deliver [AttachmentFileKey] and
/// [AttachmentEncryptionManifest] inside an independently authenticated E2EE
/// message. Neither value belongs in a homeserver media descriptor.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chat_media/chat_media.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

part 'src/aad_codec.dart';
part 'src/attachment_cipher.dart';
part 'src/attachment_context.dart';
part 'src/attachment_exception.dart';
part 'src/attachment_key.dart';
part 'src/attachment_manifest.dart';
part 'src/attachment_staging.dart';
part 'src/ciphertext_chunk.dart';
