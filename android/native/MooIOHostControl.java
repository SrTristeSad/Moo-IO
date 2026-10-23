package org.love2d.android;

import android.content.Intent;
import android.os.Build;
import android.util.Log;
import java.io.BufferedReader;
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

    public MooIOHostControl(MooIOActivity activity) throws IOException {
        this.activity = activity;
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
                String path = request.startsWith("GET /start ") ? "/start"
                    : request.startsWith("GET /stop ") ? "/stop"
                    : request.startsWith("GET /status ") ? "/status" : "";
                int code = 200;
                String body;
                if ("/start".equals(path)) {
                    try {
                        Intent intent = new Intent(activity, MooIOServerService.class);
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
