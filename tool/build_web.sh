#!/usr/bin/env bash
#
# Build one of the three Flutter web targets and stamp its own <head>.
#
# Flutter compiles every web entry point through the single shared
# `web/index.html`, so all three surfaces would otherwise ship the
# storefront's title, description and og: tags. `MaterialApp.title` fixes
# the browser tab once the app boots, but nothing fixes the static head —
# which is exactly what a crawler or a Viber/Messenger link preview reads.
# Pasting the admin console's URL into a chat produced a card reading
# "All In One POS Shop — Order online from your local shop."
#
# Build and stamp are one command on purpose: a separate "remember to patch
# the head" step is a step that eventually gets skipped.
#
# Usage:  tool/build_web.sh shop|admin|invoices
set -euo pipefail

target="${1:-}"
case "$target" in
  shop)
    entry="lib/storefront/storefront_main.dart"
    title="All In One POS Shop"
    desc="All In One POS — order online from your local shop. Browse the catalog and place a guest order."
    og_title="All In One POS Shop"
    og_desc="Order online from your local shop."
    # The only public surface of the three: leave it indexable.
    robots=""
    ;;
  admin)
    entry="lib/admin/admin_main.dart"
    title="All In One POS Admin"
    desc="Licence administration for All In One POS. Staff sign-in required."
    og_title="All In One POS Admin"
    og_desc="Licence administration. Staff sign-in required."
    robots="noindex, nofollow"
    ;;
  invoices)
    entry="lib/invoices_web/invoices_web_main.dart"
    title="All In One POS Invoices"
    desc="View your shop's invoices in the browser. Licence key required."
    og_title="All In One POS Invoices"
    og_desc="View your shop's invoices in the browser."
    robots="noindex, nofollow"
    ;;
  *)
    echo "usage: tool/build_web.sh shop|admin|invoices" >&2
    exit 2
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ ! -f env.local.json ]; then
  echo "error: env.local.json missing — the build needs SUPABASE_URL/ANON_KEY." >&2
  exit 1
fi

echo "==> building $target ($entry)"
flutter build web -t "$entry" \
  --dart-define-from-file=env.local.json \
  --no-web-resources-cdn

index="build/web/index.html"
echo "==> stamping $index for $target"

python3 - "$index" "$title" "$desc" "$og_title" "$og_desc" "$robots" <<'PY'
import re, sys

path, title, desc, og_title, og_desc, robots = sys.argv[1:7]
html = open(path, encoding="utf-8").read()


def sub_once(pattern, replacement, text, what):
    """Replace exactly one match, or fail loudly.

    A silent no-op here ships the wrong metadata, which is the bug this
    script exists to prevent — so a changed web/index.html should break
    the build rather than quietly produce a mislabelled bundle.
    """
    new, n = re.subn(pattern, lambda _: replacement, text, count=1)
    if n != 1:
        sys.exit(f"error: expected 1 {what} in {path}, found {n} — "
                 "web/index.html changed shape; update tool/build_web.sh")
    return new


html = sub_once(r"<title>.*?</title>", f"<title>{title}</title>", html, "<title>")
html = sub_once(r'<meta name="description" content=".*?">',
                f'<meta name="description" content="{desc}">', html, "description")
html = sub_once(r'<meta property="og:title" content=".*?">',
                f'<meta property="og:title" content="{og_title}">', html, "og:title")
html = sub_once(r'<meta property="og:description" content=".*?">',
                f'<meta property="og:description" content="{og_desc}">', html, "og:description")

if robots:
    html = sub_once(r'(<meta property="og:type" content="website">)',
                    f'<meta name="robots" content="{robots}">\n  \\1'
                    .replace("\\1", '<meta property="og:type" content="website">'),
                    html, "og:type anchor")

open(path, "w", encoding="utf-8").write(html)
print(f"    title       {title}")
print(f"    description {desc[:58]}...")
if robots:
    print(f"    robots      {robots}")
PY

echo "==> build/web ready for $target"
