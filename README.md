# Auggment Scoreboard

Live sports scores in the Omarchy bar, powered by ESPN. A compact rotating
score sits in the bar; click it for a larger board, right-click for settings.

Fork of the TV scoreboard in [Auggment-Scoreboard](https://github.com/auggnation/Auggment-Scoreboard),
reshaped into a lightweight Omarchy shell bar-widget plugin.

## What it shows

- **Bar:** a compact rotating score, e.g. `KC 24–17 LV` while live, `LAL@BOS`
  before tip-off. Only your favourite teams appear. The colour tells the state:
  accent = live, muted = final.
- **Board (left click):** your favourite teams' live and upcoming games, with
  the game clock and period/quarter/inning/frame (e.g. `2:52 - 4th`, `Top 5th`,
  `72'`) and the date + time for upcoming games. Racing and golf show their
  leaderboards.
- **Settings (right click):** bar position, leagues, favourite teams (add and
  remove), per-team look-ahead days, racing drivers and golfers, and per-team
  bar colours.

## Placement

On first run the widget opens its settings and asks where it should sit in the
bar — **Top left**, **Middle**, or **Top right**. Picking one moves the widget
immediately (it runs `omarchy bar move io.github.auggnation.auggment-scoreboard
--section left|center|right`). You can change it any time from Settings, or
directly:

```bash
omarchy bar move io.github.auggnation.auggment-scoreboard --section center
```

## Requirements

- Omarchy (Quickshell shell).
- `python3` (already present on Omarchy). No pip packages — the fetcher uses
  only the Python standard library.

## Install

```bash
omarchy plugin add https://github.com/auggnation/omarchy-auggment-scoreboard --enable
```

Then pick a position, leagues and teams in the panel that opens.

## Settings

All settings live in **`~/.config/auggment/scoreboard.json`** and are written by
the right-click panel. Highlights:

| Key | Meaning | Default |
|-----|---------|---------|
| `position` | Bar section: `"left"`, `"center"` or `"right"` | `"right"` |
| `leagues` | ESPN league slugs, e.g. `"football/nfl"` | `["football/nfl"]` |
| `teams` | Favourites as `"<league>:<ABBR>"`, e.g. `"football/nfl:KC"` | `[]` |
| `days_ahead_teams` | Per-team look-ahead days, e.g. `{"football/nfl:KC": 21}` | `{}` |
| `racing` | Drivers per racing league | `{}` |
| `golf` | Golf players | `[]` |
| `team_colors` | `"<league>:<ABBR>"` → `"#RRGGBB"` bar colour | `{}` |
| `days_ahead` | Default look-ahead when a team has no override | `7` |
| `days_back` | How far back to include finals | `1` |
| `rotate_seconds` | Seconds per score in the bar | `6` |
| `refresh_seconds` | How often to refetch | `60` |

**Per-team look-ahead:** set a different number of days for each favourite team
in Settings, so (for example) you can see every Chiefs game three weeks out
while other teams stay at the default.

## Data sources

- Most leagues come from the public ESPN API (`site.api.espn.com`,
  `site.web.api.espn.com`).
- The **CFL** (`football/cfl`) is served by
  [TheSportsDB](https://www.thesportsdb.com/) (free v1 API), because ESPN does
  not carry current CFL scores.
- No account, no tracking.

## Files

- Reads/writes only `~/.config/auggment/scoreboard.json`.
- Calls `omarchy bar move` when you change the bar position.
- Nothing else on your system is touched.

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
