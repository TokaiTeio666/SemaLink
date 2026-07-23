export enum A2AFixtureFidelity {
  EXACT_OFFICIAL = 'EXACT_OFFICIAL',
  DERIVED_FROM_OFFICIAL = 'DERIVED_FROM_OFFICIAL',
  PROJECT_COMPATIBILITY = 'PROJECT_COMPATIBILITY'
}

export class A2AFixture {
  readonly sourceUrl: string;
  readonly documentTitle: string;
  readonly documentVersion: string;
  readonly scenario: string;
  readonly fidelity: A2AFixtureFidelity;
  readonly json: string;

  constructor(sourceUrl: string, documentTitle: string, documentVersion: string, scenario: string,
    fidelity: A2AFixtureFidelity, json: string) {
    this.sourceUrl = sourceUrl;
    this.documentTitle = documentTitle;
    this.documentVersion = documentVersion;
    this.scenario = scenario;
    this.fidelity = fidelity;
    this.json = json;
  }
}

const COMMAND_URL: string =
  'https://developer.huawei.com/consumer/cn/doc/service/agent2agent-device-commands-0000002594605828';
const CONVERSATION_URL: string =
  'https://developer.huawei.com/consumer/cn/doc/service/agent2agent-chat-0000002660585429';
const CANCEL_URL: string =
  'https://developer.huawei.com/consumer/cn/doc/service/agent2agent-exp-0000002660465491';

export const FIRST_CONVERSATION: A2AFixture = new A2AFixture(
  CONVERSATION_URL, '对话', 'V0.6 / 2026-07-02', '首次对话请求', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":"req-1","method":"message/stream","params":{"message":{"messageId":"msg-1","role":"ROLE_USER","parts":[{"text":"查询本机知识","mediaType":"text/plain"}]},"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent"}}}'
);

export const FOLLOW_UP: A2AFixture = new A2AFixture(
  CONVERSATION_URL, '对话', 'V0.6 / 2026-07-02', '继续已有任务', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":2,"method":"message/stream","params":{"message":{"messageId":"msg-2","taskId":"task-1","contextId":"ctx-1","role":"ROLE_USER","parts":[{"text":"改为本机查询"}]},"metadata":{"traceId":"trace-2","agentId":"semalink_knowledge_agent"}}}'
);

export const TASK_CANCEL: A2AFixture = new A2AFixture(
  CANCEL_URL, '任务取消', 'V0.6 / 2026-07-02', '取消任务', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":"req-cancel","method":"tasks/cancel","params":{"id":"task-1","metadata":{"traceId":"trace-3","agentId":"semalink_knowledge_agent"}}}'
);

export const STREAM_ARTIFACT_UPDATE: A2AFixture = new A2AFixture(
  COMMAND_URL, '端 A2A 消息指令', 'V0.6 / 2026-07-02', 'Artifact 最后一帧', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":"req-1","result":{"artifactUpdate":{"taskId":"task-1","contextId":"ctx-1","artifact":{"artifactId":"artifact-1","parts":[{"text":"回答","mediaType":"text/plain"}]},"append":false,"lastChunk":true},"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent","agentVersion":"1.0.0"}}}'
);

export const STREAM_COMPLETED: A2AFixture = new A2AFixture(
  COMMAND_URL, '端 A2A 消息指令', 'V0.6 / 2026-07-02', '流式最终状态', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":"req-1","result":{"statusUpdate":{"taskId":"task-1","contextId":"ctx-1","status":{"state":"TASK_STATE_COMPLETED","timestamp":"2026-07-02T00:00:00.000Z"}},"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent","agentVersion":"1.0.0"}}}'
);

