# SemaLink 三设备跨设备知识闭环真机测试

状态：`AWAITING_DEVICE_SPIKE` / `COMPILED_NOT_EXECUTED`

本文档只定义真机执行步骤。当前代码已完成 API 24 编译与 HAP 打包，但尚未在三台 HarmonyOS 真机上执行，因此不得将本状态描述为真机通过。

## 前置条件

- 三台 API 24 Phone，记为 A、B、C。
- 三台设备安装同一 AppID、同一构建版本的 SemaLink。
- 设备处于官方应用协作可用条件：同一可信组网；需要时处于同一局域网或蓝牙可达范围。
- 三台设备均授予 `ohos.permission.DISTRIBUTED_DATASYNC`。
- B 导入“数据库事务”知识，C 导入“软件测试”知识；A 不导入这两个主题。
- B、C 的分享策略初始保持关闭。
- 不采集、截图或记录 deviceId、networkId、文件路径、SQL、数据库内部 ID。

## 1. PING/PONG 平台尖峰

1. 在 B 启动 SemaLink 并保持前台。
2. 在 A 打开协作探针，选择唯一可见的 B。
3. A 发送协议版本 1 的 PING。
4. B 接收 PING 并发送 PONG。
5. A 应显示 `PROBE_PASS`。
6. 重复 A↔C。

记录：两次结果、P50/P95、失败码。日志只允许出现掩码或别名，不允许出现完整系统设备标识。

## 2. 应用层信任

1. A 首次与 B、C 完成 HELLO。
2. 验证 A 中两台设备均为 `PENDING`，系统可见不等于应用已信任。
3. 在 A 中分别确认 B、C 为 `TRUSTED`。
4. 将 C 设置为 `BLOCKED`，确认 C 不参与画像同步和路由。
5. 将 C 改为 `REVOKED`，重启 A，确认状态持久化。
6. 重新信任 C，并编辑 B、C 的设备别名。

## 3. 画像 digest-first 交换

1. B、C 上线后，A 只交换 `profileVersion + profileDigest`。
2. digest 相同：抓取应用调试计数，确认未发送完整画像。
3. 修改 B 本地知识后刷新画像：A 应请求一次画像摘要。
4. 验证画像域不超过 20、序列化不超过 8 KiB。
5. 验证画像中无标题列表、文件名、路径、chunk、正文、查询历史、SQL、数据库 ID。
6. 在线缓存 5 分钟后应过期；离线缓存可回退但不得超过 24 小时。

## 4. 远端查询闭环

1. 在 B、C 开启分享；保持默认 `L1 / 5 条 / 512 字`。
2. A 显式选择 `REMOTE_ONLY`，查询“数据库事务 ACID”。
3. A 只应选择画像最匹配的 B，不广播给 C。
4. B 调用本地 `SemanticKnowledgeProvider.searchEvidence()`，脱敏后返回 Evidence。
5. A 显示 B 的用户别名作为来源。
6. 模拟 B 网络失败或 `BUSY`，确认仅此时回退 Top 2；其他拒绝不回退。
7. 切换 `LOCAL_AND_REMOTE`，确认本地和一个远端并行，hash 去重保留更高 relevance，总数不超过 8、单设备不超过 5。

## 5. 授权、超时、取消与幂等

1. 关闭 B 分享，A 新请求应得到 `SHARING_DISABLED`。
2. 请求 L2 而 B 未单独允许 L2，应得到 `LEVEL_DENIED`。
3. 将 A 在 B 上设为 BLOCKED/REVOKED，应得到 `UNAUTHORIZED`。
4. 同时向 B 发起 3 个运行请求，运行中不超过 2；继续压测，队列不超过 4，超限返回 `BUSY`。
5. 让检索超过 5 秒，应得到 `DEADLINE_EXCEEDED`，迟到结果不得进入 UI。
6. A 发送取消，B 停止接纳结果并返回/记录 `CANCELLED`。
7. 五分钟内重复同一 requestId，确认复用幂等结果；缓存不超过 128。
8. 关闭分享时，确认新的入站请求立即拒绝。

## 6. 隐私检查

对所有 PROFILE/QUERY 响应和访问记录检查：

- 允许：安全标题、摘要/片段、relevance、knowledgeDomain、updatedAtMs、level、来源设备别名。
- 禁止：绝对路径、SQL、数据库/文档/chunk ID、完整文档、未授权 L2、硬件 ID、networkId、原始异常。
- 单次逻辑响应不超过 64 KiB；超出时先删除低相关证据，再截断摘要并标记 `truncated`。
- 访问记录不保存完整问题或 Evidence 正文。

## 7. 重启和资源释放

1. 重启 A、B、C，确认 appInstanceId、设备别名、信任、分享策略和访问记录持久化。
2. 确认系统 transport 映射不会持久化，重连后通过 HELLO 恢复 peerKey。
3. 关闭应用，确认设备监听器、协作会话和超时任务释放。
4. 断网/恢复循环 20 次，确认退避有上限且没有无限重试或明显内存增长。

## 8. 结果记录

| 场景 | 样本数 | P50 | P95 | 结果/错误码 | 备注 |
|---|---:|---:|---:|---|---|
| A→B PING/PONG |  |  |  |  |  |
| A→C PING/PONG |  |  |  |  |  |
| 画像 digest 相同 |  |  |  |  |  |
| 画像变化拉取 |  |  |  |  |  |
| Top 1 查询 |  |  |  |  |  |
| BUSY 回退 Top 2 |  |  |  |  |  |
| 取消传播 |  |  |  |  |  |
| 5 秒超时 |  |  |  |  |  |

完成以上全部步骤并保存不含敏感标识的证据后，才可把状态从 `AWAITING_DEVICE_SPIKE` 改为真机通过。
