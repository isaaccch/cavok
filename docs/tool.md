# Cavok

Cavok is a Mac app that checks this Mac, then offers a button for each thing it can change. It also sits in the menu bar.

A clear screen means those local checks passed. It does not mean Claude or ChatGPT has decided the account is safe. Cavok never logs in, never reads a card, and never sees either company's risk system.

## What a ban actually is

Anthropic's published reasons for a ban are repeated Usage Policy violations, an account created from an unsupported location, and Terms of Service violations. OpenAI says access from an unsupported country can block or suspend an account. Neither company publishes a rule that says "this IP score" or "this daily IP change" is a ban.

Cavok watches the local signals that can make one account look like it is hopping exits, leaking a home address, or sending subscription traffic through a relay. Those are the signals discussed for this setup. They are not a complete list of why an account gets flagged.

Hong Kong, mainland China, and Macau are the only countries Cavok treats as a bad exit. It does not download Anthropic's or OpenAI's full country list.

## The checks

Each row is one check. A warning is an orange triangle. A clear row is a green check. An empty circle means Cavok measured something and is not calling it a problem.

| Row | What it measures | Why it matters | What the button does |
|---|---|---|---|
| Tunnel route | `route -n get 1.1.1.1`, then the `interface:` line. `utun`, `ipsec`, `ppp`, and `wg` count as a tunnel. Wi-Fi and Ethernet do not. The same lookup is done for IPv6 with `2606:4700:4700::1111`. | The lookup does not send a packet. `route -n get default` can still say `en0` when a WireGuard-style tunnel has installed `0.0.0.0/1` and `128.0.0.0/1`. If this row is Wi-Fi or Ethernet, Cavok does not call `claude.ai` or `chatgpt.com`. | None. |
| Exit IP | The IPv4 address and country in `https://claude.ai/cdn-cgi/trace` (`ip=` and `loc=`), and only after the route is a tunnel. | An exit in HK, CN, or MO is outside the regions this setup is using. After you pin an address, a different IP for either product is a failed pin, including another Japan IP. Cavok cannot switch Surfshark. Until the shared exit is pinned, both exit rows stay a warning. That warning does not quit anything. | **Pin this IP** appears only when both traces returned the same allowed address. It saves that shared exit. It refuses HK, CN, MO, and a one-sided result. When the country changed, both exit rows include the pinned country. |
| ChatGPT exit | `ip=` and `loc=` from `https://chatgpt.com/cdn-cgi/trace`. It is not copied from the Claude result. | A split tunnel can send ChatGPT somewhere else while Claude still looks fine. The two exits are peers. | None. Two addresses that were both read and differ, a pin mismatch, or HK, CN, or MO makes Guard quit Claude and ChatGPT. |
| Service reachability | After the route is a tunnel, `curl -4` headers for `https://claude.ai/` and `https://chatgpt.com/`. The body is discarded. | A `cf-mitigated` header, or status 403 or 421, means curl was challenged. The row names the host. This is curl's result and does not mean either app or a browser is blocked. | None. A challenge does not turn the open buttons off. The trace rows are what catch a split tunnel. |
| Shell startup files | Assignments and `launchctl setenv` lines in `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.bash_profile`, `~/.bashrc`, and `~/.profile`. | A leftover `HTTPS_PROXY` or `ANTHROPIC_BASE_URL` can send `claude` or `codex` somewhere other than the Surfshark tunnel, including a third-party relay. | **Comment out** comments those lines. The first copy is kept as `.cavok-bak` beside the file. Open a new terminal before using claude or ChatGPT. |
| Login environment | `launchctl getenv` for proxy variables and `ANTHROPIC_BASE_URL`, `OPENAI_BASE_URL`, `OPENAI_API_BASE`. | Apps launched from the Dock, including Claude and ChatGPT, inherit this environment. A value here can override the tunnel for GUI apps even when Terminal looks fine. | **Remove** runs `launchctl unsetenv` for the names it found. It does not print the values. |
| Claude configs | The `env` object in `~/.claude/settings.json`. Proxy and base-URL keys in `~/.claude.json`, including MCP server `env` blocks. `.claude/settings.json` and `.claude/settings.local.json` up to four levels under the folders in Settings. `node_modules`, `.git`, `.build`, `DerivedData`, and `Library` are skipped. | A project file overrides `~/.claude/settings.json`. A base URL that is not an Anthropic or OpenAI host sends the CLI through a relay. | **Remove** drops proxy keys, and drops a non-official base URL. A token is removed only when that same object points at a non-official host. An official base URL and its token stay. The first copy of a changed file is kept as `.cavok-bak`. |
| Codex config | `openai_base_url`, `chatgpt_base_url`, and `base_url` inside `[model_providers…]` in `~/.codex/config.toml` (`$CODEX_HOME` when that is set). | Codex uses this file for a custom API host. A project `.env` is not read. | **Comment out** comments the non-official lines. The first copy is kept as `config.toml.cavok-bak`. |
| System proxy | `HTTPEnable`, `HTTPSEnable`, `SOCKSEnable`, `ProxyAutoConfigEnable`, and `ProxyAutoDiscoveryEnable` from `scutil --proxy`. | Claude and ChatGPT follow the macOS proxy even when `launchctl` is empty. | **Turn off** runs `networksetup` on Wi-Fi and Ethernet. Surfshark is left alone. macOS asks for a password. |
| Open app sockets | `lsof` for the PIDs Cavok would quit: Claude.app, ChatGPT.app, `claude`, `claude-code`, `codex` (including `codex-aarch64-…` and `node` running `cli.js`), and a child of those processes. A hit is an open connection whose local address belongs to Wi-Fi or Ethernet. | A connection opened before the VPN can stay on the physical interface. Loopback is ignored. vim, grep, man, and git do not match by name. A child of a matched process does. | **Quit apps** force-quits that set. The set is collected before the first signal. |
| IPv6 | `curl -6` to `https://claude.ai/cdn-cgi/trace` and `https://chatgpt.com/cdn-cgi/trace` when the IPv6 route is a tunnel. An `ip=` with no colon, or one that contains `::ffff:`, is not an IPv6 result. No `interface:` line is the idle line "IPv6 not present". | On a tunnel, a real IPv6 address is compared with that same host's IPv4 country, and the two hosts are compared with each other. The row names which host returned which address. A failed `curl -6` stays "did not answer" and is an empty circle, not a green check. If IPv6 is on Wi-Fi, Cavok does not send the probe. | **Set link-local** runs `networksetup -setv6LinkLocal` on Wi-Fi, Ethernet, and other non-Surfshark services. macOS asks for a password. **Restore automatic** appears only after Cavok made that change. |
| DNS | Nameservers and `if_index : N (utun4)` from `scutil --dns`, before the "scoped queries" section. | The row stays an empty circle when nameservers were only read. It warns when a resolver interface is Wi-Fi or Ethernet while the IPv4 route is a tunnel. Resolver country is not shown. | **Flush** clears the cache with `dscacheutil` and `mDNSResponder`. It does not change which resolver you use. It does not feed Guard. |
| Time zone and locale | `TimeZone.current`, plus `AppleLocale`, `AppleLanguages`, and `AppleEnabledInputSources` on this Mac. | Warns when either exit is JP and the clock is not `Asia/Tokyo`. Also warns when those preferences carry an HK, CN, or MO tag, including `yue-Hant-HK`, `zh-Hans-HK`, `zh-Hant-HK`, and a Chinese input mode, while an exit country is not that country. | **Set to Tokyo** sets `Asia/Tokyo`, turns automatic time zone off, and remembers the previous zone. **Restore** puts that zone back and turns automatic time zone on again. Locale is not rewritten. The row does not feed Guard. macOS asks for a password. |

