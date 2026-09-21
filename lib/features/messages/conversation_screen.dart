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
          // Remove temporary/optimistic duplicate if present
          _messages.removeWhere(
            (m) => m.clientMessageId == msg.clientMessageId || m.id == msg.id,
          );
          _messages.insert(0, msg);
        });
        _markReadIfNeeded();
      }
    });
  }

  @override
  void didUpdateWidget(ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      _store.saveDraft(oldWidget.threadId, _textController.text);
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
    _scrollController.dispose();
    _store.saveDraft(widget.threadId, _textController.text);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  void _onScroll() {
    if (!_isLoadingMore &&
        _hasMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadInitialMessages() async {
    setState(() => _isLoading = true);
    debugPrint(
      '[MESSAGE_THREAD] action=open_thread threadId=${widget.threadId}',
    );
    try {
      if (_otherUserUid == null || _otherUserName == null) {
        final threads = await _repo.loadThreads();
        final found = threads.firstWhere(
          (t) => t.threadId == widget.threadId,
          orElse: () => VorynMessageThread(
            threadId: widget.threadId,
            otherUserUid: '',
            otherUserName: 'Voryn User',
            otherUserVorynId: '',
          ),
        );
        if (found.otherUserUid.isNotEmpty) {
          _otherUserUid = found.otherUserUid;
          _otherUserName = found.otherUserName;
          _otherUserVorynId = found.otherUserVorynId;
          _otherUserAvatarUrl = found.otherUserAvatarUrl;
        }
      }

      final fetched = await _repo.loadThreadMessages(
        widget.threadId,
        limit: 50,
      );
      final outbox = _store.getOutboxForThread(widget.threadId);

      if ((_otherUserUid == null || _otherUserUid!.isEmpty) &&
          fetched.isNotEmpty) {
        final currentUid = VorynBackend.client?.auth.currentUser?.id;
        final msg = fetched.first;
        if (msg.senderUid != currentUid && msg.senderUid.isNotEmpty) {
          _otherUserUid = msg.senderUid;
          _otherUserName ??= msg.senderName;
          _otherUserVorynId ??= msg.senderVorynId;
        } else if (msg.recipientUid != currentUid &&
            msg.recipientUid.isNotEmpty) {
          _otherUserUid = msg.recipientUid;
        }
      }

      if (mounted) {
        setState(() {
          _messages = [...outbox, ...fetched];
          _isLoading = false;
          _hasMore = fetched.length >= 50;
        });
        _markReadIfNeeded();
      }
    } catch (e, st) {
      debugPrint(
        '[MESSAGE_THREAD] action=open_thread_error threadId=${widget.threadId} error=$e\n$st',
      );
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _isLoadingMore = true);

    try {
      final oldest = _messages.lastWhere(
        (m) => m.status == VorynMessageDeliveryStatus.sent,
        orElse: () => _messages.last,
      );

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
            // Quick preset chips
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
                      hintText: 'Type a message (1-120 chars)…',
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
                      onPressed: canSend ? _sendMessage : null,
                      icon: const Icon(Icons.send_rounded, size: 20),
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
  const _MessageBubble({required this.message, required this.isOutgoing});

  final VorynMessage message;
  final bool isOutgoing;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final timeStr = _formatTime(message.createdAt);

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480.0),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isOutgoing ? colors.accent : colors.surface,
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
            border: isOutgoing ? null : Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: isOutgoing
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.remindToCall)
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
                message.body,
                style: TextStyle(
                  fontSize: 14,
                  color: isOutgoing ? Colors.white : colors.textPrimary,
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
                      color: isOutgoing ? Colors.white60 : colors.textMuted,
                    ),
                  ),
                  if (isOutgoing) ...[
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
