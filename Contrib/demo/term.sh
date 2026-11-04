#!/bin/bash
# Runs in the demo terminal: `spikot-wm list`, redrawn every second, so the stack column follows
# the windows as record.sh moves them. Each line is overwritten in place and cleared to its end,
# rather than clearing the screen, which flickers on video.
printf '\e]0;spikot-wm list\a\e[?25l'
while :; do
    out=$(spikot-wm list | cut -f1,3,4,5 | column -t -s $'\t')
    printf '\e[H\e[1;32m$\e[0m \e[1mspikot-wm list\e[0m\e[K\n\e[K\n'
    printf '%s\n' "$out" | sed $'s/$/\e[K/'
    printf '\e[J'
    sleep 1
done
