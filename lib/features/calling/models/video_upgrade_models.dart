import 'package:flutter/foundation.dart';

enum VideoUpgradeStatus {
  pending,
  accepted,
  declined,
  cancelled,
  expired,
}

@immutable
class VideoUpgradeRequest {
  const VideoUpgradeRequest({
    required this.id,
    required this.callId,
    required this.requestedBy,
    required this.targetUserUid,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.respondedAt,
  });

  final String id;
  final String callId;
  final String requestedBy;
  final String targetUserUid;
  final VideoUpgradeStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? respondedAt;

  bool get isPending => status == VideoUpgradeStatus.pending;
  bool isExpired({DateTime? now}) =>
      (now ?? DateTime.now().toUtc()).isAfter(expiresAt);

  factory VideoUpgradeRequest.fromJson(Map<String, dynamic> json) {
    VideoUpgradeStatus parseStatus(String? s) {
      switch (s?.toLowerCase()) {
        case 'accepted':
          return VideoUpgradeStatus.accepted;
        case 'declined':
          return VideoUpgradeStatus.declined;
        case 'cancelled':
          return VideoUpgradeStatus.cancelled;
        case 'expired':
          return VideoUpgradeStatus.expired;
        default:
          return VideoUpgradeStatus.pending;
      }
    }

    return VideoUpgradeRequest(
      id: json['id']?.toString() ?? '',
      callId: json['call_id']?.toString() ?? json['callId']?.toString() ?? '',
      requestedBy: json['requested_by']?.toString() ?? json['requestedBy']?.toString() ?? '',
      targetUserUid: json['target_user_uid']?.toString() ?? json['targetUserUid']?.toString() ?? '',
      status: parseStatus(json['status']?.toString()),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? '')?.toLocal() ?? DateTime.now().add(const Duration(seconds: 30)),
      respondedAt: json['responded_at'] != null ? DateTime.tryParse(json['responded_at'].toString())?.toLocal() : null,
    );
  }
}

@immutable
class VideoUpgradeResult {
  const VideoUpgradeResult({
    required this.isSuccess,
    this.status = VideoUpgradeStatus.pending,
    this.requestId,
    this.targetUserUid,
    this.expiresAt,
    this.errorMessage,
    this.coalesced = false,
  });

  final bool isSuccess;
  final VideoUpgradeStatus status;
  final String? requestId;
  final String? targetUserUid;
  final DateTime? expiresAt;
  final String? errorMessage;
  final bool coalesced;
}

