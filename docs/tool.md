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
| Exit IP | The IPv4 address and country in `https://claude.ai/cdn-cgi/trace` (`ip=` and `loc=`). This is the address Claude's edge sees, not the address a speed-test site sees. | An exit in HK, CN, or MO is outside the regions this setup is using. A new address after you pinned one means the account's next visit is a different IP. Cavok cannot switch Surfshark. | **Pin this IP** saves the address on this Mac. Later checks compare against it. |
| Shell startup files | Assignments and `launchctl setenv` lines in `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.bash_profile`, `~/.bashrc`, and `~/.profile`. | A leftover `HTTPS_PROXY` or `ANTHROPIC_BASE_URL` can send `claude` or `codex` somewhere other than the Surfshark tunnel, including a third-party relay. | **Comment out** comments those lines and saves a copy as `.cavok-bak` beside the file. Open a new terminal afterward. |
| Login environment | `launchctl getenv` for proxy variables and `ANTHROPIC_BASE_URL`, `OPENAI_BASE_URL`, `OPENAI_API_BASE`. | Apps launched from the Dock, including Claude, inherit this environment. A value here can override the tunnel for GUI apps even when Terminal looks fine. | **Remove** runs `launchctl unsetenv` for the names it found. It does not print the values. |
| Claude Code settings | The `env` object in `~/.claude/settings.json` only. Project `.claude` files are left alone. | A base URL that is not `api.anthropic.com` or `api.openai.com` sends Claude Code through a relay. Claude Code still phones home and reports that host. | **Remove** drops proxy keys, and drops a non-official base URL. A token is removed only when that same `env` object points at a non-official host. An official base URL and its token stay. A copy is saved as `settings.json.cavok-bak`. |
| IPv6 | A separate request, `curl -6`, to the same Claude trace URL. | If IPv4 is Japan and IPv6 is HK, CN, MO, or any other country, Claude can see the home address on the IPv6 path while a browser test still shows Japan. | **Set link-local** runs `networksetup -setv6LinkLocal` on Wi-Fi, Ethernet, and other non-Surfshark services. macOS asks for a password. **Restore automatic** appears only after Cavok made that change. |
| DNS cache | Nameservers from `scutil --dns`, before the "scoped queries" section. | Shows which resolvers the system is using. It does not decide that DNS is leaking. A router address that only serves the local network is not in this list. | **Flush** clears the cache with `dscacheutil` and `mDNSResponder`. It does not change which resolver you use. |
| Time zone | `TimeZone.current` on this Mac. | A clock that does not match the exit is a mismatch people talk about. Cavok does not treat Hong Kong time as a failure. | **Set to Tokyo** sets `Asia/Tokyo`, turns automatic time zone off, and remembers the previous zone. **Restore** puts that zone back and turns automatic time zone on again. macOS asks for a password. |

**Clean leftovers** runs the shell, login-environment, and Claude settings fixes together. It stays off when those three rows are already clear. It does not change IPv6, DNS, the time zone, or the pinned IP.

**Open Claude** opens `Claude.app` if it is installed, otherwise `https://claude.ai`. It stays off while the exit country is HK, CN, or MO, or while the exit IP could not be read.

## How a warning lines up with ban risk

| Warning | What Claude or ChatGPT can end up logging |
|---|---|
| Exit country is HK, CN, or MO | This visit came from an unsupported region, on top of whatever country the account was created in. |
| Pinned IP does not match | The same account showed up from a different address than last time. One change is ordinary. A new Surfshark server every day is the pattern Cavok is there to show you. |
| Shell, login environment, or Claude settings | Traffic or the API host is not the official one. A relay base URL is the case that has gotten subscription accounts banned quickly. |
| IPv6 country differs, or is HK, CN, or MO | One path is the VPN and the other is not. The account can receive both. |
| Time zone is not Tokyo | Nothing by itself. The button is there if you want the clock to match a Japan exit. |

## What Cavok does not check

These can still get an account flagged. Cavok has no row for them.

- Whether the account was created in a supported region, or which country the card was issued in.
- The Claude or ChatGPT phone apps. A phone on home Wi-Fi writes that address onto the same account.
- Surfshark's Kill Switch, IP Rotator, Bypasser, or which server you picked. Cavok only sees the address that comes out.
- Whether the address is a VPN, a datacenter, or a home connection. A purity score from another site is not a Cavok check.
- ChatGPT as its own path. The exit row is the Claude trace only. A split tunnel can send `chatgpt.com` somewhere else.
- WebRTC, abuse lists, and payment history.
- What you type in a chat. Usage Policy and Terms violations are outside this app.
- Project-level `.claude/settings.local.json` files. Only `~/.claude/settings.json` is read.

A timeout stays a failure to measure. Cavok does not turn a failed request into a green check.

## Where the data stays

The exit check is one request to `claude.ai` and one IPv6 attempt. Nothing is uploaded to a Cavok server. The pinned IP, the saved time zone, and the "IPv6 was changed" flag live in this Mac's preferences. File edits are backed up next to the original as `.cavok-bak` before they are written.

## Using it

The window and the menu-bar icon show the same checks. The icon shows the exit country, such as `JP`, while a check has a country.

Closing the window leaves the icon in place. **Open Window** in the panel, or **Show Cavok** in the Dock menu, brings the window back. **Quit** in the panel quits the app. Settings has one switch, **Show Cavok in the menu bar**.

Check Again is Command-R in the app menu. The Dock menu has Check Again too.

Pin the address while the Japan static server is connected, then leave that server selected. The next check tells you if the address moved. Cavok will not move it back.
