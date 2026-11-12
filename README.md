# Cavok

A Mac menu-bar app that checks this Mac, then offers a button for each thing it can change.

A clear screen means those local checks passed. It does not mean Claude or ChatGPT has decided the account is safe. Cavok never logs in, never reads a card, and never sees either company's risk system.

Hong Kong, mainland China, and Macau are the only countries Cavok treats as a bad exit. It does not download Anthropic's or OpenAI's full country list.

## Checks

Each row is one check. A warning is an orange triangle. A clear row is a green check. An empty circle means Cavok measured something and is not calling it a problem.

| Row | What it measures | What the button does |
|---|---|---|
| Exit IP | IPv4 address and country from `https://claude.ai/cdn-cgi/trace` (`ip=` and `loc=`). | **Pin this IP** saves the address. Later checks compare against it. |
| Shell startup files | Proxy and custom API host assignments in zsh and bash startup files. | **Comment out** comments those lines and saves a `.cavok-bak` copy. |
| Login environment | `launchctl getenv` for the same proxy and API host names. | **Remove** runs `launchctl unsetenv`. It does not print the values. |
| Claude Code settings | The `env` object in `~/.claude/settings.json` only. | **Remove** drops proxy keys and a non-official base URL. A token is removed only when that same `env` points at a non-official host. |
| IPv6 | A separate `curl -6` to the same Claude trace URL. | **Set link-local** on Wi-Fi and Ethernet. **Restore automatic** only after Cavok made that change. |
| DNS cache | Nameservers from `scutil --dns`, before scoped queries. | **Flush** clears the cache. It does not change which resolver you use. |
| Time zone | `TimeZone.current` on this Mac. | **Set to Tokyo**, or **Restore** the zone Cavok saved. |

**Clean leftovers** runs the shell, login-environment, and Claude settings fixes together.

**Open Claude** opens `Claude.app` if it is installed, otherwise `https://claude.ai`. It stays off while the exit country is HK, CN, or MO, or while the exit IP could not be read.

The row-by-row notes, including what a warning can show up as, are in [docs/tool.md](docs/tool.md).

## What it does not check

- Whether the account was created in a supported region, or which country the card was issued in.
- The Claude or ChatGPT phone apps.
- Surfshark's Kill Switch, IP Rotator, Bypasser, or which server you picked.
- Whether the address is a VPN, a datacenter, or a home connection.
- ChatGPT as its own path. The exit row is the Claude trace only.
- Project-level `.claude/settings.local.json`. Only `~/.claude/settings.json` is read.

A timeout stays a failure to measure. Cavok does not turn a failed request into a green check.

## Build

Requires macOS 26. `./build.sh` builds a release binary and installs `~/Applications/Cavok.app`. `./build.sh --open` quits the running copy and opens the new one.

```sh
swift test
./build.sh --open
```

Closing the window leaves the menu-bar icon in place. **Quit** in the panel quits the app.
