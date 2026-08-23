#!/bin/bash
# The test suite. There is no XCTest target: each harness compiles the shipped sources it guards,
# so a harness that stops compiling means a decision leaked out of a pure layer. See docs/testing.md.
#
# Never join a compile and its run with `&&`: `set -e` ignores a failure in a non-final AND-OR list
# member, which is how CI reported success over a harness that had not compiled since phase 10.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/tinycast-harness"
mkdir -p "$BIN"

failed=()
ran=0
only="${1:-}"

# run <name> <source...> — compile the harness and run it, recording either kind of failure.
run() {
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    ran=$((ran + 1))

    if ! swiftc -swift-version 6 "$@" "Tests/$name.swift" -o "$BIN/$name" 2>&1; then
        printf '\033[31mFAIL\033[0m  %-22s did not compile\n' "$name"
        failed+=("$name")
        return 0
    fi
    if ! "$BIN/$name"; then
        printf '\033[31mFAIL\033[0m  %-22s assertion failed\n' "$name"
        failed+=("$name")
        return 0
    fi
    printf '\033[32mok\033[0m    %-22s\n' "$name"
}

L=Tinycast/Features/Launcher/Model
run fuzz-test              $L/SearchRelevance.swift
run file-search-test       $L/SearchRelevance.swift \
                           Tinycast/Features/FileSearch/Model/*.swift
run file-search-session-test Tinycast/Platform/Signposts.swift \
                             $L/SearchRelevance.swift \
                             Tinycast/Features/FileSearch/Model/*.swift \
                             Tinycast/Features/FileSearch/Service/*.swift
run ranking-test           $L/SearchRelevance.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift
run scope-test             $L/QueryScope.swift \
                           $L/ScopeTint.swift \
                           $L/ScopeKeywords.swift
run calc-test              Tinycast/Features/Calculator/Model/*.swift
run clipboard-test         Tinycast/Features/Clipboard/Model/ClipboardStore.swift
run emoji-test             Tinycast/Features/Emoji/Model/EmojiCatalog.swift \
                           Tinycast/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Tinycast/Features/Emoji/Model/EmojiData.generated.swift
run palette-selection-test Tinycast/Features/PaletteRowIndex.swift \
                           Tinycast/Features/Emoji/Model/EmojiGridGeometry.swift
run palette-placement-test Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           $L/ScopeTint.swift \
                           Tinycast/Palette/PalettePlacement.swift
run scroll-reveal-test     Tinycast/DesignSystem/Scrolling/SelectionReveal.swift
run hover-arming-test      Tinycast/Palette/HoverArming.swift \
                           Tinycast/Palette/PaletteState.swift \
                           Tinycast/Palette/PaletteMode.swift \
                           $L/QueryScope.swift \
                           $L/ScopeTint.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift
run hotkey-test            Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Tinycast/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyAction.swift \
                           Tinycast/Features/HotKeys/Model/HyperKey.swift \
                           Tinycast/Features/HotKeys/Service/KeyShortcut.swift \
                           Tinycast/Features/SystemActions/Model/SystemAction.swift \
                           Tinycast/Features/WindowManagement/WindowCommand.swift
run callout-test           Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           $L/ScopeTint.swift \
                           Tinycast/Features/HotKeys/UI/CalloutPlacement.swift
run icon-cache-test        Tinycast/Platform/Appearance.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           $L/ScopeTint.swift \
                           Tinycast/Platform/Images/IconCache.swift
run system-action-test     Tinycast/Features/SystemActions/Model/SystemAction.swift
run appearance-test        Tinycast/Platform/Appearance.swift \
                           $L/ScopeTint.swift \
                           Tinycast/DesignSystem/Theme.swift \
                           Tinycast/Features/Settings/AppAppearance.swift
run volume-test            Tinycast/Features/SystemActions/Model/VolumeLevel.swift
run window-command-test    Tinycast/Features/WindowManagement/WindowCommand.swift \
                           Tinycast/Features/WindowManagement/WindowLayout.swift \
                           Tinycast/Features/WindowManagement/WindowActionMemory.swift
run custom-command-test    Tinycast/Features/CustomCommands/Model/CustomCommand.swift \
                           Tinycast/Features/CustomCommands/Service/ShellCommandRunner.swift
run uninstall-test         Tinycast/Features/Uninstall/Model/UninstallTarget.swift \
                           Tinycast/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Tinycast/Features/Uninstall/Model/UninstallRules.swift \
                           Tinycast/Features/Uninstall/Model/UninstallProtection.swift \
                           Tinycast/Features/Uninstall/Model/UninstallPlan.swift
run quicklink-test         Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkArchive.swift
run snippets-test          Tinycast/Platform/NotificationToken.swift \
                           Tinycast/Platform/HealthTicker.swift \
                           Tinycast/Features/Snippets/Model/*.swift \
                           Tinycast/Features/Snippets/Service/*.swift
run herdr-test             Tinycast/Features/Herdr/Model/HerdrTarget.swift \
                           Tinycast/Features/Herdr/Model/HerdrHost.swift
run vscode-test            Tinycast/Features/VSCode/Model/VSCodeProject.swift
run linear-test            Tinycast/Features/Linear/Model/LinearTarget.swift \
                           Tinycast/Features/Linear/Model/LinearCredentials.swift \
                           Tinycast/Platform/SubprocessEnvironment.swift
run websearch-test         Tinycast/Features/WebSearch/Model/WebSearchEngine.swift \
                           Tinycast/Features/WebSearch/Model/SearchSuggestions.swift \
                           Tinycast/Features/Snippets/Model/SnippetTemplateEngine.swift \
                           Tinycast/Features/Snippets/Model/Snippet.swift
run raycast-test           Tinycast/Features/Backup/Model/RaycastFormat.swift \
                           Tinycast/Features/Backup/Model/RaycastV1Decoder.swift \
                           Tinycast/Features/Backup/Service/Gunzip.swift \
                           Tinycast/Features/Clipboard/Model/ClipboardStore.swift
run settings-backup-test   Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift
run sync-test              Tinycast/Features/Sync/Model/SyncEnvelope.swift \
                           Tinycast/Features/Sync/Model/SyncPlan.swift \
                           Tinycast/Features/Backup/Model/SettingsBackup.swift \
                           Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift \
                           Tinycast/Features/Settings/AppSettingsKey.swift \
                           Tinycast/Features/CustomCommands/Model/CustomCommand.swift \
                           Tinycast/Features/Quicklinks/Model/Quicklink.swift \
                           Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Tinycast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Tinycast/Features/HotKeys/Model/HyperKey.swift \
                           Tinycast/Features/HotKeys/Service/KeyShortcut.swift
run settings-history-test  Tinycast/Features/Settings/SettingsTab.swift \
                           Tinycast/Features/Settings/SettingsHistory.swift

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

if [ ${#failed[@]} -gt 0 ]; then
    printf '\n%d harness(es) failed: %s\n' "${#failed[@]}" "${failed[*]}" >&2
    exit 1
fi
echo
if [ -n "$only" ]; then echo "$only passed."; else echo "All $ran harnesses passed."; fi
