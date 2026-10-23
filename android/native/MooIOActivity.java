package org.love2d.android;

import android.os.Bundle;
import android.util.Log;

/** LÖVE game window. Hosting only starts after the player creates a room. */
public final class MooIOActivity extends GameActivity {
    private MooIOHostControl control;

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            control = new MooIOHostControl(this);
        } catch (java.io.IOException e) {
            Log.e("MooIO-Host", "Could not initialize local room controller", e);
        }
        // No foreground Node process or ongoing notification in menus.
    }

    @Override protected void onDestroy() {
        if (control != null) {
            control.close();
            control = null;
        } else {
            stopService(new android.content.Intent(this, MooIOServerService.class));
        }
        super.onDestroy();
    }
}
