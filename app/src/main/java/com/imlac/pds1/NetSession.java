package com.imlac.pds1;

import android.content.Context;
import android.net.wifi.WifiManager;
import android.util.Log;

import java.io.IOException;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * NetSession — UDP LAN multiplayer session for Imlac PDS-1 emulator.
 *
 * Features:
 *  - Host/Guest discovery via UDP broadcast
 *  - Demo synchronization (which demo is running)
 *  - Keyboard input sharing
 *  - Chat messages
 *  - Maze War PvP state (position, bullets, kills)
 *
 * Packet format (32 bytes):
 *  [0]    type: 'D'=discover, 'W'=welcome, 'J'=join_ack,
 *               'S'=sync(demo+kbd), 'M'=maze_state,
 *               'B'=bullet, 'K'=kill_notify, 'C'=chat, 'X'=bye
 *  [1]    flags / player_id
 *  [2]    demo index (Demos.Type ordinal)
 *  [3]    keyboard low byte
 *  [4]    keyboard high byte
 *  [5]    maze_x
 *  [6]    maze_y
 *  [7]    maze_dir
 *  [8]    maze_hp
 *  [9..10] score (short BE)
 *  [11]   bullet_dir
 *  [12..15] maze seed (int BE)
 *  [16..31] chat text (UTF-8, null-terminated, 16 chars)
 */
public class NetSession {

    private static final String TAG = "NetSession";
    public  static final int PORT_GAME  = 7474;
    public  static final int PORT_BCAST = 7475;
    private static final int PKT = 32;
    private static final int TIMEOUT_MS = 500;
    private static final int PEER_TIMEOUT_MS = 6000;

    // ── Roles & State ─────────────────────────────────────────
    public enum Role   { NONE, HOST, GUEST }
    public enum Status { IDLE, HOSTING, SEARCHING, CONNECTED, DISCONNECTED }

    public volatile Role   role   = Role.NONE;
    public volatile Status status = Status.IDLE;

    // ── Peer info ─────────────────────────────────────────────
    public volatile String  peerAddr    = null;
    public volatile int     peerDemo    = 0;
    public volatile int     peerKeyboard = 0;
    // Maze War peer state
    public volatile int     peerMazeX=1, peerMazeY=1, peerMazeDir=0;
    public volatile int     peerMazeHp=3, peerMazeScore=0;
    public volatile boolean peerFiredBullet = false;
    public volatile int     peerBulletDir   = 0;
    public volatile long    mazeSeed = 0;
    public volatile long    lastPeerTime = 0;

    // ── Chat ─────────────────────────────────────────────────
    public interface ChatListener   { void onChatMessage(String from, String msg); }
    public interface EventListener  {
        void onConnected(boolean asHost, long mazeSeed);
        void onPeerSync(int demoIdx, int keyboard);
        void onPeerMazeState(int x,int y,int dir,int hp,int score);
        void onPeerBullet(int dir);
        void onPeerKilled();
        void onDisconnected();
    }

    private ChatListener  chatListener;
    private EventListener eventListener;

    // ── Sockets ───────────────────────────────────────────────
    private DatagramSocket gameSock;
    private DatagramSocket bcastSock;
    private final AtomicBoolean running = new AtomicBoolean(false);
    private Thread netThread;
    private final ConcurrentLinkedQueue<byte[]> sendQueue = new ConcurrentLinkedQueue<>();

    // ── My id ─────────────────────────────────────────────────
    public int myId = 0; // 0=host, 1=guest

    private final Context ctx;
    public NetSession(Context ctx) { this.ctx = ctx; }

    public void setChatListener(ChatListener l)   { chatListener  = l; }
    public void setEventListener(EventListener l) { eventListener = l; }

    // ─────────────────────────────────────────────────────────
    //  HOST
    // ─────────────────────────────────────────────────────────
    public void host(long seed) {
        stop(); mazeSeed=seed; role=Role.HOST; myId=0; status=Status.HOSTING;
        running.set(true);
        netThread = new Thread(this::hostLoop, "net-host");
        netThread.setDaemon(true); netThread.start();
    }

    private void hostLoop() {
        try {
            gameSock  = new DatagramSocket(PORT_GAME);
            bcastSock = new DatagramSocket(PORT_BCAST);
            bcastSock.setBroadcast(true);
            gameSock.setSoTimeout(TIMEOUT_MS);
            bcastSock.setSoTimeout(TIMEOUT_MS);
            Log.d(TAG, "HOST listening");

            byte[] buf = new byte[PKT];
            // Discovery phase
            while (running.get() && status==Status.HOSTING) {
                try {
                    DatagramPacket dp = new DatagramPacket(buf,PKT);
                    bcastSock.receive(dp);
                    if (buf[0]=='D') {
                        peerAddr = dp.getAddress().getHostAddress();
                        byte[] welcome = mkPacket('W',0,0,0,mazeSeed);
                        gameSock.send(new DatagramPacket(welcome,PKT,dp.getAddress(),PORT_GAME));
                        Log.d(TAG,"HOST: sent welcome to "+peerAddr);
                    }
                } catch (SocketTimeoutException ignored){}
                try {
                    DatagramPacket dp=new DatagramPacket(buf,PKT);
                    gameSock.receive(dp);
                    if (buf[0]=='J') {
                        peerAddr=dp.getAddress().getHostAddress();
                        status=Status.CONNECTED; myId=0;
                        Log.d(TAG,"HOST: guest connected "+peerAddr);
                        if(eventListener!=null) eventListener.onConnected(true,mazeSeed);
                        lastPeerTime=System.currentTimeMillis();
                    }
                } catch (SocketTimeoutException ignored){}
            }
            if (status==Status.CONNECTED) gameLoop();
        } catch (IOException e) {
            Log.e(TAG,"Host error: "+e);
        } finally {
            closeAll(); status=Status.DISCONNECTED;
            if(eventListener!=null) eventListener.onDisconnected();
        }
    }