**Clean leftovers** runs the shell, login-environment, Claude config, and Codex config fixes together. It stays off when those rows are already clear. It does not change IPv6, DNS, the system proxy, the time zone, or the pinned IP.

**Open Claude** opens `Claude.app` if it is installed, otherwise `https://claude.ai`. **Open ChatGPT** opens `ChatGPT.app` if it is installed, otherwise `https://chatgpt.com`. Both stay off until both exits have been read, the countries are the same allowed country, the addresses are equal and pinned, the route is a tunnel, no socket is on Wi-Fi or Ethernet, and none of the Guard reasons below are set. A missing ChatGPT trace leaves both off. A curl challenge does not.

**Guard** is a switch in the menu bar and in Settings. It is on until you turn it off.

- When the route changes, Cavok looks up `1.1.1.1` on a routing socket in this process. That is the same answer as `route -n get 1.1.1.1`. If that interface is Wi-Fi or Ethernet, Guard force-quits Claude, ChatGPT, `claude`, `codex`, and a child of those processes. The set is taken before the first signal. A path change does the same lookup. Neither one spawns `route` or `networksetup`.
- If the route is still a tunnel, Cavok waits 2.5 seconds and runs a full check, so a Surfshark reconnect can finish before the trace.
- Every minute, while the route is a tunnel, Cavok reads both IPv4 exits again. If an address or country changed, it runs a full check. A host that did not answer is not a change, but two quiet readings in a row—a host that answered last time now returns nothing—run a full check. The rows then show "did not answer" and Open turns off. Nothing is quit.
- When the Mac wakes, Cavok waits 2.5 seconds and runs a full check. A route change during that wait starts the wait over.
- A completed trace of HK, CN, or MO on Claude or ChatGPT force-quits the same processes. So does a pin mismatch on either exit, including another Japan IP, and two IPv4 exits that were both read and differ. A leftover in the shell, the login environment, a Claude config, the Codex config, or the system proxy does too. So does a Claude or ChatGPT connection on Wi-Fi or Ethernet. A real IPv6 leak does too: the IPv6 route is physical, or either host returned a real IPv6 address in HK, CN, or MO, or in a different country from that host's IPv4 exit.
- A timeout does not quit anything. The open buttons stay off until both exits have been read. No pin yet, with both countries allowed and equal, does not quit anything, but Open stays off until the shared exit is pinned. The time zone, the locale, a curl challenge, and DNS do not quit anything.
- While a check stays blocked, Guard checks about four times a second and force-quits `claude`, `codex`, Claude, ChatGPT, and a child of those processes. The match is the program name, or the script path when the program is `node`. vim, grep, man, and git do not match by name. A child of a matched process does. The set is collected before the first signal.
- Sleep quits those processes with a normal quit, before the tunnel drops. Lid-close does not use force-quit.
- Launching Claude.app or ChatGPT.app while the current check is blocked force-quits them.

