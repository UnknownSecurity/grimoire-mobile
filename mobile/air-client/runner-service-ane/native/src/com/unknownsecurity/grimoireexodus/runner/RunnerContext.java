package com.unknownsecurity.grimoireexodus.runner;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import com.adobe.fre.FREContext;
import com.adobe.fre.FREFunction;
import com.adobe.fre.FREObject;

import java.util.HashMap;
import java.util.Map;

public final class RunnerContext extends FREContext {
    private static final int NOTIFICATION_PERMISSION_REQUEST = 7314;
    private static final String NATIVE_PREFERENCES = "grimoire_runner_native";
    private static final String PERMISSION_REQUESTED = "notificationPermissionRequested";

    @Override
    public Map<String, FREFunction> getFunctions() {
        Map<String, FREFunction> functions = new HashMap<String, FREFunction>();
        functions.put("configure", new ConfigureFunction());
        functions.put("updateStatus", new UpdateStatusFunction());
        functions.put("openBatterySettings", new OpenBatterySettingsFunction());
        return functions;
    }

    @Override
    public void dispose() {
    }

    private static final class ConfigureFunction implements FREFunction {
        @Override
        public FREObject call(FREContext context, FREObject[] arguments) {
            boolean configured = false;
            try {
                boolean enabled = booleanAt(arguments, 0, false);
                boolean notifyStops = booleanAt(arguments, 1, true);
                boolean keepCpuAwake = booleanAt(arguments, 2, false);
                String state = stringAt(arguments, 3, RunnerForegroundService.STATE_IDLE);
                Activity activity = context.getActivity();
                Intent intent = RunnerForegroundService.intentFor(activity, state,
                    notifyStops, keepCpuAwake);
                if (enabled) {
                    requestNotificationPermission(activity);
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        activity.startForegroundService(intent);
                    } else {
                        activity.startService(intent);
                    }
                } else {
                    activity.stopService(intent);
                }
                configured = true;
            } catch (Throwable ignored) {
            }
            return result(configured);
        }
    }

    private static final class UpdateStatusFunction implements FREFunction {
        @Override
        public FREObject call(FREContext context, FREObject[] arguments) {
            boolean updated = false;
            try {
                String state = stringAt(arguments, 0, RunnerForegroundService.STATE_IDLE);
                boolean notifyStops = booleanAt(arguments, 1, true);
                boolean keepCpuAwake = booleanAt(arguments, 2, false);
                updated = RunnerForegroundService.updateFromExtension(state,
                    notifyStops, keepCpuAwake);
            } catch (Throwable ignored) {
            }
            return result(updated);
        }
    }

    private static final class OpenBatterySettingsFunction implements FREFunction {
        @Override
        public FREObject call(FREContext context, FREObject[] arguments) {
            boolean opened = false;
            try {
                Activity activity = context.getActivity();
                Intent intent = new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
                if (intent.resolveActivity(activity.getPackageManager()) == null) {
                    intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:" + activity.getPackageName()));
                }
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                activity.startActivity(intent);
                opened = true;
            } catch (Throwable ignored) {
            }
            return result(opened);
        }
    }

    private static void requestNotificationPermission(Activity activity) {
        if (Build.VERSION.SDK_INT >= 33
            && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            SharedPreferences preferences = activity.getSharedPreferences(NATIVE_PREFERENCES,
                Activity.MODE_PRIVATE);
            if (preferences.getBoolean(PERMISSION_REQUESTED, false)) {
                return;
            }
            preferences.edit().putBoolean(PERMISSION_REQUESTED, true).apply();
            activity.requestPermissions(
                new String[] { Manifest.permission.POST_NOTIFICATIONS },
                NOTIFICATION_PERMISSION_REQUEST);
        }
    }

    private static boolean booleanAt(FREObject[] arguments, int index, boolean fallback) {
        try {
            return arguments != null && index < arguments.length && arguments[index] != null
                ? arguments[index].getAsBool() : fallback;
        } catch (Throwable ignored) {
            return fallback;
        }
    }

    private static String stringAt(FREObject[] arguments, int index, String fallback) {
        try {
            return arguments != null && index < arguments.length && arguments[index] != null
                ? arguments[index].getAsString() : fallback;
        } catch (Throwable ignored) {
            return fallback;
        }
    }

    private static FREObject result(boolean value) {
        try {
            return FREObject.newObject(value);
        } catch (Throwable ignored) {
            return null;
        }
    }
}
