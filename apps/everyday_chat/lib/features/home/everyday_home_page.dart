import 'dart:async';
import 'dart:io';

import 'package:chat_core/chat_core_preview.dart'
    show InMemoryHomeserverRepository;
import 'package:chat_core/privacy_chat_core.dart';
import 'package:chat_media/chat_media.dart';
import 'package:chat_sync/chat_sync.dart' show ClientMessageId;
import 'package:chat_ui/chat_ui.dart';
import 'package:flutter/material.dart';
import 'package:homeserver_client/homeserver_client.dart';

import '../../l10n/everyday_localizations.dart';

const _desktopBreakpoint = 900.0;
const _mediaDescriptionLimit = 120;

class EverydayHomePage extends StatefulWidget {
  const EverydayHomePage({
    required this.mediaPicker,
    this.messageSync,
    super.key,
  });

  final MediaPickerPort mediaPicker;
  final HomeserverMessageSync? messageSync;

  @override
  State<EverydayHomePage> createState() => _EverydayHomePageState();
}

class _EverydayHomePageState extends State<EverydayHomePage> {
  EverydayLocalizations get _l10n => EverydayLocalizations.of(context);

  static const _currentMemberId = 'member-minseo';
  final _domain = SecurityDomain(
    id: 'consumer.everyday.v1',
    mode: SecurityMode.trueE2ee,
    policyVersion: '1.0',
  );
  final _mediaPolicy = MediaPolicies.consumer;
  late final HomeserverDescriptor _homeserver;
  late final ServerConnectionProfile _connectionProfile;
  late final InMemoryHomeserverRepository _homeserverRepository;
  final _searchController = TextEditingController();
  final _messageScrollController = ScrollController();
  final _displayNameController = TextEditingController(text: '민서');
  final _profileStatusController = TextEditingController(
    text: '천천히, 오래 대화해요 🌿',
  );

  int _tabIndex = 1;
  // The initial desktop conversation is one-to-one; group rooms remain opt-in.
  int _selectedChat = 1;
  int _attachmentSequence = 0;
  int _conversationSequence = 0;
  int _localMessageSequence = 0;
  bool _showConversationOnPhone = false;
  bool _isPicking = false;
  HomeserverSyncPresentation _syncPresentation =
      const HomeserverSyncPresentation.unconfigured();
  StreamSubscription<HomeserverSyncPresentation>? _syncSubscription;
  StreamSubscription<HomeserverMessageDeliveryUpdate>? _deliverySubscription;
  int _syncSubscriptionGeneration = 0;
  final Map<(String, ClientMessageId), String> _localMessageIdsByDelivery = {};
  Color _profileAccent = _profileColors.first;
  LocalMediaSelection? _profilePhoto;
  LocalMediaSelection? _profileBackground;
  final Map<String, _ConversationDraft> _draftsByConversation = {};

  static const _profileColors = <Color>[
    Color(0xFF456800),
    Color(0xFF6D3DB4),
    Color(0xFF8B65C8),
    Color(0xFF718F24),
  ];

  final List<_Conversation> _conversations = [
    const _Conversation(
      id: 'family',
      title: '우리 가족',
      preview: '오늘 저녁 7시에 만나요 😊',
      time: '오후 2:18',
      unread: 2,
      color: Color(0xFFD9FFA2),
      online: true,
      isGroup: true,
      participantCount: 4,
    ),
    const _Conversation(
      id: 'seojun',
      title: '서준',
      preview: '사진 3장을 보냈어요',
      time: '오후 1:04',
      color: Color(0xFFE1CDFF),
      online: true,
    ),
    const _Conversation(
      id: 'weekend-walk',
      title: '주말 산책 모임',
      preview: '민지: 이번 주는 서울숲 어때요?',
      time: '어제',
      unread: 8,
      color: Color(0xFFC8E98A),
      isGroup: true,
      participantCount: 6,
    ),
    const _Conversation(
      id: 'jiwoo',
      title: '지우',
      preview: '응, 확인했어!',
      time: '화요일',
      color: Color(0xFFBDA2E8),
      muted: true,
    ),
  ];

  final Map<String, List<_LocalMessage>> _messagesByConversation = {
    'family': [
      const _LocalMessage(
        text: '오늘 저녁 다 같이 먹을까요?',
        time: '오후 2:14',
        author: '엄마',
      ),
      const _LocalMessage(
        text: '좋아요! 퇴근하고 바로 갈게요.',
        time: '오후 2:16',
        mine: true,
      ),
      const _LocalMessage(
        text: '오늘 저녁 7시에 만나요 😊',
        time: '오후 2:18',
        author: '엄마',
      ),
    ],
  };

  static const _friends = <_Friend>[
    _Friend(id: 'minji', name: '민지', color: Color(0xFFB8D97A)),
    _Friend(id: 'doyun', name: '도윤', color: Color(0xFF9D83D4)),
    _Friend(id: 'yuna', name: '유나', color: Color(0xFFB8A4E3)),
    _Friend(id: 'hyeonwoo', name: '현우', color: Color(0xFFA8D88A)),
  ];

