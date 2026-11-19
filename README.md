# Cavok

Cavok is a personal macOS menu-bar app for one setup: this Mac is in Hong Kong, Surfshark is supposed to send traffic out through a Japan static server, and Claude and ChatGPT are used on that path. It checks the Mac before those apps run, and it can quit them when the path looks wrong.

A green check means that one local check passed. It does not mean the account is safe. Cavok never logs in, never reads a card, and cannot switch Surfshark for you.

Hong Kong, mainland China, and Macau are the only countries it treats as a bad exit.

## What it is for

The point is local hygiene on this machine. Claude and ChatGPT are peers. A split tunnel can make one look fine while the other leaves somewhere else, so Cavok reads both and treats a disagreement as a failed check.

Before you open either app, Cavok looks for the ways this Mac can still show a home address, a relay, or a different exit:

- The route to the public internet is Wi-Fi or Ethernet instead of a tunnel. The lookup is `route -n get 1.1.1.1`, because a WireGuard-style tunnel often leaves the literal default route on `en0`. The same lookup is repeated for the address each trace actually reached.
- `claude.ai` and `chatgpt.com` see different IP addresses or countries. Each row is its own request to `/cdn-cgi/trace`.
- Either exit is HK, CN, or MO, or either address is not the one you pinned. **Pin this IP** saves the shared address only when both traces returned that same allowed IP.
- A shell startup file, the login environment, a Claude settings file, or `~/.codex/config.toml` still points at a proxy or a non-official API host. Codex is this config check. It is not an exit row and it is not a login test.
- macOS has an HTTP, HTTPS, SOCKS, or automatic proxy turned on.
- Claude, ChatGPT, `claude`, or `codex` still has a connection whose local address is on Wi-Fi or Ethernet.
- IPv6 is a real second path. An IPv4 address, including an address returned through `::ffff:`, does not count as IPv6.
- A DNS resolver is bound to Wi-Fi or Ethernet while the IPv4 route is a tunnel. Reading the resolver addresses is not, by itself, a pass.
- The clock is not Tokyo while an exit is JP, or the locale, languages, or input sources still carry HK, CN, or MO. That row is a warning. It does not quit anything, and it does not rewrite the locale.

Guard is the part that acts. While it is on, Cavok quits Claude, ChatGPT, `claude`, and `codex` when the route leaves the tunnel, either exit is a bad country, the two exits disagree, a pinned IP no longer matches, a proxy or relay is still set, a Claude or ChatGPT connection is on Wi-Fi or Ethernet, or IPv6 is a real leak. It also quits them when the lid closes, while the tunnel is still up. A timeout, the clock, the locale, a curl challenge, and ordinary DNS do not quit anything.

**Open Claude** and **Open ChatGPT** stay off until both exits have been read and they agree on an allowed address, that shared address is pinned, the route is a tunnel, no socket is on Wi-Fi or Ethernet, and Guard has nothing to quit for. The buttons open the installed apps; they do not open a website and do not log in.

## What the Exit rows are not

The four rows under **Exit** are a report on the path, not a safety score and not a login test.

| Row | What a result means |
|---|---|
| Tunnel route | Where the next packet would go. Green means a tunnel interface. Orange means Wi-Fi or Ethernet, and Cavok has not contacted either site. |
| Exit IP | The IP and country on Claude's Cloudflare trace. |
| ChatGPT exit | The IP and country on ChatGPT's Cloudflare trace. A different address is a split, not a copy of the Claude row. |
| Service reachability | Whether curl got a normal response from `claude.ai/` and `chatgpt.com/`, or a Cloudflare challenge, 403, or 421. A green trace can sit next to an orange challenge. A browser can still reach a login page when curl cannot. |

A green Exit means the route is a tunnel, both sites saw the same allowed IP, and curl was not challenged. It does not mean you can log in. It does not mean Claude or ChatGPT will accept the account. It does not mean the IP looks like a home connection. Vendors can still call that address a VPN, a datacenter, or a proxy. Cavok does not ask them.

A Japan exit also does not change where the account was created, where the card was issued, or where the person is sitting. Anthropic's supported-regions rule is about physical location and the entity behind the account. OpenAI says access from outside its country list can lead to a block, and that a VPN can trigger one. Cavok can shrink some local mismatches. It cannot make the setup compliant, and it cannot tell you how close you are to being flagged.

## What it leaves alone

