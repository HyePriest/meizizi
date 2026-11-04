package com.jknl.tieba;

import android.app.Instrumentation;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import java.util.Calendar;

/** Displays the installed launcher icons Monday to Sunday, five seconds each. */
public class WeeklyIconsTest extends Instrumentation {
    private final String[] days = {
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    };

    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }

    private void show(int selected) {
        PackageManager pm = getTargetContext().getPackageManager();
        String pkg = getTargetContext().getPackageName();
        // Enable first, so a launcher entry is always available.
        pm.setComponentEnabledSetting(new ComponentName(pkg, "com.jknl.tieba.Launcher" + days[selected]),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP);
        for (int i = 0; i < days.length; i++) {
            if (i != selected) pm.setComponentEnabledSetting(
                new ComponentName(pkg, "com.jknl.tieba.Launcher" + days[i]),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP);
        }
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        int code = -1;
        try {
            getTargetContext().startActivity(new Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            Thread.sleep(2000);
            for (int i = 0; i < days.length; i++) {
                show(i);
                Bundle status = new Bundle();
                status.putString("stream", days[i] + " (5 seconds)\n");
                sendStatus(0, status);
                Thread.sleep(5000);
            }
            result.putString("stream", "Finished; restored today's icon.\n");
        } catch (Exception error) {
            code = 0;
            result.putString("stream", error.toString());
        } finally {
            show((Calendar.getInstance().get(Calendar.DAY_OF_WEEK) + 5) % 7);
            finish(code, result);
        }
    }
}
