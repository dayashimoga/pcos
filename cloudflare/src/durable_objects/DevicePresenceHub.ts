// DevicePresenceHub Durable Object
// Tracks device online presence, heartbeats, route resolution, and distributes real-time control commands.

export interface ActiveDevice {
  deviceId: string;
  userId: string;
  name: string;
  deviceType: string;
  lanIp?: string;
  publicIp?: string;
  wireguardPubkey?: string;
  relayEndpoint?: string;
  lastHeartbeat: number;
}

export class DevicePresenceHub implements DurableObject {
  private state: DurableObjectState;
  private activeDevices: Map<string, ActiveDevice> = new Map();
  private deviceSockets: Map<string, Set<WebSocket>> = new Map();

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  private cleanupStaleDevices(): void {
    const now = Date.now();
    const staleThreshold = 90000; // 90 seconds without heartbeat = offline
    for (const [id, dev] of this.activeDevices) {
      if (now - dev.lastHeartbeat > staleThreshold) {
        this.activeDevices.delete(id);
      }
    }
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    this.cleanupStaleDevices();

    // WebSocket upgrade for device real-time control (Send-to-Device, Play-on-TV)
    if (request.headers.get('Upgrade')?.toLowerCase() === 'websocket') {
      const deviceId = url.searchParams.get('deviceId') || '';
      if (!deviceId) {
        return new Response('Missing deviceId', { status: 400 });
      }

      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      server.accept();

      if (!this.deviceSockets.has(deviceId)) {
        this.deviceSockets.set(deviceId, new Set());
      }
      this.deviceSockets.get(deviceId)!.add(server);

      server.addEventListener('close', () => {
        this.deviceSockets.get(deviceId)?.delete(server);
      });

      return new Response(null, { status: 101, webSocket: client });
    }

    if (request.method === 'POST' && url.pathname === '/heartbeat') {
      const body = (await request.json()) as ActiveDevice;
      const clientIp = request.headers.get('cf-connecting-ip') || '';

      const updated: ActiveDevice = {
        ...body,
        publicIp: clientIp,
        lastHeartbeat: Date.now(),
      };

      this.activeDevices.set(body.deviceId, updated);
      return Response.json({ success: true, is_online: true });
    }

    if (request.method === 'GET' && url.pathname === '/resolve') {
      const targetDeviceId = url.searchParams.get('targetDeviceId') || '';
      const callerLanIp = url.searchParams.get('callerLanIp');
      const callerPublicIp = request.headers.get('cf-connecting-ip') || '';

      const target = this.activeDevices.get(targetDeviceId);
      if (!target) {
        return Response.json({
          is_online: false,
          recommended_route: 'Offline',
          message: 'Storage node is physically offline.',
        });
      }

      // Check if both devices share the exact same public IP or LAN subnet
      const samePublicIp = callerPublicIp && target.publicIp === callerPublicIp;
      const sameSubnet =
        callerLanIp &&
        target.lanIp &&
        isSameSubnet(callerLanIp, target.lanIp);

      let recommendedRoute: 'LAN' | 'P2P' | 'Relay' = 'P2P';

      if (sameSubnet || (samePublicIp && target.lanIp)) {
        recommendedRoute = 'LAN';
      } else if (target.wireguardPubkey) {
        recommendedRoute = 'P2P';
      } else {
        recommendedRoute = 'Relay';
      }

      return Response.json({
        is_online: true,
        recommended_route: recommendedRoute,
        lan_ip: target.lanIp,
        public_ip: target.publicIp,
        wireguard_pubkey: target.wireguardPubkey,
        relay_endpoint: target.relayEndpoint,
      });
    }

    if (request.method === 'POST' && url.pathname === '/command') {
      const body = (await request.json()) as {
        targetDeviceId: string;
        command: 'play_on_tv' | 'send_to_device' | 'refresh_sync';
        payload: Record<string, unknown>;
      };

      const sockets = this.deviceSockets.get(body.targetDeviceId);
      if (!sockets || sockets.size === 0) {
        return Response.json(
          { success: false, message: 'Target device has no active control channel.' },
          { status: 404 }
        );
      }

      const msg = JSON.stringify({
        command: body.command,
        payload: body.payload,
        timestamp: new Date().toISOString(),
      });

      for (const ws of sockets) {
        try {
          ws.send(msg);
        } catch (_) {}
      }

      return Response.json({ success: true, delivered: true });
    }

    if (request.method === 'GET' && url.pathname === '/devices') {
      const userId = url.searchParams.get('userId');
      const list = Array.from(this.activeDevices.values()).filter(
        (d) => !userId || d.userId === userId
      );
      return Response.json({ devices: list });
    }

    return new Response('Not Found', { status: 404 });
  }
}

function isSameSubnet(ip1: string, ip2: string): boolean {
  const parts1 = ip1.split('.');
  const parts2 = ip2.split('.');
  if (parts1.length === 4 && parts2.length === 4) {
    // Matches /24 subnet (e.g. 192.168.1.x)
    return (
      parts1[0] === parts2[0] &&
      parts1[1] === parts2[1] &&
      parts1[2] === parts2[2]
    );
  }
  return false;
}