- Account country, card country, phone number, and email age. Cavok never sees them.
- IP reputation, ASN, and whether the address is residential. That would send the IP to someone else's service. Cavok does not.
- Surfshark's selected server, protocol, Kill Switch, and Bypasser. Any `utun` looks like a tunnel.
- The browser. Sockets are checked for Claude, ChatGPT, `claude`, and `codex`. Chrome and Safari are not. WebRTC, DNS-over-HTTPS, and Private Relay are not.
- The phone apps. A phone on home Wi-Fi writes that address onto the same account.
- Project files on the Desktop, until you add that folder in Settings.

Reports name the setting that was found. They do not include secret values, and nothing is uploaded to a Cavok server. The pinned IP, the saved time zone, Guard, and the project folders stay in this Mac's preferences. The first time a file is edited, the original is kept beside it as `.cavok-bak`. A later clean does not replace that first copy.

Longer notes on each row are in [docs/tool.md](docs/tool.md). The rest of this file is how to run a session.

## Open it

The app is installed at `/Applications/Cavok.app`.

```sh
open /Applications/Cavok.app
```

You get a window and a menu-bar icon. Closing the window leaves the icon in place. **Quit** in the menu-bar panel quits Cavok.

The icon shows the exit country, such as `JP`. It shows `LAN` when traffic would leave over Wi-Fi or Ethernet. It shows `…` while a check is running.

## One normal session

1. Connect the Surfshark Japan static server.
2. Open Cavok. Wait until the rows finish.
3. **Tunnel route** should be green. If it is orange, you are not on the VPN. Cavok will not contact Claude or ChatGPT until you are.
4. On **Exit IP**, click **Pin this IP** when Claude and ChatGPT show the same allowed address. Leave that server selected.
5. Leave **Guard** on. It is on by default.
6. Click **Open Claude** or **Open ChatGPT** when those buttons are available.

Check Again is Command-R. The same button is in the menu bar and the Dock menu.

## What the symbols mean

| Symbol | Meaning |
|---|---|
| Green check | This row looks fine. |
| Orange triangle | Something is worth fixing. Read the line, then use the button on that row. |
| Empty circle | Cavok measured it and is not calling it a problem. A failed check stays here too. A timeout is not a pass. |

## What to do when a row is orange

| Row | What it is telling you | What to click |
|---|---|---|
| Tunnel route | Traffic would go out over Wi-Fi or Ethernet. | Reconnect Surfshark. There is no button. Guard quits Claude, ChatGPT, `claude`, and `codex` if this happens while they are open. |
| Exit IP | Claude's address is HK, CN, or MO, it is not the address you pinned, it differs from ChatGPT, or the shared exit is not pinned yet. | Reconnect the pinned server. **Pin this IP** appears only when both traces returned the same allowed address. |
| ChatGPT exit | ChatGPT sees a different address, an address in HK, CN, or MO, or the shared exit is not pinned yet. | Reconnect Surfshark. The two exits are peers. A split is a failed check. |
| Service reachability | curl's headers for claude.ai or chatgpt.com include `cf-mitigated`, or status 403 or 421. | Nothing to click. This is curl's result. It does not turn the open buttons off. |
| Shell startup files | A startup file still sets a proxy or a custom API address. | **Comment out**. Open a new terminal before using claude or ChatGPT. |
| Login environment | The same kind of setting is on for apps launched from the Dock. | **Remove**. |
| Claude configs | A Claude settings file points at a relay or a proxy. Project files count, not only the one in your home folder. | **Remove**. |
| Codex config | `~/.codex/config.toml` points at a relay. | **Comment out**. |
| System proxy | macOS itself has an HTTP, HTTPS, SOCKS, or automatic proxy turned on. Claude and ChatGPT follow that. | **Turn off**. macOS asks for your password. Surfshark is left alone. |
| Open app sockets | Claude, ChatGPT, Codex, or a child of those processes still has a connection on Wi-Fi or Ethernet. vim, grep, man, and git do not match by name. | **Quit apps**. |
| IPv6 | IPv6 would leave outside the tunnel, or claude.ai or chatgpt.com returned a real IPv6 address in HK, CN, MO, or a different country from that host's IPv4 exit. | **Set link-local**. macOS asks for your password. **Restore automatic** puts it back later. |
| DNS | A resolver is on Wi-Fi or Ethernet while the IPv4 route is a tunnel. | **Flush** only clears the cache. An empty circle means the nameservers were read. That is not a pass. |
| Time zone and locale | An exit is JP and the Mac clock is not Tokyo, or a locale or input source carries HK, CN, or MO while an exit is not that country. | Optional. **Set to Tokyo** only if you want the clock to match a Japan exit. Locale is not rewritten. |

**Clean leftovers** runs the shell, login-environment, Claude config, and Codex config fixes together. It stays off when those four are already clear. It does not change the VPN, the pinned IP, IPv6, DNS, or the time zone.

