import 'dart:async';

import 'package:chat_core/chat_core_preview.dart'
    show InMemoryHomeserverRepository;
import 'package:chat_core/secure_chat_core.dart';
import 'package:chat_media/chat_media.dart';
import 'package:chat_sync/chat_sync.dart' show ClientMessageId;
import 'package:chat_ui/chat_ui.dart';
import 'package:flutter/material.dart';
import 'package:homeserver_client/homeserver_client.dart';

import '../../l10n/secure_localizations.dart';
import '../profile/work_profile.dart';

const _desktopBreakpoint = 980.0;
const _detailsBreakpoint = 1280.0;
const _sidebarColor = Color(0xFF2A1748);
const _workspaceColor = Color(0xFF190F2A);

/// The local preview follows the same no-escrow boundary required in release
/// builds. Exposing this descriptor keeps that product invariant testable
/// without granting UI code access to message keys or privileged decryptors.
@visibleForTesting
HomeserverDescriptor buildSecureCollabPreviewHomeserver() {
  final domain = SecurityDomain(
    id: 'private.northstar.v1',
    mode: SecurityMode.trueE2ee,
    policyVersion: '1.0',
  );
  return HomeserverDescriptor(
    serverId: 'northstar-home',
    ownerId: 'member-owner',
    deploymentPolicy: HomeserverDeploymentPolicy.secureCollab,
    securityDomain: domain,
    capabilities: HomeserverCapabilities.secureCollabDefaults(
      protocolVersion: 'secure-collab-private/1',
      maximumGroupMembers: 250,
    ),
  );
}

class SecureWorkspacePage extends StatefulWidget {
  const SecureWorkspacePage({
    required this.mediaPicker,
    this.messageSync,
    super.key,
  });

  final MediaPickerPort mediaPicker;
  final HomeserverMessageSync? messageSync;

  @override
  State<SecureWorkspacePage> createState() => _SecureWorkspacePageState();
}

class _SecureWorkspacePageState extends State<SecureWorkspacePage> {
  SecureLocalizations get _l10n => SecureLocalizations.of(context);

  static const _currentMemberId = 'member-haneul';
  late final HomeserverDescriptor _homeserver;
  SecurityDomain get _domain => _homeserver.securityDomain;
  late final ServerConnectionProfile _connectionProfile;
  late final InMemoryHomeserverRepository _homeserverRepository;
  final _mediaPolicy = MediaPolicies.consumer;
  late final List<TextEditingController> _messageControllers;
  final _messageScrollController = ScrollController();
  int _selectedChannel = 0;
  int _nextAttachmentId = 1;
  int _nextStickerMessageId = 1;
  int _nextTimelineSequence = 3;
  int _nextConversationId = 1;
  HomeserverSyncPresentation _syncPresentation =
      const HomeserverSyncPresentation.unconfigured();
  StreamSubscription<HomeserverSyncPresentation>? _syncSubscription;
  StreamSubscription<HomeserverMessageDeliveryUpdate>? _deliverySubscription;
  int _syncSubscriptionGeneration = 0;
  final Map<(String, ClientMessageId), ({int channelIndex, int sequence})>
  _timelineMessagesByDelivery = {};

  WorkProfile _profile = const WorkProfile(
    displayName: '김하늘',
    jobTitle: '프로젝트 관리자',
    team: '제품 전략팀',
    status: '오로라 출시 준비 중',
    timezone: '서울 · UTC+9',
    accentColor: Color(0xFF6739B6),
  );

  final List<_AttachmentDraft> _attachmentDrafts = [];
  bool _isPickingMedia = false;

  final List<_Channel> _channels = [
    const _Channel(name: '제품-공지', icon: Icons.campaign_outlined, unread: 3),
    const _Channel(name: '프로젝트-오로라', icon: Icons.tag, unread: 12),
    const _Channel(name: '보안-검토', icon: Icons.shield_outlined),
    const _Channel(name: '디자인-리뷰', icon: Icons.palette_outlined),
    const _Channel(name: '고객-피드백', icon: Icons.forum_outlined, muted: true),
    const _Channel(
      name: '박서연',
      icon: Icons.person_outline,
      conversationKind: HomeserverConversationKind.direct,
    ),
    const _Channel(
      name: '이도윤',
      icon: Icons.person_outline,
      conversationKind: HomeserverConversationKind.direct,
    ),
  ];

  final Map<int, List<_ChannelTimelineEntry>> _timelinesByChannel = {
    0: [
      const _WorkspaceMessage(
        channelIndex: 0,
        sequence: 0,
        author: '한유진',
        role: '프로덕트 리드',
        text: '오로라 베타 범위를 정리했습니다. 오늘 4시 검토 전에 의견 부탁드려요.',
        time: '오전 9:12',
        color: Color(0xFFFFC47D),
      ),
      const _WorkspaceMessage(
        channelIndex: 0,
        sequence: 1,
        author: '정민호',
        role: '보안 엔지니어',
        text: '키 교체 시나리오와 장치 해지 테스트를 체크리스트에 추가했습니다.',
        time: '오전 9:25',
        color: Color(0xFF92D8CF),
      ),
      const _WorkspaceMessage(
        channelIndex: 0,
        sequence: 2,
        author: '나',
        role: '프로젝트 관리자',
        text: '좋습니다. PC 클라이언트 성능 기준도 같은 문서에 연결할게요.',
        time: '오전 9:31',
        color: Color(0xFFBFC7FF),
        mine: true,
      ),
    ],
  };

  @override
  void initState() {
    super.initState();
    _bootstrapHomeserverPreview();
    assert(_domain.mode == SecurityMode.trueE2ee);
    assert(!_homeserver.deploymentPolicy.serverRuntimeCanDecrypt);
    assert(
      _homeserver.deploymentPolicy.keyCustody ==
          EncryptionKeyCustody.memberDevicesOnly,
    );
    _messageControllers = List.generate(
      _channels.length,
      (_) => TextEditingController(),
    );
    _listenToMessageSync();
    unawaited(_synchronizeSelectedChannel());
  }

