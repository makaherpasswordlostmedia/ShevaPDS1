package com.imlac.pds1;

import android.content.Context;
import android.net.wifi.WifiManager;
import android.util.Log;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * NetGame — UDP LAN multiplayer for Maze War.
 *
 * Protocol (all packets are 16 bytes):
 *   [0]   packet type: 'H'=hello/discover, 'J'=join, 'A'=ack/welcome,
 *                      'S'=state update, 'B'=bullet, 'K'=kill, 'G'=goodbye
 *   [1]   player id (0=host, 1=guest)
 *   [2-3] grid X, grid Y
 *   [4]   direction (0-3)
 *   [5]   hp (0-3)
 *   [6-7] score (short)
 *   [8]   bullet dir or flags
 *   [9]   maze seed byte 0
 *   [10]  maze seed byte 1
 *   [11]  maze seed byte 2
 *   [12]  maze seed byte 3
 *   [13-15] reserved
 *
 * Discovery: Guest broadcasts 'H' on port 7474.
 *            Host receives, replies 'A' (welcome) with maze seed.
 *            Guest receives 'A', joins.
 */
public class NetGame {

    private static final String TAG   = "NetGame";
    public  static final int    PORT  = 7474;
    public  static final int    BCAST = 7475;
    private static final int    PKT   = 16;

    // ── Roles ─────────────────────────────────────────────────
    public enum Role { NONE, HOST, GUEST }
    public volatile Role role = Role.NONE;

    // ── Connection state ──────────────────────────────────────
    public enum Status { IDLE, HOSTING, DISCOVERING, CONNECTED, DISCONNECTED }
    public volatile Status status = Status.IDLE;
    public volatile String peerAddr = null;

    // ── Shared game state (peer's data) ───────────────────────
    public volatile int  peerX=1, peerY=1, peerDir=0;
    public volatile int  peerHp=3, peerScore=0;
    public volatile boolean peerFired=false;
    public volatile int  peerBulletDir=0;
    public volatile long mazeSeed = 0;

    // ── Local player id ───────────────────────────────────────
    public int myId = 0;  // 0=host, 1=guest

    // ── Sockets ───────────────────────────────────────────────
    private DatagramSocket gameSocket;   // main game port
    private DatagramSocket bcastSocket;  // broadcast listen (host only)
    private final AtomicBoolean running = new AtomicBoolean(false);
    private Thread recvThread;

    // ── Callbacks ─────────────────────────────────────────────
    public interface Listener {
        void onConnected(boolean asHost, long mazeSeed);
        void onPeerState(int x, int y, int dir, int hp, int score);
        void onPeerBullet(int dir);
        void onPeerKilled();
        void onDisconnected();
    }
    private Listener listener;

    private final Context ctx;

    public NetGame(Context ctx) { this.ctx = ctx; }

    public void setListener(Listener l) { this.listener = l; }

    // ─────────────────────────────────────────────────────────
    //  HOST — open game, wait for guest
    // ─────────────────────────────────────────────────────────
    public void host(long seed) {
        stop();
        role = Role.HOST;
        myId = 0;
        mazeSeed = seed;
        status = Status.HOSTING;
        running.set(true);

        recvThread = new Thread(() -> {
            try {
                gameSocket  = new DatagramSocket(PORT);
                bcastSocket = new DatagramSocket(BCAST);
                bcastSocket.setBroadcast(true);
                gameSocket.setSoTimeout(500);
                bcastSocket.setSoTimeout(500);

                Log.d(TAG, "HOST listening on port " + PORT);
                byte[] buf = new byte[PKT];

                while (running.get() && status != Status.CONNECTED) {
                    // Listen for broadcast discovery on BCAST port
                    try {
                        DatagramPacket pkt = new DatagramPacket(buf, PKT);
                        bcastSocket.receive(pkt);
                        if (buf[0] == 'H') {
                            // Guest discovered us - send welcome with maze seed
                            peerAddr = pkt.getAddress().getHostAddress();
                            byte[] welcome = buildPacket('A', 0, 1, 1, 0, 3, 0, 0, seed);
                            DatagramPacket wp = new DatagramPacket(welcome, PKT,
                                    pkt.getAddress(), PORT);
                            gameSocket.send(wp);
                            Log.d(TAG, "HOST sent welcome to " + peerAddr);
                        }
                    } catch (IOException ignored) {}

                    // Also listen on game port for join confirmation
                    try {
                        DatagramPacket pkt = new DatagramPacket(buf, PKT);
                        gameSocket.receive(pkt);
                        if (buf[0] == 'J') {
                            peerAddr = pkt.getAddress().getHostAddress();
                            status = Status.CONNECTED;
                            Log.d(TAG, "HOST: guest joined from " + peerAddr);
                            if (listener != null) listener.onConnected(true, mazeSeed);
                        }
                    } catch (IOException ignored) {}
                }

                // Main game receive loop
                gameLoop();

            } catch (IOException e) {
                Log.e(TAG, "Host error: " + e);
                status = Status.DISCONNECTED;
                if (listener != null) listener.onDisconnected();
            } finally {
                closeAll();
            }
        }, "netgame-host");
        recvThread.setDaemon(true);
        recvThread.start();
    }

