export enum CollaborationRecordStatus {
  SENDING = 'SENDING',
  SYNCED = 'SYNCED',
  OFFLINE = 'OFFLINE',
  FAILED = 'FAILED',
  TIMEOUT = 'TIMEOUT'
}

export interface CollaborationRecord {
  id: string;
  question: string;
  sourceDeviceName: string;
  sourceDeviceNames: string[];
  targetDeviceName: string;
  createdAt: number;
  status: CollaborationRecordStatus;
  summary: string;
  evidenceCount: number;
  errorMessage: string;
}

export interface CollaborationRecordInput {
  id: string;
  question: string;
  sourceDeviceName: string;
  sourceDeviceNames?: string[];
  targetDeviceName: string;
  createdAt: number;
}

export interface CollaborationRecordUpdate {
  status?: CollaborationRecordStatus;
  summary?: string;
  evidenceCount?: number;
  errorMessage?: string;
}

function cloneRecord(source: CollaborationRecord): CollaborationRecord {
  return {
    id: source.id,
    question: source.question,
    sourceDeviceName: source.sourceDeviceName,
    sourceDeviceNames: (source.sourceDeviceNames ?? []).slice(),
    targetDeviceName: source.targetDeviceName,
    createdAt: source.createdAt,
    status: source.status,
    summary: source.summary,
    evidenceCount: source.evidenceCount,
    errorMessage: source.errorMessage
  };
}

export function createSendingRecord(input: CollaborationRecordInput): CollaborationRecord {
  return {
    id: input.id,
    question: input.question,
    sourceDeviceName: input.sourceDeviceName,
    sourceDeviceNames: input.sourceDeviceNames?.slice() ?? [],
    targetDeviceName: input.targetDeviceName,
    createdAt: input.createdAt,
    status: CollaborationRecordStatus.SENDING,
    summary: '',
    evidenceCount: 0,
    errorMessage: ''
  };
}

export function updateCollaborationRecord(
  id: string,
  records: Array<CollaborationRecord>,
  updates: CollaborationRecordUpdate
): Array<CollaborationRecord> {
  const result: Array<CollaborationRecord> = [];
  for (let i = 0; i < records.length; i++) {
    const current: CollaborationRecord = records[i];
    if (current.id === id) {
      result.push({
        id: current.id,
        question: current.question,
        sourceDeviceName: current.sourceDeviceName,
        sourceDeviceNames: (current.sourceDeviceNames ?? []).slice(),
        targetDeviceName: current.targetDeviceName,
        createdAt: current.createdAt,
        status: updates.status ?? current.status,
        summary: updates.summary ?? current.summary,
        evidenceCount: updates.evidenceCount ?? current.evidenceCount,
        errorMessage: updates.errorMessage ?? current.errorMessage
      });
    } else {
      result.push(cloneRecord(current));
    }
  }
  return result;
}

export function selectCollaborationRecord(
  id: string,
  records: Array<CollaborationRecord>,
  currentSelectedId: string
): string {
  for (let i = 0; i < records.length; i++) {
    if (records[i].id === id) {
      return id;
    }
  }
  return currentSelectedId;
}

export function sortCollaborationRecords(
  records: Array<CollaborationRecord>
): Array<CollaborationRecord> {
  const result: Array<CollaborationRecord> = [];
  for (let i = 0; i < records.length; i++) {
    result.push(cloneRecord(records[i]));
  }
  result.sort((left: CollaborationRecord, right: CollaborationRecord): number => {
    if (left.createdAt !== right.createdAt) {
      return right.createdAt - left.createdAt;
    }
    return left.id < right.id ? -1 : left.id > right.id ? 1 : 0;
  });
  return result;
}
