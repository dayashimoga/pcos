# PCOS LAN Port Bridge
# Enables rootless Podman/WSL2 on Windows to be accessible from local Wi-Fi/LAN devices.
# Forwards external traffic on 0.0.0.0:80 and 0.0.0.0:443 to 127.0.0.1:80 and 127.0.0.1:443.

$ErrorActionPreference = "SilentlyContinue"

$pidFile = Join-Path $PSScriptRoot "lan_bridge.pid"
$PID | Out-File -FilePath $pidFile -Encoding ascii -Force

$cs = @'
#pragma warning disable 4014
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;

public class LanPortBridge {
    public static void StartBridge(int listenPort, string targetHost, int targetPort) {
        try {
            var listener = new TcpListener(IPAddress.Any, listenPort);
            listener.Start();
            Task.Run(async () => {
                while (true) {
                    try {
                        var client = await listener.AcceptTcpClientAsync();
                        Task.Run(async () => {
                            try {
                                using (client)
                                using (var target = new TcpClient()) {
                                    await target.ConnectAsync(targetHost, targetPort);
                                    using (var cs = client.GetStream())
                                    using (var ts = target.GetStream()) {
                                        await Task.WhenAny(cs.CopyToAsync(ts), ts.CopyToAsync(cs));
                                    }
                                }
                            } catch {}
                        });
                    } catch {}
                }
            });
        } catch {}
    }
}
'@

Add-Type -TypeDefinition $cs -ErrorAction SilentlyContinue

[LanPortBridge]::StartBridge(80, "127.0.0.1", 80)
[LanPortBridge]::StartBridge(443, "127.0.0.1", 443)

Write-Host "PCOS LAN Port Bridge active on 0.0.0.0:80 and 0.0.0.0:443 -> 127.0.0.1"

while ($true) {
    Start-Sleep -Seconds 3600
}
