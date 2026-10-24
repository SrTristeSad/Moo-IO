package org.love2d.android;

import android.util.Log;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.SNIHostName;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.Pattern;

/**
 * Private TCP -> Android platform TLS tunnel for LÖVE.
 * Uses Android's system trust store, hostname verification (HTTPS), SNI and
 * TLS 1.2+. Never accepts custom trust managers or bypasses peer validation.
 */
public final class MooIOTlsBridge implements AutoCloseable {
    private static final String TAG = "MooIO-TLS";
    private static final Pattern HOST=Pattern.compile(
      "^(?=.{4,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,24}$");
    private static final Pattern TOKEN=Pattern.compile("^[a-f0-9]{48}$");
    private final ServerSocket server;
    private final String token;
    private final Thread acceptThread;
    private final AtomicInteger active=new AtomicInteger();
    private volatile boolean closed;

    public MooIOTlsBridge(String secret) throws IOException {
        if(secret==null || !TOKEN.matcher(secret).matches())
            throw new IOException("Invalid TLS bridge secret");
        token=secret;
        server=new ServerSocket(8469,16,InetAddress.getByName("127.0.0.1"));
        acceptThread=new Thread(this::serve,"MooIO-TLS-Accept");
        acceptThread.setDaemon(true);
        acceptThread.start();
    }
    private void serve(){
        while(!closed){
            try{
                Socket client=server.accept();
                if(!client.getInetAddress().isLoopbackAddress()||active.incrementAndGet()>48){
                    active.decrementAndGet();client.close();continue;
                }
                Thread thread=new Thread(()->{
                    try{proxy(client);}catch(IOException e){
                        Log.d(TAG,"Secure connection refused");
                    }finally{
                        try{client.close();}catch(IOException ignored){}
                        active.decrementAndGet();
                    }
                },"MooIO-TLS-Connection");
                thread.setDaemon(true);thread.start();
            }catch(IOException e){
                if(!closed)Log.w(TAG,"Local TLS bridge stopped");
            }
        }
    }
    private static void pipe(InputStream source,OutputStream target) {
        byte[] buffer=new byte[16384];
        try{
            int size;
            while((size=source.read(buffer))!=-1){
                target.write(buffer,0,size);target.flush();
            }
        }catch(IOException ignored){}
    }
    private void proxy(Socket client) throws IOException {
        client.setSoTimeout(7000);
        InputStream src=client.getInputStream();
        ByteArrayOutputStream request=new ByteArrayOutputStream(360);
        int next;
        while(request.size()<360&&(next=src.read())!=-1){
            if(next==10)break;
            if(next<32&&next!=13)throw new IOException("Invalid preface");
            request.write(next);
        }
        if(request.size()>=360)throw new IOException("Preface too large");
        String preface=request.toString("US-ASCII").trim();
        String[] parts=preface.split(" ",-1);
        if(parts.length!=4||!"MOOIO-TLS1".equals(parts[0])||
          !token.equals(parts[1])||!HOST.matcher(parts[2]).matches()||
          !"443".equals(parts[3]))throw new IOException("Invalid TLS destination");
        SSLSocketFactory factory=(SSLSocketFactory)SSLSocketFactory.getDefault();
        try(SSLSocket tls=(SSLSocket)factory.createSocket(parts[2],443)){
            SSLParameters params=tls.getSSLParameters();
            params.setEndpointIdentificationAlgorithm("HTTPS");
            params.setServerNames(Collections.singletonList(new SNIHostName(parts[2])));
            tls.setSSLParameters(params);
            tls.setEnabledProtocols(new String[]{"TLSv1.3","TLSv1.2"});
            tls.setSoTimeout(7000);
            tls.startHandshake(); // aborts for unknown CA, expired, mismatched hostname
            client.getOutputStream().write("OK\n".getBytes(StandardCharsets.US_ASCII));
            client.getOutputStream().flush();
            client.setSoTimeout(0);
            tls.setSoTimeout(0);
            Thread upstream=new Thread(()->pipe(src,outputOf(tls)),"MooIO-TLS-Uplink");
            upstream.setDaemon(true);upstream.start();
            pipe(tls.getInputStream(),client.getOutputStream());
            tls.close();
            try{client.shutdownOutput();}catch(SocketException ignored){}
        }
    }
    private static OutputStream outputOf(Socket socket){
        try{return socket.getOutputStream();}
        catch(IOException exception){return new ByteArrayOutputStream();}
    }
    @Override public void close(){
        closed=true;
        try{server.close();}catch(IOException ignored){}
    }
}
