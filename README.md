# Cavok

Cavok sits in the Mac menu bar and checks this Mac before you use Claude or ChatGPT. A green check means that one local check passed. It does not mean the account is safe. Cavok never logs in, never reads a card, and cannot switch Surfshark for you.

Hong Kong, mainland China, and Macau are the only countries it treats as a bad exit.

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
4. On **Exit IP**, click **Pin this IP** while that Japan server is connected. Leave that server selected.
5. Leave **Guard** on. It is on by default.
6. Click **Open Claude** when that button is available.

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
| Tunnel route | Traffic would go out over Wi-Fi or Ethernet. | Reconnect Surfshark. There is no button. Guard quits Claude and Codex if this happens while they are open. |
| Exit IP | The address Claude sees is HK, CN, or MO, or it is not the address you pinned. | Reconnect the pinned server, or click **Pin this IP** if this new address is the one you want to keep. |
| ChatGPT exit | ChatGPT sees a different address, or an address in HK, CN, or MO. | Reconnect Surfshark. Claude can look fine while ChatGPT does not. |
| Shell startup files | A startup file still sets a proxy or a custom API address. | **Comment out**. Open a new terminal afterward. |
| Login environment | The same kind of setting is on for apps launched from the Dock. | **Remove**. |
| Claude configs | A Claude settings file points at a relay or a proxy. Project files count, not only the one in your home folder. | **Remove**. |
| Codex config | `~/.codex/config.toml` points at a relay. | **Comment out**. |
| System proxy | macOS itself has an HTTP, HTTPS, SOCKS, or automatic proxy turned on. `Claude.app` follows that. | **Turn off**. macOS asks for your password. Surfshark is left alone. |
| Open app sockets | Claude or Codex still has a connection on Wi-Fi or Ethernet from before the VPN came up. | **Quit apps**. |
| IPv6 | IPv6 would leave outside the tunnel, or it shows a different country. | **Set link-local**. macOS asks for your password. **Restore automatic** puts it back later. |
| Time zone | The Mac clock is not Tokyo. | Optional. **Set to Tokyo** only if you want the clock to match a Japan exit. |

**Clean leftovers** runs the shell, login-environment, Claude config, and Codex config fixes together. It stays off when those four are already clear. It does not change the VPN, the pinned IP, IPv6, DNS, or the time zone.

Any file Cavok edits is copied first, next to the original, with `.cavok-bak` on the name.

## Guard

Guard is the switch in the menu-bar panel and in Settings. Leave it on.

| What happened | What Guard does |
|---|---|
| Surfshark drops, or the route goes back to Wi-Fi | Quits Claude, ChatGPT, `claude`, and `codex` immediately. |
| A check actually comes back as HK, CN, or MO | Quits those same apps. |
| You close the lid | Quits them normally, while the tunnel is still up. |
| You open Claude or ChatGPT while the check is already bad | Quits them again. |
| The IP changes but the country is still allowed | Warning only. It does not quit anything. |
| A check times out | Nothing is quit. An empty circle means Cavok could not measure. |

Cavok cannot tell npm's `claude` apart from other programs by the short process name, because that name is `node`. It matches the command line instead.

## Buttons along the bottom

| Button | What it does |
|---|---|
| Check Again | Runs every row again. |
| Clean leftovers | Fixes the file and environment rows that are orange. |
| Open Claude | Opens `Claude.app`, or claude.ai if the app is not installed. Stays off when the route is not a tunnel, either exit is HK, CN, or MO, or a socket is still on Wi-Fi or Ethernet. |
| Open Window | Brings the main window back. |
| Quit | Quits Cavok. Claude keeps running. |

## Settings

Open Settings from the Cavok menu in the menu bar.

- **Show Cavok in the menu bar** hides or shows the icon. Closing the window does not hide it.
- **Guard** is the same switch as in the panel.
- **Project folders** are where Cavok looks for a leftover `.claude/settings.json` or `settings.local.json`. On first launch it adds `~/Projects` and `~/Developer` if those folders exist. Your repos on the Desktop are not included until you click **Add Folder…** and choose Desktop.

## What a clear screen still does not cover

- The phone apps. A phone on home Wi-Fi writes that address onto the same account.
- Which Surfshark server, Kill Switch, or Bypasser option you picked. Cavok only sees the address that comes out.
- Whether the address is a home connection or a datacenter.
- Where the account or the card was created.

Longer notes on each row are in [docs/tool.md](docs/tool.md).

## Build

Requires macOS 26.

```sh
swift test
./build.sh --open
```

`./build.sh` installs `~/Applications/Cavok.app`. `--open` quits the running copy and opens the new one.
