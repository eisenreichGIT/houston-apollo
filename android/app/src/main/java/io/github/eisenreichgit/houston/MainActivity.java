package io.github.eisenreichgit.houston;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import org.json.JSONObject;

/**
 * Houston itself, full screen: the same app as in the browser, served by your Apollo, so it's always the
 * Houston version installed there. The native parts (widget, tile, notifications) use Houston's shortcut key.
 */
public class MainActivity extends Activity {
    private WebView web;
    private Prefs prefs;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = new Prefs(this);
        if (prefs.base() == null) {
            startActivity(new Intent(this, SetupActivity.class));
            finish();
            return;
        }
        web = new WebView(this);
        web.setBackgroundColor(Ui.BG);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);          // Houston is a JavaScript app
        s.setDomStorageEnabled(true);          // it keeps your sign-in and preferences in local storage
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setUserAgentString(s.getUserAgentString() + " HoustonApp/" + BuildConfigLite.VERSION + " (Android)");
        web.addJavascriptInterface(new Bridge(), "HoustonAndroid");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri u = req.getUrl();
                Uri home = Uri.parse(prefs.base());
                if (home.getHost() != null && home.getHost().equals(u.getHost())) return false;
                try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (Exception ignored) { }
                return true;                   // other sites (news, GitHub, wallets) open outside the app
            }

            @Override
            public void onPageFinished(WebView view, String url) { maybePair(); }

            @Override
            public void onReceivedError(WebView view, android.webkit.WebResourceRequest req, android.webkit.WebResourceError err) {
                if (req.isForMainFrame()) showOffline();
            }
        });
        setContentView(web);
        if (b != null) web.restoreState(b); else web.loadUrl(prefs.base() + "/");
        Alerts.channel(this);
        if (prefs.key() != null) CheckJob.schedule(this);
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        if (web != null) web.saveState(out);
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) web.goBack(); else super.onBackPressed();
    }

    private void showOffline() {
        String base = prefs.base();
        String html = "<html><body style='background:#0F100D;color:#EEEAE0;font-family:sans-serif;padding:28px'>"
                + "<h2>Can't reach Houston</h2><p style='color:#9A968B'>Tried " + base.replace("<", "") + ". At home, check that this phone is on "
                + "your Wi-Fi; away from home, turn on Tailscale. Then pull down to retry, or change the address in the app's settings.</p>"
                + "<p><a style='color:#F7931A' href='" + base.replace("'", "") + "/'>Try again</a> &nbsp; "
                + "<a style='color:#F7931A' href='javascript:HoustonAndroid.openSettings()'>App settings</a></p></body></html>";
        web.loadDataWithBaseURL(base + "/", html, "text/html", "utf-8", base + "/");
    }

    /** After you sign in to Houston, offer to turn on the widget, tile and notifications (they use a shortcut key). */
    private void maybePair() {
        if (prefs.key() != null || prefs.askedForKey()) return;
        web.evaluateJavascript("(function(){try{return localStorage.getItem('apolloToken')}catch(e){return null}})()", v -> {
            String token = v == null || v.equals("null") ? null : v.replaceAll("^\"|\"$", "");
            if (token == null || token.isEmpty() || isFinishing()) return;
            prefs.askedForKey(true);
            new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                    .setTitle("Widget, quick tile and notifications?")
                    .setMessage("The Houston app can show your Apollo and the bitcoin price on your home screen, add an Apollo tile to quick settings, "
                            + "and turn Houston's alerts into notifications. This uses Houston's shortcut key (the same one Siri and shortcuts use).")
                    .setPositiveButton("Turn on", (d, w) -> pair(token))
                    .setNegativeButton("Not now", null)
                    .show();
        });
    }

    void pair(String token) {
        new Thread(() -> {
            String msg;
            try {
                Api api = new Api(prefs.base(), null);
                Api.Reply r = api.get("/api/automation", token);
                if (r.code == 401) throw new Exception("Please sign in to Houston again.");
                String key = r.json().isNull("key") ? null : r.json().optString("key", null);
                if (key == null) {
                    Api.Reply c = api.call("POST", "/api/automation", "{}", token);
                    key = new JSONObject(c.body).optString("key", null);
                }
                if (key == null) throw new Exception("Houston didn't give a key.");
                prefs.key(key);
                prefs.lastAlert(0);
                CheckJob.schedule(getApplicationContext());
                HoustonWidget.fetchAndDraw(getApplicationContext());
                Alerts.check(getApplicationContext());
                msg = "On. Add the Houston widget from your home screen, and the Apollo tile from quick settings.";
            } catch (Exception e) {
                msg = "Couldn't turn it on: " + e.getMessage();
            }
            final String m = msg;
            runOnUiThread(() -> {
                Toast.makeText(this, m, Toast.LENGTH_LONG).show();
                if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
                    requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 7);
            });
        }).start();
    }

    /** Lets the Houston page open the app's own settings ("App settings" in Houston › Settings). */
    final class Bridge {
        @JavascriptInterface
        public void openSettings() { runOnUiThread(() -> startActivity(new Intent(MainActivity.this, SettingsActivity.class))); }

        @JavascriptInterface
        public String version() { return BuildConfigLite.VERSION; }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (web != null && prefs.base() != null && web.getUrl() == null) web.loadUrl(prefs.base() + "/");
        if (web != null) maybePair();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        if (web != null && web.getVisibility() != View.VISIBLE) web.setVisibility(View.VISIBLE);
    }
}
