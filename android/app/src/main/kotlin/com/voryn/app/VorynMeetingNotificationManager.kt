package com.voryn.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

object VorynMeetingNotificationManager {
    private const val TAG = "VorynMeetingNotif"
    const val CHANNEL_ID = "voryn_meetings_v1"
    private const val CHANNEL_NAME = "Meeting Invitations"
    private const val TAG_PREFIX = "voryn_meeting_"

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming VoRyn meeting invitations and updates"
                enableLights(true)
                enableVibration(true)
                setShowBadge(true)
            }
            nm.createNotificationChannel(channel)
            Log.d(TAG, "[CHANNEL] ensured $CHANNEL_ID")
        }
    }

    fun showMeetingInvitationNotification(
        context: Context,
        meetingId: String,
        joinCode: String,
        inviterName: String,
        meetingTitle: String
    ) {
        createNotificationChannel(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val contentIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("voryn://m/$joinCode")
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("source", "notification_invitation")
            putExtra("meeting_id", meetingId)
            putExtra("join_code", joinCode)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            joinCode.hashCode(),
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = "VoRyn Meeting Invitation"
        val cleanInviter = if (inviterName.isNotBlank()) inviterName else "A contact"
        val cleanMeeting = if (meetingTitle.isNotBlank()) meetingTitle else "VoRyn Meeting"
        val bodyText = "$cleanInviter invited you to join \"$cleanMeeting\""

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(bodyText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(bodyText))
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val notifId = (joinCode.hashCode() and 0x7FFFFFFF)
        nm.notify(TAG_PREFIX + joinCode, notifId, notification)
        Log.d(TAG, "[NOTIFY] posted invitation notification for code=$joinCode meetingId=$meetingId")
    }

    fun dismissMeetingNotification(context: Context, joinCode: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notifId = (joinCode.hashCode() and 0x7FFFFFFF)
        nm.cancel(TAG_PREFIX + joinCode, notifId)
        Log.d(TAG, "[DISMISS] cancelled notification for code=$joinCode")
    }
}

