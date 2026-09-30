#!/bin/bash
# Islet JSON widget: CPU load as a low-priority live activity.
ps -A -o %cpu | awk -v cores="$(sysctl -n hw.ncpu)" '
  { s += $1 }
  END {
    load = s / cores; if (load > 100) load = 100
    printf "{\"id\":\"cpu\",\"title\":\"CPU %d%%\",\"progress\":%.2f,\"priority\":\"low\",\"icon\":\"sf:cpu\",\"sneak\":false}\n", load, load / 100
  }'
