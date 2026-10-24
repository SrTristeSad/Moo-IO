package org.love2d.android;

import android.os.Bundle;
import android.util.Log;
import java.security.SecureRandom;
import java.io.FileOutputStream;
import java.io.File;

/** LÖVE game window. Hosting only starts after the player creates a room. */
public final class MooIOActivity extends GameActivity {
    private MooIOHostControl control;
    private MooIOTlsBridge tlsBridge;

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            control = new MooIOHostControl(this);
        } catch (java.io.IOException e) {
            Log.e("MooIO-Host", "Could not initialize local room controller", e);
        }
        // Verified TLS tunnel uses Android's own CA trust store; no Node
        // foreground server and no notification are needed just to JOIN.
        try {
            byte[] bytes=new byte[24];
            new SecureRandom().nextBytes(bytes);
            StringBuilder secret=new StringBuilder(48);
            for(byte b:bytes)secret.append(String.format(java.util.Locale.US,"%02x",b&255));
            tlsBridge=new MooIOTlsBridge(secret.toString());
            try(FileOutputStream out=new FileOutputStream(
                  new File(getFilesDir(),"mooio-tls-token.txt"))){
                out.write(secret.toString().getBytes(java.nio.charset.StandardCharsets.US_ASCII));
            }
        }catch(java.io.IOException e){
            Log.e("MooIO-TLS","Secure transport not available",e);
            if(tlsBridge!=null){tlsBridge.close();tlsBridge=null;}
        }
        // No foreground Node process or ongoing notification in menus.
    }

    @Override protected void onDestroy() {
        if(tlsBridge!=null){tlsBridge.close();tlsBridge=null;}
        if (control != null) {
            control.close();
            control = null;
        } else {
            stopService(new android.content.Intent(this, MooIOServerService.class));
        }
        super.onDestroy();
    }
}
