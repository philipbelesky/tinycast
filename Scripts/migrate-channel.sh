#!/bin/bash
# One-time bundle-id migration: copies each channel's persisted state from upstream's ids
# (com.tinycast.app, com.tinycast.app.dev) to the fork's (com.belesky.tinycast[.dev]).
# See FORK.md divergence 10 for why the fork renamed its channels.
#
# Copies prefs (settings, hotkeys, consent flags — the owner renaming their own domain, not an
# import), Caches (clipboard history, rankings, rates) and Application Support (quicklinks,
# snippets, the onboarding marker). TCC grants and the login item are keyed by bundle id and cannot
# be copied: expect the Accessibility prompt once, and re-enable Launch at Login in Settings.
#
# Safe to re-run: a target that already has data is skipped, never overwritten.

set -uo pipefail

if pgrep -fl "Tinycast" >/dev/null 2>&1; then
    echo "warning: a Tinycast instance is running — quit it first so prefs land completely." >&2
fi

migrate() {
    local old=$1 new=$2

    if defaults read "$old" >/dev/null 2>&1; then
        if defaults read "$new" >/dev/null 2>&1; then
            echo "skip  prefs $new already exist"
        else
            defaults export "$old" - | defaults import "$new" -
            echo "ok    prefs $old -> $new"
        fi
    else
        echo "none  prefs $old"
    fi

    local pair
    for pair in "$HOME/Library/Caches" "$HOME/Library/Application Support"; do
        if [ -d "$pair/$old" ]; then
            if [ -e "$pair/$new" ]; then
                echo "skip  $pair/$new already exists"
            else
                cp -Rp "$pair/$old" "$pair/$new"
                echo "ok    $pair/$old -> $new"
            fi
        else
            echo "none  $pair/$old"
        fi
    done
}

migrate com.tinycast.app com.belesky.tinycast
migrate com.tinycast.app.dev com.belesky.tinycast.dev

echo
echo "Not copied (re-do by hand): Accessibility / Input Monitoring grants, Launch at Login."
echo "The old app keeps its own data; remove it when the new one checks out."
