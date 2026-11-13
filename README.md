# Cavok

Cavok is a personal macOS menu-bar app for one setup: this Mac is in Hong Kong, Surfshark is supposed to send traffic out through a Japan static server, and Claude and ChatGPT are used on that path. It checks the Mac before those apps run, and it can quit them when the path looks wrong.

A green check means that one local check passed. It does not mean the account is safe. Cavok never logs in, never reads a card, and cannot switch Surfshark for you.

Hong Kong, mainland China, and Macau are the only countries it treats as a bad exit.

## What it is for

The point is local hygiene on this machine. Claude and ChatGPT are peers. A split tunnel can make one look fine while the other leaves somewhere else, so Cavok reads both and treats a disagreement as a failed check.

Before you open either app, Cavok looks for the ways this Mac can still show a home address, a relay, or a different exit:

- The route to the public internet is Wi-Fi or Ethernet instead of a tunnel. The lookup is `route -n get 1.1.1.1`, because a WireGuard-style tunnel often leaves the literal default route on `en0`.
- `claude.ai` and `chatgpt.com` see different IP addresses or countries. Each row is its own request to `/cdn-cgi/trace`.
- Either exit is HK, CN, or MO, or either address is not the one you pinned. **Pin this IP** saves the shared address only when both traces returned that same allowed IP.
- A shell startup file, the login environment, a Claude settings file, or `~/.codex/config.toml` still points at a proxy or a non-official API host. Codex is this config check. It is not an exit row and it is not a login test.
- macOS has an HTTP, HTTPS, SOCKS, or automatic proxy turned on.
- Claude, ChatGPT, `claude`, or `codex` still has a connection whose local address is on Wi-Fi or Ethernet.
- IPv6 is a real second path. An IPv4 address, including an address returned through `::ffff:`, does not count as IPv6.
- A DNS resolver is bound to Wi-Fi or Ethernet while the IPv4 route is a tunnel. Reading the resolver addresses is not, by itself, a pass.
- The clock is not Tokyo while an exit is JP, or the locale, languages, or input sources still carry HK, CN, or MO. That row is a warning. It does not quit anything, and it does not rewrite the locale.

Guard is the part that acts. While it is on, Cavok quits Claude, ChatGPT, `claude`, and `codex` when the route leaves the tunnel, either exit is a bad country, the two exits disagree, a pinned IP no longer matches, a proxy or relay is still set, or IPv6 is a real leak. It also quits them when the lid closes, while the tunnel is still up. A timeout, the clock, the locale, a curl challenge, and ordinary DNS do not quit anything.

**Open Claude** and **Open ChatGPT** stay off until both exits have been read and they agree on an allowed address, the route is a tunnel, no socket is on Wi-Fi or Ethernet, and Guard has nothing to quit for. The buttons open the apps, or the websites if the apps are not installed. They do not log in.

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

The app is installed at `~/Applications/Cavok.app`.

```sh
open ~/Applications/Cavok.app
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
| Open app sockets | Claude, ChatGPT, or Codex still has a connection on Wi-Fi or Ethernet from before the VPN came up. | **Quit apps**. |
| IPv6 | IPv6 would leave outside the tunnel, or claude.ai or chatgpt.com returned a real IPv6 address in HK, CN, MO, or a different country from that host's IPv4 exit. | **Set link-local**. macOS asks for your password. **Restore automatic** puts it back later. |
| DNS | A resolver is on Wi-Fi or Ethernet while the IPv4 route is a tunnel. | **Flush** only clears the cache. An empty circle means the nameservers were read. That is not a pass. |
| Time zone and locale | An exit is JP and the Mac clock is not Tokyo, or a locale or input source carries HK, CN, or MO while an exit is not that country. | Optional. **Set to Tokyo** only if you want the clock to match a Japan exit. Locale is not rewritten. |

**Clean leftovers** runs the shell, login-environment, Claude config, and Codex config fixes together. It stays off when those four are already clear. It does not change the VPN, the pinned IP, IPv6, DNS, or the time zone.

The first time Cavok edits a file, it saves `.cavok-bak` next to the original and keeps that first copy. A later clean does not replace it.

## Guard

Guard is the switch in the menu-bar panel and in Settings. Leave it on.

| What happened | What Guard does |
|---|---|
| Surfshark drops, or the route goes back to Wi-Fi | Quits Claude, ChatGPT, `claude`, and `codex` immediately. |
| A check actually comes back as HK, CN, or MO | Quits those same apps. |
| You close the lid | Quits them normally, while the tunnel is still up. |
| You open Claude or ChatGPT while the check is already bad | Quits them again. |
| A pin is set and either exit is a different IP, including another Japan IP | Quits those same apps. |
| Claude and ChatGPT were both read and the addresses differ | Quits those same apps. |
| A shell file, the login environment, a Claude config, the Codex config, or a system proxy still has a leftover | Quits those same apps. |
| IPv6 is on Wi-Fi or Ethernet, or either host returned a real IPv6 address in HK, CN, MO, or a different country from that host's IPv4 exit | Quits those same apps. |
| No pin yet, and both exits are the same allowed country | Nothing is quit. Both exit rows stay orange until you pin that shared address. |
| The time zone, the locale, a curl challenge, or DNS | Nothing is quit. DNS warns only when a resolver interface is Wi-Fi or Ethernet while the IPv4 route is a tunnel. |
| A check times out | Nothing is quit. The open buttons stay off until both exits have been read. |

Cavok matches `claude`, `claude-code`, and `codex` (including `codex-aarch64-…`) by the program name. When the program is `node`, it matches the script path, including `@anthropic-ai/claude-code/` `cli.js`. A mention in vim, grep, man, or git does not count.

## Buttons along the bottom

| Button | What it does |
|---|---|
| Check Again | Runs every row again. |
| Clean leftovers | Fixes the file and environment rows that are orange. |
| Open Claude | Opens `Claude.app`, or claude.ai if the app is not installed. |
| Open ChatGPT | Opens `ChatGPT.app`, or chatgpt.com if the app is not installed. |
| Open Window | Brings the main window back. |
| Quit | Quits Cavok. Claude and ChatGPT keep running. |

Both open buttons use one rule. They stay off until both exits have been read, the countries are the same allowed country, the addresses are equal, the route is a tunnel, no socket is on Wi-Fi or Ethernet, and Guard has nothing to quit for. A missing ChatGPT trace leaves both off. A curl challenge does not.

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

`./build.sh` installs `~/Applications/Cavok.app`. `--open` quits the running copy and opens the new one.
