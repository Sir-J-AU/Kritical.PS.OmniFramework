function Invoke-KritEstatePushSweep {
<#
.SYNOPSIS
    Finds every piece of work that exists ONLY on this machine -- across every git repo and every
    worktree under the given roots -- and, with -Apply, gets it into GitHub (and an Azure DevOps
    mirror remote, if one is configured) without touching anyone's checkout. DRY-RUN BY DEFAULT.

.DESCRIPTION
    Operator order 2026-10-05: "make sure we get every last thing into GitHub and Azure DevOps,
    programmatically extending PS.GH". Proven necessary the same day: a 207 MB vendor corpus and a
    97 MB search database lived only on the laptop, gitignored; worktrees held uncommitted and
    unpushed work; nothing systematically looked.

    WHAT IT REPORTS (one row per git checkout or linked worktree; read-only, GIT_OPTIONAL_LOCKS=0):
      - uncommitted tracked changes and untracked (non-ignored) files;
      - commits on no remote ref, and local branches with no upstream (ref facts are per REPOSITORY,
        not per worktree: a repo and its linked worktrees share one ref store, so they are
        attributed ONCE, to the repo's primary checkout -- RefsOwner -- never double-counted);
      - a missing GitHub remote;
      - every STASH ENTRY whose commit no remote has (StashEntriesNotOnRemote);
      - local TAGS the GitHub remote lacks (LocalTagsNotOnRemote) and local tags that DIFFER from the
        remote's tag of the same name (DivergedTags -- reported, never overwritten);
      - DANGLING commits (tips found by git fsck with reflogs ignored) and reflog-only commits younger than
        -DanglingMaxAgeDays (DanglingCommits), capped at -MaxDanglingPerRepo;
      - a DETACHED-HEAD worktree whose HEAD no remote ref reaches (DetachedNotOnRemoteCommits), even when a
        local branch holds the commit;
      - whether an Azure DevOps mirror remote exists;
      - CANDIDATE-UNTRACKED-ASSETS: gitignored directories/files of >= 1 MB that hold source-like
        content (md json csv ps1 py sqlite html pdf). NEVER pushed automatically -- listed with size
        for the operator to decide (the 207 MB corpus case).

    VERDICTS: AT-RISK | ASSETS-ONLY | CLEAN | UNKNOWN (probe failed; a skip is never a pass) |
    EXCLUDED-SECRETS-PATH | SKIPPED-TRANSIENT | SKIPPED-FOREIGN-LEASE.

    WHAT -Apply DOES, per AT-RISK row, in this order (never force, never delete, never rewrite):
      1. Actions gate: Test-KritGitHubPushPermitted. A repo that can spend GitHub-hosted runner
         minutes is only REPORTED (ApplyAction = BLOCKED-ACTIONS) and NOTHING is mutated, unless the
         CALLER has set KRIT_ACTIONS_FREEZE_OVERRIDE=1. This cmdlet never sets it.
      2. Repo lease (Enter-KritRepoLease / Exit-KritRepoLease, LaneId on both). Pass 3a runs over every repo
         BEFORE pass 3b over every surface: a snapshot's parent is the checkout's HEAD, so pushing it first
         would make that branch's commits "already on the remote" and the branch would never be pushed
         under its own name.
      3b. (second pass) Uncommitted + untracked non-ignored work -> a NEW branch
         preserve/<machine>/<worktree-name>/<yyyyMMdd-HHmm>, built from a PRIVATE temporary index so
         the real index, the working tree, HEAD and the current branch are never modified, with every
         file secret-scanned (gitleaks, fail-closed) first. Pushed with Invoke-KritGitHubChunkedPush.
      3a. (first pass) Every local branch with commits on no remote is pushed under its own name (fast-forward or
         new branch only; a DIVERGED branch is reported, never overwritten). main/master are NOT
         pushed to the remote default branch: their unpushed commits go to
         preserve/<machine>/<repo>/<stamp>-<branch> instead, so nothing lands on the default branch
         without a PR.
      3c. (third pass, owner rows) stash entries, dangling commits and tags:
            - every stash entry on no remote -> its OWN branch preserve/<machine>/<repo>/stash-<n>-<yyyyMMdd-HHmm>
              AT THE STASH COMMIT (its index and untracked commits travel with it), pushed. The stash is never
              popped, applied or dropped; the checkout is not touched.
            - every dangling tip -> preserve/<machine>/<repo>/dangling-<sha8>, pushed.
            - every local tag the remote lacks is pushed (never forced). A tag that exists on the remote at a
              DIFFERENT object is reported DIVERGED-TAG and left alone (APPLIED-WITH-HELD).
            All three go through the same history secret scan as every other push: a finding or a scanner
            that cannot answer HOLDS the ref (fail closed). They run AFTER pass 3a because a stash or dangling
            commit's ancestry would otherwise make a real branch's commits look already published.
      5. With -IncludeAzureDevOpsMirror: the same refs to the ADO mirror remote IF one is configured;
         otherwise ADO-MIRROR-NOT-CONFIGURED plus what is needed. No Azure Resource Manager, storage
         or subscription call is ever made; no ADO repository is created here.

    HARD-CODED EXCLUSIONS (tested): any path containing "Secrets" (a repo whose own path contains it
    is never even opened); files over 95 MB; node_modules, bin, obj, .venv; transient gate
    worktrees; any repo with a LIVE FOREIGN lease (another lane's -- e.g. the Engineering System
    primary checkout while another session holds it). Gitignored content is never auto-pushed.

    PARALLELISM: the probe phase runs under ForEach-Object -Parallel with -ThrottleLimit (default 2:
    the laptop is overloaded). Kritical.PS.OmniFramework has no throttled-execution primitive
    (read from source 2026-10-05); with -LoadOmniFramework this cmdlet uses its Write-KriticalLog
    for run events. Apply is deliberately SEQUENTIAL: one push at a time.

.PARAMETER Root
    Roots to sweep. Default: Get-KritEstateSweepRoot (the configured estate roots).
.PARAMETER Repo
    Optional repo/worktree folder names to restrict to (wildcards allowed).
.PARAMETER ThrottleLimit
    Probe concurrency. Default 2.
.PARAMETER Apply
    Perform the preserve + push actions. Without it nothing in any repo is changed.
.PARAMETER IncludeAzureDevOpsMirror
    With -Apply, also push the same refs to an ADO mirror remote when the repo has one.
.PARAMETER ReceiptPath
    Directory for the CSV / JSON / markdown receipt. Default: scripts\state\estate-push-sweep under
    this module's root (gitignored).
.PARAMETER LaneId
    Lease/lane identity. Default estate-push-sweep. A lease held by any OTHER lane is foreign.
.PARAMETER CheckActions
    Also run the Actions gate during a dry run (costs gh API calls) so BLOCKED-ACTIONS is visible
    before -Apply.
.PARAMETER ShowFiles
    The dry run lists every affected file (status untracked/modified/staged, size, RISK flag) when a repo has 50
    or fewer of them; above 50 it prints counts only unless this switch is given. RISK = EXCLUDE-SUGGESTED for
    *.zip *.7z *.env* *User_Download* *.pfx *.p12 *.key *.pem *.kdbx *.pst *.ost and any file over 50 MB. Paths and
    sizes only -- file contents are never printed. -Apply behaves as before and prints the same risk warnings.
.PARAMETER Fetch
    git fetch --all before measuring (default off: the laptop is overloaded; remote-tracking refs
    are used as cached).
.PARAMETER GitHubRemotePattern
    Regex a remote URL must match to count as the GitHub remote. Default github\.com. (Test seam.)
.PARAMETER AdoRemotePattern
    Regex identifying an Azure DevOps remote URL. Default dev\.azure\.com|visualstudio\.com.
.PARAMETER PushPermissionProvider
    TEST SEAM, same contract as Sync-KritGitHubUnpushedBranches. Do not pass in production.
.PARAMETER SecretScanner
    TEST SEAM: scriptblock taking -FilePath -RepoRoot, returning Ok/Findings/Rules/Error. Default is
    the estate's gitleaks wrapper. Fails closed.
.PARAMETER HistoryScanner
    TEST SEAM: scriptblock taking -RepoPath -LogOpts (a `git log` revision range of the commits about to be
    published), returning Ok/Findings/Rules/Error. Default is `gitleaks git`. Every ref is secret-scanned over
    `<ref> --not --remotes=<remote>` BEFORE it is pushed; a finding or a scanner that cannot give a verdict HOLDS
    the push (fail closed). Branches whose NAME says do-not-push / token-in-history / secret are held outright.
.PARAMETER PerRepoBudgetSeconds
    Wall-clock budget for the APPLY work on ONE repo (all passes together). A repo that has used it is HELD for its remaining
    refs (BUDGET-EXCEEDED, APPLIED-WITH-HELD) and the sweep moves on; nothing is killed mid-write. The secret scanners have
    their own hard timeouts (SCANNER-TIMEOUT). Default 900. Lane psgh-sweep-hardening-20261011.
.PARAMETER SkipStash
    Do not look for stash entries that exist on no remote.
.PARAMETER SkipTags
    Do not compare local tags with the remote (this is the only part that makes a network call: one
    git ls-remote --tags per repo that HAS local tags) and do not push tags.
.PARAMETER SkipDangling
    Do not run git fsck for dangling / reflog-only commits (the slow part on a large repo).
.PARAMETER DanglingMaxAgeDays
    A reflog-only commit older than this is left to git's own reflog expiry. Default 90. A commit with no
    reflog entry at all is kept at any age.
.PARAMETER MaxDanglingPerRepo
    Newest-first cap on dangling tips preserved per repo; the overflow is reported (DANGLING-OVER-CAP).
.PARAMETER LoadOmniFramework
    Import Kritical.PS.OmniFramework (if installed) and log run events with Write-KriticalLog.
.PARAMETER PassThruSummary
    Return one summary object (counts, Rows, Assets, receipt file paths) instead of the rows.

.OUTPUTS
    Row objects (or the summary with -PassThruSummary). Receipts: <stamp>.csv, -assets.csv, .json, .md.

.EXAMPLE
    Invoke-KritEstatePushSweep -Root C:\NoOneDrive\Github, C:\NoOneDrive\worktrees -ThrottleLimit 2 -ReceiptPath C:\NoOneDrive\AgentOutput\x

.EXAMPLE
    # after review of the dry run:
    Invoke-KritEstatePushSweep -Root C:\NoOneDrive\Github, C:\NoOneDrive\worktrees -Apply -IncludeAzureDevOpsMirror
#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$Root,
        [string[]]$Repo,
        [ValidateRange(1, 16)][int]$ThrottleLimit = 2,
        [switch]$Apply,
        [switch]$ShowFiles,
        [switch]$IncludeAzureDevOpsMirror,
        [string]$ReceiptPath,
        [string]$LaneId = 'estate-push-sweep',
        [switch]$CheckActions,
        [switch]$Fetch,
        [switch]$SkipStash,
        [switch]$SkipTags,
        [switch]$SkipDangling,
        [ValidateRange(1, 3650)][int]$DanglingMaxAgeDays = 90,
        [ValidateRange(1, 5000)][int]$MaxDanglingPerRepo = 50,
        [string]$GitHubRemotePattern = 'github\.com',
        [string]$AdoRemotePattern = 'dev\.azure\.com|visualstudio\.com',
        [ValidateRange(10, 5000)][int]$ChunkSize = 500,
        [ValidateRange(1, 86400)][int]$PerRepoBudgetSeconds = 900,
        [scriptblock]$PushPermissionProvider,
        [scriptblock]$SecretScanner,
        [scriptblock]$HistoryScanner,
        [switch]$LoadOmniFramework,
        [switch]$PassThruSummary
    )

    $started = [datetime]::UtcNow
    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    $fileStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $machine = $env:COMPUTERNAME
    $pol = _KritEpsPolicy
    # Measure-Object -Sum over an empty set returns nothing, and `.Sum` on nothing throws under the module's
    # ambient StrictMode -Version Latest -- sum by hand.
    $sumOf = { param($Items, [scriptblock]$Pick) $t = [double]0; foreach ($i in @($Items)) { $t += [double](& $Pick $i) }; $t }

    if ($LoadOmniFramework -and -not (Get-Command Write-KriticalLog -ErrorAction SilentlyContinue)) {
        Import-Module Kritical.PS.OmniFramework -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>$null 4>$null 6>$null
    }
    $log = {
        param([string]$Message, [string]$Level = 'Info')
        if (Get-Command Write-KriticalLog -ErrorAction SilentlyContinue) {
            try { Write-KriticalLog -Message $Message -Level $Level -Tag 'estate-push-sweep' 6>$null } catch { $null = $_ }
        }
    }
    if (-not $SecretScanner) {
        $SecretScanner = { param($FilePath, $RepoRoot) _KritWpcGitleaksScan -FilePath $FilePath -RepoRoot $RepoRoot }
    }
    if (-not $HistoryScanner) {
        $HistoryScanner = { param($RepoPath, $LogOpts) _KritEpsGitleaksRangeScan -RepoPath $RepoPath -LogOpts $LogOpts }
    }
    if (-not $ReceiptPath) {
        $ReceiptPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts\state\estate-push-sweep'
    }
    if (-not $Root -or @($Root).Count -eq 0) {
        $Root = @(Get-KritEstateSweepRoot | Where-Object Ok | Select-Object -ExpandProperty Path)
    }
    & $log "estate push sweep start: apply=$([bool]$Apply) throttle=$ThrottleLimit roots=$(@($Root) -join ',')"

    # ---------------------------------------------------------------- streamed receipt (JSONL)
    # Lane psgh-sweep-hardening-20261011: the sweep used to write its receipt only at the very end, so a run killed after
    # 4h40m left NOTHING. Every event is appended the moment it happens; the CSV/JSON/MD receipts at the end are unchanged.
    New-Item -ItemType Directory -Path $ReceiptPath -Force | Out-Null
    $base = Join-Path $ReceiptPath "estate-push-sweep-$fileStamp"
    $jsonlPath = "$base.jsonl"
    $emit = {
        param([hashtable]$Evt)
        $Evt['atUtc'] = [datetime]::UtcNow.ToString('o')
        try { [System.IO.File]::AppendAllText($jsonlPath, (($Evt | ConvertTo-Json -Depth 5 -Compress) + "`n"), [System.Text.UTF8Encoding]::new($false)) } catch { $null = $_ }
    }
    & $emit @{ event = 'start'; mode = $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' }); lane = $LaneId; roots = @($Root); machine = $machine; perRepoBudgetSeconds = $PerRepoBudgetSeconds }

    # ---------------------------------------------------------------- discovery
    $targets = [System.Collections.Generic.List[object]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $rootNotes = [System.Collections.Generic.List[string]]::new()
    foreach ($r0 in @($Root)) {
        if (-not (Test-Path -LiteralPath $r0 -PathType Container)) { $rootNotes.Add("ROOT-MISSING: $r0"); continue }
        $r1 = (Resolve-Path -LiteralPath $r0).ProviderPath.TrimEnd('\', '/')
        # Find-KritGitRepo refuses a result it cannot vouch for, so hand it a sentinel that exists
        # under this root: the root itself if it is a repo, else its first repo child.
        $sentinel = $null
        if (Test-Path -LiteralPath (Join-Path $r1 '.git')) { $sentinel = $r1 }
        else {
            $sentinel = Get-ChildItem -LiteralPath $r1 -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') } |
                Select-Object -First 1 -ExpandProperty FullName
        }
        if (-not $sentinel) { $rootNotes.Add("NO-REPOS-FOUND-UNDER: $r1"); continue }
        $found = @(Find-KritGitRepo -Root $r1 -SentinelRepoPath $sentinel -MaxDepth 3 -ErrorAction Stop)
        foreach ($f in $found) {
            if ($f.Kind -notin @('CHECKOUT', 'WORKTREE')) { continue }
            if (-not $seenPaths.Add($f.RepoPath)) { continue }
            $targets.Add([pscustomobject]@{ Path = $f.RepoPath; Kind = $f.Kind; Root = $r1; Name = (Split-Path -Leaf $f.RepoPath) })
        }
    }
    if ($Repo) {
        $keep = @($targets | Where-Object { $n = $_.Name; @($Repo | Where-Object { $n -like $_ }).Count -gt 0 })
        $targets = [System.Collections.Generic.List[object]]::new()
        foreach ($k in $keep) { $targets.Add($k) }
    }

    # ---------------------------------------------------------------- pre-probe exclusions
    $rows = [System.Collections.Generic.List[object]]::new()
    $probeList = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $targets) {
        $skip = $null
        if ($t.Path -match $pol.SecretsPattern) { $skip = 'EXCLUDED-SECRETS-PATH' }
        elseif ((Test-KritRepoIsTransientWorktree -Name $t.Name).IsTransient) { $skip = 'SKIPPED-TRANSIENT' }
        if ($skip) {
            $rows.Add([pscustomobject]@{ Target = $t; Probe = $null; Verdict = $skip })
        } else { $probeList.Add($t) }
    }

    # ---------------------------------------------------------------- probe (throttled, parallel)
    $bundle = "function _KritEpsTestExcludedPath {`n" + ${function:_KritEpsTestExcludedPath}.ToString() + "`n}`n" +
              "function _KritEpsProbeRepo {`n" + ${function:_KritEpsProbeRepo}.ToString() + "`n}"
    $pMax = [long]$pol.MaxFileBytes; $pSeg = @($pol.ExcludedSegments); $pSec = [string]$pol.SecretsPattern
    $pLarge = [long]$pol.LargeIgnoredBytes; $pExt = @($pol.SourceExtensions); $pFetch = [bool]$Fetch
    $probeOut = @()
    if ($probeList.Count -gt 0) {
        $probeOut = @($probeList.ToArray() | ForEach-Object -Parallel {
            . ([scriptblock]::Create($using:bundle))
            $t = $_
            try {
                $sp = @{
                    Path = $t.Path; MaxFileBytes = $using:pMax; ExcludedSegments = $using:pSeg; SecretsPattern = $using:pSec
                    LargeIgnoredBytes = $using:pLarge; SourceExtensions = $using:pExt
                }
                if ($using:pFetch) { $sp.Fetch = $true }
                $p = _KritEpsProbeRepo @sp
            } catch {
                $p = [pscustomobject]@{ Path = $t.Path; Ok = $false; Error = $_.Exception.Message }
            }
            [pscustomobject]@{ Target = $t; Probe = $p }
        } -ThrottleLimit $ThrottleLimit)
    }
    foreach ($po in $probeOut) { $rows.Add([pscustomobject]@{ Target = $po.Target; Probe = $po.Probe; Verdict = '' }) }

    # ---------------------------------------------------------------- ref-fact ownership
    # A repo and its linked worktrees share one ref store: attribute the ref facts ONCE.
    $owners = @{}
    $groups = $rows | Where-Object { $_.Probe -and $_.Probe.Ok -and $_.Probe.CommonDir } | Group-Object { $_.Probe.CommonDir }
    foreach ($g in $groups) {
        $primary = @($g.Group | Where-Object { -not $_.Probe.IsLinkedWorktree } | Sort-Object { $_.Target.Path })
        $ownerRow = if ($primary.Count -gt 0) { $primary[0] } else { @($g.Group | Sort-Object { $_.Target.Path })[0] }
        $owners[$g.Name] = $ownerRow.Target.Path
    }

    # ---------------------------------------------------------------- repo-level facts (owner rows only; throttled, parallel)
    # Stashes, tags and dangling commits live in the repository's shared ref/object store, so they are measured ONCE per
    # repository (its owner row), never once per worktree. A repo with no remote is skipped: it is AT-RISK already.
    $repoFacts = @{}
    if (-not ($SkipStash -and $SkipTags -and $SkipDangling)) {
        $factTargets = [System.Collections.Generic.List[object]]::new()
        foreach ($op in @($owners.Values | Sort-Object -Unique)) {
            $prow = @($rows | Where-Object { $_.Probe -and $_.Target.Path -ieq $op })[0]
            if (-not $prow -or $prow.Probe.NoRemotes) { continue }
            $ghr = @($prow.Probe.Remotes | Where-Object { $_.Url -match $GitHubRemotePattern })
            $rn = ''
            if ($ghr.Count -gt 0) { $pk = @($ghr | Where-Object { $_.Name -eq 'origin' }); if ($pk.Count -eq 0) { $pk = $ghr }; $rn = $pk[0].Name }
            $factTargets.Add([pscustomobject]@{ Path = $op; Remote = $rn })
        }
        if ($factTargets.Count -gt 0) {
            $fBundle = "function _KritEpsProbeRepoFacts {`n" + ${function:_KritEpsProbeRepoFacts}.ToString() + "`n}"
            $fSkipStash = [bool]$SkipStash; $fSkipTags = [bool]$SkipTags; $fSkipDangling = [bool]$SkipDangling
            $fAge = [int]$DanglingMaxAgeDays; $fMax = [int]$MaxDanglingPerRepo
            $factOut = @($factTargets.ToArray() | ForEach-Object -Parallel {
                . ([scriptblock]::Create($using:fBundle))
                $t = $_
                try {
                    $sp = @{ Path = $t.Path; RemoteName = $t.Remote; DanglingMaxAgeDays = $using:fAge; MaxDanglingPerRepo = $using:fMax }
                    if ($using:fSkipStash) { $sp.SkipStash = $true }
                    if ($using:fSkipTags) { $sp.SkipTags = $true }
                    if ($using:fSkipDangling) { $sp.SkipDangling = $true }
                    _KritEpsProbeRepoFacts @sp
                } catch {
                    [pscustomobject]@{ Path = $t.Path; Ok = $false; Error = $_.Exception.Message }
                }
            } -ThrottleLimit $ThrottleLimit)
            foreach ($f in $factOut) { $repoFacts[[string]$f.Path] = $f }
        }
    }

    # ---------------------------------------------------------------- classify
    $assetRows = [System.Collections.Generic.List[object]]::new()
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $t = $row.Target; $pr = $row.Probe
        $o = [ordered]@{
            Machine = $machine; RepoPath = $t.Path; RepoName = $t.Name; Kind = $t.Kind; Root = $t.Root; Branch = ''
            Verdict = ''; Reasons = ''; TrackedChanged = 0; Untracked = 0; EligibleFiles = 0; ExcludedFiles = 0; OverLimitFiles = 0
            RefsOwner = $false; RefsOwnedBy = ''; UnpushedCommits = 0; UnpushedBranches = ''; NoUpstreamBranches = 0
            DetachedUnreachableCommits = 0; StashCount = 0
            StashEntriesNotOnRemote = 0; LocalTagsNotOnRemote = 0; DivergedTags = 0; DanglingCommits = 0; DetachedNotOnRemoteCommits = 0
            HasGitHubRemote = $false; GitHubRemote = ''; HasAdoRemote = $false; AdoRemote = ''; AdoMirror = ''
            CandidateAssetCount = 0; CandidateAssetMB = 0.0; LeaseHolder = ''
            ActionsState = 'NOT-CHECKED'; PlannedActions = ''; ApplyAction = ''; ApplyDetail = ''
            PreserveBranch = ''; PreserveSha = ''; PushedRefs = ''; Error = ''; RiskFiles = 0; Files = @()
        }
        if ($row.Verdict) { $o.Verdict = $row.Verdict; $out.Add([pscustomobject]$o); continue }
        if (-not $pr -or -not $pr.Ok) {
            $o.Verdict = 'UNKNOWN'; $o.Error = if ($pr) { [string]$pr.Error } else { 'no probe result' }
            $out.Add([pscustomobject]$o); continue
        }
        $o.Branch = $pr.Branch
        $o.TrackedChanged = $pr.TrackedChanged; $o.Untracked = $pr.Untracked
        $o.EligibleFiles = $pr.EligibleCount; $o.ExcludedFiles = $pr.ExcludedCount; $o.OverLimitFiles = $pr.OverLimitCount
        $o.StashCount = $pr.StashCount
        $o.Files = @($pr.Files)
        $o.RiskFiles = @($o.Files | Where-Object { $_.Risk -eq 'EXCLUDE-SUGGESTED' }).Count
        $isOwner = ($owners.ContainsKey($pr.CommonDir) -and ($owners[$pr.CommonDir] -ieq $t.Path))
        $o.RefsOwner = $isOwner
        if (-not $isOwner -and $owners.ContainsKey($pr.CommonDir)) { $o.RefsOwnedBy = $owners[$pr.CommonDir] }
        $gh = @($pr.Remotes | Where-Object { $_.Url -match $GitHubRemotePattern })
        $ado = @($pr.Remotes | Where-Object { $_.Url -match $AdoRemotePattern -or $_.Name -in @('ado', 'azuredevops') })
        if ($gh.Count -gt 0) {
            $pick = @($gh | Where-Object { $_.Name -eq 'origin' }); if ($pick.Count -eq 0) { $pick = $gh }
            $o.HasGitHubRemote = $true; $o.GitHubRemote = $pick[0].Name
        }
        if ($ado.Count -gt 0) { $o.HasAdoRemote = $true; $o.AdoRemote = $ado[0].Name }
        $o.AdoMirror = if ($o.HasAdoRemote) { "PRESENT:$($o.AdoRemote)" } else { 'ABSENT' }

        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($pr.TrackedChanged -gt 0) { $reasons.Add("DIRTY-TRACKED:$($pr.TrackedChanged)") }
        if ($pr.Untracked -gt 0) { $reasons.Add("UNTRACKED:$($pr.Untracked)") }
        if ($isOwner) {
            $o.UnpushedCommits = $pr.UnpushedCommitTotal
            $o.NoUpstreamBranches = $pr.NoUpstreamCount
            $o.UnpushedBranches = (@($pr.BranchFacts | Where-Object { $_.Unique } | ForEach-Object { $_.Name }) -join ';')
            if ($pr.UnpushedCommitTotal -gt 0) { $reasons.Add("UNPUSHED-COMMITS:$($pr.UnpushedCommitTotal)") }
            if ($pr.NoUpstreamCount -gt 0) { $reasons.Add("BRANCHES-NO-UPSTREAM:$($pr.NoUpstreamCount)") }
            if (-not $o.HasGitHubRemote) { $reasons.Add('NO-GITHUB-REMOTE') }
        }
        if ($pr.Detached -and $pr.DetachedUnreachable -gt 0) {
            $o.DetachedUnreachableCommits = $pr.DetachedUnreachable
            $reasons.Add("DETACHED-HEAD-COMMITS-ON-NO-REF:$($pr.DetachedUnreachable)")
        }
        if ($pr.Detached -and $pr.DetachedNotOnRemote -gt 0) {
            $o.DetachedNotOnRemoteCommits = $pr.DetachedNotOnRemote
            $reasons.Add("DETACHED-HEAD-NOT-ON-REMOTE:$($pr.DetachedNotOnRemote)")
        }
        $factsUnknown = ''
        $extrasAtRisk = $false
        if ($isOwner -and $repoFacts.ContainsKey($t.Path)) {
            $rfx = $repoFacts[$t.Path]
            if (-not $rfx.Ok) { $factsUnknown = "REPO-FACTS-UNKNOWN:$($rfx.Error)"; $reasons.Add($factsUnknown) }
            else {
                $o.StashEntriesNotOnRemote = [int]$rfx.StashNotOnRemote
                $o.LocalTagsNotOnRemote = @($rfx.TagsNotOnRemote).Count
                $o.DivergedTags = @($rfx.DivergedTags).Count
                $o.DanglingCommits = @($rfx.DanglingTips).Count
                if ($o.StashEntriesNotOnRemote -gt 0) { $reasons.Add("STASHES-NOT-ON-REMOTE:$($o.StashEntriesNotOnRemote)") }
                if ($o.LocalTagsNotOnRemote -gt 0) { $reasons.Add("LOCAL-TAGS-NOT-ON-REMOTE:$($o.LocalTagsNotOnRemote)") }
                if ($o.DivergedTags -gt 0) { $reasons.Add("DIVERGED-TAG:$($o.DivergedTags)") }
                if ($o.DanglingCommits -gt 0) { $reasons.Add("DANGLING-COMMITS:$($o.DanglingCommits)") }
                if ($rfx.DanglingOverCap -gt 0) { $reasons.Add("DANGLING-OVER-CAP:$($rfx.DanglingOverCap)") }
                if ($rfx.TagCheck) { $factsUnknown = [string]$rfx.TagCheck; $reasons.Add([string]$rfx.TagCheck) }
                if ($rfx.DanglingCheck) { $reasons.Add([string]$rfx.DanglingCheck) }
                $extrasAtRisk = ($o.StashEntriesNotOnRemote + $o.LocalTagsNotOnRemote + $o.DivergedTags + $o.DanglingCommits) -gt 0
            }
        }
        # branches with no upstream are REPORTED; they only make the row AT-RISK when they carry commits
        # no remote has (UNPUSHED-COMMITS), or when the repo has no GitHub remote at all.
        $atRisk = ($pr.TrackedChanged + $pr.Untracked -gt 0) -or ($isOwner -and ($pr.UnpushedCommitTotal -gt 0 -or -not $o.HasGitHubRemote)) -or
                  ($pr.Detached -and $pr.DetachedUnreachable -gt 0) -or ($pr.Detached -and $pr.DetachedNotOnRemote -gt 0) -or $extrasAtRisk
        if ($pr.CandidateAssets.Count -gt 0) {
            $o.CandidateAssetCount = $pr.CandidateAssets.Count
            $o.CandidateAssetMB = [math]::Round((& $sumOf @($pr.CandidateAssets) { param($x) $x.SizeBytes }) / 1MB, 1)
            foreach ($a in $pr.CandidateAssets) {
                $assetRows.Add([pscustomobject]@{
                    Machine = $machine; RepoPath = $t.Path; RepoName = $t.Name; Kind = $t.Kind; RelativePath = $a.RelativePath
                    AssetKind = $a.Kind; SizeMB = [math]::Round($a.SizeBytes / 1MB, 2); SizeBytes = $a.SizeBytes
                    SourceLikeFiles = $a.SourceLikeFiles; SourceLikeMB = [math]::Round($a.SourceLikeBytes / 1MB, 2)
                    Extensions = $a.Extensions; Truncated = $a.Truncated; Status = 'CANDIDATE-UNTRACKED-ASSETS'
                })
            }
        }
        $o.Verdict = if ($atRisk) { 'AT-RISK' } elseif ($pr.CandidateAssets.Count -gt 0) { 'ASSETS-ONLY' } else { 'CLEAN' }
        if ($pr.NoRemotes -and $o.Verdict -eq 'CLEAN' -and $isOwner) { $o.Verdict = 'AT-RISK' }
        # a question the sweep could not answer is never read as "nothing there" (S20): CLEAN becomes UNKNOWN
        if ($factsUnknown -and $o.Verdict -eq 'CLEAN') { $o.Verdict = 'UNKNOWN'; $o.Error = $factsUnknown }

        # foreign lease: skip (report facts, mutate nothing)
        try {
            $lease = Get-KritRepoLeaseStatus -RepoPath $t.Path -ErrorAction Stop
            if ($lease -and -not $lease.IsExpired -and -not $lease.IsOrphaned -and $lease.LaneId -ne $LaneId) {
                $o.LeaseHolder = [string]$lease.LaneId
                $reasons.Add("WOULD-BE-$($o.Verdict)")
                $o.Verdict = 'SKIPPED-FOREIGN-LEASE'
            }
        } catch { $reasons.Add("LEASE-STATUS-UNREADABLE:$($_.Exception.Message)") }
        $o.Reasons = ($reasons -join '; ')

        # planned actions + Actions gate
        if ($o.Verdict -eq 'AT-RISK') {
            $plan = [System.Collections.Generic.List[string]]::new()
            if ($pr.EligibleCount -gt 0) { $plan.Add("preserve-branch($($pr.EligibleCount) files)+push") }
            if ($isOwner -and $pr.UnpushedBranchCount -gt 0) { $plan.Add("push-branches($($pr.UnpushedBranchCount))") }
            if ($o.StashEntriesNotOnRemote -gt 0) { $plan.Add("preserve-stashes($($o.StashEntriesNotOnRemote))+push") }
            if ($o.DanglingCommits -gt 0) { $plan.Add("preserve-dangling($($o.DanglingCommits))+push") }
            if ($o.LocalTagsNotOnRemote -gt 0) { $plan.Add("push-tags($($o.LocalTagsNotOnRemote))") }
            if ($o.DivergedTags -gt 0) { $plan.Add("HOLD-DIVERGED-TAGS($($o.DivergedTags))") }
            if (-not $o.HasGitHubRemote) { $plan.Add('BLOCKED-NO-GITHUB-REMOTE') }
            if ($IncludeAzureDevOpsMirror) { $plan.Add($(if ($o.HasAdoRemote) { 'ado-mirror-push' } else { 'ADO-MIRROR-NOT-CONFIGURED' })) }
            $o.PlannedActions = ($plan -join ' | ')
            if (($Apply -or $CheckActions) -and $o.HasGitHubRemote) {
                try {
                    $perm = if ($PushPermissionProvider) { & $PushPermissionProvider -Path $t.Path -Remote $o.GitHubRemote }
                            else {
                                # INCIDENT 2026-10-12: also name the paths this sweep would publish (commits on no remote + uncommitted paths),
                                # so a head that ADDS .github/workflows/* is refused unless repo-level Actions is disabled.
                                $hpLog = @(& git -C $t.Path log --branches --not --remotes --name-only '--pretty=format:' 2>$null)
                                $hpLogRc = $LASTEXITCODE
                                $hpSt = @(& git -C $t.Path status --porcelain 2>$null)
                                $hpStRc = $LASTEXITCODE
                                if ($hpLogRc -ne 0 -or $hpStRc -ne 0) { throw "could not list the paths to be published (git log rc=$hpLogRc, git status rc=$hpStRc)" }
                                $hp = @($hpLog | Where-Object { $_ }) + @($hpSt | ForEach-Object { ([string]$_).Substring([Math]::Min(3, ([string]$_).Length)) -replace '^.* -> ', '' -replace '^"|"$', '' })
                                Test-KritGitHubPushPermitted -Path $t.Path -Remote $o.GitHubRemote -HeadPaths $hp
                            }
                } catch { $perm = [pscustomobject]@{ Permitted = $false; Verdict = 'REFUSED-CANNOT-DETERMINE'; Reason = $_.Exception.Message } }
                $okPerm = ($null -ne $perm -and (@($perm.PSObject.Properties.Name) -contains 'Permitted') -and [bool]$perm.Permitted)
                $o.ActionsState = if ($okPerm) { 'PERMITTED:' + $perm.Verdict } else { 'BLOCKED-ACTIONS:' + $(if ($perm -and $perm.Verdict) { $perm.Verdict } else { 'REFUSED-CANNOT-DETERMINE' }) }
            }
        }
        $out.Add([pscustomobject]$o)
    }

    foreach ($o in $out) { & $emit @{ event = 'classified'; repo = $o.RepoPath; kind = $o.Kind; verdict = $o.Verdict; reasons = $o.Reasons; trackedChanged = $o.TrackedChanged; untracked = $o.Untracked; unpushedCommits = $o.UnpushedCommits; actionsState = $o.ActionsState; plannedActions = $o.PlannedActions } }

    # ---------------------------------------------------------------- per-file view (EES blocker D5)
    # Dry run: list each affected file when a repo has <= 50 of them, or with -ShowFiles; else counts only.
    # -Apply: behaviour unchanged; only the RISK warning list is printed. Paths and sizes only, never contents.
    $fmtSize = {
        param([long]$b)
        if ($b -ge 1MB) { '{0:N1} MB' -f ($b / 1MB) } elseif ($b -ge 1KB) { '{0:N1} KB' -f ($b / 1KB) } else { "$b B" }
    }
    $riskHint = 'Move EXCLUDE-SUGGESTED files out of the repo (or add to .gitignore) before -Apply'
    foreach ($o in @($out | Where-Object { $_.Verdict -eq 'AT-RISK' -and @($_.Files).Count -gt 0 })) {
        $affected = [int]($o.TrackedChanged + $o.Untracked)
        if ($Apply) {
            $risky = @($o.Files | Where-Object { $_.Risk -eq 'EXCLUDE-SUGGESTED' })
            if ($risky.Count -gt 0) {
                Write-Warning "$($o.RepoName): $($risky.Count) EXCLUDE-SUGGESTED file(s) are about to be preserved and pushed:"
                foreach ($f in $risky) { Write-Warning ("  [{0}] {1}  {2}  RISK=EXCLUDE-SUGGESTED" -f $f.Status, (& $fmtSize $f.SizeBytes), $f.Path) }
                Write-Warning $riskHint
            }
            continue
        }
        if ($affected -gt 50 -and -not $ShowFiles) {
            Write-Host "$($o.RepoName): $affected files affected ($($o.RiskFiles) flagged EXCLUDE-SUGGESTED); re-run with -ShowFiles to list them."
            continue
        }
        Write-Host "$($o.RepoName): $affected file(s) affected:"
        foreach ($f in $o.Files) {
            Write-Host ("  [{0}] {1}  {2}{3}" -f $f.Status, (& $fmtSize $f.SizeBytes), $f.Path, $(if ($f.Risk) { "  RISK=$($f.Risk)" } else { '' }))
        }
        if ($o.RiskFiles -gt 0) { Write-Host $riskHint }
    }

    # ---------------------------------------------------------------- apply (sequential)
    # TWO PASSES, in this order, because of ancestry: a preserve snapshot's parent is the checkout's HEAD, so
    # pushing a snapshot first would make that branch's commits "already on the remote" (reachable from the
    # preserve ref) and the branch itself would never be pushed under its own name.
    #   pass 1  every repo's local branches with commits on no remote (owner rows only)
    #   pass 2  every surface's uncommitted + untracked work -> preserve branch -> push; then the ADO mirror
    $probeByPath = @{}
    foreach ($row in $rows) { if ($row.Probe) { $probeByPath[$row.Target.Path] = $row.Probe } }
    if ($Apply) {
        $state = @{}
        $atRisk = @($out | Where-Object { $_.Verdict -eq 'AT-RISK' })
        foreach ($o in $atRisk) {
            if (-not $o.HasGitHubRemote) { $o.ApplyAction = 'BLOCKED-NO-GITHUB-REMOTE'; continue }
            if ($o.ActionsState -like 'BLOCKED-ACTIONS*') { $o.ApplyAction = 'BLOCKED-ACTIONS'; $o.ApplyDetail = $o.ActionsState; continue }
            $state[$o.RepoPath] = @{ Steps = [System.Collections.Generic.List[string]]::new(); Pushed = [System.Collections.Generic.List[string]]::new(); Mirror = [System.Collections.Generic.List[object]]::new(); Failed = $false; Held = $false }
        }
        # LEASE ONLY AROUND THE WRITE (lane psgh-sweep-hardening-20261011). Scanning is read-only and can be slow; the sweep used to
        # hold a repo's lease across it (2 hours on one repo, blocking another landing). Every mutation below goes through this.
        $withLease = {
            param([string]$LeasePath, [scriptblock]$Body)
            Enter-KritRepoLease -RepoPath $LeasePath -LaneId $LaneId -Reason 'Invoke-KritEstatePushSweep' | Out-Null
            try { & $Body }
            finally { try { Exit-KritRepoLease -RepoPath $LeasePath -LaneId $LaneId | Out-Null } catch { Write-Warning "lease release failed for ${LeasePath}: $($_.Exception.Message)" } }
        }
        # PER-REPO WALL-CLOCK BUDGET: one stopwatch per repo, running only while that repo is being worked on.
        $budgetSw = @{}
        foreach ($o in $atRisk) { $budgetSw[$o.RepoPath] = [System.Diagnostics.Stopwatch]::new() }
        # At least ONE ref per repo is always attempted (a slow enumeration alone must not starve a repo of its first push); the
        # budget bites from the second attempt on.
        $budgetWork = @{}
        $overBudget = { param([string]$BudgetPath) $sw = $budgetSw[$BudgetPath]; [bool]($sw -and $sw.Elapsed.TotalSeconds -ge $PerRepoBudgetSeconds -and $budgetWork[$BudgetPath] -gt 0) }
        $pushRef = {
            param([string]$RepoPath, [string]$Remote, [string]$LocalRef, [string]$RemoteBranch)
            try {
                if (& $overBudget $RepoPath) { return "HELD-BUDGET-EXCEEDED:$Remote/${RemoteBranch}:repo used its ${PerRepoBudgetSeconds}s budget" }
                $budgetWork[$RepoPath] = 1 + [int]$budgetWork[$RepoPath]
                # secret-scan the commits this push would publish BEFORE any byte leaves the machine; fail closed
                $hs = $null
                try { $hs = & $HistoryScanner -RepoPath $RepoPath -LogOpts "$LocalRef --not --remotes=$Remote" }
                catch { return "HELD-SCANNER-FAILED:$Remote/${RemoteBranch}:$($_.Exception.Message)" }
                if (-not $hs -or -not $hs.Ok) { return "HELD-SCANNER-FAILED:$Remote/${RemoteBranch}:$(if ($hs) { $hs.Error } else { 'scanner returned nothing' })" }
                if ($hs.Findings -gt 0) { return "HELD-SECRET-IN-HISTORY:$Remote/${RemoteBranch}:$(@($hs.Rules) -join ',')" }
                & $withLease $RepoPath { $null = Invoke-KritGitHubChunkedPush -Path $RepoPath -Remote $Remote -Branch $RemoteBranch -LocalRef $LocalRef -ChunkSize $ChunkSize -Apply -Confirm:$false 6>$null }
                $ls = @(& git -C $RepoPath ls-remote $Remote "refs/heads/$RemoteBranch" 2>$null)
                $loc = @(& git -C $RepoPath rev-parse --verify --quiet "$LocalRef^{commit}" 2>$null)
                $remSha = if ($ls.Count -gt 0) { ($ls[0] -split '\s+')[0] } else { '' }
                if ($loc.Count -gt 0 -and $remSha -eq $loc[0].Trim()) { return "OK:$Remote/$RemoteBranch" }
                return "UNVERIFIED:$Remote/$RemoteBranch"
            } catch { return "FAILED:$Remote/${RemoteBranch}:$($_.Exception.Message)" }
        }
        $pushTag = {
            param([string]$RepoPath, [string]$Remote, [string]$Tag)
            try {
                if (& $overBudget $RepoPath) { return "HELD-BUDGET-EXCEEDED:$Remote/tag-${Tag}:repo used its ${PerRepoBudgetSeconds}s budget" }
                # a tag publishes every commit it reaches that the remote lacks: scan them first, fail closed
                $hs = $null
                try { $hs = & $HistoryScanner -RepoPath $RepoPath -LogOpts "refs/tags/$Tag --not --remotes=$Remote" }
                catch { return "HELD-SCANNER-FAILED:$Remote/tag-${Tag}:$($_.Exception.Message)" }
                if (-not $hs -or -not $hs.Ok) { return "HELD-SCANNER-FAILED:$Remote/tag-${Tag}:$(if ($hs) { $hs.Error } else { 'scanner returned nothing' })" }
                if ($hs.Findings -gt 0) { return "HELD-SECRET-IN-HISTORY:$Remote/tag-${Tag}:$(@($hs.Rules) -join ',')" }
                # never forced: a tag the remote already has at another object is refused by git itself
                $pushRc = & $withLease $RepoPath { $null = & git -C $RepoPath push $Remote "refs/tags/${Tag}:refs/tags/${Tag}" 2>&1; $LASTEXITCODE }
                $ls = @(& git -C $RepoPath ls-remote $Remote "refs/tags/$Tag" 2>$null)
                $loc = @(& git -C $RepoPath rev-parse --verify --quiet "refs/tags/$Tag" 2>$null)
                $remSha = if ($ls.Count -gt 0) { ($ls[0] -split '\s+')[0] } else { '' }
                if ($loc.Count -gt 0 -and $remSha -eq $loc[0].Trim()) { return "OK:$Remote/tag-$Tag" }
                return "UNVERIFIED:$Remote/tag-${Tag} (push exit $pushRc)"
            } catch { return "FAILED:$Remote/tag-${Tag}:$($_.Exception.Message)" }
        }
        foreach ($pass in @(1, 2, 3)) {
            foreach ($o in $atRisk) {
                if (-not $state.ContainsKey($o.RepoPath)) { continue }
                $st = $state[$o.RepoPath]
                if ($pass -eq 1 -and -not $o.RefsOwner) { continue }
                $pr = $probeByPath[$o.RepoPath]
                $hasDetached = ($pr -and $pr.Detached -and $pr.DetachedUnreachable -gt 0)
                if ($pass -eq 2 -and $pr -and $pr.Detached -and -not $hasDetached -and $pr.DetachedNotOnRemote -gt 0) {
                    # a local branch holds this HEAD: if pass 1 got it onto a remote there is nothing left to do here;
                    # if it did not (held, failed, no branch), name it and push the name. Failure to ask counts as "still off".
                    $stillOff = @(& git -C $o.RepoPath rev-list -n 1 HEAD --not --remotes 2>$null)
                    if ($LASTEXITCODE -ne 0 -or $stillOff.Count -gt 0) { $hasDetached = $true }
                }
                $facts = $null
                if ($repoFacts.ContainsKey($o.RepoPath)) { $facts = $repoFacts[$o.RepoPath] }
                $hasExtras = ($o.RefsOwner -and $facts -and $facts.Ok -and ($o.StashEntriesNotOnRemote + $o.DanglingCommits + $o.LocalTagsNotOnRemote + $o.DivergedTags) -gt 0)
                if ($pass -eq 3 -and -not $hasExtras) { continue }
                if ($pass -eq 2 -and -not ($pr -and ($pr.TrackedChanged + $pr.Untracked) -gt 0) -and -not $hasDetached -and -not $IncludeAzureDevOpsMirror) { continue }
                # No lease is taken for the visit: reads and secret scans run unleased, every write goes through $withLease.
                $stepsBefore = $st.Steps.Count
                $budgetSw[$o.RepoPath].Start()
                try {
                    if (& $overBudget $o.RepoPath) { $st.Steps.Add("BUDGET-EXCEEDED:pass-${pass}:repo used its ${PerRepoBudgetSeconds}s budget; remaining work for this repo is held"); $st.Held = $true; continue }

                    if ($pass -eq 1) {
                        # local branches with commits on no remote -- repo-level, owner row only
                        # A TERMINATING error inside the enumerator is not caught by -ErrorAction; 2026-10-08 one
                        # such error aborted the sweep for the whole estate. Fail this surface closed and carry on.
                        $cands = @()
                        try { $cands = @(Get-KritGitHubUnpushedBranches -Path $o.RepoPath -Remote $o.GitHubRemote -Fetch:$false -ErrorAction Stop) }
                        catch { $st.Steps.Add("UNPUSHED-ENUMERATION-FAILED:$($_.Exception.Message)"); $st.Failed = $true }
                        foreach ($c in $cands) {
                            if ($c.Recommendation -eq 'skip-diverged-remote-has-commits-not-local') { $st.Steps.Add("diverged-not-pushed:$($c.Branch)"); continue }
                            if ($c.Recommendation -eq 'skip-ref-vanished') { $st.Steps.Add("ref-vanished-not-pushed:$($c.Branch)"); continue }
                            if (-not $c.NeedsPush) { continue }
                            if ($c.Branch -match $pol.HeldBranchPattern) { $st.Steps.Add("HELD-BY-NAME:$($c.Branch)"); $st.Held = $true; continue }
                            if ($c.Branch -in @('main', 'master')) {
                                # never land local commits on the remote default branch without a PR
                                $rb = ('preserve/{0}/{1}/{2}-{3}' -f $machine, (Split-Path -Leaf $o.RepoPath), $stamp, $c.Branch) -replace '[^A-Za-z0-9._/-]', '-'
                                $res = & $pushRef $o.RepoPath $o.GitHubRemote $c.HeadSha $rb
                                $st.Steps.Add("push-$($c.Branch)-as-preserve:$res")
                                if ($res -like 'OK:*') { $st.Pushed.Add($rb); $st.Mirror.Add(@{ Ref = $c.HeadSha; Branch = $rb }) } elseif ($res -like 'HELD-*') { $st.Held = $true } else { $st.Failed = $true }
                            } else {
                                $res = & $pushRef $o.RepoPath $o.GitHubRemote "refs/heads/$($c.Branch)" $c.Branch
                                $st.Steps.Add("push-$($c.Branch):$res")
                                if ($res -like 'OK:*') { $st.Pushed.Add($c.Branch); $st.Mirror.Add(@{ Ref = "refs/heads/$($c.Branch)"; Branch = $c.Branch }) } elseif ($res -like 'HELD-*') { $st.Held = $true } else { $st.Failed = $true }
                            }
                        }
                    } elseif ($pass -eq 2) {
                        # uncommitted + untracked work -> preserve branch, pushed
                        if ($pr -and ($pr.TrackedChanged + $pr.Untracked) -gt 0) {
                            $snap = _KritEpsNewPreserveSnapshot -RepoPath $o.RepoPath -LaneId $LaneId -Machine $machine -Stamp $stamp -SecretScanner $SecretScanner -WithLease $withLease
                            $st.Steps.Add("snapshot:$($snap.Verdict)")
                            if (@($snap.Held).Count -gt 0) { $st.Steps.Add("held:$(@($snap.Held).Count)") }
                            if ($snap.Verdict -eq 'PRESERVED') {
                                $o.PreserveBranch = $snap.BranchName; $o.PreserveSha = $snap.Sha
                                $res = & $pushRef $o.RepoPath $o.GitHubRemote "refs/heads/$($snap.BranchName)" $snap.BranchName
                                $st.Steps.Add("push-preserve:$res")
                                if ($res -like 'OK:*') { $st.Pushed.Add($snap.BranchName); $st.Mirror.Add(@{ Ref = "refs/heads/$($snap.BranchName)"; Branch = $snap.BranchName }) } elseif ($res -like 'HELD-*') { $st.Held = $true } else { $st.Failed = $true }
                            } elseif ($snap.Verdict -like 'ERROR*' -or $snap.Verdict -like 'REFUSED*') { $st.Failed = $true }
                        }
                        # a detached HEAD whose commits are on no ref: name them (HEAD does not move) and push the name.
                        # When there was also dirty work, the snapshot above already carries these commits as its ancestry.
                        if ($hasDetached -and [string]::IsNullOrEmpty($o.PreserveBranch)) {
                            $det = & $withLease $o.RepoPath { _KritEpsNewDetachedRef -RepoPath $o.RepoPath -Machine $machine -Stamp $stamp }
                            $st.Steps.Add("detached-ref:$($det.Verdict)")
                            if ($det.Verdict -eq 'PRESERVED-DETACHED') {
                                $o.PreserveBranch = $det.BranchName; $o.PreserveSha = $det.Sha
                                $res = & $pushRef $o.RepoPath $o.GitHubRemote "refs/heads/$($det.BranchName)" $det.BranchName
                                $st.Steps.Add("push-detached:$res")
                                if ($res -like 'OK:*') { $st.Pushed.Add($det.BranchName); $st.Mirror.Add(@{ Ref = "refs/heads/$($det.BranchName)"; Branch = $det.BranchName }) } elseif ($res -like 'HELD-*') { $st.Held = $true } else { $st.Failed = $true }
                            } else { $st.Failed = $true }
                        }
                        # ADO mirror: the same refs, only if a mirror remote exists
                        if ($IncludeAzureDevOpsMirror) {
                            if (-not $o.HasAdoRemote) { $st.Steps.Add('ADO-MIRROR-NOT-CONFIGURED') }
                            else {
                                foreach ($m in $st.Mirror) {
                                    $res = & $pushRef $o.RepoPath $o.AdoRemote $m.Ref $m.Branch
                                    $st.Steps.Add("ado:$res")
                                    if ($res -like 'HELD-*') { $st.Held = $true } elseif ($res -notlike 'OK:*') { $st.Failed = $true }
                                }
                            }
                        }
                    }
                    if ($pass -eq 3) {
                        # stashes, dangling commits, tags -- never popped, never forced, every ref secret-scanned first
                        $mStart = $st.Mirror.Count
                        $mach = _KritEpsSafeSegment $machine
                        $leaf = _KritEpsSafeSegment (Split-Path -Leaf $o.RepoPath)
                        foreach ($se in @($facts.StashEntries | Where-Object { -not $_.OnRemote })) {
                            $prefix = "preserve/$mach/$leaf/stash-$($se.Index)-"
                            $rb = _KritEpsFindLocalBranchAt -RepoPath $o.RepoPath -Prefix "$prefix*" -Sha $se.Sha
                            if (-not $rb) {
                                $nr = & $withLease $o.RepoPath { _KritEpsNewNamedRef -RepoPath $o.RepoPath -Name "$prefix$stamp" -Sha $se.Sha }
                                if ($nr.Verdict -notin @('CREATED', 'REUSED')) { $st.Steps.Add("stash-$($se.Index)-ref:$($nr.Verdict)"); $st.Failed = $true; continue }
                                $rb = $nr.Name
                            }
                            $res = & $pushRef $o.RepoPath $o.GitHubRemote "refs/heads/$rb" $rb
                            $st.Steps.Add("push-stash-$($se.Index):$res")
                            if ($res -like 'OK:*') { $st.Pushed.Add($rb); $st.Mirror.Add(@{ Ref = "refs/heads/$rb"; Branch = $rb }) } elseif ($res -like 'HELD-*') { $st.Held = $true } else { $st.Failed = $true }
                        }
                        foreach ($dt in @($facts.DanglingTips)) {
                            $short = $dt.Sha.Substring(0, 8)
                            $nr = & $withLease $o.RepoPath { _KritEpsNewNamedRef -RepoPath $o.RepoPath -Name "preserve/$mach/$leaf/dangling-$short" -Sha $dt.Sha }
                            if ($nr.Verdict -notin @('CREATED', 'REUSED')) { $st.Steps.Add("dangling-${short}-ref:$($nr.Verdict)"); $st.Failed = $true; continue }
                            $res = & $pushRef $o.RepoPath $o.GitHubRemote "refs/heads/$($nr.Name)" $nr.Name
                            $st.Steps.Add("push-dangling-${short}:$res")
                            if ($res -like 'OK:*') { $st.Pushed.Add($nr.Name); $st.Mirror.Add(@{ Ref = "refs/heads/$($nr.Name)"; Branch = $nr.Name }) } elseif ($res -like 'HELD-*') { $st.Held = $true } else { $st.Failed = $true }
                        }
                        foreach ($tg in @($facts.TagsNotOnRemote)) {
                            $res = & $pushTag $o.RepoPath $o.GitHubRemote $tg
                            $st.Steps.Add("tag-${tg}:$res")
                            if ($res -like 'OK:*') { $st.Pushed.Add("tag:$tg") } elseif ($res -like 'HELD-*') { $st.Held = $true } else { $st.Failed = $true }
                        }
                        foreach ($dv in @($facts.DivergedTags)) { $st.Steps.Add("DIVERGED-TAG:$dv"); $st.Held = $true }
                        if ($IncludeAzureDevOpsMirror -and $st.Mirror.Count -gt $mStart) {
                            if (-not $o.HasAdoRemote) { $st.Steps.Add('ADO-MIRROR-NOT-CONFIGURED') }
                            else {
                                foreach ($m in @($st.Mirror.GetRange($mStart, $st.Mirror.Count - $mStart))) {
                                    $res = & $pushRef $o.RepoPath $o.AdoRemote $m.Ref $m.Branch
                                    $st.Steps.Add("ado:$res")
                                    if ($res -like 'HELD-*') { $st.Held = $true } elseif ($res -notlike 'OK:*') { $st.Failed = $true }
                                }
                            }
                        }
                    }
                } catch {
                    # e.g. the repo lease could not be taken for a write: fail THIS repo's visit closed and carry on with the estate
                    $st.Steps.Add("ERROR-PASS-${pass}:$($_.Exception.Message)"); $st.Failed = $true
                } finally {
                    $budgetSw[$o.RepoPath].Stop()
                    & $emit @{ event = 'visit'; pass = $pass; repo = $o.RepoPath; elapsedRepoSeconds = [math]::Round($budgetSw[$o.RepoPath].Elapsed.TotalSeconds, 1); steps = @($st.Steps | Select-Object -Skip $stepsBefore); failed = [bool]$st.Failed; held = [bool]$st.Held }
                }
            }
        }
        foreach ($o in $atRisk) {
            if (-not $state.ContainsKey($o.RepoPath)) { continue }
            $st = $state[$o.RepoPath]
            $o.PushedRefs = ($st.Pushed -join ';')
            $o.ApplyDetail = ($st.Steps -join ' | ')
            $o.ApplyAction = if ($st.Failed) { 'PARTIAL-OR-FAILED' } elseif ($st.Held) { 'APPLIED-WITH-HELD' } elseif ($st.Steps.Count -eq 0) { 'NOTHING-TO-DO' } else { 'APPLIED' }
            & $emit @{ event = 'repo-final'; repo = $o.RepoPath; applyAction = $o.ApplyAction; pushedRefs = $o.PushedRefs; seconds = [math]::Round($budgetSw[$o.RepoPath].Elapsed.TotalSeconds, 1) }
        }
    }

    # ---------------------------------------------------------------- summary + receipts
    $all = @($out.ToArray())
    $summary = [ordered]@{
        Machine = $machine; Mode = $(if ($Apply) { 'APPLY' } else { 'DRY-RUN' }); StartedUtc = $started.ToString('o')
        FinishedUtc = ''; Roots = @($Root); ThrottleLimit = $ThrottleLimit; LaneId = $LaneId
        RootNotes = $rootNotes.ToArray(); Total = $all.Count
        Verdicts = @($all | Group-Object Verdict | Sort-Object Name | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join '; '
        AtRiskCheckouts = @($all | Where-Object { $_.Verdict -eq 'AT-RISK' -and $_.Kind -eq 'CHECKOUT' }).Count
        AtRiskWorktrees = @($all | Where-Object { $_.Verdict -eq 'AT-RISK' -and $_.Kind -eq 'WORKTREE' }).Count
        UnpushedCommits = [int](& $sumOf @($all | Where-Object { $_.RefsOwner -and $_.Verdict -in @('AT-RISK', 'SKIPPED-FOREIGN-LEASE') }) { param($x) $x.UnpushedCommits })
        StashEntriesNotOnRemote = [int](& $sumOf @($all | Where-Object { $_.RefsOwner -and $_.Verdict -in @('AT-RISK', 'SKIPPED-FOREIGN-LEASE') }) { param($x) $x.StashEntriesNotOnRemote })
        LocalTagsNotOnRemote = [int](& $sumOf @($all | Where-Object { $_.RefsOwner -and $_.Verdict -in @('AT-RISK', 'SKIPPED-FOREIGN-LEASE') }) { param($x) $x.LocalTagsNotOnRemote })
        DivergedTags = [int](& $sumOf @($all | Where-Object { $_.RefsOwner -and $_.Verdict -in @('AT-RISK', 'SKIPPED-FOREIGN-LEASE') }) { param($x) $x.DivergedTags })
        DanglingCommits = [int](& $sumOf @($all | Where-Object { $_.RefsOwner -and $_.Verdict -in @('AT-RISK', 'SKIPPED-FOREIGN-LEASE') }) { param($x) $x.DanglingCommits })
        UncommittedFiles = [int](& $sumOf @($all | Where-Object { $_.Verdict -in @('AT-RISK', 'SKIPPED-FOREIGN-LEASE') }) { param($x) $x.TrackedChanged + $x.Untracked })
        ReposWithNoGitHubRemote = @($all | Where-Object { $_.RefsOwner -and -not $_.HasGitHubRemote }).Count
        ReposWithAdoMirror = @($all | Where-Object { $_.RefsOwner -and $_.HasAdoRemote }).Count
        CandidateAssetCount = $assetRows.Count
        CandidateAssetMB = [math]::Round((& $sumOf $assetRows.ToArray() { param($x) $x.SizeBytes }) / 1MB, 1)
        Applied = @($all | Where-Object { $_.ApplyAction -eq 'APPLIED' }).Count
        BlockedActions = @($all | Where-Object { $_.ActionsState -like 'BLOCKED-ACTIONS*' }).Count
        Receipts = [ordered]@{}
    }
    $flat =$all | Select-Object -Property * -ExcludeProperty Files
    $flat | Export-Csv -LiteralPath "$base.csv" -NoTypeInformation -Encoding utf8
    $assetRows.ToArray() | Sort-Object SizeBytes -Descending | Export-Csv -LiteralPath "$base-assets.csv" -NoTypeInformation -Encoding utf8
    $summary.FinishedUtc = [datetime]::UtcNow.ToString('o')
    $summary.Receipts = [ordered]@{ Csv = "$base.csv"; AssetsCsv = "$base-assets.csv"; Json = "$base.json"; Markdown = "$base.md"; Jsonl = $jsonlPath }
    [pscustomobject]@{ Summary = [pscustomobject]$summary; Rows = $all; Assets = $assetRows.ToArray() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$base.json" -Encoding utf8

    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("REGENERATE: Invoke-KritEstatePushSweep -Root $(@($Root) -join ',') -ThrottleLimit $ThrottleLimit -ReceiptPath '$ReceiptPath'$(if ($Apply) { ' -Apply' })")
    $md.Add(''); $md.Add("# Estate push sweep -- $($summary.Mode) -- $machine -- $stamp (Melbourne local)"); $md.Add('')
    $md.Add("Roots: $(@($Root) -join ', ') | throttle $ThrottleLimit | lane $LaneId | started $($summary.StartedUtc) UTC | finished $($summary.FinishedUtc) UTC"); $md.Add('')
    $md.Add('## Headline'); $md.Add('')
    $md.Add("- Surfaces examined: $($summary.Total) ($($summary.Verdicts))")
    $md.Add("- AT-RISK checkouts: $($summary.AtRiskCheckouts); AT-RISK worktrees: $($summary.AtRiskWorktrees)")
    $md.Add("- Commits on no remote (counted once per repo, via its primary checkout): $($summary.UnpushedCommits)")
    $md.Add("- Stash entries on no remote: $($summary.StashEntriesNotOnRemote); local tags the remote lacks: $($summary.LocalTagsNotOnRemote); diverged tags (held): $($summary.DivergedTags); dangling commits: $($summary.DanglingCommits)")
    $md.Add("- Uncommitted + untracked non-ignored files in AT-RISK/leased surfaces: $($summary.UncommittedFiles)")
    $md.Add("- Repos with no GitHub remote: $($summary.ReposWithNoGitHubRemote); repos with an ADO mirror remote: $($summary.ReposWithAdoMirror)")
    $md.Add("- CANDIDATE-UNTRACKED-ASSETS: $($summary.CandidateAssetCount) item(s), $($summary.CandidateAssetMB) MB (NOT pushed automatically -- operator decision)")
    if ($Apply) { $md.Add("- Applied: $($summary.Applied) surface(s); BLOCKED-ACTIONS: $($summary.BlockedActions)") }
    foreach ($n in $summary.RootNotes) { $md.Add("- Note: $n") }
    $md.Add(''); $md.Add('## AT-RISK surfaces'); $md.Add('')
    $md.Add('| Surface | Kind | Branch | Dirty | Untracked | Unpushed (repo) | Branches no upstream | GitHub | ADO | Actions | Applied |'); $md.Add('|---|---|---|---:|---:|---:|---:|---|---|---|---|')
    foreach ($a in ($all | Where-Object Verdict -eq 'AT-RISK' | Sort-Object RepoPath)) {
        $md.Add("| $($a.RepoPath) | $($a.Kind) | $($a.Branch) | $($a.TrackedChanged) | $($a.Untracked) | $($a.UnpushedCommits)$(if (-not $a.RefsOwner -and $a.RefsOwnedBy) { ' (refs: ' + (Split-Path -Leaf $a.RefsOwnedBy) + ')' }) | $($a.NoUpstreamBranches) | $(if ($a.HasGitHubRemote) { $a.GitHubRemote } else { 'NONE' }) | $($a.AdoMirror) | $($a.ActionsState) | $($a.ApplyAction) |")
    }
    $md.Add(''); $md.Add('## Skipped (not touched)'); $md.Add('')
    foreach ($s in ($all | Where-Object { $_.Verdict -like 'SKIPPED*' -or $_.Verdict -like 'EXCLUDED*' -or $_.Verdict -eq 'UNKNOWN' } | Sort-Object Verdict, RepoPath)) {
        $md.Add("- $($s.Verdict): $($s.RepoPath)$(if ($s.LeaseHolder) { ' (lease held by ' + $s.LeaseHolder + ')' })$(if ($s.Reasons) { ' -- ' + $s.Reasons })$(if ($s.Error) { ' -- ' + $s.Error })")
    }
    $md.Add(''); $md.Add('## CANDIDATE-UNTRACKED-ASSETS (gitignored, source-like, >= 1 MB; never auto-pushed)'); $md.Add('')
    $md.Add('| Size MB | Surface | Path | Kind | Source-like files | Extensions |'); $md.Add('|---:|---|---|---|---:|---|')
    foreach ($a in ($assetRows | Sort-Object SizeBytes -Descending)) {
        $md.Add("| $($a.SizeMB) | $($a.RepoPath) | $($a.RelativePath) | $($a.AssetKind)$(if ($a.Truncated) { ' (size truncated)' }) | $($a.SourceLikeFiles) | $($a.Extensions) |")
    }
    $md.Add(''); $md.Add('## Azure DevOps mirror'); $md.Add('')
    $md.Add($(if ($summary.ReposWithAdoMirror -eq 0) { 'No scanned repository has an Azure DevOps remote, so -IncludeAzureDevOpsMirror has nothing to push to. Needed from the operator: the target org/project and one ADO repository per GitHub repo (this cmdlet never creates ADO repositories and makes no Azure Resource Manager, storage or subscription call), then `git remote add ado <url>` per repo.' } else { "$($summary.ReposWithAdoMirror) repo(s) have an ADO mirror remote; see the AdoMirror column." }))
    $md.Add(''); $md.Add('## Hard-coded exclusions'); $md.Add('')
    $md.Add("Paths containing Secrets (repo never opened); files over 95 MB; node_modules, bin, obj, .venv; transient gate worktrees; repos with a live foreign lease; gitignored content is reported, never pushed. Actions gate: Test-KritGitHubPushPermitted (override only if the caller set KRIT_ACTIONS_FREEZE_OVERRIDE=1).")
    Set-Content -LiteralPath "$base.md" -Value ($md -join "`n") -Encoding utf8
    & $log "estate push sweep done: $($summary.Total) surfaces; at-risk $($summary.AtRiskCheckouts + $summary.AtRiskWorktrees); receipt $base.md"
    & $emit @{ event = 'done'; total = $summary.Total; verdicts = $summary.Verdicts; applied = $summary.Applied; receipt = "$base.md" }

    if ($PassThruSummary) { return [pscustomobject]@{ Summary = [pscustomobject]$summary; Rows = $all; Assets = $assetRows.ToArray(); Receipts = $summary.Receipts } }
    return $all
}