    // ─────────────────────────────────────────────────────────
    //  GUEST
    // ─────────────────────────────────────────────────────────
    public void discover() {
        stop(); role=Role.GUEST; myId=1; status=Status.SEARCHING;
        running.set(true);
        netThread = new Thread(this::guestLoop, "net-guest");
        netThread.setDaemon(true); netThread.start();
    }

    private void guestLoop() {
        try {
            gameSock = new DatagramSocket(PORT_GAME);
            gameSock.setBroadcast(true);
            gameSock.setSoTimeout(TIMEOUT_MS);
            InetAddress bcast = getBroadcastAddr();
            byte[] disc = mkPacket('D',1,0,0,0);
            byte[] buf  = new byte[PKT];
            long deadline = System.currentTimeMillis()+30_000;
            Log.d(TAG,"GUEST discovering, bcast="+bcast);

            while (running.get() && status==Status.SEARCHING
                   && System.currentTimeMillis()<deadline) {
                try { gameSock.send(new DatagramPacket(disc,PKT,bcast,PORT_BCAST)); }
                catch(IOException ignored){}
                try {
                    DatagramPacket dp=new DatagramPacket(buf,PKT);
                    gameSock.receive(dp);
                    if (buf[0]=='W') {
                        peerAddr=dp.getAddress().getHostAddress();
                        mazeSeed=decodeSeed(buf,12);
                        byte[] join=mkPacket('J',1,0,0,0);
                        gameSock.send(new DatagramPacket(join,PKT,dp.getAddress(),PORT_GAME));
                        status=Status.CONNECTED;
                        Log.d(TAG,"GUEST: connected to "+peerAddr+" seed="+mazeSeed);
                        if(eventListener!=null) eventListener.onConnected(false,mazeSeed);
                        lastPeerTime=System.currentTimeMillis();
                    }
                } catch(SocketTimeoutException ignored){}
            }
            if (status==Status.CONNECTED) gameLoop();
            else { status=Status.DISCONNECTED; if(eventListener!=null) eventListener.onDisconnected(); }
        } catch (IOException e) {
            Log.e(TAG,"Guest error: "+e);
        } finally { closeAll(); }
    }

    // ─────────────────────────────────────────────────────────
    //  GAME LOOP — receive + send queue
    // ─────────────────────────────────────────────────────────
    private void gameLoop() throws IOException {
        gameSock.setSoTimeout(TIMEOUT_MS);
        byte[] buf = new byte[PKT];
        Log.d(TAG,"Game loop as "+role);
        while (running.get()) {
            // Drain send queue
            byte[] toSend;
            while ((toSend=sendQueue.poll())!=null) {
                try {
                    gameSock.send(new DatagramPacket(toSend,PKT,
                            InetAddress.getByName(peerAddr),PORT_GAME));
                } catch(IOException ignored){}
            }
            // Receive
            try {
                DatagramPacket dp=new DatagramPacket(buf,PKT);
                gameSock.receive(dp);
                lastPeerTime=System.currentTimeMillis();
                handlePacket(buf);
            } catch(SocketTimeoutException ignored){}
            // Peer timeout
            if (System.currentTimeMillis()-lastPeerTime>PEER_TIMEOUT_MS && lastPeerTime>0) {
                Log.w(TAG,"Peer timeout");
                status=Status.DISCONNECTED;
                if(eventListener!=null) eventListener.onDisconnected();
                break;
            }
        }
    }