## How a warning lines up with ban risk

| Warning | What Claude or ChatGPT can end up logging |
|---|---|
| Exit country is HK, CN, or MO | This visit came from an unsupported region, on top of whatever country the account was created in. |
| Pinned IP does not match | The same account showed up from a different address. Guard treats that as a failed pin and quits Claude and ChatGPT, including when the new address is still in Japan. |
| Tunnel route is Wi-Fi or Ethernet | The next packet can leave from the home address. Cavok has not sent a probe yet. |
| ChatGPT address differs from Claude | Codex or the ChatGPT app is on a different path. Guard quits both. |
| Shell, login environment, Claude configs, Codex config, or system proxy | Traffic or the API host is not the official one. A relay base URL is the case that has gotten subscription accounts banned quickly. |
| A socket is on Wi-Fi or Ethernet | A connection opened before the VPN is still using the physical interface. Guard quits Claude and ChatGPT. |
| IPv6 route is not a tunnel, or a host's IPv6 country differs | One path is the VPN and the other is not. The row names which host returned which address. Guard quits Claude and ChatGPT. |
| Time zone is not Tokyo, or a locale tag is HK, CN, or MO | Nothing Guard acts on. The clock button is there if you want it to match a Japan exit. Locale is not rewritten. |
| curl was challenged, or a resolver interface is physical | curl's result, or DNS leaving the tunnel. Neither one quits Claude or ChatGPT by itself. DNS does not look up a resolver's country. |

## What Cavok does not check

These can still get an account flagged. Cavok has no row for them.

- Whether the account was created in a supported region, or which country the card was issued in.
- The Claude or ChatGPT phone apps. A phone on home Wi-Fi writes that address onto the same account.
- Surfshark's Kill Switch, IP Rotator, Bypasser, or which server you picked. Cavok only sees the address that comes out.
- Whether the address is a VPN, a datacenter, or a home connection. A purity score from another site is not a Cavok check.
- HTTP/3 as its own path. The route check covers the interface. It does not open a QUIC connection.
- WebRTC, abuse lists, and payment history.
- What you type in a chat. Usage Policy and Terms violations are outside this app.
- Folders you have not added. Settings starts with Projects and Developer when those exist. Desktop is not scanned until you add it.

A timeout stays a failure to measure. Cavok does not turn a failed request into a green check, and Guard does not quit apps because a trace timed out.

## Where the data stays

When the route is a tunnel, the exit check is one IPv4 request to `claude.ai`, one IPv4 request to `chatgpt.com`, header checks for both homepages, and an IPv6 request to each trace URL when that route is a tunnel too. While that route stays a tunnel, the same two IPv4 trace requests run again every minute. A full check follows only when an address or country changed, or after two quiet readings in a row. Nothing is uploaded to a Cavok server. The pinned IP, the saved time zone, the Guard switch, the project folders, and the "IPv6 was changed" flag live in this Mac's preferences. The first time a file is edited, `.cavok-bak` is written beside it. A later edit keeps that first copy.

## Using it

The window and the menu-bar icon show the same checks. The icon shows the exit country, such as `JP`, while a check has a country. It shows `LAN` when the IPv4 route is Wi-Fi or Ethernet.

Closing the window leaves the icon in place. **Open Window** in the panel, or **Show Cavok** in the Dock menu, brings the window back. **Quit** in the panel quits the app. Settings has the menu-bar switch, the Guard switch, and the project-folder list.

Check Again is Command-R in the app menu. The Dock menu has Check Again too.

Pin the address while the Japan static server is connected, then leave that server selected. The next check tells you if the address moved. Cavok will not move it back.
