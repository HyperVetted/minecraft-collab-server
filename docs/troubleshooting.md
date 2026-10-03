# Troubleshooting

The problems I actually hit, written as: symptom, what I checked, what it turned out to be. Commands I found useful are at the bottom.

## `terraform version` shows an old version

- **Checked:** `where.exe terraform` / `(Get-Command terraform).Source` to see which file was running.
- **Turned out:** an old 32-bit Terraform was earlier on PATH than the winget install. After fixing PATH, the terminal had to be reopened to pick it up.

## `storage_account_name` not accepted on the file share

- **Checked:** the `azurerm_storage_share` docs for the provider version in the lock file (4.x).
- **Turned out:** AzureRM v4 uses `storage_account_id = azurerm_storage_account.sa.id`.

## Storage account name rejected, or "already taken" at apply

- **Turned out:** names must be 3-24 characters, lowercase letters and numbers only (no hyphens), and globally unique across Azure. The "taken" error only appears at apply.

## Plan wants to destroy and recreate the container group

- **Checked:** the plan output, which marks the argument that "forces replacement".
- **Turned out:** changing the container group name, environment variables, or ports is a replace, not an in-place update. The world is on the file share so it survives, but the public IP changes, so `server-udp-ports` has to be updated afterwards.

## Server starts, world is created, client fails with `InitialConnection-13`

- **Checked:** container logs (server started, world loaded), the ports in `az container show`, and the Bedrock version the server downloaded.
- **Turned out:** Bedrock 1.26.50+ uses NetherNet: a TCP handshake on 19132 plus a UDP port per player. The original setup only opened UDP 19132. Forcing the server back to RakNet isn't accepted.

## Can't open TCP and UDP on 19132, or can't add more ports

- **Turned out:** ACI doesn't allow the same port number for both TCP and UDP, and allows at most 5 ports per IP. I used TCP 19132 and UDP 19140-19142.

## Ports open, still can't connect

- **Checked:** the server log and `server.properties` on the share.
- **Turned out:** behind ACI's NAT the server only knows its private IP. Setting `server-udp-ports=<PUBLIC_IP>:19140-19142:19140-19142` in `/data/server.properties` and restarting fixed it. If the container group gets replaced, the IP changes and this needs updating again.

## Still can't connect, even with the right IP

- **Checked:** searched the Mojang bug tracker.
- **Turned out:** [BDS-23108](https://mojira.dev/BDS-23108): connections fail with `online-mode=true`. Setting `ONLINE_MODE = "false"` let me join. (That disables Xbox authentication, so don't leave it running unattended.)

## Sometimes I can join, sometimes I can't, with no changes

- **Checked:** compared logs from good and bad boots, and looked for a TCP listener inside the container.
- **Turned out:** bad boots log `Server started` but never log `Accepting clients on [::]:19132`, and there's no listening TCP socket on 19132. I don't know the root cause. Workaround: restart. Current fix: a liveness probe that looks for a LISTEN socket on port 19132 (`:4ABC`, state `0A`) in `/proc/net/tcp` and `/proc/net/tcp6`, so ACI restarts the container automatically when that happens.

## Edits to `server.properties` get reverted

- **Turned out:** the image rewrites any setting that has a matching environment variable into `server.properties` on every start. Change those in `main.tf`. Settings without an env var (like `server-udp-ports`) keep whatever is in the file.

## Game mode change doesn't seem to apply

- **Turned out:** I set `FORCE_GAMEMODE = "true"` alongside `GAMEMODE = "creative"`.

## Useful commands

Live logs (Ctrl+C to stop):

```powershell
az container logs -g rg-mc-bedrock-lab -n aci-mc-bedrock-lab --container-name minecraft --follow
```

State, public IP, FQDN, and ports:

```powershell
az container show -g rg-mc-bedrock-lab -n aci-mc-bedrock-lab --query "{state:instanceView.state,ip:ipAddress.ip,fqdn:ipAddress.fqdn,ports:ipAddress.ports}" -o json
```

Check what's listening inside the container:

```powershell
az container exec -g rg-mc-bedrock-lab -n aci-mc-bedrock-lab --container-name minecraft --exec-command "cat /proc/net/tcp6"
```

Look for `:4ABC` (19132 in hex) with state `0A` (LISTEN). Note that `az container exec` doesn't run your command through a shell, so things like pipes and quotes inside the command are passed literally to the program rather than interpreted. Keep it to a single simple command like the one above. Also check `/proc/net/tcp` for IPv4.

Test the TCP handshake port from Windows:

```powershell
Test-NetConnection <fqdn-or-ip> -Port 19132
```

The original guide said this test is meaningless because Bedrock used UDP only. With NetherNet the handshake is TCP, so `TcpTestSucceeded : True` is now a useful sign that the server is listening. It doesn't test the UDP gameplay ports.

Restart without changing the IP:

```powershell
az container restart -g rg-mc-bedrock-lab -n aci-mc-bedrock-lab
```