The first time Cavok edits a file, it saves `.cavok-bak` next to the original and keeps that first copy. A later clean does not replace it.

## Guard

Guard is the switch in the menu-bar panel and in Settings. Leave it on.

| What happened | What Guard does |
|---|---|
| Surfshark drops, or the route goes back to Wi-Fi | Quits Claude, ChatGPT, `claude`, `codex`, and a child of those processes. The set is taken before the first signal. |
| The route to claude.ai or chatgpt.com is Wi-Fi or Ethernet | Quits those same apps. |
| A check actually comes back as HK, CN, or MO | Quits those same apps. |
| You close the lid | Quits them normally, while the tunnel is still up. |
| The Mac wakes | Waits 2.5 seconds, then runs a full check. A network change during that wait starts the wait over. |
| The tunnel stays up and a minute passes | Reads both exits again. A full check runs when an address or country changed, or after two quiet readings in a row. A timeout by itself changes nothing. |
| You open Claude or ChatGPT while the check is already bad | Quits them again. |
| A pin is set and either exit is a different IP, including another Japan IP | Quits those same apps. |
| Claude and ChatGPT were both read and the addresses differ | Quits those same apps. |
| A shell file, the login environment, a Claude config, the Codex config, or a system proxy still has a leftover | Quits those same apps. |
| A Claude or ChatGPT connection is on Wi-Fi or Ethernet | Quits those same apps, then reads the sockets once more. |
| IPv6 is on Wi-Fi or Ethernet, or either host returned a real IPv6 address in HK, CN, MO, or a different country from that host's IPv4 exit | Quits those same apps. |
| No pin yet, and both exits are the same allowed country | Nothing is quit. Both exit rows stay orange until you pin that shared address. Open stays off until then. |
| The time zone, the locale, a curl challenge, or DNS | Nothing is quit. DNS warns only when a resolver interface is Wi-Fi or Ethernet while the IPv4 route is a tunnel. |
| A check times out | Nothing is quit. The open buttons stay off until both exits have been read. |

Cavok matches `claude`, `claude-code`, and `codex` (including `codex-aarch64-…`) by the program name. When the program is `node`, it matches the script path, including `@anthropic-ai/claude-code/` `cli.js`. A mention in vim, grep, man, or git does not count. A child of a matched process does. The quit list is collected before the first signal, because SIGKILL of the parent does not take the child with it.

## Buttons along the bottom

| Button | What it does |
|---|---|
| Check Again | Runs every row again. |
| Clean leftovers | Fixes the file and environment rows that are orange. |
| Open Claude | Opens `Claude.app`. Says `Claude.app is not installed.` when it is missing. |
| Open ChatGPT | Opens `ChatGPT.app`. Says `ChatGPT.app is not installed.` when it is missing. |
| Open Window | Brings the main window back. |
| Quit | Quits Cavok. Claude and ChatGPT keep running. |

Both open buttons use one rule. They stay off until both exits have been read, the countries are the same allowed country, the addresses are equal and pinned, the route is a tunnel, no socket is on Wi-Fi or Ethernet, and Guard has nothing to quit for. A missing ChatGPT trace leaves both off. A curl challenge does not.

## Settings

Open Settings from the Cavok menu in the menu bar.

- **Show Cavok in the menu bar** hides or shows the icon. Closing the window does not hide it.
- **Guard** is the same switch as in the panel.
- **Project folders** are where Cavok looks for a leftover `.claude/settings.json` or `settings.local.json`. On first launch it adds `~/Projects` and `~/Developer` if those folders exist. Your repos on the Desktop are not included until you click **Add Folder…** and choose Desktop.

## Build

Requires macOS 26.

```sh
swift test
./build.sh --open
```

`./build.sh` installs `/Applications/Cavok.app`. `--open` quits the running copy and opens the new one. If the content-filter entitlement is not on the signing identity, the menu-bar app still installs and the packet drop stays off.

## Packet drop on the street door

Guard arms this drop when it is on. If the filter is not actually enabled, **Open Claude** and **Open ChatGPT** stay off. A green check still does not mean the account is safe, and this drop does not make the setup compliant.

A routing message, and a later path change, look up `1.1.1.1` and the two addresses the stored traces reached on a routing socket in this process. They do not spawn `route` or `networksetup`. If any of those three interfaces is Wi-Fi or Ethernet and Guard is on, Cavok force-quits the processes below. The first path event is ignored. A change that is still a tunnel waits 2.5 seconds and runs a full check. Electron can still open a new connection before that `SIGKILL` lands. The turnstile below is what stops that new socket. It does not change what a green check means, and it does not make the setup compliant.