    // ─────────────────────────────────────────────────────────
    //  GUEST — broadcast discover, wait for host reply
    // ─────────────────────────────────────────────────────────
    public void discover() {
        stop();
        role = Role.GUEST;
        myId = 1;
        status = Status.DISCOVERING;
        running.set(true);

        recvThread = new Thread(() -> {
            try {
                gameSocket = new DatagramSocket(PORT);
                gameSocket.setBroadcast(true);
                gameSocket.setSoTimeout(500);

                InetAddress bcastAddr = getBroadcastAddress();
                Log.d(TAG, "GUEST discovering, broadcast=" + bcastAddr);

                byte[] disc = buildPacket('H', 1, 0, 0, 0, 0, 0, 0, 0);

                long deadline = System.currentTimeMillis() + 30_000; // 30s timeout
                while (running.get() && status == Status.DISCOVERING
                        && System.currentTimeMillis() < deadline) {
                    // Send broadcast
                    try {
                        DatagramPacket dp = new DatagramPacket(disc, PKT, bcastAddr, BCAST);
                        gameSocket.send(dp);
                    } catch (IOException ignored) {}

                    // Wait for host reply
                    try {
                        byte[] buf = new byte[PKT];
                        DatagramPacket rp = new DatagramPacket(buf, PKT);
                        gameSocket.receive(rp);
                        if (buf[0] == 'A') {
                            peerAddr = rp.getAddress().getHostAddress();
                            mazeSeed = decodeSeed(buf);
                            Log.d(TAG, "GUEST found host " + peerAddr + " seed=" + mazeSeed);

                            // Send join confirmation
                            byte[] join = buildPacket('J', 1, 0, 0, 0, 0, 0, 0, 0);
                            gameSocket.send(new DatagramPacket(join, PKT,
                                    rp.getAddress(), PORT));

                            status = Status.CONNECTED;
                            if (listener != null) listener.onConnected(false, mazeSeed);
                        }
                    } catch (IOException ignored) {}
                }

                if (status != Status.CONNECTED) {
                    status = Status.DISCONNECTED;
                    if (listener != null) listener.onDisconnected();
                    return;
                }

                gameLoop();

            } catch (IOException e) {
                Log.e(TAG, "Guest error: " + e);
                status = Status.DISCONNECTED;
                if (listener != null) listener.onDisconnected();
            } finally {
                closeAll();
            }
        }, "netgame-guest");
        recvThread.setDaemon(true);
        recvThread.start();
    }

    // ─────────────────────────────────────────────────────────
    //  GAME LOOP — receive peer state packets
    // ─────────────────────────────────────────────────────────
    private void gameLoop() throws IOException {
        gameSocket.setSoTimeout(5000); // 5s timeout = disconnect
        byte[] buf = new byte[PKT];
        Log.d(TAG, "Game loop started as " + role);

        while (running.get()) {
            try {
                DatagramPacket pkt = new DatagramPacket(buf, PKT);
                gameSocket.receive(pkt);
                handlePacket(buf);
            } catch (IOException e) {
                if (!running.get()) break;
                // Timeout = peer disconnected
                Log.w(TAG, "Receive timeout, peer disconnected");
                status = Status.DISCONNECTED;
                if (listener != null) listener.onDisconnected();
                break;
            }
        }
    }

