#!/bin/bash
#
# VENDORED, AND SUPERSEDED BY `spikot-wm launch` (spikot-win-9ic.1).
#
# Kept because it exists nowhere else: it is unversioned, absent from chezmoi, and was scp'd
# from icoteril@10.0.0.231:bin/mylauncher, so this copy is the only record of what the four
# cmd-f/g/e/s keybindings did before the agent took them over. Do not edit it; it is history.
#
# Three things about it are worth knowing, because they shaped the replacement:
#
#   1. `[ $PIPESTATUS -eq 0 ]` checks the wrong thing. After `output=$(spikot-wm list | rg $app)`,
#      PIPESTATUS describes the assignment, not rg, so the "application not found" branch was
#      reached by accident rather than by the test. The replacement asks CGWindowList directly.
#
#   2. The generic launch fallback never worked. `grep -i $app ~/.apps-cache` reads a file that
#      does not exist on this machine, and even then it only echoes the result. So the `case`
#      covered exactly Emacs, Firefox, Safari and Ghostty and nothing else could ever launch.
#      `spikot-wm launch` looks for <Name>.app in the usual directories instead.
#
#   3. `rg $app` matched the whole listing line, so a window *title* containing the name counted
#      as a window of that application. The replacement matches on the owner name, exactly first,
#      then by prefix, then by substring.
#
# It also needed `rg`, `choose`, and a PATH that found `spikot-wm` by bare name, which the skhd
# LaunchAgent supplied. The agent supplies its own through the config's execPath.
#
# ---------------------------------------------------------------------------------------------

app=$1
fast=$2
output=$(spikot-wm list | rg $app)

if [ $PIPESTATUS -eq 0 ]; then
    # Application windows found, offer selection if more than one window
    N=$(echo "$output" | wc -l | xargs) 
    if [ $N -eq 1 ]; then
        id=$(echo "$output" | cut -d"|" -f3 | xargs)
    else
        if [ "${fast}" = "fast" ]; then
            echo "Choosing first of [$N] options"
            id=$(echo "$output" | head -n 1 | cut -d"|" -f3 | xargs)
        else
            echo "Choosing from [$N] options"
            id=$(echo "$output" | choose -b ff79c6 -w 48 | cut -d"|" -f3 | xargs)
        fi
    fi
    echo "Move focus to existing window: [${id}]"
    # Maybe ensure workspace
    spikot-wm focus --window $id
else
    # Application not found, launching
    
    case $app in
    	"Emacs")
		emacsclient -c -n -a ""
		;;
    	"Firefox")
		open -n /Applications/Firefox.app 
		;;
    	"Safari")
		open -n /Applications/Safari.app
		;;
    	"Ghostty")
		open -n /Applications/Ghostty.app 
		;;
	*)
	    echo "Launching!"
	    echo $(grep -i $app ~/.apps-cache)
		;;
    esac

fi