Picture the Mac as a building with two doors. The tunnel door is Surfshark. The street door is Wi-Fi or Ethernet. Guard today is a person who sees Claude heading for the street and runs over to pull them back. One step can already be on the pavement. That step is the packet. The update puts a turnstile on the street door. Safari, Mail, and Surfshark keep both doors, because Surfshark has to be able to reconnect.

Any `utun` still counts as a tunnel, including macOS's own `utun` interfaces and another VPN. The traces still have to agree on an allowed country before either open button enables. A tunnel that is not Surfshark, with both exits in an allowed country, is still a pass. This update does not learn which tunnel is Surfshark.

### What gets dropped

The turnstile looks at the processes Guard already quits, and at their descendants:

| Process | How it is recognized |
|---|---|
| Claude.app | The path contains `Claude.app`. Electron helpers inside that bundle match on the same path. |
| ChatGPT.app | The path contains `ChatGPT.app`. Electron helpers inside that bundle match on the same path. |
| `claude`, `claude-code` | The program name. |
| `codex`, including `codex-aarch64-…` | The program name. |
| `node` | Only when the script path is the Claude Code CLI, including `@anthropic-ai/claude-code/` `cli.js`. The audit token does not carry the script. The extension reads the arguments for that pid once and remembers them. |
| A descendant of `claude`, `claude-code`, or `codex` | The parent chain. `curl`, `git`, `python3`, and an MCP server binary match when an ancestor matches a row above. The walk stops at pid 1. An ancestor is included only when it matches on its own. |

A mention of those names in vim, grep, man, or git does not match. `node` running any other script does not match. Chrome, Safari, and every other app do not match. `SIGKILL` of the parent does not take a child with it, which is why the child is matched on its own.

The match stores the process start time with the pid. A pid gets reused. The new process does not keep the old rule unless it matches on its own.

For a process that does match, each new TCP or UDP socket is judged before the packet is sent. The judgment is an in-process routing-socket query for that destination: `RTM_GET`, then the interface name. It returns the same answer as `route -n get` for that address. The extension does not spawn `/sbin/route` on each socket. It does not ask the system default path. The default route can still name `en0` while traffic to `1.1.1.1` uses `utun`, which is why today's check looks up `1.1.1.1`.

The function that answers "tunnel, loopback, physical, or unknown" lives in CavokKit and is unit-tested the same way the route parser is. If the extension sandbox refuses the routing socket, the filter does not arm.

| What the route says | What the turnstile does |
|---|---|
| Tunnel: `utun`, `ipsec`, `ppp`, or `wg` | Allow for now. That allow is not final. |
| Loopback, this Mac only | Allow. |
| Physical: `en*`, `bridge*`, `ap*`, or a hardware port from `networksetup` | Drop. Nothing from that socket is transmitted. |
| The route cannot be read | Drop. An unknown door is treated as the street door. |

A final allow sticks to that socket. Later packets on it are not judged again. A pid that cannot be read yet is held: those bytes are not passed, and that socket is not given a final allow. A connected TCP socket is bound to the address it had on the tunnel. When that interface disappears, those sends fail. They do not move onto Wi-Fi. The TCP leak is the new connect Electron opens after that failure, and that new connect is judged from scratch.

UDP is weaker. A socket that was allowed while the tunnel was up can send again after the route changes, with no new socket event. QUIC on that kind of socket is the case. So a tunnel allow lasts only while the route for the public destination stays a tunnel. When that route leaves the tunnel, the extension force-quits the protected set, including descendants. The menu-bar quit collects that same set before it signals. The extension's quit is the one that does not wait for the menu-bar hop.

The filter does not read the payload. It does not log the bytes. It looks at the process path, the arguments, the parent chain, the start time, and the interface name from the in-process lookup.

A system DNS lookup is not one of those sockets. `getaddrinfo` asks `mDNSResponder`, and `mDNSResponder` sends the packet. The filter sees `mDNSResponder`, so this update does not claim to drop system lookups per app, and it does not add a DNS proxy. A lookup that the app sends on its own socket still goes through the socket rule. That includes Node's own resolver and Chromium's own resolver or DNS-over-HTTPS. The DNS row in the window stays a warning for the rest of the Mac.

The existing quit stays, and the signals stay as they are today. A physical route, a bad exit, a split, a pin miss, a leftover proxy or relay, or a real IPv6 leak still force-quits Claude, ChatGPT, `claude`, `codex`, and a child of those processes. The list is taken before the first signal. Sleep still quits them normally, while the tunnel is up. A timeout, the clock, the locale, and a curl challenge still quit nothing.

