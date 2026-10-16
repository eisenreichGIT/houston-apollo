package io.github.eisenreichgit.houston;

import org.json.JSONObject;

import java.text.NumberFormat;
import java.util.Currency;
import java.util.Locale;

/** What the widget and tile show. Built from Houston's /api/v1/status (or /api/glance) and /api/price. */
final class Status {
    String state;        // online, offline, pending, unreachable, error, null
    double ths = -1;     // TH/s
    double watts = -1;
    String mode;         // eco, whisper, custom:14, ...
    String chassis;
    double price = -1;
    String fiat = "USD";
    double change = Double.NaN;
    long time;

    static Status from(JSONObject s, JSONObject p) {
        Status x = new Status();
        x.state = s.optString("status", null);
        if (!s.isNull("ghs")) x.ths = s.optDouble("ghs", -1000) / 1000;
        if (!s.isNull("watts")) x.watts = s.optDouble("watts", -1);
        x.mode = s.isNull("mode") ? null : s.optString("mode", null);
        x.chassis = s.isNull("chassis") ? null : s.optString("chassis", null);
        x.time = System.currentTimeMillis();
        if (p != null && p.optBoolean("enabled", false) && !p.isNull("price")) {
            x.price = p.optDouble("price", -1);
            x.fiat = p.optString("fiat", "USD");
            if (!p.isNull("change")) x.change = p.optDouble("change", Double.NaN);
            else if (!p.isNull("change24")) x.change = p.optDouble("change24", Double.NaN);
        }
        return x;
    }

    JSONObject toJson() {
        JSONObject o = new JSONObject();
        try {
            o.put("state", state); o.put("ths", ths); o.put("watts", watts); o.put("mode", mode); o.put("chassis", chassis);
            o.put("price", price); o.put("fiat", fiat); o.put("change", Double.isNaN(change) ? JSONObject.NULL : change); o.put("time", time);
        } catch (Exception ignored) { }
        return o;
    }

    static Status fromJson(String json) {
        if (json == null) return null;
        try {
            JSONObject o = new JSONObject(json);
            Status x = new Status();
            x.state = o.isNull("state") ? null : o.optString("state", null);
            x.ths = o.optDouble("ths", -1); x.watts = o.optDouble("watts", -1);
            x.mode = o.isNull("mode") ? null : o.optString("mode", null);
            x.chassis = o.isNull("chassis") ? null : o.optString("chassis", null);
            x.price = o.optDouble("price", -1); x.fiat = o.optString("fiat", "USD");
            x.change = o.isNull("change") ? Double.NaN : o.optDouble("change", Double.NaN);
            x.time = o.optLong("time", 0);
            return x;
        } catch (Exception e) {
            return null;
        }
    }

    boolean iii() { return "apollo-iii".equals(chassis); }

    static String modeName(String m) {
        if (m == null) return "";
        if (m.startsWith("custom:")) return m.substring(7) + " TH/s";
        switch (m) {
            case "super_eco": return "Super Eco";
            case "whisper": return "Whisper";
            case "eco": return "Eco";
            case "balanced": return "Balanced";
            case "turbo": return "Turbo";
            case "custom": return "Custom";
            default: return m;
        }
    }

    String stateText() {
        if (state == null) return "Waiting for Houston";
        switch (state) {
            case "online": return "Mining";
            case "offline": return "Stopped";
            case "pending": return "Starting";
            case "unreachable": return "Can't reach the Apollo";
            default: return state;
        }
    }

    int stateColor() {
        if ("online".equals(state)) return 0xFF3DBA74;
        if ("pending".equals(state)) return 0xFFE2C541;
        if (state == null) return 0xFF6E6A60;
        return 0xFFE5484D;
    }

    String priceText() {
        if (price < 0) return "₿ –";
        try {
            NumberFormat f = NumberFormat.getCurrencyInstance(Locale.getDefault());
            f.setCurrency(Currency.getInstance(fiat));
            f.setMaximumFractionDigits(0);
            f.setMinimumFractionDigits(0);
            return f.format(price);
        } catch (Exception e) {
            return Math.round(price) + " " + fiat;
        }
    }

    String changeText() {
        if (Double.isNaN(change)) return "";
        return (change >= 0 ? "▲ +" : "▼ −") + String.format(Locale.US, "%.2f%%", Math.abs(change));
    }

    String hashText() { return ths >= 0 && "online".equals(state) ? String.format(Locale.US, "%.2f", ths) : ("offline".equals(state) ? "0.00" : "–"); }

    String summary() {
        StringBuilder b = new StringBuilder(stateText());
        if (mode != null && !mode.isEmpty()) b.append(" · ").append(modeName(mode));
        if ("online".equals(state) && ths >= 0) b.append(" · ").append(hashText()).append(" TH/s");
        return b.toString();
    }
}
