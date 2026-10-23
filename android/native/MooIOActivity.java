package org.love2d.android;
import android.os.Bundle;
import android.util.Log;
import java.io.*;
import java.net.*;
import java.security.SecureRandom;
import java.util.*;
import java.util.zip.*;

/** LÖVE renders game; an embedded Android/Bionic Node.js runs the real server. */
public final class MooIOActivity extends GameActivity {
    private static volatile boolean started=false;
    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        synchronized (MooIOActivity.class) {
            if (started) return;
            started=true;
        }
        new Thread(this::runServer,"MooIO-Node").start();
    }
    private void runServer() {
        try {
            File root=new File(getFilesDir(),"mooio-host");
            File data=new File(getFilesDir(),"mooio-data");
            if(!root.exists()&&!root.mkdirs())throw new IOException("Cannot create server dir");
            if(!data.exists()&&!data.mkdirs())throw new IOException("Cannot create data dir");
            File entry=new File(root,"server/src/offline.mjs");
            File version=new File(root,"server-version.txt");
            String revision="v"+getPackageManager().getPackageInfo(getPackageName(),0).versionCode;
            if(!entry.isFile()||!version.isFile()||!revision.equals(read(version).trim())) {
                unpack("mooio-server.zip",root);
                write(version,revision);
            }
            String code=getPreferences(MODE_PRIVATE).getString("room_code","");
            if(code.length()<8) {
                byte[] random=new byte[16];
                new SecureRandom().nextBytes(random);
                code=Base64.getUrlEncoder().withoutPadding().encodeToString(random).replace("_","-");
                getPreferences(MODE_PRIVATE).edit().putString("room_code",code).apply();
            }
            write(new File(root,"room-code.txt"),code);
            String ip=localIPv4();
            Log.i("MooIO-Host","Starting local Node.js host at "+ip+":8080");
            String[] args={"node",entry.getAbsolutePath()};
            String[] vars={"HOST="+ip,"PORT=8080","MOO_IO_ROOM_CODE="+code,
                "MOO_IO_NETWORK_MODE=lan","MOO_IO_GUI_HOST=1",
                "MOO_IO_BOT_COUNT=0","DATA_DIR="+data.getAbsolutePath(),
                "PROTOCOL_BUILD_FILE="+new File(data,"protocol-build.json").getAbsolutePath()};
            int exit=MooIONodeBridge.start(args,vars,root.getAbsolutePath());
            Log.e("MooIO-Host","Embedded Node exited: "+exit);
        } catch(Throwable ex) {
            Log.e("MooIO-Host","Host initialization error",ex);
        }
    }
    private static String localIPv4() throws SocketException {
        Enumeration<NetworkInterface> interfaces=NetworkInterface.getNetworkInterfaces();
        List<String> candidates=new ArrayList<>();
        while(interfaces.hasMoreElements()){
            NetworkInterface iface=interfaces.nextElement();
            if(!iface.isUp()||iface.isLoopback())continue;
            Enumeration<InetAddress> ips=iface.getInetAddresses();
            while(ips.hasMoreElements()){
                InetAddress ip=ips.nextElement();
                if(ip instanceof Inet4Address&&ip.isSiteLocalAddress())
                    candidates.add(ip.getHostAddress());
            }
        }
        for(String ip:candidates)if(ip.startsWith("192.168."))return ip;
        for(String ip:candidates)if(ip.startsWith("10."))return ip;
        for(String ip:candidates)if(ip.startsWith("172."))return ip;
        return "127.0.0.1"; // no network = standalone solo
    }
    private static String read(File f)throws IOException{
        ByteArrayOutputStream buffer=new ByteArrayOutputStream();
        try(FileInputStream input=new FileInputStream(f)){
            byte[] data=new byte[4096];int n;
            while((n=input.read(data))!=-1)buffer.write(data,0,n);
        }
        return buffer.toString("UTF-8");
    }
    private static void write(File f,String text)throws IOException{
        try(FileOutputStream stream=new FileOutputStream(f)){
            stream.write(text.getBytes("UTF-8"));
        }
    }
    private void unpack(String asset,File root)throws IOException{
        String directory=root.getCanonicalPath()+File.separator;
        try(ZipInputStream zip=new ZipInputStream(getAssets().open(asset))){
            ZipEntry entry;byte[] buf=new byte[16384];
            while((entry=zip.getNextEntry())!=null){
                File dest=new File(root,entry.getName());
                if(!dest.getCanonicalPath().startsWith(directory))
                    throw new IOException("Unsafe package file");
                if(entry.isDirectory()){
                    if(!dest.exists()&&!dest.mkdirs())throw new IOException("mkdir "+dest);
                }else{
                    File parent=dest.getParentFile();
                    if(!parent.exists()&&!parent.mkdirs())throw new IOException("mkdir "+parent);
                    try(FileOutputStream out=new FileOutputStream(dest)){
                        int count;while((count=zip.read(buf))!=-1)out.write(buf,0,count);
                    }
                }
                zip.closeEntry();
            }
        }
    }
}
