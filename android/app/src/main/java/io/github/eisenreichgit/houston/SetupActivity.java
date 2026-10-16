package io.github.eisenreichgit.houston;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.text.InputType;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** First launch: where is Houston? (the Apollo's address at home, or its Tailscale name). */
public class SetupActivity extends Activity {
    private EditText address;
    private TextView status;
    private Button go;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        LinearLayout col = Ui.column(this);
        ImageView logo = new ImageView(this);
        logo.setImageResource(R.mipmap.ic_launcher);
        col.addView(logo, new LinearLayout.LayoutParams(Ui.dp(this, 72), Ui.dp(this, 72)));
        col.addView(Ui.text(this, "Connect to your Apollo", 26, Ui.TEXT, true));
        col.addView(Ui.text(this, "Houston runs on your Apollo. Enter its address: the IP from your router (like 192.168.1.50), "
                + "or its Tailscale name to use the app away from home.", 15, Ui.MUTED, false));
        address = new EditText(this);
        address.setHint("192.168.1.50");
        address.setHintTextColor(0xFF6E6A60);
        address.setTextColor(Ui.TEXT);
        address.setSingleLine(true);
        address.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        address.setImeOptions(EditorInfo.IME_ACTION_GO);
        address.setBackground(Ui.field(this));
        int p = Ui.dp(this, 14);
        address.setPadding(p, p, p, p);
        String saved = new Prefs(this).base();
        if (saved != null) address.setText(saved.replace("http://", "").replace(":8088", ""));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        lp.topMargin = Ui.dp(this, 14);
        col.addView(address, lp);
        go = Ui.button(this, "Connect", true);
        col.addView(go);
        status = Ui.text(this, "", 14, Ui.MUTED, false);
        col.addView(status);
        col.addView(Ui.text(this, "Houston must be installed on the Apollo first (install-houston.sh). Away from home, turn on Tailscale on this phone.", 13, 0xFF6E6A60, false));
        go.setOnClickListener(v -> connect());
        address.setOnEditorActionListener((v, id, e) -> { connect(); return true; });
        ScrollView sv = new ScrollView(this);
        sv.setBackgroundColor(Ui.BG);
        sv.addView(col);
        setContentView(sv);
    }

    private void connect() {
        final String base = Api.normalize(address.getText().toString());
        if (base == null) { status.setText("Enter your Apollo's address."); return; }
        go.setEnabled(false);
        status.setTextColor(Ui.MUTED);
        status.setText("Looking for Houston at " + base + "…");
        new Thread(() -> {
            String err = null, ver = null;
            try { ver = new Api(base, null).check(); }
            catch (Exception e) { err = e.getMessage() == null ? "No answer." : e.getMessage(); }
            final String error = err, version = ver;
            runOnUiThread(() -> {
                go.setEnabled(true);
                if (error != null) {
                    status.setTextColor(0xFFFF8F92);
                    status.setText("Couldn't reach Houston at " + base + ". " + error
                            + " Check the address, that this phone is on your home Wi-Fi (or Tailscale), and that Houston is installed.");
                    return;
                }
                Prefs prefs = new Prefs(this);
                if (!base.equals(prefs.base())) { prefs.key(null); prefs.askedForKey(false); prefs.lastStatus(null); prefs.lastAlert(0); }
                prefs.base(base);
                status.setText("Found Houston " + version + ".");
                startActivity(new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP));
                finish();
            });
        }).start();
    }
}
