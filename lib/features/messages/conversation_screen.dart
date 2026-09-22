import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/backend/voryn_backend.dart';
import '../../core/theme/voryn_theme.dart';
import '../../shared/widgets/voryn_avatar.dart';
import '../calling/voryn_call_service.dart';
import 'voryn_message_local_store.dart';
import 'voryn_message_models.dart';
import 'voryn_message_repository.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.threadId,
    this.otherUserUid,
    this.otherUserName,
    this.otherUserVorynId,
    this.otherUserAvatarUrl,
    this.isEmbeddedPane = false,
  });

  final String threadId;
  final String? otherUserUid;
  final String? otherUserName;
  final String? otherUserVorynId;
  final String? otherUserAvatarUrl;
  final bool isEmbeddedPane;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _repo = VorynMessageRepository.instance;
  final _store = VorynMessageLocalStore.instance;
  final _scrollController = ScrollController();
  final _textController = TextEditingController();

  List<VorynMessage> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _remindToCall = false;

  String? _otherUserUid;
  String? _otherUserName;
  String? _otherUserVorynId;
  String? _otherUserAvatarUrl;

  StreamSubscription<VorynMessage>? _messageSub;
  StreamSubscription<VorynMessage>? _messageUpdatedSub;
  StreamSubscription<Map<String, String>>? _messageDeletedForMeSub;
  StreamSubscription<String>? _threadClearedSub;

  VorynMessage? _editingMessage;
  String? _savedDraft;
  bool _isSavingEdit = false;

  final List<String> _quickPresets = const [
    'Call me back when free',
    'Can’t talk right now',
    'Will call you soon',
    'Free to talk now?',
    'Emergency - please call',
  ];

  @override
  void initState() {
    super.initState();
    _otherUserUid = widget.otherUserUid;
    _otherUserName = widget.otherUserName;
    _otherUserVorynId = widget.otherUserVorynId;
    _otherUserAvatarUrl = widget.otherUserAvatarUrl;

    _textController.text = _store.getDraft(widget.threadId);
    _textController.addListener(_onTextChanged);

    _scrollController.addListener(_onScroll);

    _loadInitialMessages();

    _messageSub = _repo.onMessageReceived.listen((msg) {
      if (msg.threadId == widget.threadId && mounted) {
        setState(() {
          _messages.removeWhere(
            (m) => m.clientMessageId == msg.clientMessageId || m.id == msg.id,
          );
          _messages.insert(0, msg);
        });
        _markReadIfNeeded();
      }
    });

    _messageUpdatedSub = _repo.onMessageUpdated.listen((updatedMsg) {
      if (updatedMsg.threadId == widget.threadId && mounted) {
        if (_editingMessage?.id == updatedMsg.id && updatedMsg.isDeleted) {
          _cancelEditing();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This message was deleted.')),
          );
        }
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == updatedMsg.id);
          if (idx != -1) {
            final existing = _messages[idx];
            if (updatedMsg.messageVersion >= existing.messageVersion) {
              _messages[idx] = existing.copyWith(
                body: updatedMsg.body,
                editedAt: updatedMsg.editedAt,
                deletedAt: updatedMsg.deletedAt,
                messageVersion: updatedMsg.messageVersion,
              );
            }
          }
        });
      }
    });

    _messageDeletedForMeSub = _repo.onMessageDeletedForMe.listen((event) {
      if (event['threadId'] == widget.threadId && mounted) {
        final targetId = event['messageId'];
        if (_editingMessage?.id == targetId) {
          _cancelEditing();
        }
        setState(() {
          _messages.removeWhere((m) => m.id == targetId);
        });
      }
    });

    _threadClearedSub = _repo.onThreadCleared.listen((clearedThreadId) {
      if (clearedThreadId == widget.threadId && mounted) {
        if (_editingMessage != null) {
          _cancelEditing();
        }
        setState(() {
          _messages.clear();
          _hasMore = false;
          _isLoadingMore = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      if (_editingMessage != null) {
        _cancelEditing();
      } else {
        _store.saveDraft(oldWidget.threadId, _textController.text);
      }
      _otherUserUid = widget.otherUserUid;
      _otherUserName = widget.otherUserName;
      _otherUserVorynId = widget.otherUserVorynId;
      _otherUserAvatarUrl = widget.otherUserAvatarUrl;
      _textController.text = _store.getDraft(widget.threadId);
      _hasMore = true;
      _loadInitialMessages();
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _messageUpdatedSub?.cancel();
    _messageDeletedForMeSub?.cancel();
    _threadClearedSub?.cancel();
    _scrollController.dispose();
    if (_editingMessage != null) {
      _store.saveDraft(widget.threadId, _savedDraft ?? '');
    } else {
      _store.saveDraft(widget.threadId, _textController.text);
    }
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_editingMessage == null) {
      _store.saveDraft(widget.threadId, _textController.text);
    }
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadInitialMessages() async {
    setState(() => _isLoading = true);
    try {
      final messages = await _repo.loadThreadMessages(
        widget.threadId,
        limit: 50,
      );
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
          _hasMore = messages.length >= 50;
          if (_otherUserUid == null && messages.isNotEmpty) {
            final myUid = VorynBackend.client?.auth.currentUser?.id ?? '';
            final otherMsg = messages.firstWhere(
              (m) => m.senderUid != myUid,
              orElse: () => messages.first,
            );
            _otherUserUid = otherMsg.senderUid == myUid
                ? otherMsg.recipientUid
                : otherMsg.senderUid;
            if (_otherUserName == null && otherMsg.senderUid != myUid) {
              _otherUserName = otherMsg.senderName;
              _otherUserVorynId = otherMsg.senderVorynId;
            }
          }
        });
        _markReadIfNeeded();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load messages: $e')));
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _isLoadingMore = true);

    try {
      final oldest = _messages.last;
      final older = await _repo.loadThreadMessages(
        widget.threadId,
        limit: 50,
        beforeCreatedAt: oldest.createdAt,
        beforeId: oldest.id,
      );

      if (mounted) {
        setState(() {
          _messages.addAll(older);
          _hasMore = older.length >= 50;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _markReadIfNeeded() {
    if (_messages.isEmpty) return;
    final latest = _messages.first;
    _repo.markThreadRead(widget.threadId, lastSeenMessageId: latest.id);
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty ||
        text.length > 120 ||
        _otherUserUid == null ||
        _otherUserUid!.isEmpty) {
      return;
    }

    _textController.clear();
    _store.clearDraft(widget.threadId);
    final remind = _remindToCall;
    setState(() => _remindToCall = false);

    try {
      final sent = await _repo.sendMessage(
        threadId: widget.threadId,
        recipientUid: _otherUserUid!,
        body: text,
        remindToCall: remind,
      );

      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere(
            (m) => m.clientMessageId == sent.clientMessageId,
          );
          if (idx != -1) {
            _messages[idx] = sent;
          } else {
            _messages.insert(0, sent);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    }
  }

  void _startEditing(VorynMessage message) {
    setState(() {
      _savedDraft = _textController.text;
      _editingMessage = message;
      _textController.text = message.body ?? '';
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: _textController.text.length),
      );
    });
  }

  void _cancelEditing() {
    setState(() {
      _textController.text = _savedDraft ?? '';
      _savedDraft = null;
      _editingMessage = null;
      _isSavingEdit = false;
    });
  }

  Future<void> _submitEdit() async {
    final msg = _editingMessage;
    if (msg == null || _isSavingEdit) return;

    final newText = _textController.text.trim();
    if (newText.isEmpty || newText.length > 120) return;

    if (newText == (msg.body ?? '')) {
      _cancelEditing();
      return;
    }

    setState(() => _isSavingEdit = true);

    try {
      final updated = await _repo.editMessage(
        messageId: msg.id,
        newBody: newText,
      );
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) {
            final existing = _messages[idx];
            if (updated.messageVersion >= existing.messageVersion) {
              _messages[idx] = existing.copyWith(
                body: updated.body,
                editedAt: updated.editedAt,
                messageVersion: updated.messageVersion,
              );
            }
          }
          _textController.text = _savedDraft ?? '';
          _savedDraft = null;
          _editingMessage = null;
          _isSavingEdit = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingEdit = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to edit: $e')));
      }
    }
  }

  void _showDeleteChoiceDialog(VorynMessage message) {
    final colors = context.vorynColors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: const Text('Delete message?'),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _confirmDeleteForMe(message);
            },
            child: Text(
              'Delete for me',
              style: TextStyle(color: colors.accent),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.danger),
            onPressed: () {
              Navigator.of(ctx).pop();
              _confirmDeleteForEveryone(message);
            },
            child: const Text('Delete for everyone'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteForMe(VorynMessage message) {
    final colors = context.vorynColors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: const Text('Delete message for me?'),
        content: const Text(
          'This message will be removed from your view only. Other participants will still be able to see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.danger),
            onPressed: () {
              Navigator.of(ctx).pop();
              _deleteMessageForMe(message);
            },
            child: const Text('Delete for me'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessageForMe(VorynMessage message) async {
    if (_editingMessage?.id == message.id) {
      _cancelEditing();
    }
    setState(() {
      _messages.removeWhere((m) => m.id == message.id);
    });

    try {
      await _repo.deleteMessageForMe(
        threadId: widget.threadId,
        messageId: message.id,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete message: $e')));
      }
    }
  }

  void _confirmDeleteForEveryone(VorynMessage message) {
    final colors = context.vorynColors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: const Text('Delete for everyone?'),
        content: const Text(
          'This message will be deleted for everyone in this chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.danger),
            onPressed: () {
              Navigator.of(ctx).pop();
              _deleteMessageForEveryone(message);
            },
            child: const Text('Delete for everyone'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessageForEveryone(VorynMessage message) async {
    if (_editingMessage?.id == message.id) {
      _cancelEditing();
    }
    try {
      await _repo.deleteMessage(message.id);
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == message.id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(
              body: null,
              deletedAt: DateTime.now(),
              messageVersion: message.messageVersion + 1,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  void _confirmClearChat() {
    final colors = context.vorynColors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: const Text('Clear chat?'),
        content: const Text(
          'All messages in this chat will be cleared from your view. The other participant will keep their chat history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.danger),
            onPressed: () {
              Navigator.of(ctx).pop();
              _clearChat();
            },
            child: const Text('Clear chat'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearChat() async {
    if (_editingMessage != null) {
      _cancelEditing();
    }
    _textController.clear();
    _store.clearDraft(widget.threadId);
    setState(() {
      _messages.clear();
      _hasMore = false;
      _isLoadingMore = false;
    });

    try {
      await _repo.clearThread(widget.threadId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Chat cleared')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to clear chat: $e')));
      }
    }
  }

  void _startCall(bool video) {
    final target = _otherUserVorynId ?? _otherUserName;
    if (target == null || target.isEmpty) return;
    const VorynCallService().start(vorynId: target, video: video).then((req) {
      if (req.id != null && mounted) {
        context.push(
          video
              ? '/active-video-call/${req.id}'
              : '/active-audio-call/${req.id}',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;
    final myUid = VorynBackend.client?.auth.currentUser?.id ?? '';

    final name = _otherUserName ?? 'Call Message';
    final nameParts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .toList();
    final initials = nameParts.map((p) => p[0].toUpperCase()).join();

    final content = Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        titleSpacing: 0,
        leading: widget.isEmbeddedPane
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              ),
        title: Row(
          children: [
            VorynAvatar(
              initials: initials.isEmpty ? '?' : initials,
              size: VorynAvatarSize.small,
              imageProvider: _otherUserAvatarUrl?.isNotEmpty == true
                  ? NetworkImage(_otherUserAvatarUrl!)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_otherUserVorynId != null &&
                      _otherUserVorynId!.isNotEmpty)
                    Text(
                      '@${_otherUserVorynId!.replaceFirst('@', '')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Audio Call',
            icon: const Icon(Icons.phone_rounded),
            onPressed: () => _startCall(false),
          ),
          IconButton(
            tooltip: 'Video Call',
            icon: const Icon(Icons.videocam_rounded),
            onPressed: () => _startCall(true),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'clear_chat') {
                _confirmClearChat();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'clear_chat',
                child: Text('Clear chat'),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet in this conversation.',
                      style: TextStyle(color: colors.textMuted),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.screen,
                      vertical: spacing.md,
                    ),
                    itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final msg = _messages[index];
                      final isOutgoing = msg.isOutgoing(myUid);
                      return _MessageBubble(
                        message: msg,
                        isOutgoing: isOutgoing,
                        onEdit: () => _startEditing(msg),
                        onDeleteChoice: () => _showDeleteChoiceDialog(msg),
                        onDeleteForMe: () => _confirmDeleteForMe(msg),
                      );
                    },
                  ),
          ),
          _buildInputBar(colors, spacing),
        ],
      ),
    );

    return content;
  }

  Widget _buildInputBar(dynamic colors, dynamic spacing) {
    final textLength = _textController.text.length;
    final isEditing = _editingMessage != null;
    final canSend = textLength > 0 && textLength <= 120;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.backgroundSoft,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Editing banner
            if (isEditing)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.accent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.edit_rounded, size: 14, color: colors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Editing message',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.accent,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _isSavingEdit ? null : _cancelEditing,
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            // Quick preset chips (only when not editing)
            if (!isEditing)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    FilterChip(
                      avatar: Icon(
                        Icons.phone_callback_rounded,
                        size: 14,
                        color: _remindToCall ? colors.accent : colors.iconMuted,
                      ),
                      label: Text(
                        'Remind to call',
                        style: TextStyle(
                          fontSize: 12,
                          color: _remindToCall
                              ? colors.accent
                              : colors.textPrimary,
                        ),
                      ),
                      selected: _remindToCall,
                      onSelected: (selected) =>
                          setState(() => _remindToCall = selected),
                      backgroundColor: colors.surface,
                      selectedColor: colors.accentSoft,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    for (final preset in _quickPresets)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(
                            preset,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            _textController.text = preset;
                            _textController.selection =
                                TextSelection.fromPosition(
                                  TextPosition(offset: preset.length),
                                );
                          },
                          backgroundColor: colors.surface,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    maxLines: 4,
                    minLines: 1,
                    maxLength: 120,
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    decoration: InputDecoration(
                      hintText: isEditing
                          ? 'Edit message…'
                          : 'Type a message (1-120 chars)…',
                      hintStyle: TextStyle(
                        color: colors.textMuted,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: colors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: colors.accent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (textLength > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '$textLength/120',
                          style: TextStyle(
                            fontSize: 10,
                            color: textLength > 120
                                ? Colors.red
                                : colors.textMuted,
                          ),
                        ),
                      ),
                    IconButton.filled(
                      onPressed: canSend
                          ? (isEditing
                                ? (_isSavingEdit ? null : _submitEdit)
                                : _sendMessage)
                          : null,
                      icon: isEditing
                          ? (_isSavingEdit
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.check_rounded, size: 20))
                          : const Icon(Icons.send_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: canSend
                            ? colors.accent
                            : colors.surfacePressed,
                        foregroundColor: canSend
                            ? Colors.white
                            : colors.iconMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isOutgoing,
    this.onEdit,
    this.onDeleteChoice,
    this.onDeleteForMe,
  });

  final VorynMessage message;
  final bool isOutgoing;
  final VoidCallback? onEdit;
  final VoidCallback? onDeleteChoice;
  final VoidCallback? onDeleteForMe;

  void _showBubbleOptions(BuildContext context) {
    final colors = context.vorynColors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOutgoing && !message.isDeleted)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onEdit?.call();
                },
              ),
            if (isOutgoing && !message.isDeleted)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: colors.danger,
                ),
                title: Text('Delete', style: TextStyle(color: colors.danger)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onDeleteChoice?.call();
                },
              )
            else
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: colors.danger,
                ),
                title: Text(
                  'Delete for me',
                  style: TextStyle(color: colors.danger),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onDeleteForMe?.call();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final timeStr = _formatTime(message.createdAt);
    final isDeleted = message.isDeleted;
    final isEdited = message.isEdited;

    final bubbleColor = isDeleted
        ? (isOutgoing ? colors.surfacePressed : colors.surface)
        : (isOutgoing ? colors.accent : colors.surface);

    final textColor = isDeleted
        ? colors.textMuted
        : (isOutgoing ? Colors.white : colors.textPrimary);

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480.0),
        child: GestureDetector(
          onLongPress: () => _showBubbleOptions(context),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isOutgoing
                    ? const Radius.circular(16)
                    : const Radius.circular(4),
                bottomRight: isOutgoing
                    ? const Radius.circular(4)
                    : const Radius.circular(16),
              ),
              border: (isOutgoing && !isDeleted)
                  ? null
                  : Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: isOutgoing
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isDeleted && message.remindToCall)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.phone_callback_rounded,
                          size: 13,
                          color: isOutgoing ? Colors.white70 : colors.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Call requested',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isOutgoing ? Colors.white70 : colors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  message.displayBody,
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: isOutgoing && !isDeleted
                            ? Colors.white60
                            : colors.textMuted,
                      ),
                    ),
                    if (isEdited) ...[
                      const SizedBox(width: 4),
                      Text(
                        '· Edited',
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: isOutgoing && !isDeleted
                              ? Colors.white60
                              : colors.textMuted,
                        ),
                      ),
                    ],
                    if (isOutgoing && !isDeleted) ...[
                      const SizedBox(width: 4),
                      if (message.status == VorynMessageDeliveryStatus.sending)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white70,
                            ),
                          ),
                        )
                      else if (message.status ==
                          VorynMessageDeliveryStatus.failed)
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 12,
                          color: Colors.amberAccent,
                        )
                      else
                        const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.white70,
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour = local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return '$displayHour:$minute $period';
}