    private void handlePacket(byte[] buf) {
        byte type = buf[0];
        if (type == 'S') {
            peerX     = buf[2] & 0xFF;
            peerY     = buf[3] & 0xFF;
            peerDir   = buf[4] & 0xFF;
            peerHp    = buf[5] & 0xFF;
            peerScore = ((buf[6]&0xFF)<<8) | (buf[7]&0xFF);
            if (listener != null)
                listener.onPeerState(peerX, peerY, peerDir, peerHp, peerScore);
        } else if (type == 'B') {
            peerFired     = true;
            peerBulletDir = buf[8] & 0xFF;
            if (listener != null) listener.onPeerBullet(peerBulletDir);
        } else if (type == 'K') {
            if (listener != null) listener.onPeerKilled();
        } else if (type == 'G') {
            status = Status.DISCONNECTED;
            if (listener != null) listener.onDisconnected();
        }
    }

    // ─────────────────────────────────────────────────────────
    //  SEND — called from game logic
    // ─────────────────────────────────────────────────────────
    public void sendState(int x, int y, int dir, int hp, int score) {
        if (status != Status.CONNECTED || peerAddr == null) return;
        byte[] pkt = buildPacket('S', myId, x, y, dir, hp, score, 0, 0);
        sendUDP(pkt);
    }

    public void sendBullet(int dir) {
        if (status != Status.CONNECTED || peerAddr == null) return;
        byte[] pkt = new byte[PKT];
        pkt[0]='B'; pkt[1]=(byte)myId; pkt[8]=(byte)dir;
        sendUDP(pkt);
    }

    public void sendKill() {
        if (status != Status.CONNECTED || peerAddr == null) return;
        byte[] pkt = new byte[PKT];
        pkt[0]='K'; pkt[1]=(byte)myId;
        sendUDP(pkt);
    }

    private void sendUDP(byte[] data) {
        if (gameSocket == null || gameSocket.isClosed()) return;
        try {
            InetAddress addr = InetAddress.getByName(peerAddr);
            gameSocket.send(new DatagramPacket(data, PKT, addr, PORT));
        } catch (IOException e) {
            Log.w(TAG, "Send failed: " + e);
        }
    }

    // ─────────────────────────────────────────────────────────
    //  UTILS
    // ─────────────────────────────────────────────────────────
    private byte[] buildPacket(char type, int id, int x, int y, int dir,
                                int hp, int score, int bdir, long seed) {
        byte[] p = new byte[PKT];
        p[0] = (byte)type; p[1] = (byte)id;
        p[2] = (byte)x;    p[3] = (byte)y;
        p[4] = (byte)dir;  p[5] = (byte)hp;
        p[6] = (byte)(score>>8); p[7] = (byte)(score&0xFF);
        p[8] = (byte)bdir;
        p[9]  = (byte)(seed>>24); p[10] = (byte)(seed>>16);
        p[11] = (byte)(seed>>8);  p[12] = (byte)(seed);
        return p;
    }

    private long decodeSeed(byte[] buf) {
        return ((long)(buf[9]&0xFF)<<24)|((long)(buf[10]&0xFF)<<16)
              |((long)(buf[11]&0xFF)<<8)|(buf[12]&0xFF);
    }

    private InetAddress getBroadcastAddress() {
        try {
            WifiManager wm = (WifiManager)
                    ctx.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            if (wm != null) {
                int ip  = wm.getDhcpInfo().ipAddress;
                int msk = wm.getDhcpInfo().netmask;
                int bcast = (ip & msk) | ~msk;
                byte[] q = ByteBuffer.allocate(4).putInt(
                        Integer.reverseBytes(bcast)).array();
                return InetAddress.getByAddress(q);
            }
        } catch (Exception e) {
            Log.w(TAG, "Broadcast addr fallback: " + e);
        }
        try { return InetAddress.getByName("255.255.255.255"); }
        catch (Exception e) { return null; }
    }

    public void stop() {
        running.set(false);
        if (recvThread != null) { recvThread.interrupt(); recvThread = null; }
        closeAll();
        status = Status.IDLE;
        role   = Role.NONE;
    }

    private void closeAll() {
        try { if (gameSocket  != null && !gameSocket.isClosed())  gameSocket.close();  } catch(Exception ignored){}
        try { if (bcastSocket != null && !bcastSocket.isClosed()) bcastSocket.close(); } catch(Exception ignored){}
    }

    public boolean isConnected() { return status == Status.CONNECTED; }
}
