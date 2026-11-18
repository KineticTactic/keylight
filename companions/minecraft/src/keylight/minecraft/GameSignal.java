package keylight.minecraft;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.StandardProtocolFamily;
import java.nio.ByteBuffer;
import java.nio.channels.DatagramChannel;
import java.nio.charset.StandardCharsets;

public final class GameSignal {
    private static final InetSocketAddress KEYLIGHT = new InetSocketAddress("127.0.0.1", 49375);
    private static final byte[] HIT = "keylight:hit:1".getBytes(StandardCharsets.US_ASCII);
    private static DatagramChannel channel;

    private GameSignal() {}

    public static void hit() { send(HIT); }
    public static void boost() { send("keylight:boost:1".getBytes(StandardCharsets.US_ASCII)); }
    public static void arrival() { send("keylight:arrival:1".getBytes(StandardCharsets.US_ASCII)); }

    public static void motion(int flight, int portal) {
        send(("keylight:motion:1:" + flight + ":" + portal).getBytes(StandardCharsets.US_ASCII));
    }

    // All callers run on the client thread. A missing listener never stalls gameplay.
    private static void send(byte[] payload) {
        try {
            if (channel == null) {
                channel = DatagramChannel.open(StandardProtocolFamily.INET);
                channel.configureBlocking(false);
            }
            channel.send(ByteBuffer.wrap(payload), KEYLIGHT);
        } catch (IOException ignored) {
            // Lighting is best effort; the next hit can open a fresh socket.
            if (channel != null) {
                try { channel.close(); } catch (IOException ignoredClose) {}
                channel = null;
            }
        }
    }
}
