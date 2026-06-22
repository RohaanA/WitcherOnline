import java.util.Collections;
import java.util.List;

public class PlayerSession
{
    public final String username;
    public volatile ClientEndpoint endpoint;
    public volatile long lastSeen;

    public volatile List<String> update1AFields = Collections.emptyList();
    public volatile List<String> update1BFields = Collections.emptyList();
    public volatile List<String> update2AFields = Collections.emptyList();
    public volatile List<String> update2BFields = Collections.emptyList();
    public volatile List<String> update3Fields = Collections.emptyList();

    // NPC sync: NPCs hosted by this player. Single concatenated payload
    // (multiple NPCs separated by '|' inside one string field).
    public volatile List<String> updateNpcFields = Collections.emptyList();

    // Ghost spawn reliability: stores the most recent UPDATE_EXEC payload from this
    // player so late-joining clients receive a full world snapshot on connect.
    // Null until this player sends their first UPDATE_EXEC.
    public volatile String lastExecPayload = null;

    public PlayerSession(String username, ClientEndpoint endpoint, long lastSeen)
    {
        this.username = username;
        this.endpoint = endpoint;
        this.lastSeen = lastSeen;
    }
}