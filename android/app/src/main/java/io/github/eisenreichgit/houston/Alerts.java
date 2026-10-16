package io.github.eisenreichgit.houston;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONObject;

/** Asks Houston for alerts it sent since the last check and shows them as Android notifications. */
final class Alerts {
    static final String CHANNEL = "alerts";

    static void channel(Context c) {
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        if (nm == null || nm.getNotificationChannel(CHANNEL) != null) return;
        NotificationChannel ch = new NotificationChannel(CHANNEL, c.getString(R.string.channel_alerts), NotificationManager.IMPORTANCE_HIGH);
        ch.setDescription("When your Apollo stops, runs hot, loses hashrate, finds a block, or new Apollo software is out");
        nm.createNotificationChannel(ch);
    }

    /** Call from a background thread. */
    static void check(Context c) {
        Prefs prefs = new Prefs(c);
        Api api = Api.of(prefs);
        if (api == null || api.key == null || !prefs.alerts()) return;
        try {
            long since = prefs.lastAlert();
            Api.Reply r = api.call("GET", "/api/v1/alerts?since=" + since, null, api.key);
            if (!r.ok()) return;
            JSONObject j = r.json();
            long now = j.optLong("now", System.currentTimeMillis() / 1000);
            if (since == 0) { prefs.lastAlert(now); return; }      // first check: start from now, don't replay old alerts
            JSONArray list = j.optJSONArray("alerts");
            long last = since;
            if (list != null) {
                for (int i = 0; i < list.length(); i++) {
                    JSONObject a = list.getJSONObject(i);
                    show(c, (int) (a.optLong("t") % 100000), a.optString("title", "Houston"), a.optString("message", ""));
                    last = Math.max(last, a.optLong("t"));
                }
            }
            prefs.lastAlert(Math.max(last, since));
        } catch (Exception ignored) {
            // Not reachable right now (away without Tailscale, Apollo restarting): try again next time
        }
    }

    static void show(Context c, int id, String title, String text) {
        if (Build.VERSION.SDK_INT >= 33 && c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return;
        channel(c);
        Intent open = new Intent(c, MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        Notification n = new Notification.Builder(c, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat)
                .setContentTitle(title)
                .setContentText(text.isEmpty() ? null : text)
                .setStyle(new Notification.BigTextStyle().bigText(text))
                .setColor(0xFFF7931A)
                .setAutoCancel(true)
                .setContentIntent(PendingIntent.getActivity(c, 2, open, PendingIntent.FLAG_IMMUTABLE))
                .build();
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        if (nm != null) nm.notify(id, n);
    }
}
