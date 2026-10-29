package com.unknownsecurity.grimoireexodus.runner;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.IBinder;
import android.os.PowerManager;

public final class RunnerForegroundService extends Service {
    public static final String STATE_IDLE = "idle";
    public static final String STATE_RUNNING = "running";
    public static final String STATE_PAUSED = "paused";
    public static final String STATE_STOPPED = "stopped";
    public static final String STATE_ERROR = "error";

    private static final String EXTRA_STATE = "runnerState";
    private static final String EXTRA_NOTIFY_STOPS = "notifyStops";
    private static final String EXTRA_KEEP_CPU_AWAKE = "keepCpuAwake";
    private static final String STATUS_CHANNEL = "grimoire_runner_status";
    private static final String ALERT_CHANNEL = "grimoire_runner_alerts";
    private static final int STATUS_NOTIFICATION_ID = 4170;
    private static final int STOP_NOTIFICATION_ID = 4171;

    private static volatile RunnerForegroundService activeService;

    private NotificationManager notificationManager;
    private PowerManager.WakeLock wakeLock;
    private String currentState = STATE_IDLE;
    private boolean notifyStops = true;
    private boolean keepCpuAwake;

    public static Intent intentFor(Context context, String state, boolean notifyStops,
            boolean keepCpuAwake) {
        Intent intent = new Intent(context, RunnerForegroundService.class);
        intent.putExtra(EXTRA_STATE, normalizeState(state));
        intent.putExtra(EXTRA_NOTIFY_STOPS, notifyStops);
        intent.putExtra(EXTRA_KEEP_CPU_AWAKE, keepCpuAwake);
        return intent;
    }

    public static boolean updateFromExtension(String state, boolean notifyStops,
            boolean keepCpuAwake) {
        RunnerForegroundService service = activeService;
        if (service == null) {
            return false;
        }
        service.applyState(normalizeState(state), notifyStops, keepCpuAwake, true);
        return true;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        activeService = this;
        notificationManager = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        createChannels();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String state = intent == null ? STATE_IDLE
            : normalizeState(intent.getStringExtra(EXTRA_STATE));
        boolean nextNotifyStops = intent == null ||
            intent.getBooleanExtra(EXTRA_NOTIFY_STOPS, true);
        boolean nextKeepCpuAwake = intent != null &&
            intent.getBooleanExtra(EXTRA_KEEP_CPU_AWAKE, false);
        currentState = state;
        notifyStops = nextNotifyStops;
        keepCpuAwake = nextKeepCpuAwake;
        startForeground(STATUS_NOTIFICATION_ID, buildStatusNotification());
        updateWakeLock();
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        if (activeService == this) {
            activeService = null;
        }
        releaseWakeLock();
        stopForeground(STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private synchronized void applyState(String state, boolean nextNotifyStops,
            boolean nextKeepCpuAwake, boolean allowStopAlert) {
        String previous = currentState;
        currentState = normalizeState(state);
        notifyStops = nextNotifyStops;
        keepCpuAwake = nextKeepCpuAwake;
        updateWakeLock();
        notificationManager.notify(STATUS_NOTIFICATION_ID, buildStatusNotification());
        if (allowStopAlert && notifyStops && isActive(previous)
            && (STATE_STOPPED.equals(currentState) || STATE_ERROR.equals(currentState))) {
            notificationManager.notify(STOP_NOTIFICATION_ID, buildStopNotification());
        }
    }

    private void createChannels() {
        NotificationChannel status = new NotificationChannel(STATUS_CHANNEL,
            "Grimoire Runner status", NotificationManager.IMPORTANCE_LOW);
        status.setDescription("Shows whether the mobile Runner is active.");
        status.setShowBadge(false);
        notificationManager.createNotificationChannel(status);

        NotificationChannel alerts = new NotificationChannel(ALERT_CHANNEL,
            "Grimoire Runner notices", NotificationManager.IMPORTANCE_DEFAULT);
        alerts.setDescription("Optional notices when an active run stops.");
        notificationManager.createNotificationChannel(alerts);
    }

    private Notification buildStatusNotification() {
        return new Notification.Builder(this, STATUS_CHANNEL)
            .setSmallIcon(smallIcon())
            .setContentTitle("Grimoire Runner")
            .setContentText(statusText(currentState))
            .setContentIntent(openApplicationIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build();
    }

    private Notification buildStopNotification() {
        return new Notification.Builder(this, ALERT_CHANNEL)
            .setSmallIcon(smallIcon())
            .setContentTitle("Grimoire Runner")
            .setContentText(STATE_ERROR.equals(currentState)
                ? "The active run stopped after an error."
                : "The active run has stopped.")
            .setContentIntent(openApplicationIntent())
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build();
    }

    private PendingIntent openApplicationIntent() {
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launch == null) {
            launch = new Intent();
        }
        launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(this, 0, launch,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private int smallIcon() {
        int icon = getApplicationInfo().icon;
        return icon == 0 ? android.R.drawable.stat_notify_sync_noanim : icon;
    }

    private void updateWakeLock() {
        boolean shouldHold = keepCpuAwake && STATE_RUNNING.equals(currentState);
        if (shouldHold) {
            if (wakeLock == null) {
                PowerManager manager = (PowerManager) getSystemService(Context.POWER_SERVICE);
                wakeLock = manager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,
                    "GrimoireExodus:Runner");
                wakeLock.setReferenceCounted(false);
            }
            if (!wakeLock.isHeld()) {
                wakeLock.acquire();
            }
        } else {
            releaseWakeLock();
        }
    }

    private void releaseWakeLock() {
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
    }

    private static boolean isActive(String state) {
        return STATE_RUNNING.equals(state) || STATE_PAUSED.equals(state);
    }

    private static String normalizeState(String state) {
        if (STATE_RUNNING.equals(state) || STATE_PAUSED.equals(state)
            || STATE_STOPPED.equals(state) || STATE_ERROR.equals(state)) {
            return state;
        }
        return STATE_IDLE;
    }

    private static String statusText(String state) {
        if (STATE_RUNNING.equals(state)) {
            return "Bot is running in the background";
        }
        if (STATE_PAUSED.equals(state)) {
            return "Bot is paused";
        }
        if (STATE_ERROR.equals(state)) {
            return "Bot stopped after an error";
        }
        if (STATE_STOPPED.equals(state)) {
            return "Bot has stopped";
        }
        return "Runner ready";
    }
}
