$script:MonitorVersion = '0.1.0'

function Get-RepoRoot { Split-Path -Parent $PSScriptRoot }

function Expand-MonitorPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ([IO.Path]::IsPathRooted($expanded)) { return $expanded }
    Join-Path (Get-RepoRoot) $expanded
}

function Get-MonitorConfig {
    param([string]$ConfigPath)
    $root = Get-RepoRoot
    if (-not $ConfigPath) { $ConfigPath = Join-Path $root 'config\config.json' }
    $example = Join-Path $root 'config\config.example.json'
    $source = if (Test-Path $ConfigPath) { $ConfigPath } else { $example }
    $cfg = Get-Content -Raw $source | ConvertFrom-Json
    $cfg.codexHome = Expand-MonitorPath $cfg.codexHome
    $cfg.dataRoot = Expand-MonitorPath $cfg.dataRoot
    $cfg | Add-Member -NotePropertyName repoRoot -NotePropertyValue $root -Force
    $cfg
}

function Initialize-MonitorStorage {
    param($Config)
    foreach ($rel in @('raw','sessions','reports','state')) {
        New-Item -ItemType Directory -Force (Join-Path $Config.dataRoot $rel) | Out-Null
    }
}

function Read-MonitorState {
    param($Config)
    $path = Join-Path $Config.dataRoot 'state\monitor-state.json'
    if (Test-Path $path) {
        try { return Get-Content -Raw $path | ConvertFrom-Json -AsHashtable } catch {}
    }
    @{ files = @{}; startedAt = (Get-Date).ToString('o') }
}

function Write-MonitorState {
    param($Config, [hashtable]$State)
    $path = Join-Path $Config.dataRoot 'state\monitor-state.json'
    $tmp = "$path.tmp"
    $State | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $tmp
    Move-Item -Force $tmp $path
}

function Get-SessionFiles {
    param($Config)
    $root = Join-Path $Config.codexHome 'sessions'
    if (-not (Test-Path $root)) { return @() }
    $files = Get-ChildItem -Path $root -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue
    if ($Config.PSObject.Properties.Name -contains 'maxSessionFileAgeDays' -and [int]$Config.maxSessionFileAgeDays -gt 0) {
        $cutoff = (Get-Date).AddDays(-[int]$Config.maxSessionFileAgeDays)
        $files = $files | Where-Object { $_.LastWriteTime -ge $cutoff }
    }
    $files = $files | Sort-Object LastWriteTime -Descending
    if ($Config.PSObject.Properties.Name -contains 'maxSessionFiles' -and [int]$Config.maxSessionFiles -gt 0) {
        $files = $files | Select-Object -First ([int]$Config.maxSessionFiles)
    }
    $files
}

function Get-SessionIdFromPath {
    param([string]$Path)
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    if ($name -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { return $Matches[1] }
    $name
}

function Estimate-TextTokens {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return 0 }
    [int][Math]::Ceiling($Text.Length / 4.0)
}

function Test-Truncated {
    param([AllowNull()][string]$Text)
    if (-not $Text) { return $false }
    $Text -match '(?i)\btruncated\b|omitted|additional lines'
}

function Redact-CommandName {
    param([AllowNull()][string]$Arguments)
    if (-not $Arguments) { return $null }
    $s = $Arguments
    try {
        $obj = $Arguments | ConvertFrom-Json -ErrorAction Stop
        foreach ($k in @('cmd','command')) {
            if ($obj.PSObject.Properties.Name -contains $k) { $s = [string]$obj.$k; break }
        }
    } catch {}
    $s = $s -replace '(?i)(api[_-]?key|token|password|secret|authorization|cookie)=\S+', '$1=<redacted>'
    $first = ($s -split '\s+')[0]
    if ($first.Length -gt 80) { return $first.Substring(0,80) }
    $first
}

function Get-ConfigSnapshot {
    param($Config)
    $snap = [ordered]@{ monitorVersion = $script:MonitorVersion }
    foreach ($pair in @(@('agents',(Join-Path $Config.codexHome 'AGENTS.md')), @('hooks',(Join-Path $Config.codexHome 'hooks.json')))) {
        if (Test-Path $pair[1]) {
            $h = Get-FileHash -Algorithm SHA256 $pair[1]
            $item = Get-Item $pair[1]
            $snap["$($pair[0])Hash"] = $h.Hash.ToLowerInvariant()
            $snap["$($pair[0])Bytes"] = $item.Length
        }
    }
    $snap
}

