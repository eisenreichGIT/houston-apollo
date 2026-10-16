package io.github.eisenreichgit.houston;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.text.format.DateFormat;
import android.widget.RemoteViews;

import java.util.Date;

/** Home-screen widget: bitcoin price, miner status, hashrate and mode. Refreshes every 15 minutes and on tap. */
public class HoustonWidget extends AppWidgetProvider {
    static final String REFRESH = "io.github.eisenreichgit.houston.REFRESH";

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        draw(context, Status.fromJson(new Prefs(context).lastStatus()), null);
        refreshAsync(context, goAsync());
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (REFRESH.equals(intent.getAction())) {
            draw(context, Status.fromJson(new Prefs(context).lastStatus()), "Updating…");
            refreshAsync(context, goAsync());
        }
    }

    @Override
    public void onEnabled(Context context) { CheckJob.schedule(context); }

    private static void refreshAsync(Context context, PendingResult done) {
        final Context app = context.getApplicationContext();
        new Thread(() -> {
            try { fetchAndDraw(app); } finally { if (done != null) done.finish(); }
        }).start();
    }

    /** Fetches the status and redraws every widget. Call from a background thread. */
    static Status fetchAndDraw(Context context) {
        Prefs prefs = new Prefs(context);
        Api api = Api.of(prefs);
        if (api == null) { draw(context, null, "Open Houston to set it up"); return null; }
        try {
            Status s = api.status();
            prefs.lastStatus(s.toJson().toString());
            draw(context, s, null);
            return s;
        } catch (Exception e) {
            draw(context, Status.fromJson(prefs.lastStatus()), "Can't reach Houston (home Wi-Fi or Tailscale?)");
            return null;
        }
    }

    static void draw(Context context, Status s, String note) {
        AppWidgetManager m = AppWidgetManager.getInstance(context);
        int[] ids = m.getAppWidgetIds(new ComponentName(context, HoustonWidget.class));
        if (ids == null || ids.length == 0) return;
        RemoteViews v = new RemoteViews(context.getPackageName(), R.layout.widget);
        if (s != null) {
            v.setTextViewText(R.id.w_price, s.priceText());
            v.setTextViewText(R.id.w_change, s.changeText());
            v.setTextColor(R.id.w_change, Double.isNaN(s.change) ? 0xFF9A968B : s.change >= 0 ? 0xFF8BDDAE : 0xFFFF8F92);
            v.setTextViewText(R.id.w_hash, s.hashText());
            v.setTextViewText(R.id.w_mode, Status.modeName(s.mode));
            v.setInt(R.id.w_dot, "setColorFilter", s.stateColor());
            String when = s.time > 0 ? DateFormat.getTimeFormat(context).format(new Date(s.time)) : "";
            String watts = s.watts >= 0 && "online".equals(s.state) ? Math.round(s.watts) + " W · " : "";
            v.setTextViewText(R.id.w_meta, note != null ? note : s.stateText() + " · " + watts + "updated " + when);
        } else {
            v.setTextViewText(R.id.w_meta, note != null ? note : "Tap to open Houston");
        }
        Intent open = new Intent(context, MainActivity.class);
        v.setOnClickPendingIntent(R.id.w_root, PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE));
        Intent refresh = new Intent(context, HoustonWidget.class).setAction(REFRESH);
        v.setOnClickPendingIntent(R.id.w_refresh, PendingIntent.getBroadcast(context, 1, refresh, PendingIntent.FLAG_IMMUTABLE));
        m.updateAppWidget(ids, v);
    }
}
