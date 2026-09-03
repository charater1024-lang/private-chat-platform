import 'dart:io';

import 'package:chat_media/chat_media.dart';
import 'package:chat_ui/chat_ui.dart';
import 'package:flutter/material.dart';

import '../../l10n/secure_localizations.dart';

@immutable
class WorkProfile {
  const WorkProfile({
    required this.displayName,
    required this.jobTitle,
    required this.team,
    required this.status,
    required this.timezone,
    required this.accentColor,
    this.profileImagePath,
    this.coverImagePath,
  });

  final String displayName;
  final String jobTitle;
  final String team;
  final String status;
  final String timezone;
  final Color accentColor;
  final String? profileImagePath;
  final String? coverImagePath;

  String get summary => '$jobTitle · $team\n$status · $timezone';
}

/// Uses a local path only when the item still exists. The shared image widgets
/// apply bounded decode sizes; this app never calls `readAsBytes` on originals.
ImageProvider<Object>? localImageProviderIfExists(String? path) {
  final normalizedPath = path?.trim();
  if (normalizedPath == null || normalizedPath.isEmpty) return null;
  final file = File(normalizedPath);
  if (!file.existsSync()) return null;
  return FileImage(file);
}

Future<WorkProfile?> showWorkProfileEditor(
  BuildContext context, {
  required WorkProfile initialProfile,
  required MediaPickerPort mediaPicker,
}) {
  return showModalBottomSheet<WorkProfile>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (context) => _WorkProfileEditor(
      initialProfile: initialProfile,
      mediaPicker: mediaPicker,
    ),
  );
}

class _WorkProfileEditor extends StatefulWidget {
  const _WorkProfileEditor({
    required this.initialProfile,
    required this.mediaPicker,
  });

  final WorkProfile initialProfile;
  final MediaPickerPort mediaPicker;

  @override
  State<_WorkProfileEditor> createState() => _WorkProfileEditorState();
}

class _WorkProfileEditorState extends State<_WorkProfileEditor> {
  SecureLocalizations get _l10n => SecureLocalizations.of(context);

  static const _accentChoices = <Color>[
    Color(0xFF6739B6),
    Color(0xFF456800),
    Color(0xFF7D5BB5),
    Color(0xFF6B8528),
    Color(0xFF4E3A68),
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _titleController;
  late final TextEditingController _teamController;
  late final TextEditingController _statusController;
  late final TextEditingController _timezoneController;
  late Color _accentColor;
  String? _profileImagePath;
  String? _coverImagePath;
  String? _errorText;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    _nameController = TextEditingController(text: profile.displayName);
    _titleController = TextEditingController(text: profile.jobTitle);
    _teamController = TextEditingController(text: profile.team);
    _statusController = TextEditingController(text: profile.status);
    _timezoneController = TextEditingController(text: profile.timezone);
    _accentColor = profile.accentColor;
    _profileImagePath = profile.profileImagePath;
    _coverImagePath = profile.coverImagePath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    _teamController.dispose();
    _statusController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  WorkProfile get _draftProfile => WorkProfile(
    displayName: _nameController.text.trim().isEmpty
        ? _l10n.unnamed
        : _nameController.text.trim(),
    jobTitle: _titleController.text.trim(),
    team: _teamController.text.trim(),
    status: _statusController.text.trim(),
    timezone: _timezoneController.text.trim(),
    accentColor: _accentColor,
    profileImagePath: _profileImagePath,
    coverImagePath: _coverImagePath,
  );

  Future<void> _pickImage({required bool cover}) async {
    if (_pickingImage) return;
    setState(() {
      _pickingImage = true;
      _errorText = null;
    });

    try {
      final selections = await widget.mediaPicker.pick(
        MediaPickRequest(kinds: const {MediaKind.image}, maxSelections: 1),
      );
      if (!mounted || selections.isEmpty) return;
      final result = MediaPolicies.consumer.validate(selections);
      if (result.isInvalid) {
        setState(() {
          _errorText = _l10n.profileImagePolicyError;
        });
        return;
      }
      final selection = selections.first;
      if (selection.kind != MediaKind.image) {
        setState(() => _errorText = _l10n.profileImageOnly);
        return;
      }
      setState(() {
        if (cover) {
          _coverImagePath = selection.localPath;
        } else {
          _profileImagePath = selection.localPath;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _errorText = _l10n.profileImageOpenFailed);
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorText = _l10n.profileNameRequired);
      return;
    }
    Navigator.of(context).pop(_draftProfile);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = _draftProfile;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .92,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: _l10n.profileEditorClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
                Expanded(
                  child: Text(
                    _l10n.profileEditorTitle,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                FilledButton(
                  key: const ValueKey('work-profile-save'),
                  onPressed: _save,
                  child: Text(_l10n.save),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 24 + bottomInset),
              children: [
                ProfileHero(
                  displayName: profile.displayName,
                  status: profile.summary,
                  accentColor: _accentColor,
                  profileImage: localImageProviderIfExists(_profileImagePath),
                  backgroundImage: localImageProviderIfExists(_coverImagePath),
                  onEditProfilePhoto: _pickingImage
                      ? null
                      : () => _pickImage(cover: false),
                  onEditBackground: _pickingImage
                      ? null
                      : () => _pickImage(cover: true),
                  profileEditTooltip: _l10n.profilePhotoSelect,
                  backgroundEditTooltip: _l10n.coverImageSelect,
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sync_outlined, size: 19),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _l10n.profileLocalNotice,
                          style: const TextStyle(fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText!,
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _DirectoryTextField(
                  key: const ValueKey('profile-name-field'),
                  inputKey: const ValueKey('profile-name-input'),
                  controller: _nameController,
                  label: _l10n.name,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _DirectoryTextField(
                  inputKey: const ValueKey('profile-title-input'),
                  controller: _titleController,
                  label: _l10n.jobTitle,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _DirectoryTextField(
                  inputKey: const ValueKey('profile-team-input'),
                  controller: _teamController,
                  label: _l10n.team,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('profile-status-input'),
                  controller: _statusController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _l10n.statusMessage,
                    prefixIcon: const Icon(Icons.bolt_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('profile-timezone-input'),
                  controller: _timezoneController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _l10n.timezone,
                    hintText: _l10n.timezoneHint,
                    prefixIcon: const Icon(Icons.schedule_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _l10n.profileTheme,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  _l10n.profileThemeDescription,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final entry in _accentChoices.indexed)
                      Semantics(
                        button: true,
                        selected: entry.$2 == _accentColor,
                        label: _l10n.profileThemeSemantics(entry.$1 + 1),
                        child: InkWell(
                          key: ValueKey('profile-theme-${entry.$1}'),
                          onTap: () => setState(() => _accentColor = entry.$2),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: entry.$2,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: entry.$2 == _accentColor
                                    ? scheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: entry.$2 == _accentColor
                                ? const Icon(Icons.check, color: Colors.white)
                                : null,
                          ),
                        ),
                      ),
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

class _DirectoryTextField extends StatelessWidget {
  const _DirectoryTextField({
    required this.inputKey,
    required this.controller,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final Key inputKey;
  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = SecureLocalizations.of(context);
    return TextField(
      key: inputKey,
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.badge_outlined),
        suffixIcon: Tooltip(
          message: l10n.localEditAvailable,
          child: const Icon(Icons.edit_outlined, size: 18),
        ),
      ),
    );
  }
}
