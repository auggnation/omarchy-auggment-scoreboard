# Auggment Scoreboard

Live sports scores in the Omarchy bar, powered by ESPN. A compact rotating
score sits in the bar; click it for a larger board, right-click for settings.

Fork of the TV scoreboard in [Auggment-Scoreboard](https://github.com/auggnation/Auggment-Scoreboard),
reshaped into a lightweight Omarchy shell bar-widget plugin.

## What it shows

- **Bar:** a compact rotating score, e.g. `KC 24–17 LV` while live, `LAL@BOS`
  before tip-off. The colour tells the state: accent = live, muted = final.
- **Board (left click):** favourites first, then live, upcoming and finals,
  with the game clock and period/quarter/inning/frame
  (e.g. `2:52 - 4th`, `Top 5th`, `72'`) and the date + time for upcoming
  games. Racing and golf show their leaderboards.
- **Settings (right click):** leagues, favourite teams, racing drivers and
  golfers, per-team bar colours, and how far ahead to look.

## Requirements

- Omarchy (Quickshell shell).
- `python3` (already present on Omarchy). No pip packages — the fetcher uses
  only the Python standard library.

## Install

```bash
omarchy plugin add https://github.com/auggnation/omarchy-auggment-scoreboard --enable
```

Then click the widget (or right-click) to choose your leagues and teams.

## Settings

All settings live in **`~/.config/auggment/scoreboard.json`** and are written by
the right-click panel. Highlights:

| Key | Meaning | Default |
|-----|---------|---------|
| `leagues` | ESPN league slugs, e.g. `"football/nfl"` | `["football/nfl"]` |
| `teams` | Favourites as `"<league>:<ABBR>"`, e.g. `"football/nfl:KC"` | `[]` |
| `racing` | Drivers per racing league | `{}` |
| `golf` | Golf players | `[]` |
| `team_colors` | `"<league>:<ABBR>"` → `"#RRGGBB"` bar colour | `{}` |
| `days_ahead` | How far ahead to look for games | `7` |
| `days_back` | How far back to include finals | `1` |
| `rotate_seconds` | Seconds per score in the bar | `6` |
| `refresh_seconds` | How often to refetch from ESPN | `60` |

## Network and files

- **Network:** reads scores from the public ESPN API
  (`site.api.espn.com`, `site.web.api.espn.com`). No account, no tracking.
- **Files:** reads/writes only `~/.config/auggment/scoreboard.json`. Nothing
  else on your system is touched.

## Removal

```bash
omarchy plugin remove io.github.auggnation.auggment-scoreboard
rm -f ~/.config/auggment/scoreboard.json
```

## Credits

- Scores and league coverage modelled on
  [Auggment-Scoreboard](https://github.com/auggnation/Auggment-Scoreboard).
- Plugin structure follows Omarchy's first-party bar-widget convention.

## License

MIT — see [LICENSE](LICENSE).
