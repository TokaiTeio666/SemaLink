# SemaLink DSK 远端任务与可靠传输设计

## 决策

本轮只使用 DSK/SoftBus 作为控制面和数据面，不接入 NetworkKit TLS。DSK 数据通道承载 `TASK`、`TASK_ACK`、`EVIDENCE_PAGE`、`EVIDENCE_ACK`、`EVIDENCE_COMPLETE`、`TSF`、`CANCEL` 和 `ERROR`。

## 远端任务闭环

`Task3TlsCoordinator` 提供统一入站数据回调。运行时将同一条消息分发给 `PeerTaskResponder` 和发起端任务协调器。远端查询使用 `deviceId + peerTaskId + round` 作为等待键，收到页面后累积证据，收到 `EVIDENCE_COMPLETE` 后完成当前轮次。

## 可靠分页

每页不超过数据帧预算，发送端最多同时发送 4 页；每页等待 1500ms ACK，最多发送 3 次。接收端按页索引幂等缓存，校验摘要后回 ACK，全部页面齐备后再完成轮次。取消、断开、超时和任务终态必须清除分页状态。

## 生命周期

数据监听器采用可注销的多回调集合；绑定超时句柄显式保存并在成功、失败、关闭时清理；未完成分片按设备和 frameId 设置上限与过期清理；连接关闭必须解除业务监听和等待者。

## 验收

- 真实入口能把远端 TASK 发给响应器，并把页面回传给发起端。
- 重复页、乱序页、丢 ACK 和迟到页不会重复计入或污染终态。
- 单台设备断开不影响其他设备。
- 连续任务后不存在未完成定时器、分页缓存或回调。