  @override
  void didUpdateWidget(covariant SecureWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.messageSync, widget.messageSync)) return;
    unawaited(_syncSubscription?.cancel());
    unawaited(_deliverySubscription?.cancel());
    _timelineMessagesByDelivery.clear();
    _listenToMessageSync();
    unawaited(_synchronizeSelectedChannel());
  }

  void _bootstrapHomeserverPreview() {
    _homeserver = buildSecureCollabPreviewHomeserver();
    _connectionProfile = ServerConnectionProfile(
      profileId: 'secure-collab-private-preview',
      serverId: _homeserver.serverId,
      productKind: ProductKind.secureCollab,
      endpoint: Uri.parse('https://chat.northstar.invalid'),
      memberId: _currentMemberId,
      credentialReference: CredentialReference(
        'os-keychain:northstar-private-preview',
      ),
      tlsPeerPolicy: const TlsPeerPolicy.platformTrust(),
    );
    final joinedAt = DateTime.utc(2026, 9, 1);
    final owner = ServerMember.owner(
      memberId: 'member-owner',
      handle: '@owner:northstar',
      displayName: '홈서버 소유자',
      joinedAt: joinedAt,
    );
    _homeserverRepository = InMemoryHomeserverRepository.bootstrap(
      descriptor: _homeserver,
      owner: owner,
    );
    const members = <(String, String, String)>[
      (_currentMemberId, '@haneul:northstar', '김하늘'),
      ('member-seoyeon', '@seoyeon:northstar', '박서연'),
      ('member-doyoon', '@doyoon:northstar', '이도윤'),
      ('member-yujin', '@yujin:northstar', '한유진'),
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
  }

  @override
  void dispose() {
    for (final controller in _messageControllers) {
      controller.dispose();
    }
    _messageScrollController.dispose();
    _syncSubscriptionGeneration += 1;
    unawaited(_syncSubscription?.cancel());
    unawaited(_deliverySubscription?.cancel());
    _timelineMessagesByDelivery.clear();
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
    final localMessage = _timelineMessagesByDelivery[key];
    if (localMessage == null) return;
    final timeline = _timelinesByChannel[localMessage.channelIndex];
    final messageIndex = timeline?.indexWhere(
      (entry) =>
          entry is _WorkspaceMessage && entry.sequence == localMessage.sequence,
    );
    if (timeline == null || messageIndex == null || messageIndex < 0) return;
    final entry = timeline[messageIndex];
    if (entry is! _WorkspaceMessage) return;
    setState(() {
      timeline[messageIndex] = entry.copyWith(
        deliveryState: update.deliveryState,
      );
    });
    if (update.deliveryState == HomeserverMessageDeliveryState.acknowledged ||
        update.deliveryState == HomeserverMessageDeliveryState.failed) {
      _timelineMessagesByDelivery.remove(key);
    }
  }

  String _syncConversationId(int channelIndex) =>
      'secure-channel-$channelIndex';

  Future<void> _synchronizeSelectedChannel() async {
    final sync = widget.messageSync;
    if (sync == null) return;
    final localConversationId = _syncConversationId(_selectedChannel);
    await sync.synchronize(localConversationId);
  }

  void _selectChannel(int index) {
    setState(() => _selectedChannel = index);
    unawaited(_synchronizeSelectedChannel());
  }

  Future<void> _createMemberConversation() async {
    final currentMember = _homeserverRepository.memberById(
      requestedBy: _currentMemberId,
      memberId: _currentMemberId,
    );
    assert(currentMember.memberId == _currentMemberId);
    final directory = _homeserverRepository
        .listDirectory(requestedBy: _currentMemberId)
        .where(
          (member) =>
              member.memberId != _currentMemberId &&
              member.memberId != _homeserver.ownerId,
        )
        .toList(growable: false);
    final draft = await showDialog<_MemberConversationDraft>(
      context: context,
      builder: (context) => _MemberConversationDialog(members: directory),
    );
    if (!mounted || draft == null) return;

    final selectedIds = draft.members.map((member) => member.memberId).toSet();
    final group = selectedIds.length > 1;
    final title = group ? draft.title : draft.members.single.displayName;
    final request = ConversationRequest(
      conversationId: 'member-conversation-${_nextConversationId++}',
      creatorId: _currentMemberId,
      kind: group
          ? HomeserverConversationKind.group
          : HomeserverConversationKind.direct,
      participantIds: {_currentMemberId, ...selectedIds},
      title: group ? title : null,
    );
    final created = _homeserverRepository.createConversation(
      request,
      createdAt: DateTime.now().toUtc(),
    );
    assert(created.creatorId == _currentMemberId);

    final channelIndex = _channels.length;
    setState(() {
      _channels.add(
        _Channel(
          name: title,
          icon: group ? Icons.groups_outlined : Icons.person_outline,
          conversationKind: created.kind,
        ),
      );
      _messageControllers.add(TextEditingController());
      _timelinesByChannel[channelIndex] = [];
      _selectedChannel = channelIndex;
    });
    _showFeedback(
      group ? _l10n.groupConversationCreated : _l10n.directConversationCreated,
    );
    unawaited(_synchronizeSelectedChannel());
  }

  Future<void> _sendMessage() async {
    final channelIndex = _selectedChannel;
    final localConversationId = _syncConversationId(channelIndex);
    final controller = _messageControllers[channelIndex];
    final text = controller.text.trim();
    final drafts = _attachmentDrafts
        .where((draft) => draft.channelIndex == channelIndex)
        .toList(growable: false);
    if (text.isEmpty && drafts.isEmpty) return;
    final sync = widget.messageSync;
    final syncConfigured =
        text.isNotEmpty && (sync?.isConfigured(localConversationId) ?? false);
    int? outboundSequence;
    setState(() {
      final timeline = _timelinesByChannel.putIfAbsent(channelIndex, () => []);
      if (text.isNotEmpty) {
        outboundSequence = _nextTimelineSequence++;
        timeline.add(
          _WorkspaceMessage(
            channelIndex: channelIndex,
            sequence: outboundSequence!,
            author: _profile.displayName,
            role: _profile.jobTitle,
            text: text,
            time: _l10n.timeNow,
            color: _profile.accentColor,
            mine: true,
            deliveryState: syncConfigured
                ? HomeserverMessageDeliveryState.queued
                : HomeserverMessageDeliveryState.localOnly,
          ),
        );
      }
      for (final draft in drafts) {
        timeline.add(
          _SentMediaMessage(
            id: draft.id,
            channelIndex: channelIndex,
            sequence: _nextTimelineSequence++,
            selection: draft.pending.selection,
            accessibilityDescription: draft.accessibilityDescription.trim(),
          ),
        );
      }
      _attachmentDrafts.removeWhere(
        (draft) => draft.channelIndex == channelIndex,
      );
    });
    controller.clear();
    _scrollToLatest();

    final sentSequence = outboundSequence;
    if (!syncConfigured || sync == null || sentSequence == null) return;
    HomeserverMessageDeliveryState deliveryState;
    try {
      final result = await sync.sendText(
        localConversationId: localConversationId,
        plaintext: text,
      );
      deliveryState = result.deliveryState;
      final clientMessageId = result.clientMessageId;
      if (clientMessageId != null &&
          deliveryState != HomeserverMessageDeliveryState.acknowledged &&
          deliveryState != HomeserverMessageDeliveryState.failed) {
        _timelineMessagesByDelivery[(localConversationId, clientMessageId)] = (
          channelIndex: channelIndex,
          sequence: sentSequence,
        );
      }
    } on Object {
      deliveryState = HomeserverMessageDeliveryState.failed;
    }
    if (!mounted) return;
    final timeline = _timelinesByChannel[channelIndex];
    final messageIndex = timeline?.indexWhere(
      (entry) => entry is _WorkspaceMessage && entry.sequence == sentSequence,
    );
    if (timeline == null || messageIndex == null || messageIndex < 0) return;
    final entry = timeline[messageIndex];
    if (entry is! _WorkspaceMessage) return;
    setState(() {
      timeline[messageIndex] = entry.copyWith(deliveryState: deliveryState);
    });
  }

  Future<void> _openComposerActions() async {
    if (_isPickingMedia) return;
    final action = await showModalBottomSheet<_ComposerAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                child: Semantics(
                  header: true,
                  child: Text(
                    _l10n.addItemTitle,
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              ListTile(
                key: const ValueKey('collab-add-media-action'),
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(_l10n.mediaActionTitle),
                subtitle: Text(_l10n.mediaActionSubtitle),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ComposerAction.media),
              ),
              ListTile(
                key: const ValueKey('collab-add-animated-sticker-action'),
                leading: const Icon(Icons.sentiment_satisfied_alt_outlined),
                title: Text(_l10n.stickersActionTitle),
                subtitle: Text(_l10n.stickersActionSubtitle),
                onTap: () =>
                    Navigator.of(sheetContext)
                        .pop(_ComposerAction.animatedSticker),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _ComposerAction.media:
        await _pickAttachments();
        return;
      case _ComposerAction.animatedSticker:
        await _openAnimatedStickerPicker();
        return;
    }
  }

  Future<void> _openAnimatedStickerPicker() async {
    final selected = await showModalBottomSheet<AnimatedStickerDefinition>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) {
        final sheetHeight = (MediaQuery.sizeOf(sheetContext).height * .72)
            .clamp(320.0, 520.0)
            .toDouble();
        return SafeArea(
          child: SizedBox(
            height: sheetHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                  child: Semantics(
                    header: true,
                    child: Text(
                      _l10n.stickersActionTitle,
                      key: const ValueKey('collab-animated-sticker-title'),
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                Expanded(
                  child: AnimatedStickerPicker(
                    key: const ValueKey('collab-animated-sticker-picker'),
                    stickers: signatureAnimatedStickerPack,
                    characterLabels: _stickerCharacterLabels(_l10n),
                    emptyLabel: _l10n.stickerEmpty,
                    previousPageTooltip: _l10n.stickerPreviousPage,
                    nextPageTooltip: _l10n.stickerNextPage,
                    pageSemanticLabelBuilder: _l10n.stickerPageSemantics,
                    semanticLabelBuilder: (sticker) =>
                        _stickerLabel(_l10n, sticker),
                    assetPackage: 'chat_ui',
                    onStickerSelected: (sticker) =>
                        Navigator.of(sheetContext).pop(sticker),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || selected == null) return;

    setState(() {
      _timelinesByChannel
          .putIfAbsent(_selectedChannel, () => [])
          .add(
            _SentAnimatedStickerMessage(
              id: 'private-sticker-${_nextStickerMessageId++}',
              sticker: selected,
              channelIndex: _selectedChannel,
              sequence: _nextTimelineSequence++,
            ),
          );
    });
    _scrollToLatest();
  }

  Future<void> _pickAttachments() async {
    if (_isPickingMedia) return;
    final channelIndex = _selectedChannel;
    final channelDrafts = _attachmentDrafts
        .where((draft) => draft.channelIndex == channelIndex)
        .toList(growable: false);
    final remaining = _mediaPolicy.maxFiles - channelDrafts.length;
    if (remaining <= 0) {
      _showFeedback(_l10n.maxAttachments);
      return;
    }

    setState(() => _isPickingMedia = true);
    try {
      final selected = await widget.mediaPicker.pick(
        MediaPickRequest(
          kinds: const {MediaKind.image, MediaKind.video, MediaKind.file},
          maxSelections: remaining,
        ),
      );
      if (!mounted || selected.isEmpty) return;

      final combined = [
        for (final draft in channelDrafts) draft.pending.selection,
        ...selected,
      ];
      final validation = _mediaPolicy.validate(combined);
      if (validation.isInvalid) {
        _showFeedback(_validationMessage(validation));
        return;
      }

      setState(() {
        for (final selection in selected) {
          final id = 'private-media-${_nextAttachmentId++}';
          _attachmentDrafts.add(
            _AttachmentDraft(
              id: id,
              channelIndex: channelIndex,
              pending: PendingAttachment.queued(
                id: id,
                selection: selection,
              ).markReady(),
            ),
          );
        }
      });
    } catch (_) {
      if (mounted) _showFeedback(_l10n.fileOpenFailed);
    } finally {
      if (mounted) setState(() => _isPickingMedia = false);
    }
  }

  String _validationMessage(MediaValidationResult result) {
    if (result.contains(MediaValidationCode.tooManyFiles)) {
      return _l10n.maxAttachments;
    }
    if (result.contains(MediaValidationCode.imageTooLarge)) {
      return _l10n.imageTooLarge;
    }
    if (result.contains(MediaValidationCode.videoTooLarge)) {
      return _l10n.videoTooLarge;
    }
    if (result.contains(MediaValidationCode.fileTooLarge)) {
      return _l10n.genericFileTooLarge;
    }
    if (result.contains(MediaValidationCode.mimeTypeNotAllowed) ||
        result.contains(MediaValidationCode.kindMimeMismatch)) {
      return _l10n.mediaNotAllowed;
    }
    return _l10n.attachmentPolicyMismatch;
  }

  void _removeAttachment(String id) {
    setState(() => _attachmentDrafts.removeWhere((draft) => draft.id == id));
  }

  void _updateAccessibilityDescription(String id, String value) {
    final index = _attachmentDrafts.indexWhere((draft) => draft.id == id);
    if (index < 0) return;
    _attachmentDrafts[index].accessibilityDescription = value;
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _editProfile() async {
    final updated = await showWorkProfileEditor(
      context,
      initialProfile: _profile,
      mediaPicker: widget.mediaPicker,
    );
    if (!mounted || updated == null) return;
    setState(() => _profile = updated);
    _showFeedback(_l10n.profileSaved);
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messageScrollController.hasClients) return;
      _messageScrollController.animateTo(
        _messageScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _desktopBreakpoint) {
          return _buildMobile();
        }
        return _buildDesktop(
          showDetails: constraints.maxWidth >= _detailsBreakpoint,
        );
      },
    );
  }

  Widget _buildDesktop({required bool showDetails}) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _WorkspaceSwitcher(profile: _profile, onEditProfile: _editProfile),
            SizedBox(
              width: 280,
              child: _ChannelSidebar(
                channels: _channels,
                selectedIndex: _selectedChannel,
                onSelected: _selectChannel,
                onCreateConversation: _createMemberConversation,
              ),
            ),
            Expanded(child: _buildChannelView()),
            if (showDetails) ...[
              const VerticalDivider(width: 1),
              const SizedBox(width: 290, child: _DetailsPanel()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobile() {
    final channel = _channels[_selectedChannel];
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _l10n.appTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            Text(
              channel.isConversation ? channel.name : '# ${channel.name}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _l10n.search,
            onPressed: () {},
            icon: const Icon(Icons.search),
          ),
          IconButton(
            key: const ValueKey('mobile-profile-edit'),
            tooltip: _l10n.profileEditTooltip(_profile.displayName),
            onPressed: _editProfile,
            icon: CircleAvatar(
              radius: 15,
              backgroundColor: _profile.accentColor,
              backgroundImage: localImageProviderIfExists(
                _profile.profileImagePath,
              ),
              child:
                  localImageProviderIfExists(_profile.profileImagePath) == null
                  ? Text(
                      _profile.displayName.characters.first,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    )
                  : null,
            ),
          ),
          IconButton(
            tooltip: _l10n.channelInfo,
            onPressed: () {},
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      drawer: Drawer(
        width: 310,
        child: SafeArea(
          child: _ChannelSidebar(
            channels: _channels,
            selectedIndex: _selectedChannel,
            onSelected: (index) {
              _selectChannel(index);
              Navigator.of(context).pop();
            },
            onCreateConversation: () {
              Navigator.of(context).pop();
              _createMemberConversation();
            },
          ),
        ),
      ),
      body: _buildChannelView(showHeader: false),
      bottomNavigationBar: keyboardVisible
          ? null
          : NavigationBar(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.forum_outlined),
                  label: _l10n.navConversations,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.checklist_outlined),
                  label: _l10n.navTasks,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.notifications_outlined),
                  label: _l10n.navActivity,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.account_circle_outlined),
                  label: _l10n.navProfile,
                ),
              ],
            ),
    );
  }

  Widget _buildChannelView({bool showHeader = true}) {
    final channel = _channels[_selectedChannel];
    final controller = _messageControllers[_selectedChannel];
    final attachmentDrafts = _attachmentDrafts
        .where((draft) => draft.channelIndex == _selectedChannel)
        .toList(growable: false);
    final timeline =
        _timelinesByChannel[_selectedChannel] ??
        const <_ChannelTimelineEntry>[];
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
        final composerHeightFraction = keyboardVisible
            ? .62
            : attachmentDrafts.isEmpty
            ? .58
            : .82;
        final composerHeightLimit =
            (constraints.maxHeight * composerHeightFraction)
                .clamp(96.0, keyboardVisible ? 280.0 : 440.0)
                .toDouble();
        return Column(
          children: [
            if (showHeader)
              _ChannelHeader(
                channel: channel,
                profile: _profile,
                onEditProfile: _editProfile,
              ),
            _PrivacySecurityBanner(
              policyVersion: _domain.policyVersion,
              syncConfigured:
                  _syncPresentation.connectionStatus !=
                  HomeserverConnectionStatus.unconfigured,
            ),
            Expanded(
              child: ListView.builder(
                key: const ValueKey('collab-message-list'),
                controller: _messageScrollController,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                itemCount:
                    1 +
                    (attachmentDrafts.isEmpty ? 1 : 0) +
                    timeline.length +
                    (channel.isConversation ? 0 : 1),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final startLabel = switch (channel.conversationKind) {
                      HomeserverConversationKind.direct =>
                        _l10n.directConversationStart(channel.name),
                      HomeserverConversationKind.group =>
                        _l10n.groupConversationStart(channel.name),
                      null => _l10n.channelStart(channel.name),
                    };
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: StatusPill(
                          label: startLabel,
                          icon: channel.icon,
                          color: scheme.primary,
                          compact: true,
                        ),
                      ),
                    );
                  }
                  if (attachmentDrafts.isEmpty && index == 1) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ServerConnectionBanner(
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
                          _l10n.memberOnlyEncryptionMode,
                          _syncStatusLabel,
                        ],
                      ),
                    );
                  }
                  final timelineIndex =
                      index - 1 - (attachmentDrafts.isEmpty ? 1 : 0);
                  if (timelineIndex < timeline.length) {
                    return _buildTimelineEntry(timeline[timelineIndex]);
                  }
                  return const _TaskCard();
                },
              ),
            ),
            _CollabComposer(
              channelName: channel.name,
              conversationKind: channel.conversationKind,
              controller: controller,
              onSend: _sendMessage,
              isPickingMedia: _isPickingMedia,
              attachments: attachmentDrafts,
              onRemoveAttachment: _removeAttachment,
              onDescriptionChanged: _updateAccessibilityDescription,
              onOpenComposerActions: _openComposerActions,
              maxHeight: composerHeightLimit,
              compactPolicy: keyboardVisible,
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimelineEntry(_ChannelTimelineEntry entry) {
    if (entry is _WorkspaceMessage) {
      return _CollabMessageCard(
        key: ValueKey('timeline-message-${entry.sequence}'),
        message: entry,
      );
    }
    if (entry is _SentMediaMessage) {
      return _LocalOnlyTimelineItem(
        key: ValueKey('timeline-media-${entry.sequence}'),
        statusKey: ValueKey('collab-media-delivery-${entry.id}'),
        label: _l10n.deliveryLocalOnly,
        child: _CollabMediaCard(media: entry),
      );
    }
    if (entry is _SentAnimatedStickerMessage) {
      return _LocalOnlyTimelineItem(
        key: ValueKey('timeline-sticker-${entry.sequence}'),
        statusKey: ValueKey('collab-sticker-delivery-${entry.id}'),
        label: _l10n.deliveryLocalOnly,
        child: AnimatedStickerMessageCard(
          key: ValueKey('sent-sticker-${entry.id}'),
          sticker: entry.sticker,
          timeLabel: _l10n.timeNow,
          isMine: true,
          assetPackage: 'chat_ui',
          semanticLabel: _stickerLabel(_l10n, entry.sticker),
        ),
      );
    }
    throw StateError('Unknown channel timeline entry: $entry');
  }
}

