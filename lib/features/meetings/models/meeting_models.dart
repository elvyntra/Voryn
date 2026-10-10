import 'package:flutter/foundation.dart';

/// Normalizes any raw user input or link into the standard xxx-xxx-xxx join code.
/// Supports 9-character unhyphenated codes, links with prefixes, and mixed case.
String? normalizeMeetingJoinCode(String raw) {
  var code = raw.trim().toLowerCase();
  if (code.isEmpty) return null;

  // Strip known URL prefixes if present
  if (code.contains('/m/')) {
    code = code.split('/m/').last;
  } else if (code.contains('/j/')) {
    code = code.split('/j/').last;
  } else if (code.contains('/')) {
    code = code.split('/').last;
  }

  // Remove any whitespace
  code = code.replaceAll(RegExp(r'\s+'), '');

  // Reject invalid characters (anything other than alphanumeric and hyphens)
  if (RegExp(r'[^0-9a-z\-]').hasMatch(code)) {
    return null;
  }

  // If unhyphenated 9 chars (e.g., k7qmzxp2f or hex a1f4b29e0), format as xxx-xxx-xxx
  if (RegExp(r'^[0-9a-z]{9}$').hasMatch(code)) {
    code = '${code.substring(0, 3)}-${code.substring(3, 6)}-${code.substring(6, 9)}';
  }

  // Validate strict 3-3-3 pattern
  if (!RegExp(r'^[0-9a-z]{3}-[0-9a-z]{3}-[0-9a-z]{3}$').hasMatch(code)) {
    return null;
  }

  return code;
}

@immutable
class VorynMeetingSummary {
  const VorynMeetingSummary({
    required this.id,
    required this.title,
    required this.joinCode,
    required this.access,
    required this.status,
    this.scheduledAt,
    this.startedAt,
    this.endedAt,
    required this.hostUid,
    required this.myRole,
    required this.isHost,
    required this.activeParticipantCount,
    required this.historicalAttendeeCount,
    this.myJoinedAt,
    this.myInvitedAt,
  });

  final String id;
  final String title;
  final String joinCode;
  final String access; // 'link' | 'invited'
  final String status; // 'ready' | 'active' | 'ended' | 'cancelled'
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String hostUid;
  final String myRole; // 'host' | 'participant'
  final bool isHost;
  final int activeParticipantCount;
  final int historicalAttendeeCount;
  final DateTime? myJoinedAt;
  final DateTime? myInvitedAt;

  bool get isActive => status == 'active';
  bool get isReady => status == 'ready';
  bool get isEnded => status == 'ended' || status == 'cancelled';
  bool get isInvited => !isHost && myInvitedAt != null && myJoinedAt == null;

  /// Calculate duration ONLY when both startedAt and endedAt are present and meeting has ended.
  /// Never invent or fabricate durations for unstarted or ongoing meetings.
  String? get formattedDuration {
    if (startedAt == null || endedAt == null) return null;
    final diff = endedAt!.difference(startedAt!);
    if (diff.isNegative) return null;
    final minutes = diff.inMinutes;
    if (minutes < 1) return '< 1 min';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    return rem == 0 ? '$hours hr' : '$hours hr $rem min';
  }

  /// Formatted date string using native Dart date methods
  String get formattedDate {
    final dt = startedAt ?? scheduledAt ?? DateTime.now();
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;

    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $period';

    if (isToday) return 'Today · $timeStr';
    if (isYesterday) return 'Yesterday · $timeStr';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day} · $timeStr';
  }

  factory VorynMeetingSummary.fromJson(Map<String, dynamic> json) {
    return VorynMeetingSummary(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Voryn Meeting',
      joinCode: json['join_code'] as String? ?? '',
      access: json['access'] as String? ?? 'link',
      status: json['status'] as String? ?? 'ready',
      scheduledAt: json['scheduled_at'] != null ? DateTime.tryParse(json['scheduled_at'].toString())?.toLocal() : null,
      startedAt: json['started_at'] != null ? DateTime.tryParse(json['started_at'].toString())?.toLocal() : null,
      endedAt: json['ended_at'] != null ? DateTime.tryParse(json['ended_at'].toString())?.toLocal() : null,
      hostUid: json['host_uid'] as String? ?? '',
      myRole: json['my_role'] as String? ?? 'participant',
      isHost: json['is_host'] as bool? ?? false,
      activeParticipantCount: (json['active_participant_count'] as num?)?.toInt() ?? 0,
      historicalAttendeeCount: (json['historical_attendee_count'] as num?)?.toInt() ?? 0,
      myJoinedAt: json['my_joined_at'] != null ? DateTime.tryParse(json['my_joined_at'].toString())?.toLocal() : null,
      myInvitedAt: json['my_invited_at'] != null ? DateTime.tryParse(json['my_invited_at'].toString())?.toLocal() : null,
    );
  }
}

enum MeetingParticipantState {
  invited,
  joined,
  left,
}

@immutable
class VorynMeetingParticipant {
  const VorynMeetingParticipant({
    required this.meetingId,
    required this.userUid,
    required this.role,
    required this.displayName,
    this.avatarUrl,
    this.invitedAt,
    this.joinedAt,
    this.leftAt,
    this.isActive = false,
  });

  final String meetingId;
  final String userUid;
  final String role; // 'host' | 'participant'
  final String displayName;
  final String? avatarUrl;
  final DateTime? invitedAt;
  final DateTime? joinedAt;
  final DateTime? leftAt;
  final bool isActive;

  bool get isHost => role == 'host';

