#!/bin/zsh
# Defiant nightly refresh:
#   crawl OSM facilities → rebuild directory → refresh article data blocks →
#   cards → build → QA gate → commit → publish to GitHub Pages through pr-push.
# Resilient: if the crawl mirror is down, it still rebuilds from existing data.
# Since 2026-11-18 (her word) the site is served at nanobotco.github.io/defiant/ from
# this repo's docs/; defiant.to only 301s there (cloudflare-mirror/defiant-redirect).
# Private CRM (partners.db, drafts) is gitignored, so pushes leave it out.
set -o pipefail
REPO="$HOME/Developer/claude code projects/defiant-site"
LOG="$HOME/Library/Logs/defiant-nightly.log"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # gh, for pr-push under launchd
cd "$REPO" || exit 1

echo "───── $(date '+%Y-%m-%d %H:%M') nightly refresh ─────" >> "$LOG"
python3 partners/crawl.py     >> "$LOG" 2>&1 || echo "  crawl: skipped/failed (using existing data)" >> "$LOG"
python3 build_directory.py    >> "$LOG" 2>&1
python3 articles.py refresh   >> "$LOG" 2>&1 || echo "  articles: refresh skipped (a source was down; blocks keep last good data)" >> "$LOG"
python3 make_cards.py         >> "$LOG" 2>&1 || echo "  cards: skipped (Pillow?)" >> "$LOG"
python3 build.py              >> "$LOG" 2>&1 || { echo "  BUILD FAILED — stopping" >> "$LOG"; exit 1; }

# Local commit always — the ledger of what changed, whether or not we deploy.
git add -A >> "$LOG" 2>&1
if git diff --cached --quiet; then
  echo "  no changes" >> "$LOG"
else
  git commit -q -m "Nightly refresh $(date '+%Y-%m-%d')

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" >> "$LOG" 2>&1
  echo "  committed ✓" >> "$LOG"
fi

# The QA gate decides whether tonight's build goes out the door.
if python3 articles.py qa >> "$LOG" 2>&1; then
  if "$HOME/.claude/bin/pr-push" "$REPO" "Nightly refresh $(date '+%Y-%m-%d')" >> "$LOG" 2>&1
  then echo "  published ✓ (GitHub Pages, nanobotco.github.io/defiant/)" >> "$LOG"
  else echo "  PUBLISH FAILED (pr-push exit $?)" >> "$LOG"; fi
else
  echo "  QA gate closed — built + committed, holding the deploy for a human look" >> "$LOG"
fi
