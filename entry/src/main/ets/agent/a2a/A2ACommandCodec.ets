import { AppError, ErrorStage } from '../../common/AppError';
import {
  A2ACancelCommand,
  A2ACommand,
  A2ACommandKind,
  A2AConversationCommand,
  A2AMetadata,
  A2ARequestId
} from './A2AModels';

const MAX_QUERY_CHARS: number = 1000;

function protocolError(code: string, message: string): AppError {
  return new AppError(code, message, ErrorStage.PROTOCOL, true);
}

function requireRecord(value: Object | undefined): Record<string, Object> {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw protocolError('E_A2A_PARAMS', 'A2A object field is invalid');
  }
  return value as Record<string, Object>;
}

function requireString(record: Record<string, Object>, field: string): string {
  const value: Object | undefined = record[field];
  if (typeof value !== 'string' || value.length === 0) {
    throw protocolError('E_A2A_PARAMS', 'A2A string field is invalid');
  }
  return value;
}

function optionalString(record: Record<string, Object>, field: string): string | undefined {
  const value: Object | undefined = record[field];
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== 'string' || value.length === 0) {
    throw protocolError('E_A2A_PARAMS', 'A2A optional string field is invalid');
  }
  return value;
}

function requireRequestId(record: Record<string, Object>): A2ARequestId {
  const value: Object | undefined = record['id'];
  if (typeof value === 'string' && value.length > 0) {
    return value;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  throw protocolError('E_A2A_REQUEST', 'JSON-RPC request id is invalid');
}

function decodeMetadata(value: Object | undefined): A2AMetadata {
  const metadata: Record<string, Object> = requireRecord(value);
  return new A2AMetadata(requireString(metadata, 'traceId'), requireString(metadata, 'agentId'));
}

export class A2ACommandCodec {
  decode(data: string): A2ACommand {
    let parsed: Object;
    try {
      parsed = JSON.parse(data) as Object;
    } catch (_error) {
      throw protocolError('E_A2A_PARSE', 'Invalid JSON-RPC payload');
    }
    const envelope: Record<string, Object> = requireRecord(parsed);
    if (requireString(envelope, 'jsonrpc') !== '2.0') {
      throw protocolError('E_A2A_REQUEST', 'Unsupported JSON-RPC version');
    }
    const requestId: A2ARequestId = requireRequestId(envelope);
    const method: string = requireString(envelope, 'method');
    const params: Record<string, Object> = requireRecord(envelope['params']);
    if (method === A2ACommandKind.MESSAGE_STREAM) {
      return this.decodeMessage(requestId, params);
    }
    if (method === A2ACommandKind.TASK_CANCEL) {
      return new A2ACancelCommand(requestId, requireString(params, 'id'), decodeMetadata(params['metadata']));
    }
    throw protocolError('E_A2A_UNSUPPORTED', 'A2A method is unsupported');
  }

  private decodeMessage(requestId: A2ARequestId, params: Record<string, Object>): A2AConversationCommand {
    const message: Record<string, Object> = requireRecord(params['message']);
    if (requireString(message, 'role') !== 'ROLE_USER') {
      throw protocolError('E_A2A_PARAMS', 'Only user messages are accepted');
    }
    const partsValue: Object | undefined = message['parts'];
    if (partsValue === undefined || !Array.isArray(partsValue)) {
      throw protocolError('E_A2A_PARAMS', 'Message parts are invalid');
    }
    const parts: Object[] = partsValue as Object[];
    let queryText: string = '';
    for (const value of parts) {
      const part: Record<string, Object> = requireRecord(value);
      const text: Object | undefined = part['text'];
      const mediaType: Object | undefined = part['mediaType'];
      const data: Object | undefined = part['data'];
      const url: Object | undefined = part['url'];
      if (typeof text !== 'string' || data !== undefined || url !== undefined ||
        (mediaType !== undefined && mediaType !== 'text/plain')) {
        throw protocolError('E_A2A_PARAMS', 'Unsupported A2A message part');
      }
      queryText = queryText.length === 0 ? text : queryText + '\n' + text;
    }
    const normalized: string = queryText.trim();
    if (normalized.length === 0 || normalized.length > MAX_QUERY_CHARS) {
      throw protocolError('E_A2A_PARAMS', 'A2A query text is invalid');
    }
    return new A2AConversationCommand(
      requestId,
      requireString(message, 'messageId'),
      normalized,
      decodeMetadata(params['metadata']),
      optionalString(message, 'contextId'),
      optionalString(message, 'taskId')
    );
  }
}
