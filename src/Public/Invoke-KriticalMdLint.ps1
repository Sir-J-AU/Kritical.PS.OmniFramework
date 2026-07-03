function Invoke-KriticalMdLint {
<#
.SYNOPSIS
    Programmatic markdown lint + auto-renumber for Kritical customer-facing documents.

.DESCRIPTION
    Repeatable SOP linter. Six deterministic passes:

      1. STRIKETHROUGH SCRUB — removes `~~text~~` (markdown strikethrough means deleted).
      2. CLOSED-ITEM SCRUB — removes checklist items annotated `*(closed — ...)*`,
         `*(confirmed — ...)*`, `*(deferred — ...)*`, `*(already known)*`, `*(already in place)*`.
      3. SECTION AUTO-RELETTER — re-letters `## A. / ## B. / ...` sequentially from A.
         Handles duplicate letters (forces uniqueness).
      4. ITEM CODE AUTO-RENUMBER — within each section, renumbers `**A1** / **A2** / ...`
         sequentially 1, 2, 3... with the new section letter.
      5. CROSS-REFERENCE REWRITE — body-text refs like "items G1-G3" / "row K7" follow the
         old→new map. Conservative match — only triggers on word-boundary contexts to avoid
         SKU false positives like MST-NCE-103-C100.
      6. EMPTY-SECTION SCRUB — removes section headings with no content underneath.

    Dry-run by default. Pass -Apply to write.

.PARAMETER Path
    File OR directory. Directory = all *.md.

.PARAMETER Apply
    Write changes back. Default dry-run.

.PARAMETER Filter
    Glob filter when Path is a directory. Default '*.md'.

.PARAMETER NoStrikethrough / NoClosedItems / NoRenumber / NoEmptySection
    Skip individual passes.

.PARAMETER Quiet
    Suppress console output.

.EXAMPLE
    Invoke-KriticalMdLint -Path C:\path\to\Access-Checklist.md            # dry-run
    Invoke-KriticalMdLint -Path C:\path\to\Access-Checklist.md -Apply    # write
    Invoke-KriticalMdLint -Path C:\path\to\customer\folder -Apply        # bulk

.NOTES
    Author: Joshua Finley — Kritical Pty Ltd
    Part of Kritical.PS.OmniFramework 1.1.8+
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Apply,
        [string]$Filter = '*.md',
        [switch]$NoStrikethrough,
        [switch]$NoClosedItems,
        [switch]$NoRenumber,
        [switch]$NoEmptySection,
        [switch]$Quiet
    )

    $targets = @()
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $targets = Get-ChildItem -LiteralPath $Path -Filter $Filter -File | Select-Object -ExpandProperty FullName
    } elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
        $targets = @((Resolve-Path -LiteralPath $Path).Path)
    } else {
        throw "Path not found: $Path"
    }

    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($file in $targets) {
        $orig = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        if (-not $orig) { continue }
        $text = $orig
        $report = [System.Collections.Generic.List[string]]::new()
        $letterMap = [ordered]@{}

        # ---- PASS 1 — STRIKETHROUGH SCRUB --------------------------------------
        if (-not $NoStrikethrough) {
            $strikePat = '~~[^~]+~~'
            $cnt = ([regex]::Matches($text, $strikePat)).Count
            if ($cnt -gt 0) {
                $text = [regex]::Replace($text, $strikePat, '')
                $report.Add("Pass 1: removed $cnt strikethrough(s)")
            }
        }

        # ---- PASS 2 — CLOSED-ITEM SCRUB ----------------------------------------
        if (-not $NoClosedItems) {
            $closedPat = '(?m)^\s*-\s+\[[ x]\]\s+(?:\*\*[A-Z]\d+\*\*\s+)?\*\((?:closed|confirmed|deferred[^)]*|already[^)]*|done|noop)\b[^)]*\)\*[^\r\n]*\r?\n'
            $cnt = ([regex]::Matches($text, $closedPat)).Count
            if ($cnt -gt 0) {
                $text = [regex]::Replace($text, $closedPat, '')
                $report.Add("Pass 2: removed $cnt closed/confirmed/deferred item(s)")
            }
        }

        # ---- PASS 3 + 4 + 5 — SECTION + ITEM + CROSS-REF RENUMBER (single-pass) -
        if (-not $NoRenumber) {
            # Step A: walk text, find all section headings in document order, build old→new map.
            $sectionPat = '(?m)^(##+ )([A-Z])(\. [^\r\n]+)$'
            $sectionMatches = [regex]::Matches($text, $sectionPat)
            $next = [int][char]'A'
            foreach ($m in $sectionMatches) {
                $newLetter = [char]$next
                # Every section heading gets the next sequential letter regardless of its old letter.
                # We use INDEX as the key (since duplicate old-letters exist), but we also map by
                # old-letter for cross-ref lookups (first occurrence wins for cross-ref purposes).
                $oldLetter = $m.Groups[2].Value
                if (-not $letterMap.Contains($oldLetter)) {
                    $letterMap[$oldLetter] = $newLetter.ToString()
                }
                $next++
            }

            # Step B: collect ALL match positions in original text:
            #   - section headings
            #   - bold item codes **[A-Z]\d+**
            #   - bare cross-reference codes [A-Z]\d+ (word-boundary-aware)
            # Then walk linearly, emit unchanged chars + rewritten matches.
            # ITEM = a bold code at the START of a checklist row `- [ ] **X1** ...` or `- [ ] **X1 (label)** ...`
            # Group 1 = checkbox prefix (preserved), Group 2 = letter, Group 3 = num, Group 4 = trailing content inside bold.
            $itemPat   = '(?m)^(\s*-\s+\[[ x]\]\s+)\*\*([A-Z])(\d+)([^\*]*)\*\*'
            # BOLD-REF = a `**X1**` bold code anywhere ELSE (in body intros, paragraphs) → cross-ref, doesn't increment counter
            $boldRefPat = '\*\*([A-Z])(\d+)([^\*]*)\*\*'
            # CROSS-REF in plain text = `X1` with safe word-boundary, gated by valid-item set
            $crossPat  = '(?<=[\s\(\[\>/\-])([A-Z])(\d+)(?=[\s\.\,\)\]\:\;\?\!\-/]|$)'

            # Build the set of OLD item codes that actually exist as checklist-row items.
            # Cross-references are only rewritten when the matched (letter,num) is in this set.
            $validOldItemCodes = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($im in [regex]::Matches($text, $itemPat)) {
                [void]$validOldItemCodes.Add("$($im.Groups[2].Value)$($im.Groups[3].Value)")
            }

            $events = [System.Collections.Generic.List[pscustomobject]]::new()
            # Sections: each has its OWN new letter based on its document-order index.
            $sectionOrder = 0
            $nextLetter = [int][char]'A'
            foreach ($m in $sectionMatches) {
                $newL = [char]($nextLetter + $sectionOrder)
                $events.Add([pscustomobject]@{
                    Index = $m.Index; Length = $m.Length; Kind = 'section'
                    Replacement = "$($m.Groups[1].Value)${newL}$($m.Groups[3].Value)"
                    OldLetter = $m.Groups[2].Value; NewLetter = $newL.ToString()
                })
                $sectionOrder++
            }
            $itemPositions = [System.Collections.Generic.HashSet[int]]::new()
            foreach ($m in [regex]::Matches($text, $itemPat)) {
                # The whole match starts at $m.Index (includes the checkbox prefix).
                # We want the event Index to be at the START of `**X1**` to keep replacement aligned.
                $prefixLen = $m.Groups[1].Length
                $boldStart = $m.Index + $prefixLen
                $boldLen   = $m.Length - $prefixLen
                $events.Add([pscustomobject]@{
                    Index = $boldStart; Length = $boldLen; Kind = 'item'
                    OldLetter = $m.Groups[2].Value; OldNum = $m.Groups[3].Value
                    TrailingText = $m.Groups[4].Value
                })
                [void]$itemPositions.Add($boldStart)
            }
            # In-text bold refs (not checklist-row items) → treat as bold cross-refs (preserve bold markers, rewrite letter)
            foreach ($m in [regex]::Matches($text, $boldRefPat)) {
                if ($itemPositions.Contains($m.Index)) { continue }
                $events.Add([pscustomobject]@{
                    Index = $m.Index; Length = $m.Length; Kind = 'boldref'
                    Match = $m; OldLetter = $m.Groups[1].Value; OldNum = $m.Groups[2].Value
                    TrailingText = $m.Groups[3].Value
                })
            }
            foreach ($m in [regex]::Matches($text, $crossPat)) {
                $events.Add([pscustomobject]@{
                    Index = $m.Index; Length = $m.Length; Kind = 'cross'
                    Match = $m; OldLetter = $m.Groups[1].Value; OldNum = $m.Groups[2].Value
                })
            }
            # v0.2 — section-letter ranges like "B-H" / "sections A-H" / "items B–G" where BOTH
            # endpoints map to known sections. Guarded — letters must NOT be adjacent to word chars
            # (avoids matching inside hyphenated words like "test-tenant" — t and t aren't single caps).
            # Pattern: word-boundary, single-cap, dash (regular or en-dash), single-cap, word-boundary.
            $sectionRangePat = '(?<![A-Za-z0-9])([A-Z])[\-–]([A-Z])(?![A-Za-z0-9])'
            foreach ($m in [regex]::Matches($text, $sectionRangePat)) {
                $startL = $m.Groups[1].Value
                $endL   = $m.Groups[2].Value
                if ($letterMap.Contains($startL) -and $letterMap.Contains($endL)) {
                    $events.Add([pscustomobject]@{
                        Index = $m.Index; Length = $m.Length; Kind = 'sectionrange'
                        Match = $m; StartOld = $startL; EndOld = $endL
                    })
                }
            }

            # Sort by Index
            $events = $events | Sort-Object Index

            # Items use their section's NEW letter (from sectionOrder walk).
            # Determine current section new-letter as we walk.
            $sb = [System.Text.StringBuilder]::new()
            $cursor = 0
            $currentNewLetter = $null
            $itemCounter = @{}

            foreach ($evt in $events) {
                if ($evt.Index -lt $cursor) { continue }  # overlap protection
                [void]$sb.Append($text.Substring($cursor, $evt.Index - $cursor))

                if ($evt.Kind -eq 'section') {
                    $currentNewLetter = $evt.NewLetter
                    $itemCounter[$currentNewLetter] = 0
                    [void]$sb.Append($evt.Replacement)
                } elseif ($evt.Kind -eq 'item') {
                    if (-not $currentNewLetter) {
                        # Item appearing before any section — leave alone
                        [void]$sb.Append($evt.Match.Value)
                    } else {
                        if (-not $itemCounter.Contains($currentNewLetter)) { $itemCounter[$currentNewLetter] = 0 }
                        $itemCounter[$currentNewLetter]++
                        # Preserve any trailing text inside the bold markers (e.g. "(recommended)")
                        $trailing = $evt.TrailingText
                        [void]$sb.Append("**${currentNewLetter}$($itemCounter[$currentNewLetter])${trailing}**")
                    }
                } elseif ($evt.Kind -eq 'boldref') {
                    # In-text bold reference like `**G1**` in body intro — rewrite letter via map, keep bold + trailing text
                    $oldL = $evt.OldLetter
                    $oldN = $evt.OldNum
                    $oldCode = "${oldL}${oldN}"
                    if ($letterMap.Contains($oldL) -and $validOldItemCodes.Contains($oldCode)) {
                        $newL = $letterMap[$oldL]
                        [void]$sb.Append("**${newL}${oldN}$($evt.TrailingText)**")
                    } else {
                        [void]$sb.Append($evt.Match.Value)
                    }
                } elseif ($evt.Kind -eq 'sectionrange') {
                    # Section-letter range like "B-H" — rewrite both endpoints via section map
                    $newStart = $letterMap[$evt.StartOld]
                    $newEnd   = $letterMap[$evt.EndOld]
                    # Preserve the dash character (regular - or en-dash – ) from the original match
                    $dashChar = $evt.Match.Value.Substring(1, 1)
                    [void]$sb.Append("${newStart}${dashChar}${newEnd}")
                } else {
                    # Plain-text cross-reference — gated on the valid-item-set so D365/M365/E5 etc. stay intact
                    $oldL = $evt.OldLetter
                    $oldN = $evt.OldNum
                    $oldCode = "${oldL}${oldN}"
                    if ($letterMap.Contains($oldL) -and $validOldItemCodes.Contains($oldCode)) {
                        $newL = $letterMap[$oldL]
                        [void]$sb.Append("${newL}${oldN}")
                    } else {
                        [void]$sb.Append($evt.Match.Value)
                    }
                }
                $cursor = $evt.Index + $evt.Length
            }
            [void]$sb.Append($text.Substring($cursor))
            $text = $sb.ToString()

            # Report
            $changedSections = 0
            $i = 0
            foreach ($m in $sectionMatches) {
                $expectedNew = [char]([int][char]'A' + $i)
                if ($m.Groups[2].Value -ne $expectedNew.ToString()) { $changedSections++ }
                $i++
            }
            if ($changedSections -gt 0) {
                $summary = ($letterMap.GetEnumerator() | Where-Object { $_.Key -ne $_.Value } | ForEach-Object { "$($_.Key)→$($_.Value)" }) -join ', '
                $report.Add("Pass 3-5: re-lettered $changedSections section(s) + items + cross-refs: $summary")
            }
        }

        # ---- PASS 6 — EMPTY-SECTION SCRUB --------------------------------------
        if (-not $NoEmptySection) {
            $emptyPat = '(?ms)^##+ [A-Z]\. [^\r\n]+\r?\n(?:[\s\-]*\r?\n)*(?=##|\z|---)'
            $cnt = ([regex]::Matches($text, $emptyPat)).Count
            if ($cnt -gt 0) {
                $text = [regex]::Replace($text, $emptyPat, '')
                $report.Add("Pass 6: removed $cnt empty section(s)")
            }
        }

        # Collapse 3+ consecutive blank lines to 2
        $text = [regex]::Replace($text, '(\r?\n){4,}', "`n`n`n")

        # ---- Write or report ----------------------------------------------------
        $modified = ($text -ne $orig)
        if ($Apply -and $modified) {
            if ($PSCmdlet.ShouldProcess($file, 'Apply MdLint changes')) {
                Set-Content -LiteralPath $file -Value $text -Encoding UTF8
                $report.Add("WRITTEN")
            }
        } elseif ($modified) {
            $report.Add("DRY-RUN: would write")
        } else {
            $report.Add("clean")
        }

        $result = [pscustomobject]@{
            Path      = $file
            Modified  = $modified
            Changes   = $report.ToArray()
            LetterMap = $letterMap
        }
        $results.Add($result)
        if (-not $Quiet) {
            $color = if ($modified) { 'Yellow' } else { 'DarkGray' }
            Write-Host ("[{0}] {1}" -f (Split-Path -Leaf $file), ($report -join ' · ')) -ForegroundColor $color
        }
    }

    return $results
}