function Convert-CodexRecordToMetric {
    param($Record, [string]$FilePath, $Config)
    $sid = Get-SessionIdFromPath $FilePath
    $ts = $Record.timestamp
    $p = $Record.payload
    if (-not $p) { return @() }
    $out = New-Object System.Collections.Generic.List[object]

    if ($Record.type -eq 'session_meta') {
        $sid = if ($p.session_id) { $p.session_id } elseif ($p.id) { $p.id } else { $sid }
        $out.Add([ordered]@{ timestamp=$ts; sessionId=$sid; event='session_meta'; cwd=$p.cwd; cliVersion=$p.cli_version; source=$p.source; modelProvider=$p.model_provider; monitorVersion=$script:MonitorVersion })
    } elseif ($Record.type -eq 'event_msg' -and $p.type -eq 'token_count') {
        $info = $p.info
        $out.Add([ordered]@{ timestamp=$ts; sessionId=$sid; event='token_count'; inputTokensExact=$info.input_tokens; cachedInputTokensExact=$info.cached_input_tokens; outputTokensExact=$info.output_tokens; totalTokensExact=$info.total_tokens })
    } elseif ($Record.type -eq 'event_msg' -and $p.type -eq 'task_started') {
        $out.Add([ordered]@{ timestamp=$ts; sessionId=$sid; event='task_started'; turnId=$p.turn_id; modelContextWindow=$p.model_context_window; collaborationMode=$p.collaboration_mode_kind })
    } elseif ($Record.type -eq 'turn_context') {
        $out.Add([ordered]@{ timestamp=$ts; sessionId=$sid; event='turn_context'; turnId=$p.turn_id; cwd=$p.cwd; currentDate=$p.current_date; timezone=$p.timezone; approvalPolicy=$p.approval_policy })
    } elseif ($Record.type -eq 'response_item') {
        if ($p.type -eq 'function_call') {
            $out.Add([ordered]@{ timestamp=$ts; sessionId=$sid; event='tool_call'; tool=$p.name; callId=$p.call_id; commandName=(Redact-CommandName $p.arguments) })
        } elseif ($p.type -eq 'function_call_output') {
            $text = [string]$p.output
            $chars = $text.Length
            $evt = [ordered]@{ timestamp=$ts; sessionId=$sid; event='tool_result'; callId=$p.call_id; outputCharacters=$chars; outputBytes=([Text.Encoding]::UTF8.GetByteCount($text)); estimatedOutputTokens=(Estimate-TextTokens $text); truncated=(Test-Truncated $text) }
            if ($chars -ge [int]$Config.veryLargeToolOutputChars) { $evt.incident='very_large_tool_output' }
            elseif ($chars -ge [int]$Config.largeToolOutputChars) { $evt.incident='large_tool_output' }
            $out.Add($evt)
        } elseif ($p.type -eq 'message') {
            $chars = 0
            if ($p.content) { $chars = ([string]($p.content | ConvertTo-Json -Compress -Depth 8)).Length }
            $out.Add([ordered]@{ timestamp=$ts; sessionId=$sid; event='message_metadata'; role=$p.role; characters=$chars; estimatedTokens=(Estimate-TextTokens ('x' * $chars)) })
        }
    } elseif ($Record.type -eq 'event_msg' -and $p.type -eq 'item_completed') {
        $dur = $null
        if ($p.started_at_ms -and $p.completed_at_ms) { $dur = [int64]$p.completed_at_ms - [int64]$p.started_at_ms }
        if ($p.item -and $p.item.type -eq 'function_call_output') {
            $out.Add([ordered]@{ timestamp=$ts; sessionId=$sid; event='tool_completed'; callId=$p.item.call_id; durationMs=$dur })
        }
    }
    $out.ToArray()
}