### Why this shape

A list of blocked IP addresses on the street door does not do this job. Cloudflare can answer with a different address after the tunnel has fallen back to `en0`. The new address is not on the list, and the packet still leaves. A packet filter rule also cannot name Claude.app, the `node` script, or a child `curl`. The socket filter's flow object has the remote endpoint and the audit token, and the endpoint can be empty when the socket is new. It does not carry an interface name, so the interface has to come from the routing-socket query above.

The main rules on this Mac, in `/etc/pf.conf`, only evaluate anchors under `com.apple/*`. The update does not add a host-wide block, a GID sandbox, or an anchor that drops every program on Wi-Fi. Surfshark's own traffic has to keep using the physical interface so the tunnel can come back. If the filter cannot arm, that is the end of this update. A host-wide block is not the fallback.

The update also leaves these alone:

- Time zone, locale, and input sources. Nothing is rewritten, and nothing is hooked inside Claude or ChatGPT to report a different clock or language.
- Hardware serial and hardware UUID.
- Browser fingerprints, cookies, and a separate browser.
- ASN lookups, IP reputation, and any service that would be sent the exit address.
- Account country, card country, and login. Cavok still never logs in.
- Which `utun` is Surfshark. The traces remain the exit check.

### How it turns on

The turnstile is a content-filter system extension, `CavokGuardFilter`, embedded in `Cavok.app`. On each new socket it asks one function in CavokKit: does this process, or an ancestor, match the table above, and is the in-process route a tunnel, loopback, physical, or unknown.

Arming happens when Guard is on, before a drop is noticed. Turning Guard off disables the filter. Quitting Cavok disables the filter. The first time it is enabled, macOS asks for approval in System Settings. That approval is once.

The app and the extension need a paid Apple Developer Program membership, and a profile for `com.isaaccheung.cavok` that carries the content-filter entitlement (`content-filter-provider`). A free Personal Team profile cannot carry it. An ad-hoc signature cannot activate a system extension. SIP stays on. This update does not turn SIP off, and it does not use system-extension developer mode as the way to run. If the membership or the entitlement is missing, the menu-bar app still installs, the filter stays off, and the window says the packet drop is not armed. There is no substitute that blocks the whole Mac.

Apple activates a system extension from an app in `/Applications`. `./build.sh` installs `/Applications/Cavok.app`. That copy asks for an administrator password when this user cannot write `/Applications` directly, the same way the IPv6 and system-proxy buttons already do.

While Guard is on and the filter is not actually enabled, **Open Claude** and **Open ChatGPT** stay off. A good exit reading with no armed drop is still an open street door. The help under the buttons says the packet drop is not armed.

The Guard control in the menu bar and in the window gains one line:

| State | Line |
|---|---|
| Filter enabled | Packet drop is on. Wi-Fi and Ethernet stay closed for Claude and ChatGPT. |
| The extension is not in this build | Packet drop is not armed. This build does not include the filter extension. Open stays off. |
| macOS needs approval | Packet drop needs your approval in System Settings. **Open System Settings** sits next to the line. Open stays off. |
| Activation or preferences failed | The line names the error. Open stays off. |
| Guard on, filter not enabled | Packet drop is not armed. Open stays off. |

### How it will be checked

`swift test` covers the decision function and nothing that needs root:

| Case | Result |
|---|---|
| Protected process, route for that destination is a tunnel | Allow for this lookup. The allow is not final once the route leaves the tunnel. |
| Protected process, route is `en0` or another physical interface | Drop. |
| Protected process, route cannot be read | Drop. |
| Protected process, destination is loopback | Allow. |
| `node` running the Claude Code `cli.js` | Drop when the route is physical. |
| `node` running any other script | Allow. |
| `curl`, `git`, or `python3` whose ancestor is `claude`, `claude-code`, or `codex` | Drop when the route is physical. |
| Same pid later, with a different start time, and no match of its own | Allow. |
| vim, grep, man, or git mentioning claude, with no matching ancestor | Allow. |
| A system lookup sent by `mDNSResponder` | Outside this decision. Not a per-app drop. |

The live check, after install, is on this Mac. Approve the extension. Confirm the Guard line says the packet drop is on. Turn the tunnel off. Safari should still load an ordinary page. The filter log should show a drop for a protected process, including a `curl` started under `claude` or `codex`. That check does not open a signed-in Claude or ChatGPT session. If the extension will not activate, or the sandbox refuses the routing socket, the work stops on that error. A host-wide packet-filter block is not the fallback.
