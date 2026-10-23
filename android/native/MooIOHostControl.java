package org.love2d.android;

import android.content.Intent;
import android.os.Build;
import android.util.Log;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.security.SecureRandom;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

/**
 * App-private lifecycle channel for the embedded Node host.
 *
 * Node is NEVER started when merely opening the game. Only the Lua create-room
 * action calls /start. Leaving a room calls /stop; closing the Activity also
 * stops the foreground service. Bound strictly to loopback, no LAN control API.
 */
public final class MooIOHostControl implements AutoCloseable {
    private static final String TAG = "MooIO-HostControl";
    private final MooIOActivity activity;
    private final ServerSocket listener;
    private final Thread thread;
    private volatile boolean closed = false;
    private volatile boolean roomRequested = false;
    private final String token;

    public MooIOHostControl(MooIOActivity activity) throws IOException {
        this.activity = activity;
        byte[] secret = new byte[24];
        new SecureRandom().nextBytes(secret);
        StringBuilder text = new StringBuilder(secret.length * 2);
        for (byte b : secret) text.append(String.format(java.util.Locale.US, "%02x", b & 255));
        token = text.toString();
        try (FileOutputStream output = new FileOutputStream(
                new File(activity.getFilesDir(), "mooio-control-token.txt"))) {
            output.write(token.getBytes(StandardCharsets.US_ASCII));
        }
        this.listener = new ServerSocket(8082, 4, InetAddress.getByName("127.0.0.1"));
        thread = new Thread(this::serve, "MooIO-HostControl");
        thread.setDaemon(true);
        thread.start();
    }

    private void serve() {
        while (!closed) {
            try (Socket client = listener.accept()) {
                client.setSoTimeout(1300);
                if (!client.getInetAddress().isLoopbackAddress()) continue;
                BufferedReader input = new BufferedReader(
                    new InputStreamReader(client.getInputStream(), StandardCharsets.US_ASCII));
                String request = input.readLine();
                if (request == null || request.length() > 256) continue;
                // Secret resides in the app-private sandbox and is never
                // exposed by the control API. Other Android apps cannot toggle
                // our local room merely by opening loopback TCP connections.
                String startPrefix = "GET /start/" + token + "/";
                int botCount = 0;
                String path = "";
                if (request.startsWith(startPrefix)) {
                    int space = request.indexOf(' ', startPrefix.length());
                    String count = space > startPrefix.length()
                        ? request.substring(startPrefix.length(), space) : "";
                    if (count.matches("[0-8]")) {
                        path = "/start";
                        botCount = Integer.parseInt(count);
                    }
                } else if (request.startsWith("GET /stop/" + token + " ")) {
                    path = "/stop";
                } else if (request.startsWith("GET /status/" + token + " ")) {
                    path = "/status";
                }
                int code = 200;
                String body;
                if ("/start".equals(path)) {
                    try {
                        Intent intent = new Intent(activity, MooIOServerService.class);
                        intent.putExtra("mooio.bot_count", botCount);
                        if (Build.VERSION.SDK_INT >= 26)
                            activity.startForegroundService(intent);
                        else activity.startService(intent);
                        roomRequested = true;
                        body = "started";
                    } catch (RuntimeException e) {
                        Log.e(TAG, "Cannot start offline server", e);
                        roomRequested = false;
                        code = 503;
                        body = "start_failed";
                    }
                } else if ("/stop".equals(path)) {
                    roomRequested = false;
                    activity.stopService(new Intent(activity, MooIOServerService.class));
                    body = "stopped";
                } else if ("/status".equals(path)) {
                    body = roomRequested ? "hosting" : "idle";
                } else {
                    code = 404;
                    body = "not_found";
                }
                byte[] bytes = body.getBytes(StandardCharsets.US_ASCII);
                String response = "HTTP/1.1 " + code + (code == 200 ? " OK" : " Error")
                    + "\r\nContent-Type: text/plain\r\nContent-Length: " + bytes.length
                    + "\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n";
                OutputStream out = client.getOutputStream();
                out.write(response.getBytes(StandardCharsets.US_ASCII));
                out.write(bytes);
                out.flush();
            } catch (IOException e) {
                if (!closed) Log.w(TAG, "Lifecycle control socket error", e);
            }
        }
    }

    @Override public void close() {
        if (closed) return;
        closed = true;
        roomRequested = false;
        try { listener.close(); } catch (IOException ignored) {}
        activity.stopService(new Intent(activity, MooIOServerService.class));
    }
}
