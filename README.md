# Auggment Scoreboard

Live scores for your favorite teams in the Omarchy Quattro bar. The bar shows one
game at a time (live, today, upcoming or final) and rotates through your teams.
Teams with no game in their look-ahead window are not shown.

## Install

```sh
omarchy plugin add https://github.com/auggnation/omarchy-auggment-scoreboard.git --enable
```

## Usage

- **Left click** – open the game view (click again to close).
- **Right click** – open settings (leagues, favorite teams, colors, look-ahead).
- **Middle click** – refresh now.
- **Scroll** over the widget – step through games.
- **Escape** closes the panel. In the panel: `n`/`p` next/previous, `r` refresh, `s` settings.

```sh
omarchy-shell shell summon io.github.auggnation.auggment-scoreboard '{}'
omarchy-shell shell hide io.github.auggnation.auggment-scoreboard
```

## Configure

Settings are edited in the panel and stored in `~/.config/auggment/scoreboard.json`
(mode 0600). Move the widget with:

```sh
omarchy bar move io.github.auggnation.auggment-scoreboard --section center
```

## What it runs, reads and writes

This plugin runs unsandboxed with your user permissions. Review before enabling:

- **Requires** `python3` (standard library only, no pip packages).
- **Network:** `bin/fetch-scores.py` requests scores from ESPN (`site.api.espn.com`,
  `site.web.api.espn.com`) and, for the CFL, TheSportsDB (`www.thesportsdb.com`).
  No account or API key is needed and no personal data is sent.
- **Files written:** `~/.config/auggment/scoreboard.json` (settings) and
  `~/.cache/auggment/scoreboard-cache.json` (short-lived score cache).
- **Commands:** `python3 bin/*.py`; `omarchy bar move` (only when you pick a bar
  position); `xdg-open` (only when you click a game to open its page).
- No installer, service or remote build step.

## Remove

```sh
omarchy plugin remove io.github.auggnation.auggment-scoreboard
rm -rf ~/.config/auggment ~/.cache/auggment   # optional: delete settings and cache
```
