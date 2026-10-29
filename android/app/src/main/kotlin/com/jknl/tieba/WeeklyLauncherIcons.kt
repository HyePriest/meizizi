package com.jknl.tieba

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.util.Calendar

/** Monday through Sunday, using the device's current date and time zone. */
object WeeklyLauncherIcons {
    private val days = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")

    fun refresh(context: Context) {
        try {
            applyToday(context)
        } catch (error: Exception) {
            // A launcher update must never prevent the reader from opening.
            Log.w("WeeklyLauncherIcons", "Unable to update launcher icon", error)
        } finally {
            try {
                scheduleNextDay(context)
            } catch (error: Exception) {
                Log.w("WeeklyLauncherIcons", "Unable to schedule icon update", error)
            }
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