class _ServerConnectionBanner extends StatelessWidget {
  const _ServerConnectionBanner({required this.title, required this.labels});

  final String title;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '$title. ${labels.join('. ')}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
        color: scheme.secondaryContainer.withValues(alpha: .38),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_outlined, size: 16, color: scheme.secondary),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  for (var index = 0; index < labels.length; index += 1)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: .78),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                index == 1
                                    ? Icons.schedule_outlined
                                    : Icons.info_outline,
                                size: 13,
                                color: index == 1
                                    ? scheme.tertiary
                                    : scheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  labels[index],
                                  style: const TextStyle(
                                    fontSize: 10,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceSwitcher extends StatelessWidget {
  const _WorkspaceSwitcher({
    required this.profile,
    required this.onEditProfile,
  });

  final WorkProfile profile;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    return ColoredBox(
      color: _workspaceColor,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            const SizedBox(height: 16),
            Tooltip(
              message: 'Northstar',
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C6FE5),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Text(
                  'N',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _WorkspaceButton(label: 'P', color: Color(0xFF315F73)),
            const SizedBox(height: 12),
            IconButton(
              tooltip: l10n.addWorkspace,
              onPressed: () {},
              color: Colors.white70,
              icon: const Icon(Icons.add),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: IconButton(
                key: const ValueKey('workspace-avatar-profile-edit'),
                tooltip: l10n.profileEditTooltip(profile.displayName),
                onPressed: onEditProfile,
                icon: CircleAvatar(
                  radius: 18,
                  backgroundColor: profile.accentColor,
                  backgroundImage: localImageProviderIfExists(
                    profile.profileImagePath,
                  ),
                  child:
                      localImageProviderIfExists(profile.profileImagePath) ==
                          null
                      ? Text(
                          profile.displayName.characters.first,
                          style: const TextStyle(color: Colors.white),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceButton extends StatelessWidget {
  const _WorkspaceButton({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ChannelSidebar extends StatelessWidget {
  const _ChannelSidebar({
    required this.channels,
    required this.selectedIndex,
    required this.onSelected,
    required this.onCreateConversation,
  });

  final List<_Channel> channels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onCreateConversation;

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    return ColoredBox(
      color: _sidebarColor,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Northstar Studio',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.appTitle,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.newMessage,
                    onPressed: () {},
                    color: Colors.white,
                    icon: const Icon(Icons.edit_square, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: l10n.workspaceSearch,
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.white60),
                  fillColor: Colors.white.withValues(alpha: .08),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
                    child: Text(
                      l10n.channels,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final entry in channels.asMap().entries)
                    if (!entry.value.isConversation)
                      _ChannelRow(
                        key: ValueKey('collab-channel-${entry.key}'),
                        channel: entry.value,
                        selected: entry.key == selectedIndex,
                        onTap: () => onSelected(entry.key),
                      ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 8, 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.directMessages,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('new-member-conversation-button'),
                          tooltip: l10n.newDirectMessage,
                          onPressed: onCreateConversation,
                          color: Colors.white,
                          icon: const Icon(
                            Icons.add_comment_outlined,
                            size: 19,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                    child: Text(
                      l10n.memberCanCreate,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                  ),
                  for (final entry in channels.asMap().entries)
                    if (entry.value.isConversation)
                      _ChannelRow(
                        key: ValueKey('collab-conversation-${entry.key}'),
                        channel: entry.value,
                        selected: entry.key == selectedIndex,
                        onTap: () => onSelected(entry.key),
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_person_outlined,
                        color: Color(0xFFBFC7FF),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          l10n.privacySecurityActive,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final _Channel channel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: selected
            ? Colors.white.withValues(alpha: .13)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(channel.icon, size: 18, color: Colors.white70),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    channel.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: channel.unread > 0
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (channel.unread > 0)
                  Text(
                    '${channel.unread}',
                    style: const TextStyle(
                      color: Color(0xFFD7D2FF),
                      fontSize: 12,
                    ),
                  )
                else if (channel.muted)
                  const Icon(
                    Icons.notifications_off_outlined,
                    size: 14,
                    color: Colors.white38,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({
    required this.channel,
    required this.profile,
    required this.onEditProfile,
  });

  final _Channel channel;
  final WorkProfile profile;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(channel.icon, size: 21),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(switch (channel.conversationKind) {
                    HomeserverConversationKind.direct =>
                      l10n.directConversationPurpose,
                    HomeserverConversationKind.group =>
                      l10n.groupConversationPurpose,
                    null => l10n.channelPurpose,
                  }, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.startHuddle,
              onPressed: () {},
              icon: const Icon(Icons.headset_mic_outlined),
            ),
            IconButton(
              tooltip: l10n.search,
              onPressed: () {},
              icon: const Icon(Icons.search),
            ),
            IconButton(
              key: const ValueKey('channel-header-profile-edit'),
              tooltip: l10n.profileEditTooltip(profile.displayName),
              onPressed: onEditProfile,
              icon: CircleAvatar(
                radius: 14,
                backgroundColor: profile.accentColor,
                backgroundImage: localImageProviderIfExists(
                  profile.profileImagePath,
                ),
                child:
                    localImageProviderIfExists(profile.profileImagePath) == null
                    ? Text(
                        profile.displayName.characters.first,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      )
                    : null,
              ),
            ),
            IconButton(
              tooltip: l10n.channelInfo,
              onPressed: () {},
              icon: const Icon(Icons.info_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacySecurityBanner extends StatelessWidget {
  const _PrivacySecurityBanner({
    required this.policyVersion,
    required this.syncConfigured,
  });

  final String policyVersion;
  final bool syncConfigured;

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.tertiaryContainer.withValues(alpha: .65),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactAction =
              constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.4;
          return Row(
            children: [
              Icon(
                Icons.enhanced_encryption_outlined,
                size: 18,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  syncConfigured
                      ? l10n.trueE2eeTransportBanner(policyVersion)
                      : l10n.trueE2eeBanner(policyVersion),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (compactAction)
                IconButton(
                  tooltip: l10n.viewSecurityDetails,
                  onPressed: () {},
                  icon: const Icon(Icons.security_outlined),
                )
              else
                TextButton(
                  onPressed: () {},
                  child: Text(l10n.viewSecurityDetails),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CollabMessageCard extends StatelessWidget {
  const _CollabMessageCard({required this.message, super.key});

  final _WorkspaceMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChatAvatar(
            label: message.author,
            backgroundColor: message.color,
            radius: 20,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      message.author,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      message.role,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    Text(
                      message.time,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(message.text, style: const TextStyle(height: 1.4)),
                if (message.deliveryState != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _deliveryLabelForMessage(l10n, message),
                    key: ValueKey('collab-delivery-${message.sequence}'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  children: [
                    _Reaction(label: message.mine ? '✅ 2' : '👍 4'),
                    _Reaction(label: l10n.reply),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalOnlyTimelineItem extends StatelessWidget {
  const _LocalOnlyTimelineItem({
    required this.statusKey,
    required this.label,
    required this.child,
    super.key,
  });

  final Key statusKey;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 18, 7),
            child: Row(
              key: statusKey,
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
        ),
      ],
    );
  }
}

class _CollabMediaCard extends StatelessWidget {
  const _CollabMediaCard({required this.media});

  final _SentMediaMessage media;

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    final selection = media.selection;
    final description = media.accessibilityDescription;
    final chatKind = _chatMediaKindOrNull(selection.kind);
    if (chatKind == null) {
      return _CollabFileCard(media: media);
    }
    return Padding(
      key: ValueKey('sent-media-${media.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: MediaMessageCard(
        kind: chatKind,
        timeLabel: l10n.timeNow,
        isMine: true,
        thumbnail: selection.kind == MediaKind.image
            ? localImageProviderIfExists(selection.localPath)
            : null,
        caption: description.isEmpty
            ? selection.fileName
            : '${selection.fileName}\n${l10n.accessibilityDescription(description)}',
        status: MediaMessageStatus.sent,
      ),
    );
  }
}

class _CollabFileCard extends StatelessWidget {
  const _CollabFileCard({required this.media});

  final _SentMediaMessage media;

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final selection = media.selection;
    final description = media.accessibilityDescription.trim();
    final size = _formatBytes(selection.byteLength);
    return Padding(
      key: ValueKey('sent-media-${media.id}'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Semantics(
        container: true,
        label: [
          l10n.genericFileLabel,
          selection.fileName,
          size,
          if (description.isNotEmpty) description,
          l10n.timeNow,
        ].join('. '),
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.insert_drive_file_outlined,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selection.fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            description.isEmpty
                                ? '${l10n.genericFileLabel} · $size'
                                : '${l10n.genericFileLabel} · $size · '
                                      '$description',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 15,
                          color: scheme.onPrimaryContainer,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.timeNow,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Reaction extends StatelessWidget {
  const _Reaction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard();

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(50, 2, 0, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_outlined, size: 19, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.taskCardTitle,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              StatusPill(
                label: l10n.inProgress,
                color: Color(0xFF4F46A5),
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const LinearProgressIndicator(value: .72, minHeight: 6),
          const SizedBox(height: 8),
          Text(
            l10n.taskCardProgress,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CollabComposer extends StatelessWidget {
  const _CollabComposer({
    required this.channelName,
    required this.conversationKind,
    required this.controller,
    required this.onSend,
    required this.isPickingMedia,
    required this.attachments,
    required this.onRemoveAttachment,
    required this.onDescriptionChanged,
    required this.onOpenComposerActions,
    required this.maxHeight,
    required this.compactPolicy,
  });

  final String channelName;
  final HomeserverConversationKind? conversationKind;
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isPickingMedia;
  final List<_AttachmentDraft> attachments;
  final ValueChanged<String> onRemoveAttachment;
  final void Function(String id, String value) onDescriptionChanged;
  final VoidCallback onOpenComposerActions;
  final double maxHeight;
  final bool compactPolicy;

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    final mediaAttachments = attachments
        .where((draft) => draft.pending.selection.kind != MediaKind.file)
        .toList(growable: false);
    final fileAttachments = attachments
        .where((draft) => draft.pending.selection.kind == MediaKind.file)
        .toList(growable: false);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 12),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SingleChildScrollView(
                key: const ValueKey('collab-composer-scroll'),
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AttachmentDraftTray(
                      items: [
                        for (final draft in mediaAttachments)
                          AttachmentDraftItem(
                            id: draft.id,
                            kind: _chatMediaKindOrNull(
                              draft.pending.selection.kind,
                            )!,
                            fileName: draft.pending.selection.fileName,
                            sizeLabel: _formatBytes(
                              draft.pending.selection.byteLength,
                            ),
                            thumbnail:
                                draft.pending.selection.kind == MediaKind.image
                                ? localImageProviderIfExists(
                                    draft.pending.selection.localPath,
                                  )
                                : null,
                          ),
                      ],
                      removeTooltip: l10n.removeAttachment,
                      onRemove: (item) => onRemoveAttachment(item.id),
                    ),
                    if (fileAttachments.isNotEmpty)
                      SizedBox(
                        height: 76,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                          itemCount: fileAttachments.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final draft = fileAttachments[index];
                            return _GenericFileDraftTile(
                              draft: draft,
                              removeTooltip: l10n.removeAttachment,
                              onRemove: () => onRemoveAttachment(draft.id),
                            );
                          },
                        ),
                      ),
                    if (attachments.isNotEmpty)
                      SizedBox(
                        height: 66,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                          itemCount: attachments.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final draft = attachments[index];
                            return SizedBox(
                              width: 280,
                              child: TextFormField(
                                key: ValueKey(
                                  'attachment-description-${draft.id}',
                                ),
                                initialValue: draft.accessibilityDescription,
                                onChanged: (value) =>
                                    onDescriptionChanged(draft.id, value),
                                maxLength: 160,
                                decoration: InputDecoration(
                                  labelText: l10n.attachmentDescriptionLabel(
                                    draft.pending.selection.fileName,
                                  ),
                                  hintText: l10n.attachmentDescriptionHint,
                                  counterText: '',
                                  isDense: true,
                                  prefixIcon: const Icon(
                                    Icons.accessibility_new_outlined,
                                    size: 19,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    TextField(
                      key: const ValueKey('collab-message-input'),
                      controller: controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      decoration: InputDecoration(
                        hintText: switch (conversationKind) {
                          HomeserverConversationKind.direct =>
                            l10n.directMessageHint(channelName),
                          HomeserverConversationKind.group =>
                            l10n.groupMessageHint(channelName),
                          null => l10n.messageChannelHint(channelName),
                        },
                        fillColor: Colors.transparent,
                      ),
                    ),
                    Padding(
                      padding: compactPolicy
                          ? const EdgeInsets.fromLTRB(12, 2, 12, 0)
                          : const EdgeInsets.fromLTRB(12, 4, 12, 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.security_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.attachmentPolicySummary,
                              maxLines: compactPolicy ? 1 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compactPolicy ? 10 : 11,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 6, 5),
                      child: Row(
                        children: [
                          IconButton(
                            key: const ValueKey('collab-plus-button'),
                            tooltip: l10n.addMenu,
                            onPressed: isPickingMedia
                                ? null
                                : onOpenComposerActions,
                            icon: isPickingMedia
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.add_circle_outline,
                                    size: 20,
                                  ),
                          ),
                          IconButton(
                            tooltip: l10n.createTask,
                            onPressed: () {},
                            icon: const Icon(
                              Icons.check_box_outlined,
                              size: 20,
                            ),
                          ),
                          const Spacer(),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: controller,
                            builder: (context, value, child) {
                              final canSend =
                                  value.text.trim().isNotEmpty ||
                                  attachments.isNotEmpty;
                              return IconButton.filled(
                                key: const ValueKey('collab-send-button'),
                                tooltip: l10n.send,
                                onPressed: canSend ? onSend : null,
                                icon: const Icon(Icons.send_rounded, size: 18),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GenericFileDraftTile extends StatelessWidget {
  const _GenericFileDraftTile({
    required this.draft,
    required this.removeTooltip,
    required this.onRemove,
  });

  final _AttachmentDraft draft;
  final String removeTooltip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final selection = draft.pending.selection;
    final size = _formatBytes(selection.byteLength);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label:
          '${SecureLocalizations.of(context).genericFileLabel}. '
          '${selection.fileName}. $size',
      child: SizedBox(
        width: 280,
        child: Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(Icons.insert_drive_file_outlined, color: scheme.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selection.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(size, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
              IconButton(
                tooltip: removeTooltip,
                onPressed: onRemove,
                constraints: BoxConstraints.tight(const Size.square(48)),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            l10n.channelInfo,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          _DetailSection(
            icon: Icons.people_outline,
            title: l10n.members,
            detail: l10n.membersDetail,
          ),
          _DetailSection(
            icon: Icons.folder_open_outlined,
            title: l10n.sharedFiles,
            detail: l10n.sharedFilesDetail,
          ),
          _DetailSection(
            icon: Icons.push_pin_outlined,
            title: l10n.pinnedItems,
            detail: l10n.pinnedItemsDetail,
          ),
          const Divider(height: 32),
          Text(
            l10n.securityStatus,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _SecurityCheck(label: l10n.memberKeyCustodyStatus),
          _SecurityCheck(label: l10n.encryptedAttachmentStatus),
          _SecurityCheck(label: l10n.homeserverBlindStatus),
          _SecurityCheck(label: l10n.integrityAnchorStatus),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(detail),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {},
    );
  }
}

class _SecurityCheck extends StatelessWidget {
  const _SecurityCheck({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.schedule_outlined,
            color: Color(0xFF8A6515),
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _MemberConversationDialog extends StatefulWidget {
  const _MemberConversationDialog({required this.members});

  final List<DirectoryMember> members;

  @override
  State<_MemberConversationDialog> createState() =>
      _MemberConversationDialogState();
}

class _MemberConversationDialogState extends State<_MemberConversationDialog> {
  final _groupNameController = TextEditingController();
  final Set<String> _selectedMemberIds = {};

  List<DirectoryMember> get _selectedMembers => widget.members
      .where((member) => _selectedMemberIds.contains(member.memberId))
      .toList(growable: false);

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  void _submit() {
    final selected = _selectedMembers;
    if (selected.isEmpty) return;
    final l10n = SecureLocalizations.of(context);
    final typedTitle = _groupNameController.text.trim();
    final title = selected.length > 1
        ? typedTitle.isEmpty
              ? l10n.groupConversationDefault(
                  selected.map((member) => member.displayName).join(', '),
                )
              : typedTitle
        : selected.single.displayName;
    Navigator.of(context)
        .pop(_MemberConversationDraft(members: selected, title: title));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    final selected = _selectedMembers;
    final selectedCount = selected.length;
    final group = selectedCount > 1;
    final scheme = Theme.of(context).colorScheme;
    final defaultGroupName = group
        ? l10n.groupConversationDefault(
            selected.map((member) => member.displayName).join(', '),
          )
        : '';

    return AlertDialog(
      scrollable: true,
      title: Text(l10n.newDirectDialogTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.newDirectDialogInstruction,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: .52),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 18),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        l10n.memberCanCreate,
                        key: const ValueKey('member-can-create-notice'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              switch (selectedCount) {
                0 => l10n.selectMembers,
                1 => l10n.oneMemberSelected,
                _ => l10n.manyMembersSelected(selectedCount),
              },
              key: const ValueKey('member-conversation-type'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            for (final member in widget.members)
              CheckboxListTile(
                key: ValueKey('directory-member-${member.memberId}'),
                value: _selectedMemberIds.contains(member.memberId),
                onChanged: (selected) => setState(() {
                  if (selected ?? false) {
                    _selectedMemberIds.add(member.memberId);
                  } else {
                    _selectedMemberIds.remove(member.memberId);
                  }
                }),
                controlAffinity: ListTileControlAffinity.trailing,
                contentPadding: EdgeInsets.zero,
                secondary: CircleAvatar(
                  child: Text(member.displayName.characters.first),
                ),
                title: Text(member.displayName),
                subtitle: Text(l10n.activeMember),
              ),
            if (group) ...[
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('member-group-name-input'),
                controller: _groupNameController,
                maxLength: 60,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.groupConversationName,
                  hintText: defaultGroupName,
                  helperText: l10n.groupConversationHelper,
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
          key: const ValueKey('member-conversation-create-button'),
          onPressed: selectedCount == 0 ? null : _submit,
          icon: Icon(group ? Icons.group_add_outlined : Icons.chat_outlined),
          label: Text(l10n.createConversation),
        ),
      ],
    );
  }
}

class _MemberConversationDraft {
  const _MemberConversationDraft({required this.members, required this.title});

  final List<DirectoryMember> members;
  final String title;
}

class _Channel {
  const _Channel({
    required this.name,
    required this.icon,
    this.unread = 0,
    this.muted = false,
    this.conversationKind,
  });

  final String name;
  final IconData icon;
  final int unread;
  final bool muted;
  final HomeserverConversationKind? conversationKind;

  bool get isConversation => conversationKind != null;
}

abstract interface class _ChannelTimelineEntry {
  int get channelIndex;
  int get sequence;
}

class _WorkspaceMessage implements _ChannelTimelineEntry {
  const _WorkspaceMessage({
    required this.channelIndex,
    required this.sequence,
    required this.author,
    required this.role,
    required this.text,
    required this.time,
    required this.color,
    this.mine = false,
    this.deliveryState,
  });

  @override
  final int channelIndex;
  @override
  final int sequence;
  final String author;
  final String role;
  final String text;
  final String time;
  final Color color;
  final bool mine;
  final HomeserverMessageDeliveryState? deliveryState;

  _WorkspaceMessage copyWith({HomeserverMessageDeliveryState? deliveryState}) =>
      _WorkspaceMessage(
        channelIndex: channelIndex,
        sequence: sequence,
        author: author,
        role: role,
        text: text,
        time: time,
        color: color,
        mine: mine,
        deliveryState: deliveryState ?? this.deliveryState,
      );
}

String _deliveryLabelForMessage(
  SecureLocalizations l10n,
  _WorkspaceMessage message,
) => switch (message.deliveryState!) {
  HomeserverMessageDeliveryState.localOnly => l10n.deliveryLocalOnly,
  HomeserverMessageDeliveryState.queued => l10n.deliveryQueued,
  HomeserverMessageDeliveryState.acknowledged => l10n.deliveryAcknowledged,
  HomeserverMessageDeliveryState.retryScheduled => l10n.deliveryRetryScheduled,
  HomeserverMessageDeliveryState.blocked => l10n.deliveryBlocked,
  HomeserverMessageDeliveryState.failed => l10n.deliveryFailed,
};

class _AttachmentDraft {
  _AttachmentDraft({
    required this.id,
    required this.channelIndex,
    required this.pending,
  });

  final String id;
  final int channelIndex;
  final PendingAttachment pending;
  String accessibilityDescription = '';
}

class _SentMediaMessage implements _ChannelTimelineEntry {
  const _SentMediaMessage({
    required this.id,
    required this.channelIndex,
    required this.sequence,
    required this.selection,
    required this.accessibilityDescription,
  });

  final String id;
  @override
  final int channelIndex;
  @override
  final int sequence;
  final LocalMediaSelection selection;
  final String accessibilityDescription;
}

class _SentAnimatedStickerMessage implements _ChannelTimelineEntry {
  const _SentAnimatedStickerMessage({
    required this.id,
    required this.sticker,
    required this.channelIndex,
    required this.sequence,
  });

  final String id;
  final AnimatedStickerDefinition sticker;
  @override
  final int channelIndex;
  @override
  final int sequence;
}

enum _ComposerAction { media, animatedSticker }

ChatMediaKind? _chatMediaKindOrNull(MediaKind kind) {
  return switch (kind) {
    MediaKind.image => ChatMediaKind.image,
    MediaKind.video => ChatMediaKind.video,
    MediaKind.file => null,
  };
}

String _formatBytes(int bytes) {
  const kib = 1024;
  const mib = kib * 1024;
  if (bytes >= mib) {
    final value = bytes / mib;
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} MB';
  }
  if (bytes >= kib) {
    final value = bytes / kib;
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} KB';
  }
  return '$bytes B';
}

String _stickerLabel(
  SecureLocalizations l10n,
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

Map<String, String> _stickerCharacterLabels(SecureLocalizations l10n) => {
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
