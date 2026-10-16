package io.github.eisenreichgit.houston;

import android.app.AlertDialog;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.widget.Toast;

/** Quick-settings tile: shows the miner's status; tap for Start, Stop and the power modes. */
public class StatusTile extends TileService {
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onStartListening() {
        Status cached = Status.fromJson(new Prefs(this).lastStatus());
        paint(cached);
        new Thread(() -> {
            Status s = HoustonWidget.fetchAndDraw(getApplicationContext());
            if (s != null) main.post(() -> paint(s));
        }).start();
    }

    private void paint(Status s) {
        Tile t = getQsTile();
        if (t == null) return;
        t.setLabel("Apollo");
        t.setState(s != null && "online".equals(s.state) ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        if (Build.VERSION.SDK_INT >= 29) t.setSubtitle(s == null ? "Houston" : s.summary().replaceFirst("^Mining · ", ""));
        t.updateTile();
    }

    @Override
    public void onClick() {
        Prefs prefs = new Prefs(this);
        if (prefs.key() == null) {
            Toast.makeText(this, "Open Houston and turn on the widget and tile in the app's settings", Toast.LENGTH_LONG).show();
            return;
        }
        unlockAndRun(this::choose);
    }

    private void choose() {
        Status s = Status.fromJson(new Prefs(this).lastStatus());
        boolean iii = s != null && s.iii();
        final String[] actions = iii
                ? new String[]{"start", "stop", "super_eco", "eco", "balanced", "turbo"}
                : new String[]{"start", "stop", "whisper", "eco", "balanced", "turbo"};
        final String[] labels = iii
                ? new String[]{"Start mining", "Stop mining", "Super Eco", "Eco", "Balanced", "Turbo"}
                : new String[]{"Start mining", "Stop mining", "Whisper (quietest)", "Eco", "Balanced", "Turbo"};
        AlertDialog d = new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle(s == null ? "Apollo" : s.summary())
                .setItems(labels, (dlg, which) -> run(actions[which]))
                .setNegativeButton("Cancel", null)
                .create();
        showDialog(d);
    }

    private void run(String action) {
        Api api = Api.of(new Prefs(this));
        if (api == null) return;
        new Thread(() -> {
            String msg;
            try { msg = api.action(action); } catch (Exception e) { msg = e.getMessage() != null ? e.getMessage() : "Can't reach Houston"; }
            final String m = msg;
            main.post(() -> Toast.makeText(getApplicationContext(), m, Toast.LENGTH_LONG).show());
        }).start();
    }
}