  MeetingParticipantState get state {
    if (joinedAt != null && leftAt == null) return MeetingParticipantState.joined;
    if (joinedAt != null && leftAt != null) return MeetingParticipantState.left;
    return MeetingParticipantState.invited;
  }

  factory VorynMeetingParticipant.fromJson(Map<String, dynamic> json) {
    return VorynMeetingParticipant(
      meetingId: json['meeting_id'] as String,
      userUid: json['user_uid'] as String,
      role: json['role'] as String? ?? 'participant',
      displayName: json['display_name'] as String? ?? 'Participant',
      avatarUrl: json['avatar_url'] as String?,
      invitedAt: json['invited_at'] != null ? DateTime.tryParse(json['invited_at'].toString())?.toLocal() : null,
      joinedAt: json['joined_at'] != null ? DateTime.tryParse(json['joined_at'].toString())?.toLocal() : null,
      leftAt: json['left_at'] != null ? DateTime.tryParse(json['left_at'].toString())?.toLocal() : null,
      isActive: json['is_active'] == true,
    );
  }
}

@immutable
class MeetingInvitationResult {
  const MeetingInvitationResult({
    required this.userUid,
    required this.isSuccess,
    this.errorMessage,
  });

  final String userUid;
  final bool isSuccess;
  final String? errorMessage;
}

@immutable
class VorynPrejoinMeeting {
  const VorynPrejoinMeeting({
    required this.meetingId,
    required this.title,
    required this.joinCode,
    required this.status,
    required this.access,
    this.hostName,
    this.hostAvatarUrl,
    required this.activeParticipantCount,
    required this.capacity,
  });

  final String meetingId;
  final String title;
  final String joinCode;
  final String status;
  final String access;
  final String? hostName;
  final String? hostAvatarUrl;
  final int activeParticipantCount;
  final int capacity;

  factory VorynPrejoinMeeting.fromJson(Map<String, dynamic> json, {required String joinCode}) {
    return VorynPrejoinMeeting(
      meetingId: (json['meeting_id'] ?? json['id']) as String,
      title: json['title'] as String? ?? 'Voryn Meeting',
      joinCode: joinCode,
      status: json['status'] as String? ?? 'ready',
      access: json['access'] as String? ?? 'link',
      hostName: json['host_name'] as String?,
      hostAvatarUrl: json['host_avatar_url'] as String?,
      activeParticipantCount: (json['active_participant_count'] as num?)?.toInt() ?? 0,
      capacity: (json['capacity'] as num?)?.toInt() ?? 8,
    );
  }
}

@immutable
class VorynCreatedMeeting {
  const VorynCreatedMeeting({
    required this.id,
    required this.title,
    required this.joinCode,
    required this.access,
    required this.status,
    required this.livekitRoomName,
  });

  final String id;
  final String title;
  final String joinCode;
  final String access;
  final String status;
  final String livekitRoomName;

  factory VorynCreatedMeeting.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final roomName = json['livekit_room_name'] as String?;
    return VorynCreatedMeeting(
      id: id,
      title: json['title'] as String? ?? 'Voryn Meeting',
      joinCode: json['join_code'] as String? ?? '',
      access: json['access'] as String? ?? 'link',
      status: json['status'] as String? ?? 'ready',
      livekitRoomName: (roomName != null && roomName.isNotEmpty)
          ? roomName
          : 'voryn-meeting-$id',
    );
  }
}

@immutable
class VorynJoinedMeeting {
  const VorynJoinedMeeting({
    required this.meetingId,
    required this.title,
    required this.livekitRoomName,
    required this.role,
    required this.status,
    required this.access,
    this.joinCode,
    this.livekitToken,
    this.livekitUrl,
    this.initialMic = true,
    this.initialCamera = false,
  });

  final String meetingId;
  final String title;
  final String livekitRoomName;
  final String role;
  final String status;
  final String access;
  final String? joinCode;
  final String? livekitToken;
  final String? livekitUrl;
  final bool initialMic;
  final bool initialCamera;

  bool get isHost => role == 'host';

  factory VorynJoinedMeeting.fromJson(
    Map<String, dynamic> json, {
    String? livekitToken,
    String? livekitUrl,
    String? joinCode,
    bool initialMic = true,
    bool initialCamera = false,
  }) {
    final meetingId = (json['meeting_id'] ?? json['id']) as String;
    final roomName = json['livekit_room_name'] as String?;
    return VorynJoinedMeeting(
      meetingId: meetingId,
      title: json['title'] as String? ?? 'Voryn Meeting',
      livekitRoomName: (roomName != null && roomName.isNotEmpty)
          ? roomName
          : 'voryn-meeting-$meetingId',
      role: json['role'] as String? ?? 'participant',
      status: json['status'] as String? ?? 'active',
      access: json['access'] as String? ?? 'link',
      joinCode: joinCode ?? (json['join_code'] as String?),
      livekitToken: livekitToken,
      livekitUrl: livekitUrl,
      initialMic: initialMic,
      initialCamera: initialCamera,
    );
  }
}

enum MeetingEndStatus {
  ended,
  endedCleanupPending,
  failedBeforeDb,
}

@immutable
class MeetingEndResult {
  const MeetingEndResult({
    required this.status,
    required this.dbEnded,
    required this.roomDeleted,
    this.errorMessage,
  });

  final MeetingEndStatus status;
  final bool dbEnded;
  final bool roomDeleted;
  final String? errorMessage;

  bool get isFullyTerminated => dbEnded && roomDeleted;
  bool get isEndedWithCleanupPending => dbEnded && !roomDeleted;
}

