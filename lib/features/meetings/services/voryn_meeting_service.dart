import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../contacts/voryn_contact_service.dart';
import '../models/meeting_models.dart';

/// Service responsible for authoritative Voryn Meetings database RPCs and LiveKit token negotiation.
class VorynMeetingService {
  VorynMeetingService({SupabaseClient? client}) : _client = client;

  static VorynMeetingService? _instance;
  static VorynMeetingService get instance => _instance ??= VorynMeetingService();

  @visibleForTesting
  static set instance(VorynMeetingService service) => _instance = service;

  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;
  SupabaseClient? get _safeClient {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Lists all meetings hosted or joined by the current authenticated user.
  Future<List<VorynMeetingSummary>> listMyMeetings() async {
    final res = await client.rpc('list_my_meetings');
    if (res is! List) return [];
    return res
        .map((item) => VorynMeetingSummary.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  /// Creates a new meeting record via authoritative create_voryn_meeting RPC.
  Future<VorynCreatedMeeting> createMeeting({
    required String title,
    String access = 'link',
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 60) {
      throw ArgumentError('Meeting title must be between 1 and 60 characters');
    }
    if (access != 'link' && access != 'invited') {
      throw ArgumentError('Access must be either "link" or "invited"');
    }

    final res = await client.rpc(
      'create_voryn_meeting',
      params: {
        'meeting_title': cleanTitle,
        'meeting_access': access,
      },
    );

    if (res is List && res.isNotEmpty) {
      return VorynCreatedMeeting.fromJson(Map<String, dynamic>.from(res.first as Map));
    } else if (res is Map) {
      return VorynCreatedMeeting.fromJson(Map<String, dynamic>.from(res));
    }
    throw StateError('Failed to create meeting: unexpected response from server');
  }

  /// Resolves meeting pre-join metadata by join code without joining or mutating membership.
  Future<VorynPrejoinMeeting?> resolveMeetingForPrejoin(String rawCode) async {
    final normalized = normalizeMeetingJoinCode(rawCode);
    if (normalized == null) return null;

    final res = await client.rpc(
      'resolve_meeting_for_prejoin',
      params: {'candidate_code': normalized},
    );

    if (res is List && res.isNotEmpty) {
      return VorynPrejoinMeeting.fromJson(
        Map<String, dynamic>.from(res.first as Map),
        joinCode: normalized,
      );
    } else if (res is Map && res.isNotEmpty) {
      return VorynPrejoinMeeting.fromJson(
        Map<String, dynamic>.from(res),
        joinCode: normalized,
      );
    }
    return null;
  }

  /// Explicitly joins a meeting via join_voryn_meeting RPC and obtains the LiveKit token.
  /// If LiveKit token request fails, automatically rolls back membership via leave_voryn_meeting.
  Future<VorynJoinedMeeting> joinMeeting(
    String rawCode, {
    bool initialMic = true,
    bool initialCamera = false,
  }) async {
    final normalized = normalizeMeetingJoinCode(rawCode);
    if (normalized == null) {
      throw ArgumentError('Invalid meeting code format');
    }

    final res = await client.rpc(
      'join_voryn_meeting',
      params: {'candidate_code': normalized},
    );

    Map<String, dynamic> row;
    if (res is List && res.isNotEmpty) {
      row = Map<String, dynamic>.from(res.first as Map);
    } else if (res is Map && res.isNotEmpty) {
      row = Map<String, dynamic>.from(res);
    } else {
      throw StateError('Failed to join meeting: meeting not found or unavailable');
    }

    final meetingId = (row['meeting_id'] ?? row['id']) as String;

    // Request LiveKit meeting token from Edge Function
    String? token;
    String? livekitUrl;
    try {
      final tokenResponse = await client.functions.invoke(
        'livekit-token',
        body: {'meetingId': meetingId},
      );

      final tokenData = tokenResponse.data;
      if (tokenData is Map && tokenData['token'] is String) {
        token = tokenData['token'] as String;
        livekitUrl = tokenData['url'] as String?;
      } else {
        throw StateError('Invalid token response from server');
      }
    } catch (e) {
      // Roll back membership to avoid leaving participant stranded in DB
      try {
        await client.rpc('leave_voryn_meeting', params: {'p_meeting_id': meetingId});
      } catch (_) {
        // Rollback best effort
      }
      throw StateError('Unable to obtain meeting token: $e');
    }

    return VorynJoinedMeeting.fromJson(
      row,
      livekitToken: token,
      livekitUrl: livekitUrl,
      joinCode: normalized,
      initialMic: initialMic,
      initialCamera: initialCamera,
    );
  }

  /// Host starts a ready meeting.
  Future<void> startMeeting(String meetingId) async {
    await client.rpc('start_voryn_meeting', params: {'p_meeting_id': meetingId});
  }

  /// Participant leaves the meeting.
  Future<void> leaveMeeting(String meetingId) async {
    final res = await client.rpc('leave_voryn_meeting', params: {'p_meeting_id': meetingId});
    if (res is List && res.isNotEmpty) {
      final row = Map<String, dynamic>.from(res.first as Map);
      final activeCount = (row['active_participant_count'] as num?)?.toInt() ?? 0;
      final status = row['status'] as String?;
      if (status == 'ended' && activeCount == 0) {
        // Trigger server-controlled LiveKit room cleanup for auto-ended zero-participant room
        try {
          await client.functions.invoke(
            'end-voryn-meeting',
            body: {'meetingId': meetingId, 'action': 'cleanup', 'reason': 'last_participant_left'},
          );
        } catch (e) {
          debugPrint('[MEETING] Best-effort cleanup on last leave failed: $e');
        }
      }
    }
  }

  /// Host ends the meeting for everyone via canonical server-side termination endpoint.
  Future<MeetingEndResult> endMeetingForEveryone(String meetingId) async {
    try {
      final response = await client.functions.invoke(
        'end-voryn-meeting',
        body: {'meetingId': meetingId, 'action': 'host_end'},
      );
      final data = response.data;
      if (data is Map) {
        final dbEnded = data['dbEnded'] == true;
        final roomDeleted = data['roomDeleted'] == true;
        if (data['ok'] == true) {
          return MeetingEndResult(
            status: MeetingEndStatus.ended,
            dbEnded: true,
            roomDeleted: roomDeleted,
          );
        } else if (dbEnded) {
          return MeetingEndResult(
            status: MeetingEndStatus.endedCleanupPending,
            dbEnded: true,
            roomDeleted: roomDeleted,
            errorMessage: data['error'] as String?,
          );
        }
      }
      return MeetingEndResult(
        status: MeetingEndStatus.failedBeforeDb,
        dbEnded: false,
        roomDeleted: false,
        errorMessage: (data is Map ? data['error'] as String? : null) ?? 'Failed to end meeting',
      );
    } on FunctionException catch (fe) {
      final details = fe.details;
      if (details is Map && details['dbEnded'] == true) {
        return MeetingEndResult(
          status: MeetingEndStatus.endedCleanupPending,
          dbEnded: true,
          roomDeleted: false,
          errorMessage: details['error'] as String? ?? fe.reasonPhrase,
        );
      }
      final msg = details is Map ? (details['error'] as String?) : fe.reasonPhrase;
      return MeetingEndResult(
        status: MeetingEndStatus.failedBeforeDb,
        dbEnded: false,
        roomDeleted: false,
        errorMessage: msg ?? 'Termination failed before database update (${fe.status})',
      );
    } catch (e) {
      return MeetingEndResult(
        status: MeetingEndStatus.failedBeforeDb,
        dbEnded: false,
        roomDeleted: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Fetches real meeting participants and their invitation/attendance state.
  Future<List<VorynMeetingParticipant>> getMeetingParticipants(String meetingId) async {
    final c = _safeClient;
    if (c == null) return [];
    try {
      final res = await c.rpc(
        'list_meeting_participants',
        params: {'p_meeting_id': meetingId},
      );
      if (res is! List) return [];
      return res
          .map((item) => VorynMeetingParticipant.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (e) {
      debugPrint('[MEETING] Failed to list participants: $e');
      return [];
    }
  }

  /// Invites a single registered contact to a meeting via authoritative Edge Function with RPC fallback.
  Future<MeetingInvitationResult> inviteParticipant(String meetingId, String targetUserUid) async {
    final cleanUid = targetUserUid.trim();
    if (cleanUid.isEmpty) {
      return MeetingInvitationResult(
        userUid: targetUserUid,
        isSuccess: false,
        errorMessage: 'Invalid target user ID',
      );
    }

    final c = _safeClient;
    if (c == null) {
      return MeetingInvitationResult(
        userUid: cleanUid,
        isSuccess: false,
        errorMessage: 'Service client unavailable',
      );
    }

    // 1. Attempt canonical Edge Function invocation (authoritative RPC + FCM push)
    try {
      final fnRes = await c.functions.invoke(
        'send-meeting-invitation',
        body: {
          'meetingId': meetingId,
          'targetUserUid': cleanUid,
        },
      );
      if (fnRes.status == 200 && fnRes.data is Map) {
        final data = fnRes.data as Map;
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first as Map;
          if (first['success'] == true) {
            return MeetingInvitationResult(userUid: cleanUid, isSuccess: true);
          } else {
            return MeetingInvitationResult(
              userUid: cleanUid,
              isSuccess: false,
              errorMessage: first['error']?.toString() ?? 'Invitation failed',
            );
          }
        }
      } else if (fnRes.status >= 400 && fnRes.data is Map) {
        final err = (fnRes.data as Map)['error']?.toString();
        if (err != null && err.isNotEmpty) {
          return MeetingInvitationResult(
            userUid: cleanUid,
            isSuccess: false,
            errorMessage: err,
          );
        }
      }
    } catch (e) {
      debugPrint('[MEETING] Edge function invitation fallback to direct RPC: $e');
    }

    // 2. Resilient fallback to direct database RPC
    try {
      await c.rpc(
        'invite_meeting_participant',
        params: {
          'p_meeting_id': meetingId,
          'p_target_user_id': cleanUid,
        },
      );
      return MeetingInvitationResult(userUid: cleanUid, isSuccess: true);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '').replaceAll('PostgrestException: ', '');
      debugPrint('[MEETING] Failed to invite $cleanUid: $msg');
      return MeetingInvitationResult(
        userUid: cleanUid,
        isSuccess: false,
        errorMessage: msg,
      );
    }
  }

  /// Batch invites multiple contacts with individual success/failure reporting and retry safety.
  Future<List<MeetingInvitationResult>> inviteParticipants(
    String meetingId,
    List<String> targetUserUids,
  ) async {
    final cleanUids = targetUserUids.map((u) => u.trim()).where((u) => u.isNotEmpty).toList();
    if (cleanUids.isEmpty) return const [];

    final c = _safeClient;
    if (c != null) {
      // Attempt canonical batch Edge Function
      try {
        final fnRes = await c.functions.invoke(
          'send-meeting-invitation',
          body: {
            'meetingId': meetingId,
            'targetUserUids': cleanUids,
          },
        );
        if (fnRes.status == 200 && fnRes.data is Map) {
          final data = fnRes.data as Map;
          final resultsList = data['results'] as List?;
          if (resultsList != null && resultsList.isNotEmpty) {
            return resultsList.map((item) {
              final m = item as Map;
              final uid = m['user_uid']?.toString() ?? '';
              if (m['success'] == true) {
                return MeetingInvitationResult(userUid: uid, isSuccess: true);
              } else {
                return MeetingInvitationResult(
                  userUid: uid,
                  isSuccess: false,
                  errorMessage: m['error']?.toString() ?? 'Invitation failed',
                );
              }
            }).toList();
          }
        }
      } catch (e) {
        debugPrint('[MEETING] Batch edge function invocation failed, falling back: $e');
      }
    }

    final results = <MeetingInvitationResult>[];
    for (final uid in cleanUids) {
      final res = await inviteParticipant(meetingId, uid);
      results.add(res);
    }
    return results;
  }

  /// Returns contacts that are eligible to be invited to a meeting.
  /// Excludes: current user, blocked contacts, and invalid UIDs.
  Future<List<VorynStoredContact>> getEligibleContacts(
    String meetingId, {
    VorynContactService contactService = const VorynContactService(),
  }) async {
    final contacts = await contactService.loadContacts();
    final currentUid = _safeClient?.auth.currentUser?.id;

    return contacts.where((c) {
      if (c.uid.trim().isEmpty) return false;
      if (currentUid != null && c.uid == currentUid) return false;
      if (c.blocked) return false;
      return true;
    }).toList();
  }
}

