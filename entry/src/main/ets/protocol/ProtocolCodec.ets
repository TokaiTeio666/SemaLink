import { AppError, ErrorStage } from '../common/AppError';
import {
  ProtocolEnvelope, ProtocolPayload, MessageType, QueryPayload, QueryAckPayload,
  ResultPayload, ErrorPayload, PROTOCOL_VERSION, MAX_MESSAGE_BYTES, MAX_QUESTION_CHARS,
  MAX_SUMMARY_CHARS
} from './ProtocolModels';
import { LocalKnowledgeResult } from '../contracts/knowledge/KnowledgeModels';

const VALID_MESSAGE_TYPES: string[] = ['QUERY', 'QUERY_ACK', 'RESULT', 'ERROR'];

function countUtf8Bytes(text: string): number {
  let byteCount: number = 0;
  for (let i = 0; i < text.length; i++) {
    const codePoint: number | undefined = text.codePointAt(i);
    if (codePoint === undefined) {
      continue;
    }
    if (codePoint <= 0x7F) {
      byteCount += 1;
    } else if (codePoint <= 0x7FF) {
      byteCount += 2;
    } else if (codePoint <= 0xFFFF) {
      byteCount += 3;
      if (codePoint >= 0xD800 && codePoint <= 0xDBFF) {
        i++; // skip low surrogate
      }
    } else {
      byteCount += 4;
      i++; // skip low surrogate
    }
  }
  return byteCount;
}

