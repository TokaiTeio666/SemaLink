# P4 Semantic Loop Acceptance

This acceptance run is limited to one local device and one connected remote API 24 device.
It does not introduce Network Kit, sockets, a vector database, MindSpore Lite, or background
work. Legacy QUERY, QUERY_ACK, RESULT, and ERROR behavior remains part of the matrix.

## Required scenarios

| Scenario | Expected result |
|---|---|
| Local route, L1 sufficient | One round, ENOUGH, no L2 evidence |
| Remote route, L1 insufficient | TASK -> TASK_ACK -> EVIDENCE(L1) -> TSF(NEED_MORE) |
| Remote route, L2 sufficient | EVIDENCE(L2) -> TSF(ENOUGH), two rounds |
| Two rounds insufficient | TSF(ABORT), phase ABORTED, INSUFFICIENT_EVIDENCE |
| Byte budget exhausted | No over-budget EVIDENCE; task aborts deterministically |
| Private-group task | Only PRIVATE_GROUP evidence is eligible |
| Stale remote profile | Remote route excluded; E_PROFILE_STALE |
| Disconnect during task | Task ends with E_BACKGROUND_INTERRUPTED; no later dispatch |
| Invalid semantic envelope | Envelope rejected with E_SEMANTIC_PROTOCOL_INVALID |
| Duplicate message/evidence | First delivery only; no duplicate evaluation |
| Multi-page evidence | Every encoded page is at most 1 KiB; TSF runs once after all pages arrive |
| Out-of-order or missing page | Out-of-order pages are reassembled; a missing page does not trigger TSF and times out at the task latency budget |
| Legacy single-page evidence | Missing page metadata is normalized to page 0 of 1 |

## Metrics to capture

Record raw latency samples for each task and report P50/P95 from those samples. Capture first
result latency, completion latency, selected device, route score and subscores, round, TSF,
privacy level, total protocol bytes, and EVIDENCE bytes. EVIDENCE bytes must be counted from
selected EVIDENCE payloads only; protocol bytes are reported separately.

For the fixed fixture run, record the result for all 20 queries: 8 local, 8 remote, and 4
cross-device cases, including the two L1-sufficient and two L2-insufficient cases. Repeat the
matrix on two API 24 devices with one connected remote device and attach the raw samples and
device build identifiers to the test report.

## Current run record

The deterministic unit fixture records raw latency samples `[120, 180, 260]` ms; its P50 is
180 ms and P95 is 260 ms. The metric assertion also verifies separate protocol and EVIDENCE
byte totals, privacy, round, TSF, and route fields.

The two-device API 24 matrix was not executed in this run: the prescribed Hvigor `test` and
`assembleHap` commands both stopped before compilation with `00303217`, because
`DEVECO_SDK_HOME` is invalid. No device build identifiers or real-device P50/P95 values are
claimed. This is a verification blocker, not a passing result.

## Commands

```powershell
$node = 'D:\Program Files\DevEco Studio\tools\node\node.exe'
$hvigor = 'D:\Program Files\DevEco Studio\tools\hvigor\bin\hvigorw.js'
& $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug test
& $node $hvigor --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap
```

The commands are only passing when they return exit code 0 and provide explicit Hvigor
success output. An invalid DEVECO_SDK_HOME or missing root hvigorw.js is a verification blocker,
not a passing result.