export const SUBMITTED_TASK: A2AFixture = new A2AFixture(
  COMMAND_URL, '端 A2A 消息指令', 'V0.6 / 2026-07-02', '首帧响应', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":"req-1","result":{"task":{"id":"task-1","contextId":"ctx-1","status":{"state":"TASK_STATE_SUBMITTED","timestamp":"2026-07-02T00:00:00.000Z"}},"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent","agentVersion":"1.0.0"}}}'
);
export const WORKING_UPDATE: A2AFixture = new A2AFixture(
  COMMAND_URL, '端 A2A 消息指令', 'V0.6 / 2026-07-02', 'WORKING', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":"req-1","result":{"statusUpdate":{"taskId":"task-1","contextId":"ctx-1","status":{"state":"TASK_STATE_WORKING","timestamp":"2026-07-02T00:00:00.000Z"}},"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent","agentVersion":"1.0.0"}}}'
);
export const INPUT_REQUIRED_UPDATE: A2AFixture = new A2AFixture(
  COMMAND_URL, '端 A2A 消息指令', 'V0.6 / 2026-07-02', 'INPUT_REQUIRED', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":"req-1","result":{"statusUpdate":{"taskId":"task-1","contextId":"ctx-1","status":{"state":"TASK_STATE_INPUT_REQUIRED","timestamp":"2026-07-02T00:00:00.000Z","message":{"role":"ROLE_AGENT","parts":[{"text":"是否改为本机查询？","mediaType":"text/plain"}]}}},"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent","agentVersion":"1.0.0"}}}'
);
export const FAILED_UPDATE: A2AFixture = new A2AFixture(
  COMMAND_URL, '端 A2A 消息指令', 'V0.6 / 2026-07-02', 'FAILED', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":"req-1","result":{"statusUpdate":{"taskId":"task-1","contextId":"ctx-1","status":{"state":"TASK_STATE_FAILED","timestamp":"2026-07-02T00:00:00.000Z","message":{"role":"ROLE_AGENT","parts":[{"text":"处理失败","mediaType":"text/plain"},{"data":{"error":{"code":"-32603","message":"处理失败"}}}]}}},"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent","agentVersion":"1.0.0"}}}'
);
export const NON_STREAM_COMPLETED: A2AFixture = new A2AFixture(
  COMMAND_URL, '端 A2A 消息指令', 'V0.6 / 2026-07-02', '完整 Task 辅助响应', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":"req-1","result":{"task":{"id":"task-1","contextId":"ctx-1","status":{"state":"TASK_STATE_COMPLETED","timestamp":"2026-07-02T00:00:00.000Z"},"artifacts":[{"artifactId":"artifact-1","parts":[{"text":"回答","mediaType":"text/plain"}]}]},"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent","agentVersion":"1.0.0"}}}'
);
export const CONTEXT_INVALID: A2AFixture = new A2AFixture(
  COMMAND_URL, '端 A2A 消息指令', 'V0.6 / 2026-07-02', 'Context 失效', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":"req-1","error":{"code":99911222,"message":"Context invalid"}}'
);
export const INVALID_REQUEST: A2AFixture = new A2AFixture(
  COMMAND_URL, '端 A2A 消息指令', 'V0.6 / 2026-07-02', '非法请求错误', A2AFixtureFidelity.PROJECT_COMPATIBILITY,
  '{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"Invalid request"}}'
);

export const CANCELLED_RESPONSE: A2AFixture = new A2AFixture(
  CANCEL_URL, '任务取消', 'V0.6 / 2026-07-02', '取消成功响应', A2AFixtureFidelity.DERIVED_FROM_OFFICIAL,
  '{"jsonrpc":"2.0","id":"req-1","result":{"id":"task-1","contextId":"ctx-1","status":{"state":"TASK_STATE_CANCELLED","timestamp":"2026-07-02T00:00:00.000Z"},"metadata":{"traceId":"trace-1","agentId":"semalink_knowledge_agent","agentVersion":"1.0.0"}}}'
);

export const ALL_FIXTURES: A2AFixture[] = [
  FIRST_CONVERSATION, FOLLOW_UP, TASK_CANCEL, SUBMITTED_TASK, WORKING_UPDATE,
  STREAM_ARTIFACT_UPDATE, STREAM_COMPLETED, INPUT_REQUIRED_UPDATE, FAILED_UPDATE,
  NON_STREAM_COMPLETED, CANCELLED_RESPONSE, CONTEXT_INVALID, INVALID_REQUEST
];
