package com.jknl.tieba

import android.app.Activity
import android.app.ActivityManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.Calendar

/**
 * Monday through Sunday, using the device's current date and time zone.
 *
 * Switching launcher aliases while the app is on screen is unsafe on some ROMs
 * (observed on iQOO / OriginOS): the system closes the task that was opened
 * through the alias being disabled, and the launcher briefly reports the app as
 * "not installed". So the icon is only switched while no activity of this app
 * is visible. A midnight alarm that arrives while the app is in use is deferred
 * until the user leaves the app.
 */
object WeeklyLauncherIcons {
    private const val TAG = "WeeklyLauncherIcons"
    private const val LEAVE_DELAY_MS = 1500L
    private val days = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
    private val main = Handler(Looper.getMainLooper())

    // Only touched on the main thread (activity callbacks and broadcast receivers).
    private var startedActivities = 0
    private var appContext: Context? = null
    private val applyAfterLeaving = Runnable {
        val context = appContext ?: return@Runnable
        if (startedActivities == 0 && !anotherAppOnTopOfOurTask(context)) applySafely(context)
    }

    fun onActivityStarted(activity: Activity) {
        startedActivities++
        appContext = activity.applicationContext
        main.removeCallbacks(applyAfterLeaving)
        // Keep the midnight alarm alive, but never switch icons while visible.
        scheduleSafely(activity)
    }

    fun onActivityStopped(activity: Activity) {
        startedActivities = maxOf(0, startedActivities - 1)
        if (startedActivities == 0 && !activity.isChangingConfigurations) {
            main.removeCallbacks(applyAfterLeaving)
            main.postDelayed(applyAfterLeaving, LEAVE_DELAY_MS)
        }
    }

    /** Called by the midnight alarm, boot and time changes. */
    fun refresh(context: Context) {
        appContext = context.applicationContext
        if (startedActivities == 0) applySafely(context)
        // Otherwise onActivityStopped switches the icon when the user leaves.
        scheduleSafely(context)
    }

    private fun applySafely(context: Context) {
        try {
            applyToday(context)
        } catch (error: Exception) {
            // A launcher update must never prevent the reader from opening.
            Log.w(TAG, "Unable to update launcher icon", error)
        }
    }

    private fun scheduleSafely(context: Context) {
        try {
            scheduleNextDay(context)
        } catch (error: Exception) {
            Log.w(TAG, "Unable to schedule icon update", error)
        }
    }

    /**
     * A share sheet, photo picker or document picker opened from the app runs
     * inside our task while our own activity is stopped. Switching then would
     * close it, so wait for the next time the user leaves the app.
     */
    private fun anotherAppOnTopOfOurTask(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 23) return false
        return try {
            val manager = context.getSystemService(ActivityManager::class.java) ?: return false
            manager.appTasks.any { task ->
                val top = task.taskInfo.topActivity
                top != null && top.packageName != context.packageName
            }
        } catch (error: Exception) {
            Log.w(TAG, "Unable to inspect app tasks", error)
            true
        }
    }

    private fun applyToday(context: Context) {
        val today = (Calendar.getInstance().get(Calendar.DAY_OF_WEEK) + 5) % 7
        val manager = context.packageManager
        val changes = days.mapIndexedNotNull { index, day ->
            val component = ComponentName(context.packageName, "com.jknl.tieba.Launcher$day")
            val desired = if (index == today) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            val current = manager.getComponentEnabledSetting(component)
            val enabled = current == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (current == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && index == 0)
            if (enabled == (index == today)) null else component to desired
        }
        if (changes.isEmpty()) return
        if (Build.VERSION.SDK_INT >= 33) {
            manager.setComponentEnabledSettings(changes.map { (component, state) ->
                PackageManager.ComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
            })
        } else {
            // Enable the new entry first so there is always a working launcher entry.
            changes.sortedBy { (_, state) -> if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) 0 else 1 }
                .forEach { (component, state) ->
                    manager.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
                }
        }
    }

    private fun scheduleNextDay(context: Context) {
        val nextMidnight = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val intent = Intent(context, WeeklyLauncherIconReceiver::class.java)
            .setAction("${context.packageName}.ROTATE_LAUNCHER_ICON")
        val pending = PendingIntent.getBroadcast(context, 7100, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // Inexact scheduling avoids asking for an exact-alarm permission for a cosmetic change.
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextMidnight.timeInMillis, pending)
    }
}

class WeeklyLauncherIconReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        WeeklyLauncherIcons.refresh(context)
    }
}
