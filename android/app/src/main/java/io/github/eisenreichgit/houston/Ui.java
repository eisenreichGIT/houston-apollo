package io.github.eisenreichgit.houston;

import android.content.Context;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Small helpers for the app's two native screens (setup and settings), in Houston's colors. */
final class Ui {
    static final int BG = 0xFF0F100D, CARD = 0xFF151612, LINE = 0xFF2B2B26, TEXT = 0xFFEEEAE0, MUTED = 0xFF9A968B, BTC = 0xFFF7931A;

    static int dp(Context c, float v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, c.getResources().getDisplayMetrics());
    }

    static LinearLayout column(Context c) {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.VERTICAL);
        int p = dp(c, 20);
        l.setPadding(p, dp(c, 28), p, p);
        l.setBackgroundColor(BG);
        return l;
    }

    static TextView text(Context c, String s, float sp, int color, boolean bold) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setPadding(0, dp(c, 6), 0, dp(c, 6));
        return t;
    }

    static Button button(Context c, String s, boolean primary) {
        Button b = new Button(c);
        b.setText(s);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        b.setTextColor(primary ? BG : TEXT);
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(dp(c, 10));
        g.setColor(primary ? TEXT : CARD);
        g.setStroke(dp(c, 1), primary ? TEXT : LINE);
        b.setBackground(g);
        b.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(c, 50));
        lp.topMargin = dp(c, 10);
        b.setLayoutParams(lp);
        return b;
    }

    static GradientDrawable field(Context c) {
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(dp(c, 10));
        g.setColor(0xFF191A16);
        g.setStroke(dp(c, 1), LINE);
        return g;
    }
}
