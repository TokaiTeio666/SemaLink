import { describe, expect, it } from '@ohos/hypium';
import { A2ACommandCodec } from '../main/ets/agent/a2a/A2ACommandCodec';
import { A2ACommandKind, A2AMetadata } from '../main/ets/agent/a2a/A2AModels';
import { A2AResponseFactory } from '../main/ets/agent/a2a/A2AResponseFactory';
import {
  ALL_FIXTURES,
  FIRST_CONVERSATION,
  FOLLOW_UP,
  TASK_CANCEL,
  SUBMITTED_TASK,
  WORKING_UPDATE,
  STREAM_ARTIFACT_UPDATE,
  STREAM_COMPLETED,
  INPUT_REQUIRED_UPDATE,
  FAILED_UPDATE,
  NON_STREAM_COMPLETED,
  CANCELLED_RESPONSE,
  CONTEXT_INVALID,
  A2AFixtureFidelity
}
  from './fixtures/a2a/HuaweiA2AV06Fixtures';

function result(json: string): Record<string, Object> {
  return (JSON.parse(json) as Record<string, Object>)['result'] as Record<string, Object>;
}

function stateFromTask(value: Record<string, Object>): string {
  const task: Record<string, Object> = value['task'] as Record<string, Object>;
  return (task['status'] as Record<string, Object>)['state'] as string;
}

function stateFromUpdate(value: Record<string, Object>): string {
  const update: Record<string, Object> = value['statusUpdate'] as Record<string, Object>;
  return (update['status'] as Record<string, Object>)['state'] as string;
}

function canonical(value: Object): string {
  if (value === null) {
    return 'null';
  }
  if (Array.isArray(value)) {
    const items: Object[] = value as Object[];
    const encoded: string[] = [];
    for (const item of items) {
      encoded.push(canonical(item));
    }
    return '[' + encoded.join(',') + ']';
  }
  if (typeof value === 'object') {
    const recordValue: Record<string, Object> = value as Record<string, Object>;
    const keys: string[] = Object.keys(recordValue).sort();
    const fields: string[] = [];
    for (const key of keys) {
      const child: Object = recordValue[key];
      const normalized: string = key === 'timestamp' && typeof child === 'string'
        ? '"<timestamp>"' : canonical(child);
      fields.push(JSON.stringify(key) + ':' + normalized);
    }
    return '{' + fields.join(',') + '}';
  }
  return JSON.stringify(value) as string;
}

function assertFixture(actual: string, fixture: string): void {
  expect(canonical(JSON.parse(actual) as Object)).assertEqual(canonical(JSON.parse(fixture) as Object));
}

