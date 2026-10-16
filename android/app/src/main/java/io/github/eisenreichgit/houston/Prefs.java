package io.github.eisenreichgit.houston;

import android.content.Context;
import android.content.SharedPreferences;

/** App settings, private to this app: Houston's address, the shortcut key, alert bookkeeping. */
final class Prefs {
    private final SharedPreferences p;

    Prefs(Context c) { p = c.getApplicationContext().getSharedPreferences("houston", Context.MODE_PRIVATE); }

    String base() { return p.getString("base", null); }
    void base(String v) { p.edit().putString("base", v).apply(); }

    /** Houston's shortcut key (Settings › Siri, Google & shortcuts): lets the widget, tile and alerts work without the app open. */
    String key() { return p.getString("key", null); }
    void key(String v) { p.edit().putString("key", v).apply(); }

    boolean askedForKey() { return p.getBoolean("askedKey", false); }
    void askedForKey(boolean v) { p.edit().putBoolean("askedKey", v).apply(); }

    boolean alerts() { return p.getBoolean("alerts", true); }
    void alerts(boolean v) { p.edit().putBoolean("alerts", v).apply(); }

    long lastAlert() { return p.getLong("lastAlert", 0); }
    void lastAlert(long v) { p.edit().putLong("lastAlert", v).apply(); }

    String lastStatus() { return p.getString("lastStatus", null); }
    void lastStatus(String json) { p.edit().putString("lastStatus", json).apply(); }

    void forget() { p.edit().clear().apply(); }
}
