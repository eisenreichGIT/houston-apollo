package io.github.eisenreichgit.houston;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

/** The app's own settings: Houston's address, notifications, and the widget/tile pairing. */
public class SettingsActivity extends Activity {
    private Prefs prefs;
    private TextView pairText;
    private Button pairBtn;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = new Prefs(this);
        LinearLayout col = Ui.column(this);
        col.addView(Ui.text(this, "Houston app", 26, Ui.TEXT, true));

        col.addView(Ui.text(this, "Houston address", 13, Ui.MUTED, false));
        col.addView(Ui.text(this, String.valueOf(prefs.base()), 17, Ui.TEXT, false));
        Button change = Ui.button(this, "Change address", false);
        change.setOnClickListener(v -> startActivity(new Intent(this, SetupActivity.class)));
        col.addView(change);

        col.addView(Ui.text(this, " ", 8, Ui.MUTED, false));
        col.addView(Ui.text(this, "Widget, quick tile and notifications", 13, Ui.MUTED, false));
        pairText = Ui.text(this, "", 15, Ui.TEXT, false);
        col.addView(pairText);
        pairBtn = Ui.button(this, "", false);
        pairBtn.setOnClickListener(v -> togglePair());
        col.addView(pairBtn);

        Switch alerts = new Switch(this);
        alerts.setText("Show Houston's alerts as notifications");
        alerts.setTextColor(Ui.TEXT);
        alerts.setTextSize(16);
        alerts.setChecked(prefs.alerts());
        alerts.setPadding(0, Ui.dp(this, 16), 0, Ui.dp(this, 8));
        alerts.setOnCheckedChangeListener((v, on) -> {
            prefs.alerts(on);
            if (on && Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
                requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 7);
        });
        col.addView(alerts);
        col.addView(Ui.text(this, "Android lets the app check at most every 15 minutes, so alerts can arrive up to 15 minutes late, and only when "
                + "this phone can reach your Apollo (home Wi-Fi, or Tailscale when away). For instant alerts anywhere, also use the ntfy app (Houston › Settings › Alerts).", 13, Ui.MUTED, false));
        Button test = Ui.button(this, "Show a test notification", false);
        test.setOnClickListener(v -> {
            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 7);
                return;
            }
            Alerts.show(this, 1, "Houston test", "Alerts from your Apollo will look like this.");
        });
        col.addView(test);

        col.addView(Ui.text(this, " ", 8, Ui.MUTED, false));
        Button guide = Ui.button(this, "How the app works (guide)", false);
        guide.setOnClickListener(v -> startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/eisenreichGIT/houston-apollo/blob/main/docs/apps.md"))));
        col.addView(guide);
        col.addView(Ui.text(this, "Houston app " + BuildConfigLite.VERSION + " · unofficial, not affiliated with FutureBit", 12, 0xFF6E6A60, false));

        ScrollView sv = new ScrollView(this);
        sv.setBackgroundColor(Ui.BG);
        sv.addView(col);
        setContentView(sv);
        render();
    }

    private void render() {
        boolean on = prefs.key() != null;
        pairText.setText(on ? "On. Add the widget from your home screen (long-press › Widgets › Houston) and the Apollo tile from quick settings (edit tiles)."
                : "Off. Turn on to use the widget, quick tile and notifications. Sign in to Houston first.");
        pairBtn.setText(on ? "Turn off" : "Turn on");
    }

    private void togglePair() {
        if (prefs.key() != null) {
            new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                    .setTitle("Turn off the widget, tile and notifications?")
                    .setMessage("The app forgets Houston's shortcut key. (The key stays valid in Houston for Siri and other shortcuts; make a new one there to revoke it.)")
                    .setPositiveButton("Turn off", (d, w) -> {
                        prefs.key(null);
                        CheckJob.cancel(this);
                        HoustonWidget.draw(this, null, "Open Houston to turn the widget on");
                        render();
                    })
                    .setNegativeButton("Cancel", null)
                    .show();
        } else {
            prefs.askedForKey(false);
            Toast.makeText(this, "Back in Houston, tap Turn on when asked.", Toast.LENGTH_LONG).show();
            finish();
        }
    }

    @Override
    protected void onResume() { super.onResume(); render(); }
}
