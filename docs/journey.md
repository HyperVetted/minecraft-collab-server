# Journey log

What actually happened while building this, in order. Everything here happened on 2026-10-03.

## Why this project

I was learning Terraform for the Associate (004) exam and wanted a real project where I'd have to read provider docs and fix my own mistakes, not just follow a tutorial. A Minecraft server seemed like a good fit: a resource group, storage, and a container, and an obvious test of whether it works (can I join, and is my stuff still there after a restart).

I followed a deployment guide for running Bedrock on ACI with Terraform. It turned out the guide was written for the older Bedrock network transport (RakNet), where everything goes over UDP 19132. That ended up mattering a lot.

## Setup hiccups

- **Wrong Terraform on PATH.** I installed Terraform with winget, but an old 32-bit Terraform from an earlier install was earlier on my PATH, so `terraform version` showed the old one. Fixing PATH and reopening the terminal sorted it out. A terminal opened before a PATH change doesn't see the change.
- **AzureRM v4 changed the file share argument.** Examples I found used `storage_account_name` on `azurerm_storage_share`. In v4 it's `storage_account_id`, which takes the storage account's ID.
- **Storage account naming.** Lowercase letters and numbers only, no hyphens, 3-24 characters, and globally unique. A name that's already taken only shows up as an error at apply, not at plan.
- **Case-sensitive values.** Some arguments only accept exact values, like `Hot` and not `hot`.
- The first `plan` sat silent for a few minutes. I think that was Azure registering resource providers on the subscription.

## The server started, but I couldn't connect

The container came up, the logs said the server started, and the world folder appeared on the file share. But the game client couldn't connect. It failed with `InitialConnection-13`.

## Accidentally replacing the container group

While I was working on this I changed the container group's `name`. I expected Terraform to rename it. Instead the plan said destroy and create. Changing the name of a container group is a **replace**, not an update, because Azure can't rename it in place.

The good news: the world survived, because it lives on the file share, not in the container. It wasn't the persistence test I'd planned, but it showed the share was doing its job.

## NetherNet

After a lot of searching I found that Bedrock 1.26.50 and newer require a newer transport called NetherNet. As far as I understand it:

- The client first does a handshake over **TCP** 19132.
- Gameplay then goes over **UDP**, on a separate port for each connected player.

I tried forcing the server back to RakNet, but the server refused to do that. So the guide's "UDP 19132 only" setup can't work with current Bedrock.

## ACI port limits

Opening the ports NetherNet needs ran into two ACI limits:

1. You can't open the same port number for both TCP and UDP. So I couldn't have TCP 19132 and UDP 19132 at the same time.
2. There's a maximum of 5 ports per IP.

I ended up with TCP 19132 for the handshake and UDP 19140-19142 for gameplay. Instead of writing three `ports` blocks by hand I used a `dynamic "ports"` block with `range()`. I got an off-by-one at first: `range(a, b)` doesn't include `b`. For 19140 through 19142 it has to be `range(19140, 19143)`.

## The server only knows its private IP

Even with the ports open it still didn't work. ACI puts the container behind NAT, so the server only sees its private IP and tells clients to use that for the UDP ports. The fix was the `server-udp-ports` setting in `server.properties`, with the public IP in it:

```
server-udp-ports=<PUBLIC_IP>:19140-19142:19140-19142
```

I'm still not 100% sure of the exact meaning of each part of that value. I set it based on what I read and it works.

This isn't in Terraform. I set it by hand in the file on the share, and it has to be updated whenever the container group gets replaced, since that changes the public IP.

## Mojang bug BDS-23108

Still failing. I found a Mojang bug report, [BDS-23108](https://mojira.dev/BDS-23108), where connections fail when `online-mode=true`. To test that, I set `ONLINE_MODE = "false"`, and then I joined successfully.

Online mode off means there's no Xbox account authentication, so I don't leave the server running when I'm not around. I plan to turn it back on once the bug is fixed.

## Persistence test

The planned test this time: I placed a crafting table, disconnected, restarted the container with `az container restart`, and rejoined. The crafting table was still there. I also saw the world database files on the share get compacted, which confirmed the server was really writing to the share and not somewhere inside the container.

## Intermittent failures

After that, sometimes I could join and sometimes I couldn't, with no config changes in between. Looking through the logs I noticed a pattern: on the boots that worked, the log had a line `Accepting clients on [::]:19132`. On the boots that didn't, that line never appeared, even though the log still said `Server started`, and there was no TCP listener on 19132 at all. I don't know why some boots skip it. At first the workaround was restarting until the line showed up.

The fix I added is a `liveness_probe` on the container. It runs:

```
sh -c "grep -qE ':4ABC [0-9A-F]+:0000 0A' /proc/net/tcp /proc/net/tcp6"
```

`/proc/net/tcp` and `/proc/net/tcp6` list the container's sockets with ports in hex. 19132 is `4ABC` in hex, and state `0A` means LISTEN. If no socket is listening on 19132, the grep fails, and after 3 failures (checked every 30 seconds, starting 120 seconds after start because the server takes a while to boot) ACI restarts the container. Since restart policy is `Always`, the bad boot gets replaced with a new boot automatically, and a restart keeps the same IP.

## Settings that don't stick

I tried changing some settings by editing `server.properties` on the share in the portal. Some changes worked and some got reverted. It turned out the image rewrites any setting that has an environment variable into `server.properties` on every start, using the env var value (or its default). So for those settings the env vars in `main.tf` are the source of truth. Settings with no env var, like `server-udp-ports`, are left alone, which is why that one sticks.

## Switching to creative

The guide used survival. I switched to creative by setting `GAMEMODE = "creative"` and also `FORCE_GAMEMODE = "true"`. My understanding is that without force-gamemode, an existing world and existing players can keep the mode they already had, so changing `GAMEMODE` alone might not do anything visible.

Changing environment variables replaces the container group, so this also meant a new public IP and updating `server-udp-ports` again.