    private void handlePacket(byte[] p) {
        switch((char)p[0]) {
            case 'S':  // sync: demo + keyboard
                peerDemo     = p[2]&0xFF;
                peerKeyboard = ((p[3]&0xFF)<<8)|(p[4]&0xFF);
                if(eventListener!=null)
                    eventListener.onPeerSync(peerDemo, peerKeyboard);
                break;
            case 'M':  // maze state
                peerMazeX   = p[5]&0xFF; peerMazeY    = p[6]&0xFF;
                peerMazeDir = p[7]&0xFF; peerMazeHp   = p[8]&0xFF;
                peerMazeScore=((p[9]&0xFF)<<8)|(p[10]&0xFF);
                if(eventListener!=null)
                    eventListener.onPeerMazeState(peerMazeX,peerMazeY,peerMazeDir,peerMazeHp,peerMazeScore);
                break;
            case 'B':  // bullet
                peerFiredBullet=true; peerBulletDir=p[11]&0xFF;
                if(eventListener!=null) eventListener.onPeerBullet(peerBulletDir);
                break;
            case 'K':  // kill
                if(eventListener!=null) eventListener.onPeerKilled();
                break;
            case 'C':  // chat
                String msg=decodeChat(p,16);
                if(chatListener!=null) chatListener.onChatMessage("OPP",msg);
                break;
            case 'X':  // bye
                status=Status.DISCONNECTED;
                if(eventListener!=null) eventListener.onDisconnected();
                break;
        }
    }

    // ─────────────────────────────────────────────────────────
    //  SEND METHODS (thread-safe, non-blocking)
    // ─────────────────────────────────────────────────────────
    public void sendSync(int demoIdx, int keyboard) {
        if(!isConnected()) return;
        byte[] p=new byte[PKT]; p[0]='S'; p[1]=(byte)myId;
        p[2]=(byte)demoIdx; p[3]=(byte)(keyboard>>8); p[4]=(byte)(keyboard&0xFF);
        sendQueue.offer(p);
    }

    public void sendMazeState(int x,int y,int dir,int hp,int score) {
        if(!isConnected()) return;
        byte[] p=new byte[PKT]; p[0]='M'; p[1]=(byte)myId;
        p[5]=(byte)x; p[6]=(byte)y; p[7]=(byte)dir; p[8]=(byte)hp;
        p[9]=(byte)(score>>8); p[10]=(byte)(score&0xFF);
        sendQueue.offer(p);
    }

    public void sendBullet(int dir) {
        if(!isConnected()) return;
        byte[] p=new byte[PKT]; p[0]='B'; p[1]=(byte)myId; p[11]=(byte)dir;
        sendQueue.offer(p);
    }

    public void sendKill() {
        if(!isConnected()) return;
        byte[] p=new byte[PKT]; p[0]='K'; p[1]=(byte)myId;
        sendQueue.offer(p);
    }

    public void sendChat(String text) {
        if(!isConnected()) return;
        byte[] p=new byte[PKT]; p[0]='C'; p[1]=(byte)myId;
        encodeChat(text,p,16);
        sendQueue.offer(p);
        // Echo locally
        if(chatListener!=null) chatListener.onChatMessage("ME",text);
    }

    // ─────────────────────────────────────────────────────────
    //  UTILS
    // ─────────────────────────────────────────────────────────
    private byte[] mkPacket(char type,int id,int demoIdx,int kbd,long seed) {
        byte[] p=new byte[PKT];
        p[0]=(byte)type; p[1]=(byte)id; p[2]=(byte)demoIdx;
        p[3]=(byte)(kbd>>8); p[4]=(byte)(kbd&0xFF);
        p[12]=(byte)(seed>>24); p[13]=(byte)(seed>>16);
        p[14]=(byte)(seed>>8);  p[15]=(byte)(seed);
        return p;
    }

    private long decodeSeed(byte[] p,int off) {
        return ((long)(p[off]&0xFF)<<24)|((long)(p[off+1]&0xFF)<<16)
              |((long)(p[off+2]&0xFF)<<8)|(p[off+3]&0xFF);
    }

    private void encodeChat(String s,byte[] p,int off) {
        byte[] b=s.getBytes(StandardCharsets.UTF_8);
        int len=Math.min(b.length,PKT-off-1);
        System.arraycopy(b,0,p,off,len);
    }

    private String decodeChat(byte[] p,int off) {
        int end=off; while(end<PKT&&p[end]!=0) end++;
        return new String(p,off,end-off,StandardCharsets.UTF_8);
    }

    private InetAddress getBroadcastAddr() {
        try {
            WifiManager wm=(WifiManager)ctx.getApplicationContext()
                    .getSystemService(Context.WIFI_SERVICE);
            if(wm!=null){
                int ip=wm.getDhcpInfo().ipAddress, msk=wm.getDhcpInfo().netmask;
                int bc=(ip&msk)|~msk;
                byte[] b=new byte[]{(byte)bc,(byte)(bc>>8),(byte)(bc>>16),(byte)(bc>>24)};
                return InetAddress.getByAddress(b);
            }
        } catch(Exception ignored){}
        try { return InetAddress.getByName("255.255.255.255"); }
        catch(Exception e){ return null; }
    }

    public void stop() {
        running.set(false);
        if(netThread!=null){netThread.interrupt();netThread=null;}
        closeAll(); status=Status.IDLE; role=Role.NONE;
    }

    private void closeAll() {
        try{if(gameSock !=null&&!gameSock.isClosed()) gameSock.close();}catch(Exception ignored){}
        try{if(bcastSock!=null&&!bcastSock.isClosed())bcastSock.close();}catch(Exception ignored){}
    }

    public boolean isConnected(){ return status==Status.CONNECTED; }
}
