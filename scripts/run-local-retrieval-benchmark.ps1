param(
  [ValidateSet('baseline', 'latest')]
  [string]$Label = 'latest',
  [string]$SdkHome = $env:DEVECO_SDK_HOME,
  [string]$HvigorPath = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$RunModePath = Join-Path $ProjectRoot 'entry\src\test\benchmark\BenchmarkRunMode.ets'
$CoverageLog = Join-Path $ProjectRoot 'entry\.test\default\intermediates\test\coverage_data\coverage.log'
$ResultFile = Join-Path $ProjectRoot 'entry\.test\default\intermediates\test\coverage_data\test_result.txt'
$OutputDirectory = Join-Path $ProjectRoot 'benchmark-results'
if ([string]::IsNullOrWhiteSpace($SdkHome)) {
  throw 'DEVECO_SDK_HOME is not set. Set it or pass -SdkHome.'
}
$Hvigor = if ([string]::IsNullOrWhiteSpace($HvigorPath)) {
  Join-Path (Split-Path -Parent $SdkHome) 'tools\hvigor\bin\hvigorw.bat'
} else {
  $HvigorPath
}
if (-not (Test-Path -LiteralPath $Hvigor -PathType Leaf)) {
  throw "Hvigor wrapper was not found at $Hvigor. Pass -HvigorPath."
}

function Read-EncodedChunks([string]$Kind) {
  $pattern = "SEMALINK_BENCH_${Kind}_(?<index>\d{4})_(?<total>\d{4}):(?<data>\S+)"
  $matches = Select-String -LiteralPath $CoverageLog -Pattern $pattern -AllMatches |
    ForEach-Object { $_.Matches } |
    ForEach-Object {
      [PSCustomObject]@{
        Index = [int]$_.Groups['index'].Value
        Total = [int]$_.Groups['total'].Value
        Data = $_.Groups['data'].Value
      }
    } | Sort-Object Index
  if (-not $matches) {
    throw "No $Kind benchmark chunks were found in $CoverageLog"
  }
  $expected = $matches[0].Total
  if ($matches.Count -ne $expected) {
    throw "Expected $expected $Kind chunks but found $($matches.Count)"
  }
  return [Uri]::UnescapeDataString(($matches.Data -join ''))
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$DisabledRunMode = 'export const RUN_FULL_LOCAL_RETRIEVAL_BENCHMARK: boolean = false;' + [Environment]::NewLine
$EnabledRunMode = 'export const RUN_FULL_LOCAL_RETRIEVAL_BENCHMARK: boolean = true;' + [Environment]::NewLine
[IO.File]::WriteAllText($RunModePath, $EnabledRunMode, [Text.UTF8Encoding]::new($false))
try {
  $env:DEVECO_SDK_HOME = $SdkHome
  & $Hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug test --no-daemon
  if ($LASTEXITCODE -ne 0) {
    throw "Hvigor benchmark command failed with exit code $LASTEXITCODE"
  }
  $testResult = Get-Content -Raw -Encoding UTF8 -LiteralPath $ResultFile
  if ($testResult -notmatch 'class=LocalRetrievalFullBenchmark[\s\S]*?result=Success') {
    throw 'Hypium did not report the full benchmark test as successful.'
  }
  $json = Read-EncodedChunks 'JSON'
  $markdown = Read-EncodedChunks 'MARKDOWN'
  $parsed = $json | ConvertFrom-Json
  $jsonPath = Join-Path $OutputDirectory "local-retrieval-$Label.json"
  $markdownPath = Join-Path $OutputDirectory "local-retrieval-$Label.md"
  [IO.File]::WriteAllText($jsonPath, $json, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($markdownPath, $markdown, [Text.UTF8Encoding]::new($false))
  Write-Output $jsonPath
  Write-Output $markdownPath
  if ($Label -eq 'latest') {
    $answerable = $parsed.development.answerableQueryCount + $parsed.holdout.answerableQueryCount
    $noAnswer = $parsed.development.noAnswerQueryCount + $parsed.holdout.noAnswerQueryCount
    $combinedTop1 = (($parsed.development.top1Accuracy * $parsed.development.answerableQueryCount) +
      ($parsed.holdout.top1Accuracy * $parsed.holdout.answerableQueryCount)) / $answerable
    $combinedTop3 = (($parsed.development.top3Recall * $parsed.development.answerableQueryCount) +
      ($parsed.holdout.top3Recall * $parsed.holdout.answerableQueryCount)) / $answerable
    $combinedTop5 = (($parsed.development.top5Recall * $parsed.development.answerableQueryCount) +
      ($parsed.holdout.top5Recall * $parsed.holdout.answerableQueryCount)) / $answerable
    $combinedMrr = (($parsed.development.mrr * $parsed.development.answerableQueryCount) +
      ($parsed.holdout.mrr * $parsed.holdout.answerableQueryCount)) / $answerable
    $combinedSuccess = (($parsed.development.querySuccessRate * $parsed.development.answerableQueryCount) +
      ($parsed.holdout.querySuccessRate * $parsed.holdout.answerableQueryCount)) / $answerable
    $combinedRejection = (($parsed.development.noAnswerRejectionRate * $parsed.development.noAnswerQueryCount) +
      ($parsed.holdout.noAnswerRejectionRate * $parsed.holdout.noAnswerQueryCount)) / $noAnswer
    $combinedFalsePositive = (($parsed.development.falsePositiveRate * $parsed.development.noAnswerQueryCount) +
      ($parsed.holdout.falsePositiveRate * $parsed.holdout.noAnswerQueryCount)) / $noAnswer
    $acceptanceFailures = New-Object System.Collections.Generic.List[string]
    if ($combinedTop1 -lt 0.85) { $acceptanceFailures.Add("Top-1=$combinedTop1") }
    if ($combinedTop3 -lt 0.95) { $acceptanceFailures.Add("Top-3=$combinedTop3") }
    if ($combinedTop5 -lt 0.98) { $acceptanceFailures.Add("Top-5=$combinedTop5") }
    if ($combinedMrr -lt 0.90) { $acceptanceFailures.Add("MRR=$combinedMrr") }
    if ($combinedSuccess -lt 0.95) { $acceptanceFailures.Add("success=$combinedSuccess") }
    if ($combinedRejection -lt 0.90) { $acceptanceFailures.Add("rejection=$combinedRejection") }
    if ($combinedFalsePositive -gt 0.10) { $acceptanceFailures.Add("falsePositive=$combinedFalsePositive") }
    foreach ($latency in $parsed.latency) {
      if ($latency.level -eq 'L1' -and ($latency.p50Ms -gt 50 -or $latency.p95Ms -gt 100)) {
        $acceptanceFailures.Add("L1/topK=$($latency.topK) P50/P95=$($latency.p50Ms)/$($latency.p95Ms)")
      }
      if ($latency.level -eq 'L2' -and ($latency.p50Ms -gt 75 -or $latency.p95Ms -gt 150)) {
        $acceptanceFailures.Add("L2/topK=$($latency.topK) P50/P95=$($latency.p50Ms)/$($latency.p95Ms)")
      }
    }
    if ($acceptanceFailures.Count -gt 0) {
      throw 'Latest benchmark failed acceptance: ' + ($acceptanceFailures -join '; ')
    }
  }
} finally {
  [IO.File]::WriteAllText($RunModePath, $DisabledRunMode, [Text.UTF8Encoding]::new($false))
}