  @override
  void initState() {
    super.initState();
    assert(_domain.mode == SecurityMode.trueE2ee);
    _homeserver = HomeserverDescriptor(
      serverId: 'greenhouse-home',
      ownerId: 'member-owner',
      deploymentPolicy: HomeserverDeploymentPolicy.privacyConsumer,
      securityDomain: _domain,
      capabilities: HomeserverCapabilities.privacyDefaults(),
    );
    _connectionProfile = ServerConnectionProfile(
      profileId: 'everyday-local-preview',
      serverId: _homeserver.serverId,
      productKind: ProductKind.consumer,
      endpoint: Uri.parse('https://family.greenhouse.invalid'),
      memberId: _currentMemberId,
      credentialReference: CredentialReference('os-keychain:everyday-preview'),
      tlsPeerPolicy: const TlsPeerPolicy.platformTrust(),
    );
    final joinedAt = DateTime.utc(2026, 9, 1);
    final owner = ServerMember.owner(
      memberId: _homeserver.ownerId,
      handle: '@owner:greenhouse',
      displayName: '홈서버 소유자',
      joinedAt: joinedAt,
    );
    _homeserverRepository = InMemoryHomeserverRepository.bootstrap(
      descriptor: _homeserver,
      owner: owner,
    );
    const members = <(String, String, String)>[
      (_currentMemberId, '@minseo:greenhouse', '민서'),
      ('minji', '@minji:greenhouse', '민지'),
      ('doyun', '@doyun:greenhouse', '도윤'),
      ('yuna', '@yuna:greenhouse', '유나'),
      ('hyeonwoo', '@hyeonwoo:greenhouse', '현우'),
    ];
    for (final (memberId, handle, displayName) in members) {
      final invitationProof = _localPreviewInvitationProof(memberId);
      _homeserverRepository.inviteMember(
        requestedBy: owner.memberId,
        memberId: memberId,
        handle: handle,
        displayName: displayName,
        role: MemberRole.member,
        invitedAt: joinedAt,
        inviteExpiresAt: joinedAt.add(const Duration(days: 7)),
        invitationProofDigest: InvitationProofDigest.fromProof(invitationProof),
      );
      _homeserverRepository.acceptInvitation(
        memberId: memberId,
        acceptedAt: joinedAt.add(const Duration(minutes: 1)),
        invitationProof: invitationProof,
      );
    }
    _listenToMessageSync();
    unawaited(_synchronizeSelectedConversation());
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant EverydayHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.messageSync, widget.messageSync)) return;
    unawaited(_syncSubscription?.cancel());
    unawaited(_deliverySubscription?.cancel());
    _localMessageIdsByDelivery.clear();
    _listenToMessageSync();
    unawaited(_synchronizeSelectedConversation());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    for (final draft in _draftsByConversation.values) {
      draft.dispose();
    }
    _displayNameController.dispose();
    _profileStatusController.dispose();
    _messageScrollController.dispose();
    _syncSubscriptionGeneration += 1;
    unawaited(_syncSubscription?.cancel());
    unawaited(_deliverySubscription?.cancel());
    _localMessageIdsByDelivery.clear();
    super.dispose();
  }

  void _listenToMessageSync() {
    final generation = ++_syncSubscriptionGeneration;
    final sync = widget.messageSync;
    _syncPresentation =
        sync?.presentation ?? const HomeserverSyncPresentation.unconfigured();
    _syncSubscription = sync?.presentations.listen((presentation) {
      if (!mounted || generation != _syncSubscriptionGeneration) return;
      setState(() => _syncPresentation = presentation);
    });
    _deliverySubscription = sync?.deliveryUpdates.listen((update) {
      if (!mounted || generation != _syncSubscriptionGeneration) return;
      _applyDeliveryUpdate(update);
    });
  }

  void _applyDeliveryUpdate(HomeserverMessageDeliveryUpdate update) {
    final key = (update.localConversationId, update.clientMessageId);
    final localMessageId = _localMessageIdsByDelivery[key];
    if (localMessageId == null) return;
    final messages = _messagesByConversation[update.localConversationId];
    final messageIndex = messages?.indexWhere(
      (message) => message.localId == localMessageId,
    );
    if (messages == null || messageIndex == null || messageIndex < 0) return;
    setState(() {
      messages[messageIndex] = messages[messageIndex].copyWith(
        deliveryState: update.deliveryState,
      );
    });
    if (update.deliveryState == HomeserverMessageDeliveryState.acknowledged ||
        update.deliveryState == HomeserverMessageDeliveryState.failed) {
      _localMessageIdsByDelivery.remove(key);
    }
  }

  Future<void> _synchronizeSelectedConversation() async {
    final sync = widget.messageSync;
    if (sync == null) return;
    final conversationId = _selectedConversationId;
    await sync.synchronize(conversationId);
  }

  void _onSearchChanged() => setState(() {});

  Iterable<MapEntry<int, _Conversation>> get _filteredConversations {
    final query = _searchController.text.trim().toLowerCase();
    return _conversations.asMap().entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.value.title.toLowerCase().contains(query) ||
          entry.value.preview.toLowerCase().contains(query);
    });
  }

  void _selectChat(int index, bool isDesktop) {
    setState(() {
      _selectedChat = index;
      _showConversationOnPhone = !isDesktop;
    });
    unawaited(_synchronizeSelectedConversation());
  }

  List<_LocalMessage> get _messages {
    final conversationId = _conversations[_selectedChat].id;
    return _messagesByConversation.putIfAbsent(conversationId, () => []);
  }

  String get _selectedConversationId => _conversations[_selectedChat].id;

  _ConversationDraft _draftFor(String conversationId) =>
      _draftsByConversation.putIfAbsent(conversationId, _ConversationDraft.new);

  _ConversationDraft get _selectedDraft => _draftFor(_selectedConversationId);

  Future<void> _showNewConversation({required bool isDesktop}) async {
    final currentMember = _homeserverRepository.memberById(
      requestedBy: _currentMemberId,
      memberId: _currentMemberId,
    );
    assert(currentMember.memberId == _currentMemberId);
    final activeMemberIds = _homeserverRepository
        .listDirectory(requestedBy: _currentMemberId)
        .map((member) => member.memberId)
        .toSet();
    final registeredFriends = _friends
        .where((friend) => activeMemberIds.contains(friend.id))
        .toList(growable: false);
    final draft = await showDialog<_NewConversationDraft>(
      context: context,
      builder: (context) => _NewConversationDialog(friends: registeredFriends),
    );
    if (!mounted || draft == null) return;

    _conversationSequence += 1;
    final conversationId = 'local-conversation-$_conversationSequence';
    final isGroup = draft.participants.length > 1;
    final created = _homeserverRepository.createConversation(
      ConversationRequest(
        conversationId: conversationId,
        creatorId: _currentMemberId,
        kind: isGroup
            ? HomeserverConversationKind.group
            : HomeserverConversationKind.direct,
        participantIds: {
          _currentMemberId,
          ...draft.participants.map((friend) => friend.id),
        },
        title: isGroup ? draft.title : null,
      ),
      createdAt: DateTime.now().toUtc(),
    );
    assert(created.creatorId == _currentMemberId);
    final conversation = _Conversation(
      id: conversationId,
      title: draft.title,
      preview: isGroup
          ? _l10n.newGroupPreview(draft.participants.length + 1)
          : _l10n.newDirectPreview,
      time: _l10n.timeNow,
      color: draft.participants.first.color,
      online: !isGroup,
      isGroup: isGroup,
      participantCount: draft.participants.length + 1,
    );

    _searchController.clear();
    setState(() {
      _conversations.insert(0, conversation);
      _messagesByConversation[conversationId] = [];
      _draftsByConversation[conversationId] = _ConversationDraft();
      _selectedChat = 0;
      _showConversationOnPhone = !isDesktop;
    });
    unawaited(_synchronizeSelectedConversation());
  }

  Future<void> _pickMessageMedia() async {
    if (_isPicking) return;
    final conversationId = _selectedConversationId;
    final draft = _draftFor(conversationId);
    final remaining = _mediaPolicy.maxFiles - draft.attachments.length;
    if (remaining <= 0) {
      _showFeedback(_l10n.maxFiles(_mediaPolicy.maxFiles));
      return;
    }

    setState(() => _isPicking = true);
    try {
      final selected = await widget.mediaPicker.pick(
        MediaPickRequest(
          kinds: const {MediaKind.image, MediaKind.video, MediaKind.file},
          maxSelections: remaining,
        ),
      );
      if (!mounted || selected.isEmpty) return;

      final candidate = [
        ...draft.attachments.map((item) => item.selection),
        ...selected,
      ];
      final validation = _mediaPolicy.validate(candidate);
      if (validation.isInvalid) {
        _showFeedback(_validationMessage(validation.issues.first));
        return;
      }

      final additions = selected.map((selection) {
        _attachmentSequence += 1;
        return PendingAttachment.queued(
          id: 'consumer-media-$_attachmentSequence',
          selection: selection,
        ).markReady();
      });
      setState(() {
        draft.attachments = [...draft.attachments, ...additions];
      });
    } on Exception {
      if (mounted) _showFeedback(_l10n.mediaPickFailed);
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _pickProfileAsset({required bool background}) async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final selected = await widget.mediaPicker.pick(
        MediaPickRequest(kinds: const {MediaKind.image}, maxSelections: 1),
      );
      if (!mounted || selected.isEmpty) return;

      final asset = selected.first;
      final validation = _mediaPolicy.validate([asset]);
      if (asset.kind != MediaKind.image || validation.isInvalid) {
        final message = validation.isInvalid
            ? _validationMessage(validation.issues.first)
            : _l10n.profileImageOnly;
        _showFeedback(message);
        return;
      }

      setState(() {
        if (background) {
          _profileBackground = asset;
        } else {
          _profilePhoto = asset;
        }
      });
    } on Exception {
      if (mounted) _showFeedback(_l10n.imagePickFailed);
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removeAttachment(PendingAttachment attachment) {
    final draft = _selectedDraft;
    setState(() {
      draft.attachments = draft.attachments
          .where((item) => item.id != attachment.id)
          .toList(growable: false);
      if (draft.attachments.isEmpty) draft.mediaDescriptionController.clear();
    });
  }

  Future<void> _sendMessage() async {
    final conversationId = _selectedConversationId;
    final draft = _selectedDraft;
    final text = draft.messageController.text.trim();
    if (text.isEmpty && draft.attachments.isEmpty) return;

    final description = draft.mediaDescriptionController.text.trim();
    final media = draft.attachments
        .map(
          (item) =>
              _LocalMedia(selection: item.selection, description: description),
        )
        .toList(growable: false);
    _localMessageSequence += 1;
    final localMessageId = 'everyday-local-message-$_localMessageSequence';
    final sync = widget.messageSync;
    final syncConfigured =
        text.isNotEmpty && (sync?.isConfigured(conversationId) ?? false);

    setState(() {
      _messages.add(
        _LocalMessage(
          localId: localMessageId,
          text: text,
          time: _l10n.timeNow,
          mine: true,
          media: media,
          deliveryState: syncConfigured
              ? HomeserverMessageDeliveryState.queued
              : HomeserverMessageDeliveryState.localOnly,
        ),
      );
      draft.clear();
    });
    _scrollToLatest();

    if (!syncConfigured || sync == null) return;
    HomeserverMessageDeliveryState deliveryState;
    try {
      final result = await sync.sendText(
        localConversationId: conversationId,
        plaintext: text,
      );
      deliveryState = result.deliveryState;
      final clientMessageId = result.clientMessageId;
      if (clientMessageId != null &&
          deliveryState != HomeserverMessageDeliveryState.acknowledged &&
          deliveryState != HomeserverMessageDeliveryState.failed) {
        _localMessageIdsByDelivery[(conversationId, clientMessageId)] =
            localMessageId;
      }
    } on Object {
      deliveryState = HomeserverMessageDeliveryState.failed;
    }
    if (!mounted) return;
    final messages = _messagesByConversation[conversationId];
    final messageIndex = messages?.indexWhere(
      (message) => message.localId == localMessageId,
    );
    if (messages == null || messageIndex == null || messageIndex < 0) return;
    setState(() {
      messages[messageIndex] = messages[messageIndex].copyWith(
        deliveryState: deliveryState,
      );
    });
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_messageScrollController.hasClients) return;
      _messageScrollController.animateTo(
        _messageScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _showComposerActions() async {
    if (_isPicking) return;

    final action = await showModalBottomSheet<_ComposerAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Column(
                key: const ValueKey('everyday-composer-action-sheet'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(
                      _l10n.chooseItemTitle,
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  ListTile(
                    key: const ValueKey('everyday-action-media'),
                    leading: const Icon(Icons.attach_file_outlined),
                    title: Text(_l10n.mediaActionTitle),
                    subtitle: Text(_l10n.mediaActionSubtitle),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ComposerAction.media),
                  ),
                  ListTile(
                    key: const ValueKey('everyday-action-animated-sticker'),
                    leading: const Icon(Icons.emoji_emotions_outlined),
                    title: Text(_l10n.stickersActionTitle),
                    subtitle: Text(_l10n.stickersActionSubtitle),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    onTap: () =>
                        Navigator.of(sheetContext)
                            .pop(_ComposerAction.animatedSticker),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _ComposerAction.media:
        await _pickMessageMedia();
      case _ComposerAction.animatedSticker:
        await _showStickerPicker();
    }
  }

  Future<void> _showStickerPicker() async {
    final sticker = await showModalBottomSheet<AnimatedStickerDefinition>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .72,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _l10n.stickersActionTitle,
                          style: Theme.of(sheetContext).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: _l10n.stickerPickerClose,
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    _l10n.stickerPickerInstruction,
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: AnimatedStickerPicker(
                    key: const ValueKey('everyday-sticker-picker'),
                    stickers: signatureAnimatedStickerPack,
                    characterLabels: _stickerCharacterLabels(_l10n),
                    emptyLabel: _l10n.stickerEmpty,
                    previousPageTooltip: _l10n.stickerPreviousPage,
                    nextPageTooltip: _l10n.stickerNextPage,
                    pageSemanticLabelBuilder: _l10n.stickerPageSemantics,
                    semanticLabelBuilder: (sticker) =>
                        _stickerLabel(_l10n, sticker),
                    maximumTileExtent: 96,
                    assetPackage: 'chat_ui',
                    onStickerSelected: (selected) =>
                        Navigator.of(sheetContext).pop(selected),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || sticker == null) return;

    setState(() {
      _messages.add(
        _LocalMessage(
          text: '',
          time: _l10n.timeNow,
          mine: true,
          sticker: sticker,
          deliveryState: HomeserverMessageDeliveryState.localOnly,
        ),
      );
    });
  }

  void _saveProfile() {
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      _showFeedback(_l10n.profileNameRequired);
      return;
    }
    _displayNameController.text = displayName;
    _profileStatusController.text = _profileStatusController.text.trim();
    setState(() {});
    _showFeedback(_l10n.profileSaved);
  }

  void _showFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _validationMessage(MediaValidationIssue issue) {
    return switch (issue.code) {
      MediaValidationCode.tooManyFiles => _l10n.maxFiles(_mediaPolicy.maxFiles),
      MediaValidationCode.imageTooLarge => _l10n.imageTooLarge,
      MediaValidationCode.videoTooLarge => _l10n.videoTooLarge,
      MediaValidationCode.fileTooLarge => _l10n.fileTooLarge,
      MediaValidationCode.mimeTypeNotAllowed ||
      MediaValidationCode.kindMimeMismatch => _l10n.unsupportedMedia,
      _ => _l10n.unusableFile,
    };
  }

  String get _syncStatusLabel => switch (_syncPresentation.connectionStatus) {
    HomeserverConnectionStatus.unconfigured => _l10n.prototypeConnectionPending,
    HomeserverConnectionStatus.disconnected => _l10n.syncDisconnected,
    HomeserverConnectionStatus.connecting => _l10n.syncConnecting,
    HomeserverConnectionStatus.connected => _l10n.syncConnected(
      _syncPresentation.queuedCount,
    ),
    HomeserverConnectionStatus.backingOff => _l10n.syncBackingOff(
      _syncPresentation.queuedCount,
    ),
    HomeserverConnectionStatus.blocked => _l10n.syncBlocked,
    HomeserverConnectionStatus.failed => _l10n.syncFailed,
    HomeserverConnectionStatus.stopped => _l10n.syncStopped,
  };

  String? _deliveryLabel(_LocalMessage message) {
    if (!message.mine) return null;
    return switch (message.deliveryState) {
      HomeserverMessageDeliveryState.localOnly => _l10n.deliveryLocalOnly,
      HomeserverMessageDeliveryState.queued => _l10n.deliveryQueued,
      HomeserverMessageDeliveryState.acknowledged => _l10n.deliveryAcknowledged,
      HomeserverMessageDeliveryState.retryScheduled =>
        _l10n.deliveryRetryScheduled,
      HomeserverMessageDeliveryState.blocked => _l10n.deliveryBlocked,
      HomeserverMessageDeliveryState.failed => _l10n.sendFailed,
      null => _l10n.sent,
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
        if (isDesktop) return _buildDesktop(context);
        return _buildPhone(context);
      },
    );
  }

  Widget _buildDesktop(BuildContext context) {
    if (_tabIndex == 3) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _EverydayRail(
                selectedIndex: _tabIndex,
                onSelected: (index) => setState(() => _tabIndex = index),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _buildProfileEditor()),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _EverydayRail(
              selectedIndex: _tabIndex,
              onSelected: (index) => setState(() => _tabIndex = index),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 350,
              child: _tabIndex == 1
                  ? _buildConversationList(isDesktop: true)
                  : _EverydayPlaceholder(index: _tabIndex),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _tabIndex == 1
                  ? _buildConversation()
                  : const _WelcomePanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhone(BuildContext context) {
    if (_showConversationOnPhone && _tabIndex == 1) {
      return Scaffold(
        body: SafeArea(child: _buildConversation(showBackButton: true)),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: switch (_tabIndex) {
          1 => _buildConversationList(isDesktop: false),
          3 => _buildProfileEditor(),
          _ => _EverydayPlaceholder(index: _tabIndex),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            label: _l10n.navFriends,
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            label: _l10n.navChats,
          ),
          NavigationDestination(
            icon: const Icon(Icons.call_outlined),
            label: _l10n.navCalls,
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            label: _l10n.navMore,
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList({required bool isDesktop}) {
    final scheme = Theme.of(context).colorScheme;
    final entries = _filteredConversations.toList(growable: false);
    return ColoredBox(
      color: scheme.surface,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _l10n.brandTitle,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _l10n.brandTagline,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('new-conversation-button'),
                    tooltip: _l10n.newChat,
                    onPressed: () => _showNewConversation(isDesktop: isDesktop),
                    icon: const Icon(Icons.add_comment_outlined),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _l10n.searchChats,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 5, 18, 10),
              child: StatusPill(
                label: _l10n.trueE2ee,
                icon: Icons.lock_outline,
                color: scheme.primary,
                compact: true,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _HomeserverStatusPanel(
                title: _l10n.homeserverStatusTitle,
                labels: [
                  _l10n.homeserverName(
                    _syncPresentation.serverHost ??
                        _connectionProfile.endpoint.host,
                  ),
                  if (_syncPresentation.connectionStatus ==
                      HomeserverConnectionStatus.unconfigured)
                    _l10n.httpsPending
                  else
                    _l10n.transportVerificationActive,
                  _l10n.closedFederation,
                  _l10n.privacyEncryptionMode,
                  _syncStatusLabel,
                  _l10n.activeMemberCanCreate,
                ],
              ),
            ),
          ),
          if (entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(_l10n.noSearchResults)),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, visibleIndex) {
                final entry = entries[visibleIndex];
                final conversation = entry.value;
                return ConversationTile(
                  key: ValueKey('conversation-${entry.key}'),
                  title: conversation.title,
                  subtitle: conversation.preview,
                  timeLabel: conversation.time,
                  avatarColor: conversation.color,
                  unreadCount: conversation.unread,
                  isOnline: conversation.online,
                  muted: conversation.muted,
                  selected: isDesktop && _selectedChat == entry.key,
                  onTap: () => _selectChat(entry.key, isDesktop),
                );
              }, childCount: entries.length),
            ),
        ],
      ),
    );
  }

  Widget _buildConversation({bool showBackButton = false}) {
    final conversation = _conversations[_selectedChat];
    final draft = _draftFor(conversation.id);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                if (showBackButton)
                  IconButton(
                    tooltip: _l10n.conversationList,
                    onPressed: () =>
                        setState(() => _showConversationOnPhone = false),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ChatAvatar(
                  label: conversation.title,
                  backgroundColor: conversation.color,
                  radius: 21,
                  isOnline: conversation.online,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        conversation.isGroup
                            ? _l10n.groupConversationPrivacy(
                                conversation.participantCount,
                              )
                            : _l10n.directConversationPrivacy,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _l10n.voiceCall,
                  onPressed: () {},
                  icon: const Icon(Icons.call_outlined),
                ),
                IconButton(
                  tooltip: _l10n.conversationInfo,
                  onPressed: () {},
                  icon: const Icon(Icons.info_outline),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF4FBE8), Color(0xFFF7F1FF)],
              ),
            ),
            child: ListView.builder(
              controller: _messageScrollController,
              padding: const EdgeInsets.symmetric(vertical: 18),
              itemCount: _messages.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: StatusPill(
                        label: _l10n.conversationEncrypted,
                        icon: Icons.shield_outlined,
                        color: scheme.primary,
                        compact: true,
                      ),
                    ),
                  );
                }
                final messageIndex = index - 1;
                final message = _messages[messageIndex];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.sticker case final sticker?)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedStickerMessageCard(
                            key: ValueKey(
                              'everyday-sticker-message-$messageIndex',
                            ),
                            sticker: sticker,
                            timeLabel: message.time,
                            isMine: message.mine,
                            assetPackage: 'chat_ui',
                            semanticLabel: _stickerLabel(_l10n, sticker),
                          ),
                          if (message.mine)
                            _LocalOnlyItemStatus(
                              key: ValueKey(
                                'everyday-sticker-delivery-$messageIndex',
                              ),
                              label: _l10n.deliveryLocalOnly,
                            ),
                        ],
                      ),
                    for (
                      var mediaIndex = 0;
                      mediaIndex < message.media.length;
                      mediaIndex += 1
                    )
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MediaMessageCard(
                            key: ValueKey(
                              'everyday-media-message-$messageIndex-$mediaIndex',
                            ),
                            kind: _chatMediaKind(
                              message.media[mediaIndex].selection.kind,
                            ),
                            timeLabel: message.time,
                            isMine: message.mine,
                            thumbnail: _thumbnailFor(
                              message.media[mediaIndex].selection,
                            ),
                            fileName:
                                message.media[mediaIndex].selection.kind ==
                                    MediaKind.file
                                ? message.media[mediaIndex].selection.fileName
                                : null,
                            caption: message.media[mediaIndex].description,
                            sendingLabel: _l10n.sending,
                            failedLabel: _l10n.sendFailed,
                          ),
                          if (message.mine)
                            _LocalOnlyItemStatus(
                              key: ValueKey(
                                'everyday-media-delivery-$messageIndex-$mediaIndex',
                              ),
                              label: _l10n.deliveryLocalOnly,
                            ),
                        ],
                      ),
                    if (message.text.isNotEmpty)
                      MessageBubble(
                        text: message.text,
                        timeLabel: message.time,
                        isMine: message.mine,
                        author: message.author,
                        annotation: _deliveryLabel(message),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        _MessageComposer(
          controller: draft.messageController,
          descriptionController: draft.mediaDescriptionController,
          attachments: draft.attachments,
          isPicking: _isPicking,
          onAdd: _showComposerActions,
          onRemove: _removeAttachment,
          onSend: _sendMessage,
        ),
      ],
    );
  }

  Widget _buildProfileEditor() {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: CustomScrollView(
        key: const ValueKey('everyday-profile-editor'),
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(_l10n.profileCustomize),
            actions: [
              TextButton.icon(
                key: const ValueKey('profile-save-button'),
                onPressed: _saveProfile,
                icon: const Icon(Icons.check_rounded),
                label: Text(_l10n.save),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProfileHero(
                        displayName: _displayNameController.text.trim().isEmpty
                            ? _l10n.unnamed
                            : _displayNameController.text,
                        status: _profileStatusController.text.trim().isEmpty
                            ? _l10n.statusPrompt
                            : _profileStatusController.text,
                        profileImage: _profilePhoto == null
                            ? null
                            : _thumbnailFor(_profilePhoto!),
                        backgroundImage: _profileBackground == null
                            ? null
                            : _thumbnailFor(_profileBackground!),
                        accentColor: _profileAccent,
                        profileEditTooltip: _l10n.profilePhotoSelect,
                        backgroundEditTooltip: _l10n.profileBackgroundSelect,
                        onEditProfilePhoto: _isPicking
                            ? null
                            : () => _pickProfileAsset(background: false),
                        onEditBackground: _isPicking
                            ? null
                            : () => _pickProfileAsset(background: true),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        _l10n.myInfo,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('profile-display-name'),
                        controller: _displayNameController,
                        maxLength: 30,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: _l10n.displayName,
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('profile-status-message'),
                        controller: _profileStatusController,
                        maxLength: 80,
                        maxLines: 2,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: _l10n.statusMessage,
                          prefixIcon: const Icon(Icons.short_text_rounded),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _l10n.profileTheme,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          for (
                            var index = 0;
                            index < _profileColors.length;
                            index += 1
                          )
                            _ProfileColorChoice(
                              key: ValueKey('profile-color-$index'),
                              color: _profileColors[index],
                              label: [
                                _l10n.themeSprout,
                                _l10n.themePurple,
                                _l10n.themeLilac,
                                _l10n.themeOlive,
                              ][index],
                              selected: _profileAccent == _profileColors[index],
                              onSelected: () => setState(
                                () => _profileAccent = _profileColors[index],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Card(
                        color: scheme.primaryContainer.withValues(alpha: .55),
                        child: ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: Text(_l10n.profileLocalPreviewTitle),
                          subtitle: Text(_l10n.profileLocalPreviewSubtitle),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey('profile-save-bottom-button'),
                          onPressed: _saveProfile,
                          icon: const Icon(Icons.check_rounded),
                          label: Text(_l10n.profileSave),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeserverStatusPanel extends StatelessWidget {
  const _HomeserverStatusPanel({required this.title, required this.labels});

  final String title;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '$title. ${labels.join('. ')}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.dns_outlined, size: 17, color: scheme.secondary),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (var index = 0; index < labels.length; index += 1)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        index == 1
                            ? Icons.schedule_outlined
                            : Icons.info_outline,
                        size: 14,
                        color: index == 1 ? scheme.tertiary : scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          labels[index],
                          style: const TextStyle(fontSize: 11, height: 1.25),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalOnlyItemStatus extends StatelessWidget {
  const _LocalOnlyItemStatus({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 24, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smartphone_outlined,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EverydayRail extends StatelessWidget {
  const _EverydayRail({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = EverydayLocalizations.of(context);
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.forum_rounded, color: Colors.white),
          ),
        ),
      ),
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.people_outline),
          label: Text(l10n.navFriends),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text(l10n.navChats),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.call_outlined),
          label: Text(l10n.navCalls),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.grid_view_outlined),
          label: Text(l10n.navMore),
        ),
      ],
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.descriptionController,
    required this.attachments,
    required this.isPicking,
    required this.onAdd,
    required this.onRemove,
    required this.onSend,
  });

  final TextEditingController controller;
  final TextEditingController descriptionController;
  final List<PendingAttachment> attachments;
  final bool isPicking;
  final Future<void> Function() onAdd;
  final ValueChanged<PendingAttachment> onRemove;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = EverydayLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachments.isNotEmpty) ...[
              AttachmentDraftTray(
                items: attachments.map(_draftItem).toList(growable: false),
                onRemove: (item) {
                  final attachment = attachments.firstWhere(
                    (attachment) => attachment.id == item.id,
                  );
                  onRemove(attachment);
                },
                removeTooltip: l10n.removeSelection,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Semantics(
                  textField: true,
                  label: l10n.mediaDescriptionSemantics,
                  child: TextField(
                    key: const ValueKey('media-description-input'),
                    controller: descriptionController,
                    maxLength: _mediaDescriptionLimit,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: l10n.mediaDescriptionLabel,
                      hintText: l10n.mediaDescriptionHint,
                      prefixIcon: const Icon(Icons.accessibility_new_outlined),
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('everyday-attach-button'),
                    tooltip: l10n.composerAddTooltip,
                    onPressed: isPicking ? null : onAdd,
                    icon: isPicking
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_circle_outline),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('everyday-message-input'),
                      controller: controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      decoration: InputDecoration(
                        hintText: l10n.messageHint,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey('everyday-send-button'),
                    tooltip: l10n.send,
                    onPressed: onSend,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  AttachmentDraftItem _draftItem(PendingAttachment attachment) {
    final selection = attachment.selection;
    return AttachmentDraftItem(
      id: attachment.id,
      kind: _chatMediaKind(selection.kind),
      fileName: selection.fileName,
      sizeLabel: _formatBytes(selection.bytes),
      thumbnail: _thumbnailFor(selection),
    );
  }
}

class _ProfileColorChoice extends StatelessWidget {
  const _ProfileColorChoice({
    required this.color,
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = EverydayLocalizations.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: l10n.profileThemeSemantics(label),
      child: Tooltip(
        message: l10n.themeTooltip(label),
        child: InkWell(
          onTap: onSelected,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 3,
              ),
            ),
            child: selected
                ? const Icon(Icons.check_rounded, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}

class _EverydayPlaceholder extends StatelessWidget {
  const _EverydayPlaceholder({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = EverydayLocalizations.of(context);
    final labels = [
      l10n.navFriends,
      l10n.navChats,
      l10n.navCalls,
      l10n.navMore,
    ];
    const icons = [
      Icons.people_outline,
      Icons.chat_bubble_outline,
      Icons.call_outlined,
      Icons.grid_view_outlined,
    ];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icons[index],
            size: 42,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(labels[index], style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(l10n.placeholderDescription),
        ],
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();

  @override
  Widget build(BuildContext context) {
    final l10n = EverydayLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(l10n.appTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(l10n.welcomeHint),
        ],
      ),
    );
  }
}

class _NewConversationDialog extends StatefulWidget {
  const _NewConversationDialog({required this.friends});

  final List<_Friend> friends;

  @override
  State<_NewConversationDialog> createState() => _NewConversationDialogState();
}

class _NewConversationDialogState extends State<_NewConversationDialog> {
  final _groupNameController = TextEditingController();
  final Set<String> _selectedFriendIds = {};

  List<_Friend> get _selectedFriends => widget.friends
      .where((friend) => _selectedFriendIds.contains(friend.id))
      .toList(growable: false);

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  void _toggleFriend(_Friend friend, {required bool selected}) {
    setState(() {
      if (selected) {
        _selectedFriendIds.add(friend.id);
      } else {
        _selectedFriendIds.remove(friend.id);
      }
    });
  }

  void _createConversation() {
    final participants = _selectedFriends;
    if (participants.isEmpty) return;
    final l10n = EverydayLocalizations.of(context);
    final typedGroupName = _groupNameController.text.trim();
    Navigator.of(context).pop(
      _NewConversationDraft(
        participants: participants,
        groupName: participants.length > 1 && typedGroupName.isEmpty
            ? l10n.groupNameDefault(
                participants.map((friend) => friend.name).join(', '),
              )
            : typedGroupName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = EverydayLocalizations.of(context);
    final selectedFriends = _selectedFriends;
    final selectedCount = selectedFriends.length;
    final isGroup = selectedCount > 1;
    final defaultGroupName = isGroup
        ? l10n.groupNameDefault(
            selectedFriends.map((friend) => friend.name).join(', '),
          )
        : '';
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      scrollable: true,
      title: Text(l10n.newConversationTitle),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.newConversationInstruction,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Container(
                key: const ValueKey('new-conversation-type'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      isGroup ? Icons.groups_outlined : Icons.person_outline,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(switch (selectedCount) {
                        0 => l10n.selectFriend,
                        1 => l10n.oneFriendSelected,
                        _ => l10n.manyFriendsSelected(selectedCount),
                      }, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final friend in widget.friends)
              CheckboxListTile(
                key: ValueKey('friend-choice-${friend.id}'),
                value: _selectedFriendIds.contains(friend.id),
                onChanged: (selected) =>
                    _toggleFriend(friend, selected: selected ?? false),
                controlAffinity: ListTileControlAffinity.trailing,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                secondary: CircleAvatar(
                  backgroundColor: friend.color,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(friend.name.characters.first),
                ),
                title: Text(friend.name),
                subtitle: Text(l10n.friend),
              ),
            if (isGroup) ...[
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('new-group-name-input'),
                controller: _groupNameController,
                maxLength: 40,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _createConversation(),
                decoration: InputDecoration(
                  labelText: l10n.groupNameOptional,
                  hintText: defaultGroupName,
                  helperText: l10n.groupNameHelper,
                  prefixIcon: const Icon(Icons.edit_outlined),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          key: const ValueKey('new-conversation-create-button'),
          onPressed: selectedCount == 0 ? null : _createConversation,
          icon: Icon(isGroup ? Icons.group_add_outlined : Icons.chat_outlined),
          label: Text(isGroup ? l10n.createGroup : l10n.startDirect),
        ),
      ],
    );
  }
}

class _Friend {
  const _Friend({required this.id, required this.name, required this.color});

  final String id;
  final String name;
  final Color color;
}

class _NewConversationDraft {
  const _NewConversationDraft({
    required this.participants,
    required this.groupName,
  });

  final List<_Friend> participants;
  final String groupName;

  String get title {
    if (participants.length == 1) return participants.single.name;
    if (groupName.isNotEmpty) return groupName;
    return participants.map((friend) => friend.name).join(', ');
  }
}

class _Conversation {
  const _Conversation({
    required this.id,
    required this.title,
    required this.preview,
    required this.time,
    required this.color,
    this.unread = 0,
    this.online = false,
    this.muted = false,
    this.isGroup = false,
    this.participantCount = 2,
  });

  final String id;
  final String title;
  final String preview;
  final String time;
  final Color color;
  final int unread;
  final bool online;
  final bool muted;
  final bool isGroup;
  final int participantCount;
}

class _ConversationDraft {
  final messageController = TextEditingController();
  final mediaDescriptionController = TextEditingController();
  List<PendingAttachment> attachments = const [];

  void clear() {
    messageController.clear();
    mediaDescriptionController.clear();
    attachments = const [];
  }

  void dispose() {
    messageController.dispose();
    mediaDescriptionController.dispose();
  }
}

class _LocalMessage {
  const _LocalMessage({
    required this.text,
    required this.time,
    this.localId,
    this.mine = false,
    this.author,
    this.media = const [],
    this.sticker,
    this.deliveryState,
  });

  final String? localId;
  final String text;
  final String time;
  final bool mine;
  final String? author;
  final List<_LocalMedia> media;
  final AnimatedStickerDefinition? sticker;
  final HomeserverMessageDeliveryState? deliveryState;

  _LocalMessage copyWith({HomeserverMessageDeliveryState? deliveryState}) =>
      _LocalMessage(
        localId: localId,
        text: text,
        time: time,
        mine: mine,
        author: author,
        media: media,
        sticker: sticker,
        deliveryState: deliveryState ?? this.deliveryState,
      );
}

enum _ComposerAction { media, animatedSticker }

class _LocalMedia {
  const _LocalMedia({required this.selection, required this.description});

  final LocalMediaSelection selection;
  final String description;
}

ChatMediaKind _chatMediaKind(MediaKind kind) {
  return switch (kind) {
    MediaKind.image => ChatMediaKind.image,
    MediaKind.video => ChatMediaKind.video,
    MediaKind.file => ChatMediaKind.file,
  };
}

ImageProvider<Object>? _thumbnailFor(LocalMediaSelection selection) {
  if (selection.kind != MediaKind.image) return null;
  try {
    final file = File(selection.localPath);
    if (!file.existsSync()) return null;
    return FileImage(file);
  } on FileSystemException {
    return null;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib >= 100 ? 0 : 1)} KB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib >= 100 ? 0 : 1)} MB';
}

String _stickerLabel(
  EverydayLocalizations l10n,
  AnimatedStickerDefinition sticker,
) {
  final meaning = switch (sticker.effect) {
    StickerEffect.wave => l10n.stickerMeaningGreeting,
    StickerEffect.welcome => l10n.stickerMeaningWelcome,
    StickerEffect.yes => l10n.stickerMeaningAgreement,
    StickerEffect.gotIt => l10n.stickerMeaningUnderstood,
    StickerEffect.sleep => l10n.stickerMeaningSleep,
    StickerEffect.trophy => l10n.stickerMeaningSuccess,
    StickerEffect.love => l10n.stickerMeaningLove,
    StickerEffect.miss => l10n.stickerMeaningMissing,
    StickerEffect.thanks => l10n.stickerMeaningThanks,
    StickerEffect.sorry => l10n.stickerMeaningSorry,
    StickerEffect.please => l10n.stickerMeaningPlease,
    StickerEffect.comfort => l10n.stickerMeaningComfort,
    StickerEffect.laugh => l10n.stickerMeaningLaugh,
    StickerEffect.music => l10n.stickerMeaningMusic,
    StickerEffect.wow => l10n.stickerMeaningSurprise,
    StickerEffect.shock => l10n.stickerMeaningShock,
    StickerEffect.like => l10n.stickerMeaningLike,
    StickerEffect.celebrate => l10n.stickerMeaningCelebrate,
    StickerEffect.cheer => l10n.stickerMeaningCheer,
    StickerEffect.clap => l10n.stickerMeaningClap,
    StickerEffect.angry => l10n.stickerMeaningAngry,
    StickerEffect.sad => l10n.stickerMeaningSad,
    StickerEffect.cry => l10n.stickerMeaningCry,
    StickerEffect.tired => l10n.stickerMeaningTired,
    null => sticker.semanticLabel,
  };
  final character =
      _stickerCharacterLabels(l10n)[sticker.characterId] ?? sticker.characterId;
  return l10n.stickerAccessibility(character, meaning, sticker.bubbleText);
}

Map<String, String> _stickerCharacterLabels(EverydayLocalizations l10n) => {
  'mori': l10n.characterMori,
  'lulu': l10n.characterLulu,
  'bobo': l10n.characterBobo,
  'toto': l10n.characterToto,
  'nuri': l10n.characterNuri,
  'duri': l10n.characterDuri,
  'mixed': l10n.characterTogether,
};

/// Deterministic test fixture only. Production onboarding must use secure RNG.
InvitationProof _localPreviewInvitationProof(String memberId) {
  final seed = memberId.codeUnits;
  return InvitationProof(
    List.generate(32, (index) => (seed[index % seed.length] + index) & 0xff),
  );
}
