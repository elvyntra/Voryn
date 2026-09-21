package com.voryn.app

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

object VorynBackgroundAuthStore {
    private const val TAG = "VorynAuthStore"
    private const val PREFS_NAME = "voryn_background_auth_v1"

    private const val KEY_USER_UID = "user_uid"
    private const val KEY_ACCESS_TOKEN = "access_token"
    private const val KEY_REFRESH_TOKEN = "refresh_token"
    private const val KEY_EXPIRES_AT = "expires_at"
    private const val KEY_SESSION_VERSION = "session_version"
    private const val KEY_SUPABASE_URL = "supabase_url"
    private const val KEY_ANON_KEY = "anon_key"

    data class Session(
        val userUid: String,
        val accessToken: String,
        val refreshToken: String,
        val expiresAtMs: Long,
        val sessionVersion: Int,
        val supabaseUrl: String,
        val anonKey: String
    ) {
        val isExpiredOrNearExpiry: Boolean
            get() = System.currentTimeMillis() + 60_000L >= expiresAtMs
    }

    private fun getPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    @Synchronized
    fun saveSession(
        context: Context,
        userUid: String,
        accessToken: String,
        refreshToken: String,
        expiresAtMs: Long,
        supabaseUrl: String,
        anonKey: String
    ) {
        val prefs = getPrefs(context)
        val currentVersion = prefs.getInt(KEY_SESSION_VERSION, 0)
        prefs.edit()
            .putString(KEY_USER_UID, userUid)
            .putString(KEY_ACCESS_TOKEN, accessToken)
            .putString(KEY_REFRESH_TOKEN, refreshToken)
            .putLong(KEY_EXPIRES_AT, expiresAtMs)
            .putInt(KEY_SESSION_VERSION, currentVersion + 1)
            .putString(KEY_SUPABASE_URL, supabaseUrl)
            .putString(KEY_ANON_KEY, anonKey)
            .apply()
        Log.d(TAG, "[AUTH_STORE] saved session uid=$userUid version=${currentVersion + 1}")
    }

    @Synchronized
    fun getSession(context: Context): Session? {
        val prefs = getPrefs(context)
        val uid = prefs.getString(KEY_USER_UID, null) ?: return null
        val token = prefs.getString(KEY_ACCESS_TOKEN, null) ?: return null
        val refresh = prefs.getString(KEY_REFRESH_TOKEN, null) ?: return null
        val expiresAt = prefs.getLong(KEY_EXPIRES_AT, 0L)
        val version = prefs.getInt(KEY_SESSION_VERSION, 1)
        val url = prefs.getString(KEY_SUPABASE_URL, null) ?: return null
        val key = prefs.getString(KEY_ANON_KEY, null) ?: return null

        return Session(
            userUid = uid,
            accessToken = token,
            refreshToken = refresh,
            expiresAtMs = expiresAt,
            sessionVersion = version,
            supabaseUrl = url,
            anonKey = key
        )
    }

    @Synchronized
    fun updateTokens(
        context: Context,
        newAccessToken: String,
        newRefreshToken: String,
        newExpiresAtMs: Long
    ) {
        val prefs = getPrefs(context)
        val currentVersion = prefs.getInt(KEY_SESSION_VERSION, 1)
        prefs.edit()
            .putString(KEY_ACCESS_TOKEN, newAccessToken)
            .putString(KEY_REFRESH_TOKEN, newRefreshToken)
            .putLong(KEY_EXPIRES_AT, newExpiresAtMs)
            .putInt(KEY_SESSION_VERSION, currentVersion + 1)
            .apply()
        Log.d(TAG, "[AUTH_STORE] updated tokens, version=${currentVersion + 1}")
    }

    @Synchronized
    fun clear(context: Context) {
        getPrefs(context).edit().clear().apply()
        Log.d(TAG, "[AUTH_STORE] cleared background auth session")
    }

    /**
     * Refreshes access token synchronously over native HttpURLConnection.
     * Updates SharedPreferences and returns the refreshed access token, or null on failure.
     */
    @Synchronized
    fun refreshAccessToken(context: Context): String? {
        val session = getSession(context) ?: return null
        return try {
            val refreshUrl = URL("${session.supabaseUrl.trimEnd('/')}/auth/v1/token?grant_type=refresh_token")
            val conn = (refreshUrl.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 10_000
                readTimeout = 10_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("apikey", session.anonKey)
            }

            val requestJson = JSONObject().apply {
                put("refresh_token", session.refreshToken)
            }

            OutputStreamWriter(conn.outputStream).use { it.write(requestJson.toString()) }

            val responseCode = conn.responseCode
            if (responseCode in 200..299) {
                val responseText = conn.inputStream.bufferedReader().use(BufferedReader::readText)
                val json = JSONObject(responseText)
                val newAccessToken = json.getString("access_token")
                val newRefreshToken = json.optString("refresh_token", session.refreshToken)
                val expiresInSec = json.optLong("expires_in", 3600L)
                val newExpiresAtMs = System.currentTimeMillis() + (expiresInSec * 1000L)

                updateTokens(context, newAccessToken, newRefreshToken, newExpiresAtMs)
                Log.d(TAG, "[AUTH_STORE] token refresh successful")
                newAccessToken
            } else {
                Log.e(TAG, "[AUTH_STORE] token refresh failed with HTTP $responseCode")
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "[AUTH_STORE] token refresh exception: ${e.message}")
            null
        }
    }
}
