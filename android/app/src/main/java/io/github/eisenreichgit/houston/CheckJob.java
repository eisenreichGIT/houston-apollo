package io.github.eisenreichgit.houston;

import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;

/**
 * Every 15 minutes (Android's shortest background interval): refreshes the widget and turns new Houston alerts
 * into notifications. Needs the phone to reach the Apollo (home Wi-Fi, or Tailscale when away).
 */
public class CheckJob extends JobService {
    private static final int ID = 1001;

    static void schedule(Context context) {
        JobScheduler js = context.getSystemService(JobScheduler.class);
        if (js == null) return;
        JobInfo job = new JobInfo.Builder(ID, new ComponentName(context, CheckJob.class))
                .setPeriodic(15 * 60 * 1000L)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)
                .build();
        js.schedule(job);
    }

    static void cancel(Context context) {
        JobScheduler js = context.getSystemService(JobScheduler.class);
        if (js != null) js.cancel(ID);
    }

    @Override
    public boolean onStartJob(JobParameters params) {
        final Context app = getApplicationContext();
        new Thread(() -> {
            try {
                HoustonWidget.fetchAndDraw(app);
                Alerts.check(app);
            } finally {
                jobFinished(params, false);
            }
        }).start();
        return true;
    }

    @Override
    public boolean onStopJob(JobParameters params) { return true; }
}