function Read-NewJsonLines {
    param([string]$Path, [hashtable]$FileState)
    $offset = [int64]($FileState.offset ?? 0)
    $partial = [string]($FileState.partial ?? '')
    $len = (Get-Item $Path).Length
    if ($len -lt $offset) { $offset = 0; $partial = '' }
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $fs.Seek($offset, [IO.SeekOrigin]::Begin) | Out-Null
        $buf = New-Object byte[] ($len - $offset)
        $read = $fs.Read($buf, 0, $buf.Length)
        $newOffset = $offset + $read
    } finally { $fs.Close() }
    $text = $partial + [Text.Encoding]::UTF8.GetString($buf, 0, $read)
    $lines = $text.Split([string[]]@("`n"), [StringSplitOptions]::None)
    if ($offset -gt 0 -and [string]::IsNullOrEmpty($partial) -and $lines.Count -gt 0) {
        $lines = if ($lines.Count -gt 1) { $lines[1..($lines.Count - 1)] } else { @('') }
    }
    $complete = @()
    if ($lines.Count -gt 1) { $complete = $lines[0..($lines.Count-2)] }
    $newPartial = $lines[-1]
    if ($text.EndsWith("`n")) { $newPartial = '' }
    @{ lines = $complete; offset = $newOffset; partial = $newPartial }
}

function Write-RawMetric {
    param($Config, [hashtable]$Metric)
    $date = if ($Metric.timestamp) { ([datetime]$Metric.timestamp).ToString('yyyy-MM-dd') } else { (Get-Date).ToString('yyyy-MM-dd') }
    $path = Join-Path $Config.dataRoot "raw\$date.jsonl"
    ($Metric | ConvertTo-Json -Compress -Depth 12) | Add-Content -Encoding UTF8 $path
}

function Update-SessionSummary {
    param($Config, [hashtable[]]$Metrics)
    $snapshot = Get-ConfigSnapshot $Config
    foreach ($group in ($Metrics | Group-Object sessionId)) {
        $sid = $group.Name
        if (-not $sid) { continue }
        $path = Join-Path $Config.dataRoot "sessions\$sid.json"
        $s = if (Test-Path $path) { Get-Content -Raw $path | ConvertFrom-Json -AsHashtable } else { @{ sessionId=$sid; firstSeen=$null; lastSeen=$null; tokenSamples=@(); toolCalls=@{}; largestToolOutputs=@(); toolCallCount=0; toolResultCount=0; truncatedToolOutputs=0; suspectedCompactions=@(); userMessageCount=0; userMessageCharacters=0; estimatedUserMessageTokens=0; incidents=@() } }
        foreach ($m in $group.Group) {
            if (-not $s.firstSeen) { $s.firstSeen = $m.timestamp }
            $s.lastSeen = $m.timestamp
            $s.configSnapshot = $snapshot
            switch ($m.event) {
                'session_meta' { $s.cwd=$m.cwd; $s.cliVersion=$m.cliVersion; $s.monitorVersion=$m.monitorVersion }
                'task_started' { $s.modelContextWindow=$m.modelContextWindow; $s.collaborationMode=$m.collaborationMode }
                'token_count' {
                    $prev = if ($s.tokenSamples.Count) { $s.tokenSamples[-1] } else { $null }
                    $sample = @{ timestamp=$m.timestamp; inputTokensExact=$m.inputTokensExact; cachedInputTokensExact=$m.cachedInputTokensExact; outputTokensExact=$m.outputTokensExact; totalTokensExact=$m.totalTokensExact }
                    $s.tokenSamples += $sample
                    if ($m.inputTokensExact -ne $null) {
                        if ($s.firstInputTokensExact -eq $null) { $s.firstInputTokensExact = $m.inputTokensExact }
                        $s.latestInputTokensExact = $m.inputTokensExact
                        if ($s.peakInputTokensExact -eq $null -or $m.inputTokensExact -gt $s.peakInputTokensExact) { $s.peakInputTokensExact = $m.inputTokensExact }
                        if ($prev -and $prev.inputTokensExact -and $m.inputTokensExact -lt ($prev.inputTokensExact * 0.7)) {
                            $s.suspectedCompactions += @{ timestamp=$m.timestamp; beforeInputTokensExact=$prev.inputTokensExact; afterInputTokensExact=$m.inputTokensExact; reductionExact=($prev.inputTokensExact - $m.inputTokensExact) }
                        }
                    }
                }
                'tool_call' {
                    $s.toolCallCount++
                    if ($m.callId) { $s.toolCalls[$m.callId] = @{ tool=$m.tool; commandName=$m.commandName; timestamp=$m.timestamp } }
                }
                'tool_result' {
                    $s.toolResultCount++
                    if ($m.truncated) { $s.truncatedToolOutputs++ }
                    $item = @{ timestamp=$m.timestamp; callId=$m.callId; outputCharacters=$m.outputCharacters; outputBytes=$m.outputBytes; estimatedOutputTokens=$m.estimatedOutputTokens; truncated=$m.truncated }
                    if ($m.callId -and $s.toolCalls.ContainsKey($m.callId)) { $item.tool=$s.toolCalls[$m.callId].tool; $item.commandName=$s.toolCalls[$m.callId].commandName }
                    $s.largestToolOutputs += $item
                    $s.largestToolOutputs = @($s.largestToolOutputs | Sort-Object outputCharacters -Descending | Select-Object -First 20)
                    if ($m.incident) { $s.incidents += @{ timestamp=$m.timestamp; type=$m.incident; outputCharacters=$m.outputCharacters; callId=$m.callId } }
                }
                'message_metadata' {
                    if ($m.role -eq 'user') { $s.userMessageCount++; $s.userMessageCharacters += [int]$m.characters; $s.estimatedUserMessageTokens += [int]$m.estimatedTokens }
                }
            }
        }
        $tmp = "$path.tmp"
        $s | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $tmp
        Move-Item -Force $tmp $path
    }
}

