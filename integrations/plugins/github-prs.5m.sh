#!/bin/bash
# xbar-format widget: pull requests waiting for your review (needs `gh auth login`).
command -v gh >/dev/null || { echo "gh not installed | color=gray"; exit 0; }
prs=$(gh search prs --review-requested=@me --state=open --json title,url --limit 5 2>/dev/null)
n=$(echo "$prs" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
echo "$n PRs to review | sfimage=arrow.triangle.pull"
echo "---"
echo "$prs" | python3 -c 'import sys,json
for p in json.load(sys.stdin): print(p["title"][:60].replace("|","/") + " | href=" + p["url"])' 2>/dev/null
