#!/bin/bash
# Raycast Script Command: start a timer in the notch.
# @raycast.schemaVersion 1
# @raycast.title Islet Timer
# @raycast.mode silent
# @raycast.icon ⏱
# @raycast.argument1 { "type": "text", "placeholder": "5m, tea 4m, at 18:30" }
# @raycast.argument2 { "type": "text", "placeholder": "Title", "optional": true }
if [ -n "$2" ]; then
  isletctl timer "$1" --title "$2"
else
  isletctl timer "$1"
fi
