package org.love2d.android;

import android.content.Intent;
import android.os.Bundle;
import android.os.Build;
import android.util.Log;

/** Game renderer stays in the LÖVE process; Node runs in a separate app process. */
public final class MooIOActivity extends GameActivity {
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            Intent server=new Intent(this,MooIOServerService.class);
            if(Build.VERSION.SDK_INT>=26) startForegroundService(server);
            else startService(server);
        } catch(Throwable failure) {
            Log.e("MooIO-Host","Unable to start Node host service",failure);
        }
    }
}
