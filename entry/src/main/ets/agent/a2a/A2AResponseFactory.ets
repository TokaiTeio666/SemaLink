import { A2AMetadata, A2ARequestId, A2AResponseId, A2ATaskState } from './A2AModels';
import { SEMA_LINK_AGENT_ID } from '../AgentIdentity';

const AGENT_VERSION: string = '1.0.0';

interface WireMetadata {
  traceId: string;
  agentId: string;
  agentVersion: string;
}

interface WireErrorDetail {
  code: string;
  message: string;
}

interface WirePartData {
  error: WireErrorDetail;
}

interface WirePart {
  text?: string;
  mediaType?: string;
  data?: WirePartData;
}

interface WireMessage {
  role: string;
  parts: WirePart[];
}

interface WireStatus {
  state: string;
  timestamp: string;
  message?: WireMessage;
}

interface WireArtifact {
  artifactId: string;
  parts: WirePart[];
}

interface WireArtifactUpdate {
  taskId: string;
  contextId: string;
  artifact: WireArtifact;
  append: boolean;
  lastChunk: boolean;
}

interface WireTask {
  id: string;
  contextId: string;
  status: WireStatus;
  artifacts?: WireArtifact[];
}

interface WireStatusUpdate {
  taskId: string;
  contextId: string;
  status: WireStatus;
}

interface WireResult {
  task?: WireTask;
  statusUpdate?: WireStatusUpdate;
  artifactUpdate?: WireArtifactUpdate;
  metadata?: WireMetadata;
  id?: string;
  contextId?: string;
  status?: WireStatus;
}

interface WireRpcError {
  code: number;
  message: string;
}

interface WireEnvelope {
  jsonrpc: string;
  id: A2AResponseId;
  result?: WireResult;
  error?: WireRpcError;
}

function responseMetadata(metadata: A2AMetadata): WireMetadata {
  return {
    traceId: metadata.traceId,
    agentId: SEMA_LINK_AGENT_ID,
    agentVersion: AGENT_VERSION
  };
}

function status(state: A2ATaskState): WireStatus {
  return { state: state, timestamp: new Date().toISOString() };
}

function encode(envelope: WireEnvelope): string {
  return JSON.stringify(envelope);
}

export class A2AResponseFactory {
  submitted(requestId: A2ARequestId, contextId: string, taskId: string, metadata: A2AMetadata): string {
    const task: WireTask = { id: taskId, contextId: contextId, status: status(A2ATaskState.SUBMITTED) };
    const result: WireResult = { task: task, metadata: responseMetadata(metadata) };
    return encode({ jsonrpc: '2.0', id: requestId, result: result });
  }

  working(requestId: A2ARequestId, contextId: string, taskId: string, metadata: A2AMetadata): string {
    const update: WireStatusUpdate = {
      taskId: taskId, contextId: contextId, status: status(A2ATaskState.WORKING)
    };
    const result: WireResult = { statusUpdate: update, metadata: responseMetadata(metadata) };
    return encode({ jsonrpc: '2.0', id: requestId, result: result });
  }

  completed(requestId: A2ARequestId, contextId: string, taskId: string, artifactId: string,
    text: string, metadata: A2AMetadata): string {
    const part: WirePart = { text: text, mediaType: 'text/plain' };
    const artifact: WireArtifact = { artifactId: artifactId, parts: [part] };
    const task: WireTask = {
      id: taskId,
      contextId: contextId,
      status: status(A2ATaskState.COMPLETED),
      artifacts: [artifact]
    };
    const result: WireResult = { task: task, metadata: responseMetadata(metadata) };
    return encode({ jsonrpc: '2.0', id: requestId, result: result });
  }

  artifactUpdate(requestId: A2ARequestId, contextId: string, taskId: string, artifactId: string,
    text: string, append: boolean, lastChunk: boolean, metadata: A2AMetadata): string {
    const part: WirePart = { text: text, mediaType: 'text/plain' };
    const artifact: WireArtifact = { artifactId: artifactId, parts: [part] };
    const update: WireArtifactUpdate = {
      taskId: taskId,
      contextId: contextId,
      artifact: artifact,
      append: append,
      lastChunk: lastChunk
    };
    const result: WireResult = { artifactUpdate: update, metadata: responseMetadata(metadata) };
    return encode({ jsonrpc: '2.0', id: requestId, result: result });
  }

  completedStatus(requestId: A2ARequestId, contextId: string, taskId: string,
    metadata: A2AMetadata): string {
    const update: WireStatusUpdate = {
      taskId: taskId, contextId: contextId, status: status(A2ATaskState.COMPLETED)
    };
    const result: WireResult = { statusUpdate: update, metadata: responseMetadata(metadata) };
    return encode({ jsonrpc: '2.0', id: requestId, result: result });
  }

  inputRequired(requestId: A2ARequestId, contextId: string, taskId: string, text: string,
    metadata: A2AMetadata): string {
    const part: WirePart = { text: text, mediaType: 'text/plain' };
    const message: WireMessage = { role: 'ROLE_AGENT', parts: [part] };
    const value: WireStatus = status(A2ATaskState.INPUT_REQUIRED);
    value.message = message;
    const update: WireStatusUpdate = { taskId: taskId, contextId: contextId, status: value };
    const result: WireResult = { statusUpdate: update, metadata: responseMetadata(metadata) };
    return encode({ jsonrpc: '2.0', id: requestId, result: result });
  }

  failed(requestId: A2ARequestId, contextId: string, taskId: string, code: string,
    safeMessage: string, metadata: A2AMetadata): string {
    const textPart: WirePart = { text: safeMessage, mediaType: 'text/plain' };
    const detail: WireErrorDetail = { code: code, message: safeMessage };
    const data: WirePartData = { error: detail };
    const errorPart: WirePart = { data: data };
    const message: WireMessage = { role: 'ROLE_AGENT', parts: [textPart, errorPart] };
    const value: WireStatus = status(A2ATaskState.FAILED);
    value.message = message;
    const update: WireStatusUpdate = { taskId: taskId, contextId: contextId, status: value };
    const result: WireResult = { statusUpdate: update, metadata: responseMetadata(metadata) };
    return encode({ jsonrpc: '2.0', id: requestId, result: result });
  }

  cancelled(requestId: A2ARequestId, contextId: string, taskId: string, metadata: A2AMetadata): string {
    const result: WireResult = {
      id: taskId, contextId: contextId, status: status(A2ATaskState.CANCELLED),
      metadata: responseMetadata(metadata)
    };
    return encode({ jsonrpc: '2.0', id: requestId, result: result });
  }

  error(requestId: A2AResponseId, code: number, safeMessage: string): string {
    const errorValue: WireRpcError = { code: code, message: safeMessage };
    return encode({ jsonrpc: '2.0', id: requestId, error: errorValue });
  }
}