function checkRequiredFields(raw: Record<string, Object>): void {
  // ArkTS doesn't support 'in' operator; check each field individually via typeof
  if (raw['version'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: version', ErrorStage.PROTOCOL, false);
  }
  if (raw['type'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: type', ErrorStage.PROTOCOL, false);
  }
  if (raw['messageId'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: messageId', ErrorStage.PROTOCOL, false);
  }
  if (raw['sessionId'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: sessionId', ErrorStage.PROTOCOL, false);
  }
  if (raw['requestId'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: requestId', ErrorStage.PROTOCOL, false);
  }
  if (raw['sentAt'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: sentAt', ErrorStage.PROTOCOL, false);
  }
  if (raw['payload'] === undefined) {
    throw new AppError('E_PROTOCOL_INVALID', '缺少必要字段: payload', ErrorStage.PROTOCOL, false);
  }
}

export class ProtocolCodec {
  encode(envelope: ProtocolEnvelope): string {
    const text: string = JSON.stringify(envelope);
    if (countUtf8Bytes(text) > MAX_MESSAGE_BYTES) {
      throw new AppError('E_PROTOCOL_INVALID', '消息超过 16 KiB 上限', ErrorStage.PROTOCOL, false);
    }
    return text;
  }

  decode(text: string): ProtocolEnvelope {
    if (countUtf8Bytes(text) > MAX_MESSAGE_BYTES) {
      throw new AppError('E_PROTOCOL_INVALID', '消息超过 16 KiB 上限', ErrorStage.PROTOCOL, false);
    }

    let raw: Record<string, Object>;
    try {
      raw = JSON.parse(text) as Record<string, Object>;
    } catch (_e) {
      throw new AppError('E_PROTOCOL_INVALID', 'JSON 解析失败', ErrorStage.PROTOCOL, false);
    }

    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
      throw new AppError('E_PROTOCOL_INVALID', '根对象必须为 JSON 对象', ErrorStage.PROTOCOL, false);
    }

    if (raw['version'] !== PROTOCOL_VERSION) {
      throw new AppError('E_PROTOCOL_INVALID', '未知协议版本', ErrorStage.PROTOCOL, false);
    }

    const typeVal: string = raw['type'] as string;
    if (typeof raw['type'] !== 'string' || VALID_MESSAGE_TYPES.indexOf(typeVal) === -1) {
      throw new AppError('E_PROTOCOL_INVALID', '未知消息类型', ErrorStage.PROTOCOL, false);
    }

    checkRequiredFields(raw);

    if (typeof raw['messageId'] !== 'string' || (raw['messageId'] as string).length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'messageId 无效', ErrorStage.PROTOCOL, false);
    }
    if (typeof raw['sessionId'] !== 'string' || (raw['sessionId'] as string).length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'sessionId 无效', ErrorStage.PROTOCOL, false);
    }
    if (typeof raw['requestId'] !== 'string' || (raw['requestId'] as string).length === 0) {
      throw new AppError('E_PROTOCOL_INVALID', 'requestId 无效', ErrorStage.PROTOCOL, false);
    }
    if (typeof raw['sentAt'] !== 'number') {
      throw new AppError('E_PROTOCOL_INVALID', 'sentAt 无效', ErrorStage.PROTOCOL, false);
    }

    const messageType: MessageType = raw['type'] as MessageType;
    const rawPayload: Record<string, Object> = raw['payload'] as Record<string, Object>;
    if (typeof rawPayload !== 'object' || rawPayload === null || Array.isArray(rawPayload)) {
      throw new AppError('E_PROTOCOL_INVALID', 'payload 无效', ErrorStage.PROTOCOL, false);
    }

    const payload: ProtocolPayload = this.validatePayload(messageType, rawPayload);
    const result: ProtocolEnvelope = {
      version: raw['version'] as string,
      type: messageType,
      messageId: raw['messageId'] as string,
      sessionId: raw['sessionId'] as string,
      requestId: raw['requestId'] as string,
      sentAt: raw['sentAt'] as number,
      payload: payload
    };
    return result;
  }

  private validatePayload(type: MessageType, raw: Record<string, Object>): ProtocolPayload {
    switch (type) {
      case MessageType.QUERY: {
        if (typeof raw['question'] !== 'string') {
          throw new AppError('E_PROTOCOL_INVALID', 'question 字段无效', ErrorStage.PROTOCOL, false);
        }
        const question: string = (raw['question'] as string).trim();
        if (question.length === 0 || question.length > MAX_QUESTION_CHARS) {
          throw new AppError('E_QUERY_INVALID', '问题长度无效', ErrorStage.QUERY, true);
        }
        return { question: question } as QueryPayload;
      }
      case MessageType.QUERY_ACK: {
        if (typeof raw['acceptedAt'] !== 'number') {
          throw new AppError('E_PROTOCOL_INVALID', 'acceptedAt 字段无效', ErrorStage.PROTOCOL, false);
        }
        return { acceptedAt: raw['acceptedAt'] as number } as QueryAckPayload;
      }
      case MessageType.RESULT: {
        if (typeof raw['summary'] !== 'string') {
          throw new AppError('E_PROTOCOL_INVALID', 'summary 字段无效', ErrorStage.PROTOCOL, false);
        }
        if (typeof raw['sourceDeviceAlias'] !== 'string') {
          throw new AppError('E_PROTOCOL_INVALID', 'sourceDeviceAlias 字段无效', ErrorStage.PROTOCOL, false);
        }
        if (typeof raw['processingMs'] !== 'number') {
          throw new AppError('E_PROTOCOL_INVALID', 'processingMs 字段无效', ErrorStage.PROTOCOL, false);
        }
        const summary: string = raw['summary'] as string;
        if (summary.length === 0 || summary.length > MAX_SUMMARY_CHARS) {
          throw new AppError('E_PROTOCOL_INVALID', '摘要长度无效', ErrorStage.PROTOCOL, false);
        }
        const resultPayload: ResultPayload = {
          summary: summary,
          sourceDeviceAlias: raw['sourceDeviceAlias'] as string,
          processingMs: raw['processingMs'] as number
        };
        if (raw['resultType'] !== undefined) {
          if (raw['resultType'] !== 'SUMMARY' && raw['resultType'] !== 'KNOWLEDGE') {
            throw new AppError('E_PROTOCOL_INVALID', 'resultType is invalid', ErrorStage.PROTOCOL, false);
          }
          resultPayload.resultType = raw['resultType'] as 'SUMMARY' | 'KNOWLEDGE';
        }
        if (resultPayload.resultType === 'KNOWLEDGE') {
          resultPayload.knowledgeResult = this.validateKnowledgeResult(raw['knowledgeResult']);
        }
        return resultPayload;
      }
      case MessageType.ERROR: {
        if (typeof raw['code'] !== 'string' || (raw['code'] as string).length === 0) {
          throw new AppError('E_PROTOCOL_INVALID', 'error code 无效', ErrorStage.PROTOCOL, false);
        }
        if (typeof raw['message'] !== 'string' || (raw['message'] as string).length === 0) {
          throw new AppError('E_PROTOCOL_INVALID', 'error message 无效', ErrorStage.PROTOCOL, false);
        }
        return {
          code: raw['code'] as string,
          message: raw['message'] as string
        } as ErrorPayload;
      }
      default:
        throw new AppError('E_PROTOCOL_INVALID', '未知消息类型', ErrorStage.PROTOCOL, false);
    }
  }

  createQuery(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: QueryPayload): ProtocolEnvelope {
    const question: string = payload.question.trim();
    if (question.length === 0 || question.length > MAX_QUESTION_CHARS) {
      throw new AppError('E_QUERY_INVALID', '问题长度无效', ErrorStage.QUERY, true);
    }
    const queryPayload: QueryPayload = { question: question };
    return {
      version: PROTOCOL_VERSION, type: MessageType.QUERY, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: queryPayload
    };
  }

  createAck(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: QueryAckPayload): ProtocolEnvelope {
    return {
      version: PROTOCOL_VERSION, type: MessageType.QUERY_ACK, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  createResult(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: ResultPayload): ProtocolEnvelope {
    if (payload.summary.length === 0 || payload.summary.length > MAX_SUMMARY_CHARS) {
      throw new AppError('E_QUERY_INVALID', '摘要长度无效', ErrorStage.QUERY, true);
    }
    if (payload.resultType === 'KNOWLEDGE' &&
      (payload.knowledgeResult === undefined || payload.knowledgeResult.requestId !== requestId)) {
      throw new AppError('E_QUERY_INVALID', 'Knowledge result does not match request', ErrorStage.QUERY, true);
    }
    return {
      version: PROTOCOL_VERSION, type: MessageType.RESULT, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  createError(messageId: string, sessionId: string, requestId: string,
    sentAt: number, payload: ErrorPayload): ProtocolEnvelope {
    return {
      version: PROTOCOL_VERSION, type: MessageType.ERROR, messageId: messageId, sessionId: sessionId,
      requestId: requestId, sentAt: sentAt, payload: payload
    };
  }

  private validateKnowledgeResult(value: Object | undefined): LocalKnowledgeResult {
    if (value === undefined || typeof value !== 'object' || value === null || Array.isArray(value)) {
      throw new AppError('E_PROTOCOL_INVALID', 'knowledgeResult is invalid', ErrorStage.PROTOCOL, false);
    }
    const raw: Record<string, Object> = value as Record<string, Object>;
    if (raw['contractVersion'] !== '1.0' || typeof raw['requestId'] !== 'string' ||
      (raw['level'] !== 'L1' && raw['level'] !== 'L2') || typeof raw['itemCount'] !== 'number' ||
      typeof raw['payloadJson'] !== 'string' || typeof raw['truncated'] !== 'boolean' ||
      typeof raw['retrievalMs'] !== 'number' || typeof raw['indexVersion'] !== 'string' ||
      typeof raw['generatedAt'] !== 'number') {
      throw new AppError('E_PROTOCOL_INVALID', 'knowledgeResult content is invalid', ErrorStage.PROTOCOL, false);
    }
    try {
      JSON.parse(raw['payloadJson'] as string);
    } catch (_error) {
      throw new AppError('E_PROTOCOL_INVALID', 'knowledgeResult payloadJson is invalid', ErrorStage.PROTOCOL, false);
    }
    return {
      contractVersion: '1.0',
      requestId: raw['requestId'] as string,
      level: raw['level'] as 'L1' | 'L2',
      itemCount: raw['itemCount'] as number,
      payloadJson: raw['payloadJson'] as string,
      truncated: raw['truncated'] as boolean,
      retrievalMs: raw['retrievalMs'] as number,
      indexVersion: raw['indexVersion'] as string,
      generatedAt: raw['generatedAt'] as number
    };
  }
}
