package org.love2d.android;
/** One native Node.js event loop per Android app process. */
public final class MooIONodeBridge {
    static {
        System.loadLibrary("node");
        System.loadLibrary("mooiohost");
    }
    private MooIONodeBridge() {}
    public static native int start(String[] arguments,String[] env,String workingDirectory);
}