function Invoke-MonitorScan {
    param($Config, [hashtable]$State)
    Initialize-MonitorStorage $Config
    $allMetrics = New-Object System.Collections.Generic.List[hashtable]
    foreach ($file in Get-SessionFiles $Config) {
        $key = $file.FullName
        if (-not $State.files.ContainsKey($key)) {
            $initialBytes = if ($Config.PSObject.Properties.Name -contains 'initialReadBytes') { [int64]$Config.initialReadBytes } else { 1048576 }
            $startOffset = [Math]::Max(0, [int64]$file.Length - $initialBytes)
            $State.files[$key] = @{ offset = $startOffset; partial = '' }
        }
        $chunk = Read-NewJsonLines $key $State.files[$key]
        $State.files[$key].offset = $chunk.offset
        $State.files[$key].partial = $chunk.partial
        foreach ($line in $chunk.lines) {
            $line = $line.TrimEnd("`r")
            if (-not $line) { continue }
            try {
                $record = $line | ConvertFrom-Json -ErrorAction Stop
                foreach ($metric in Convert-CodexRecordToMetric $record $key $Config) {
                    $h = @{}
                    foreach ($prop in $metric.GetEnumerator()) { $h[$prop.Key] = $prop.Value }
                    Write-RawMetric $Config $h
                    $allMetrics.Add($h)
                }
            } catch {
                Write-RawMetric $Config @{ timestamp=(Get-Date).ToString('o'); sessionId=(Get-SessionIdFromPath $key); event='malformed_line'; file=$key }
            }
        }
    }
    if ($allMetrics.Count) { Update-SessionSummary $Config @($allMetrics) }
    $State.lastScan = (Get-Date).ToString('o')
    $State.lastMetricCount = $allMetrics.Count
    Write-MonitorState $Config $State
    $allMetrics.Count
}

function Start-MonitorLoop {
    param([string]$ConfigPath)
    $cfg = Get-MonitorConfig $ConfigPath
    Initialize-MonitorStorage $cfg
    $state = Read-MonitorState $cfg
    $state.pid = $PID
    $state.startedAt = (Get-Date).ToString('o')
    Write-MonitorState $cfg $state
    while ($true) {
        try { Invoke-MonitorScan $cfg $state | Out-Null } catch { $_ | Out-String | Add-Content (Join-Path $cfg.dataRoot 'state\monitor-errors.log') }
        Start-Sleep -Seconds ([int]$cfg.pollIntervalSeconds)
    }
}

function Get-SessionSummaries {
    param($Config)
    $dir = Join-Path $Config.dataRoot 'sessions'
    if (-not (Test-Path $dir)) { return @() }
    Get-ChildItem $dir -Filter '*.json' | ForEach-Object { try { Get-Content -Raw $_.FullName | ConvertFrom-Json -AsHashtable } catch {} }
}

