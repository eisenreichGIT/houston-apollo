package io.github.eisenreichgit.houston;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/** Talks to Houston on the Apollo. Call from a background thread. */
final class Api {
    static final int TIMEOUT = 8000;
    private static final int MAX = 1024 * 1024;

    final String base;
    final String key;

    Api(String base, String key) { this.base = base; this.key = key; }

    static Api of(Prefs p) { return p.base() == null ? null : new Api(p.base(), p.key()); }

    /** "192.168.1.50" -> "http://192.168.1.50:8088"; keeps https://name (Houston's https address) as given. */
    static String normalize(String input) {
        String s = input == null ? "" : input.trim();
        while (s.endsWith("/")) s = s.substring(0, s.length() - 1);
        if (s.isEmpty()) return null;
        if (!s.startsWith("http://") && !s.startsWith("https://")) s = "http://" + s;
        String rest = s.substring(s.indexOf("://") + 3);
        if (rest.contains("/")) rest = rest.substring(0, rest.indexOf('/'));
        boolean hasPort = rest.startsWith("[") ? rest.contains("]:") : rest.contains(":");
        String scheme = s.substring(0, s.indexOf("://"));
        if (!hasPort && scheme.equals("http")) rest = rest + ":8088";
        return scheme + "://" + rest;
    }

    static final class Reply {
        final int code; final String body;
        Reply(int code, String body) { this.code = code; this.body = body; }
        JSONObject json() throws JSONException { return new JSONObject(body); }
        boolean ok() { return code >= 200 && code < 300; }
    }

    Reply get(String path, String bearer) throws IOException { return call("GET", path, null, bearer); }

    Reply call(String method, String path, String body, String bearer) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(base + path).openConnection();
        c.setConnectTimeout(TIMEOUT);
        c.setReadTimeout(method.equals("POST") ? 30000 : TIMEOUT);
        c.setInstanceFollowRedirects(false);
        c.setRequestMethod(method);
        c.setRequestProperty("Accept", "application/json");
        c.setRequestProperty("User-Agent", "HoustonApp/" + BuildConfigLite.VERSION + " (Android)");
        if (bearer != null) c.setRequestProperty("Authorization", "Bearer " + bearer);
        if (body != null || method.equals("POST")) {
            byte[] b = (body == null ? "" : body).getBytes(StandardCharsets.UTF_8);
            c.setDoOutput(true);
            c.setRequestProperty("Content-Type", "application/json");
            c.setFixedLengthStreamingMode(b.length);
            try (OutputStream o = c.getOutputStream()) { o.write(b); }
        }
        int code = c.getResponseCode();
        InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
        String text = "";
        if (in != null) {
            try (InputStream i = in) {
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                byte[] buf = new byte[8192];
                int n, total = 0;
                while ((n = i.read(buf)) > 0 && total < MAX) { out.write(buf, 0, n); total += n; }
                text = out.toString("UTF-8");
            }
        }
        c.disconnect();
        return new Reply(code, text);
    }

    /** Is there a Houston at this address? Returns its version, or throws with a readable message. */
    String check() throws IOException {
        Reply r = get("/api/device", null);
        if (!r.ok()) throw new IOException("Houston answered " + r.code + ". Is this the Apollo running Houston?");
        try {
            return r.json().getString("version");
        } catch (JSONException e) {
            throw new IOException("That address answers, but it isn't Houston.");
        }
    }

    /** Status for the widget and tile: with the key, Houston's full status (mode, price); otherwise the public readings. */
    Status status() throws IOException, JSONException {
        if (key != null) {
            Reply r = call("GET", "/api/v1/status", null, key);
            if (r.ok()) return Status.from(r.json(), price());
            if (r.code != 401) throw new IOException("Houston answered " + r.code);
        }
        Reply g = get("/api/glance", null);
        if (!g.ok()) throw new IOException("Houston answered " + g.code);
        return Status.from(g.json(), price());
    }

    private JSONObject price() {
        try {
            Reply r = get("/api/price?range=1D&points=0", null);
            return r.ok() ? r.json() : null;
        } catch (IOException | JSONException e) {
            return null;
        }
    }

    /** Runs a shortcut action (start, stop, whisper, eco, ...). Returns what Houston says. */
    String action(String name) throws IOException {
        if (key == null) throw new IOException("Open Houston once and turn on the widget and tile in the app's settings.");
        Reply r = call("POST", "/api/v1/action/" + name, null, key);
        if (r.code == 401) throw new IOException("Houston's shortcut key changed. Open the app to pair again.");
        return r.body.trim();
    }
}