export default function agentProtocolGoldenFixtureTest(): void {
  describe('AgentProtocolGoldenFixture', () => {
    it('keeps all independently decodable fixtures with source provenance', 0, () => {
      expect(ALL_FIXTURES.length).assertEqual(13);
      for (const fixture of ALL_FIXTURES) {
        const envelope: Record<string, Object> = JSON.parse(fixture.json) as Record<string, Object>;
        expect(fixture.sourceUrl.indexOf('developer.huawei.com') >= 0).assertTrue();
        expect(fixture.documentTitle.length > 0).assertTrue();
        expect(fixture.documentVersion.length > 0).assertTrue();
        expect(fixture.scenario.length > 0).assertTrue();
        expect(fixture.fidelity === A2AFixtureFidelity.EXACT_OFFICIAL ||
          fixture.fidelity === A2AFixtureFidelity.DERIVED_FROM_OFFICIAL ||
          fixture.fidelity === A2AFixtureFidelity.PROJECT_COMPATIBILITY).assertTrue();
        expect(envelope['jsonrpc'] as string).assertEqual('2.0');
      }
    });

    it('decodes the official request fixtures without weakening their contracts', 0, () => {
      const codec: A2ACommandCodec = new A2ACommandCodec();
      expect(codec.decode(FIRST_CONVERSATION.json).kind).assertEqual(A2ACommandKind.MESSAGE_STREAM);
      expect(codec.decode(FOLLOW_UP.json).kind).assertEqual(A2ACommandKind.MESSAGE_STREAM);
      expect(codec.decode(TASK_CANCEL.json).kind).assertEqual(A2ACommandKind.TASK_CANCEL);
    });

    it('aligns every production response shape with its sourced fixture contract', 0, () => {
      const factory: A2AResponseFactory = new A2AResponseFactory();
      const metadata: A2AMetadata = new A2AMetadata('trace-1', 'agent-1');
      const submitted: Record<string, Object> = result(factory.submitted('req-1', 'ctx-1', 'task-1', metadata));
      expect(stateFromTask(submitted)).assertEqual(stateFromTask(result(SUBMITTED_TASK.json)));
      assertFixture(factory.submitted('req-1', 'ctx-1', 'task-1', metadata), SUBMITTED_TASK.json);
      const working: Record<string, Object> = result(factory.working('req-1', 'ctx-1', 'task-1', metadata));
      expect(stateFromUpdate(working)).assertEqual(stateFromUpdate(result(WORKING_UPDATE.json)));
      assertFixture(factory.working('req-1', 'ctx-1', 'task-1', metadata), WORKING_UPDATE.json);
      const artifact: Record<string, Object> = result(factory.artifactUpdate(
        'req-1', 'ctx-1', 'task-1', 'artifact-1', '回答', false, true, metadata));
      const artifactFixture: Record<string, Object> = result(STREAM_ARTIFACT_UPDATE.json);
      const update: Record<string, Object> = artifact['artifactUpdate'] as Record<string, Object>;
      const fixtureUpdate: Record<string, Object> = artifactFixture['artifactUpdate'] as Record<string, Object>;
      expect(update['taskId'] as string).assertEqual(fixtureUpdate['taskId'] as string);
      expect(update['contextId'] as string).assertEqual(fixtureUpdate['contextId'] as string);
      expect(update['append'] as boolean).assertEqual(fixtureUpdate['append'] as boolean);
      expect(update['lastChunk'] as boolean).assertEqual(fixtureUpdate['lastChunk'] as boolean);
      const artifactValue: Record<string, Object> = update['artifact'] as Record<string, Object>;
      expect(artifactValue['artifactId'] as string).assertEqual('artifact-1');
      expect((artifactValue['parts'] as Object[]).length).assertEqual(1);
      assertFixture(factory.artifactUpdate(
        'req-1', 'ctx-1', 'task-1', 'artifact-1', '回答', false, true, metadata),
      STREAM_ARTIFACT_UPDATE.json);
      const completed: Record<string, Object> = result(
        factory.completedStatus('req-1', 'ctx-1', 'task-1', metadata));
      expect(stateFromUpdate(completed)).assertEqual(stateFromUpdate(result(STREAM_COMPLETED.json)));
      assertFixture(factory.completedStatus('req-1', 'ctx-1', 'task-1', metadata), STREAM_COMPLETED.json);
      const completeTask: Record<string, Object> = result(
        factory.completed('req-1', 'ctx-1', 'task-1', 'artifact-1', '回答', metadata));
      expect(stateFromTask(completeTask)).assertEqual(stateFromTask(result(NON_STREAM_COMPLETED.json)));
      assertFixture(factory.completed(
        'req-1', 'ctx-1', 'task-1', 'artifact-1', '回答', metadata), NON_STREAM_COMPLETED.json);
      assertFixture(factory.inputRequired(
        'req-1', 'ctx-1', 'task-1', '是否改为本机查询？', metadata), INPUT_REQUIRED_UPDATE.json);
      assertFixture(factory.failed(
        'req-1', 'ctx-1', 'task-1', '-32603', '处理失败', metadata), FAILED_UPDATE.json);
      assertFixture(factory.cancelled(
        'req-1', 'ctx-1', 'task-1', metadata), CANCELLED_RESPONSE.json);
      const errorEnvelope: Record<string, Object> = JSON.parse(
        factory.error('req-1', 99911222, 'Context invalid')) as Record<string, Object>;
      const fixtureErrorEnvelope: Record<string, Object> = JSON.parse(CONTEXT_INVALID.json) as Record<string, Object>;
      const error: Record<string, Object> = errorEnvelope['error'] as Record<string, Object>;
      const fixtureError: Record<string, Object> = fixtureErrorEnvelope['error'] as Record<string, Object>;
      expect(error['code'] as number).assertEqual(fixtureError['code'] as number);
      expect((submitted['metadata'] as Record<string, Object>)['traceId'] as string).assertEqual('trace-1');
      expect((artifact['metadata'] as Record<string, Object>)['agentVersion'] as string).assertEqual('1.0.0');
    });
  });
}