function New-MonitorReport {
    param($Config, [switch]$Latest, [int]$Last, [string]$From, [string]$To, [switch]$Json)
    $sessions = @(Get-SessionSummaries $Config | Sort-Object lastSeen -Descending)
    if ($Latest) { $sessions = @($sessions | Select-Object -First 1) } elseif ($Last -gt 0) { $sessions = @($sessions | Select-Object -First $Last) }
    if ($From) { $sessions = @($sessions | Where-Object { [datetime]$_.lastSeen -ge [datetime]$From }) }
    if ($To) { $sessions = @($sessions | Where-Object { [datetime]$_.lastSeen -le ([datetime]$To).Date.AddDays(1).AddTicks(-1) }) }
    if ($Json) { return ($sessions | ConvertTo-Json -Depth 20) }
    $toolCalls = ($sessions | Measure-Object toolCallCount -Sum).Sum
    $trunc = ($sessions | Measure-Object truncatedToolOutputs -Sum).Sum
    $peaks = @($sessions | Where-Object { $_.peakInputTokensExact -ne $null } | ForEach-Object { [int]$_.peakInputTokensExact })
    $avgPeak = if ($peaks.Count) { [int](($peaks | Measure-Object -Average).Average) } else { $null }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Codex Context Monitor Report'); $lines.Add('')
    $lines.Add("Generated: $(Get-Date -Format o)"); $lines.Add("Sessions: $($sessions.Count)"); $lines.Add('')
    $lines.Add('## Summary'); $lines.Add("Tool calls: $toolCalls"); $lines.Add("Truncated tool outputs: $trunc")
    if ($avgPeak) { $lines.Add("Average peak input tokens exact: $avgPeak") }
    $lines.Add(''); $lines.Add('## Sessions')
    foreach ($s in $sessions) {
        $growth = if ($s.firstInputTokensExact -ne $null -and $s.latestInputTokensExact -ne $null) { [int]$s.latestInputTokensExact - [int]$s.firstInputTokensExact } else { $null }
        $lines.Add("- $($s.sessionId): first=$($s.firstInputTokensExact), latest=$($s.latestInputTokensExact), peak=$($s.peakInputTokensExact), growth=$growth, tools=$($s.toolCallCount), trunc=$($s.truncatedToolOutputs)")
    }
    $lines.Add(''); $lines.Add('## Largest Tool Outputs')
    $largest = @($sessions | ForEach-Object { $_.largestToolOutputs } | Sort-Object outputCharacters -Descending | Select-Object -First 10)
    $i = 1
    foreach ($x in $largest) { $lines.Add("$i. $($x.tool ?? 'tool') $($x.commandName ?? '') chars=$($x.outputCharacters) estimatedTokens=$($x.estimatedOutputTokens) truncated=$($x.truncated)"); $i++ }
    $lines.Add(''); $lines.Add('## Notes')
    $lines.Add('- Exact token fields come only from Codex `token_count` events.')
    $lines.Add('- Tool/user token fields are estimates from character count heuristic unless marked exact.')
    $text = ($lines -join [Environment]::NewLine)
    $text | Set-Content -Encoding UTF8 (Join-Path $Config.dataRoot 'reports\latest.md')
    $text
}

function New-ComparisonReport {
    param($Config, [string]$Before, [string]$After)
    function Select-Range($range, $all) {
        $parts = $range -split ',', 2
        $from = [datetime]$parts[0]; $to = ([datetime]$parts[1]).Date.AddDays(1).AddTicks(-1)
        @($all | Where-Object { $_.lastSeen -and [datetime]$_.lastSeen -ge $from -and [datetime]$_.lastSeen -le $to })
    }
    function Stats($items) {
        $peaks = @($items | Where-Object { $_.peakInputTokensExact -ne $null } | ForEach-Object { [double]$_.peakInputTokensExact })
        [ordered]@{
            sessions=$items.Count
            avgPeakInputTokensExact= if($peaks.Count){ [int](($peaks | Measure-Object -Average).Average) } else { $null }
            toolCalls=($items | Measure-Object toolCallCount -Sum).Sum
            truncations=($items | Measure-Object truncatedToolOutputs -Sum).Sum
            estimatedToolOutputTokens=($items | ForEach-Object { $_.largestToolOutputs } | Measure-Object estimatedOutputTokens -Sum).Sum
        }
    }
    $all = @(Get-SessionSummaries $Config)
    $b = Stats (Select-Range $Before $all); $a = Stats (Select-Range $After $all)
    $lines = @('# Codex Context Monitor Comparison','',"Before: $Before","After: $After",'','| Metric | Before | After | Change |','|---|---:|---:|---:|')
    foreach ($k in $b.Keys) {
        $change = ''
        if ($b[$k] -and $a[$k] -ne $null) { $change = '{0:P1}' -f (($a[$k]-$b[$k])/[double]$b[$k]) }
        $lines += "| $k | $($b[$k]) | $($a[$k]) | $change |"
    }
    $lines -join [Environment]::NewLine
}

Export-ModuleMember -Function *
