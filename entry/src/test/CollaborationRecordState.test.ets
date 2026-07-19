import { describe, expect, it } from '@ohos/hypium';
import {
  CollaborationRecord,
  CollaborationRecordInput,
  CollaborationRecordStatus,
  CollaborationRecordUpdate,
  createSendingRecord,
  selectCollaborationRecord,
  sortCollaborationRecords,
  updateCollaborationRecord
} from '../main/ets/collaboration/CollaborationModels';

function makeInput(id: string, createdAt: number): CollaborationRecordInput {
  return {
    id: id,
    question: '项目状态',
    sourceDeviceName: '本机',
    targetDeviceName: 'MatePad',
    createdAt: createdAt
  };
}

export default function collaborationRecordStateTest(): void {
  describe('CollaborationRecordState', () => {
    it('createSendingRecordProducesSendingStatusAndDefaults', 0, () => {
      const record: CollaborationRecord = createSendingRecord(makeInput('request-1', 1000));
      expect(record.id).assertEqual('request-1');
      expect(record.question).assertEqual('项目状态');
      expect(record.sourceDeviceName).assertEqual('本机');
      expect(record.targetDeviceName).assertEqual('MatePad');
      expect(record.createdAt).assertEqual(1000);
      expect(record.status).assertEqual(CollaborationRecordStatus.SENDING);
      expect(record.summary).assertEqual('');
      expect(record.evidenceCount).assertEqual(0);
      expect(record.errorMessage).assertEqual('');
    });

    it('updateCollaborationRecordReturnsNewArrayAndPreservesInput', 0, () => {
      const record: CollaborationRecord = createSendingRecord(makeInput('r1', 1000));
      const originalArray: Array<CollaborationRecord> = [record];
      const updates: CollaborationRecordUpdate = {
        status: CollaborationRecordStatus.SYNCED,
        summary: '摘要',
        evidenceCount: 2,
        errorMessage: ''
      };
      const updated: Array<CollaborationRecord> = updateCollaborationRecord('r1', originalArray, updates);

      expect(updated.length).assertEqual(1);
      expect(updated[0].status).assertEqual(CollaborationRecordStatus.SYNCED);
      expect(updated[0].summary).assertEqual('摘要');
      expect(updated[0].evidenceCount).assertEqual(2);
      expect(updated[0].errorMessage).assertEqual('');

      // Input array and original record must remain unchanged (immutable).
      expect(originalArray[0].status).assertEqual(CollaborationRecordStatus.SENDING);
      expect(originalArray[0].summary).assertEqual('');
      expect(record.status).assertEqual(CollaborationRecordStatus.SENDING);
      expect(record.evidenceCount).assertEqual(0);
    });

    it('updateCollaborationRecordLeavesOtherRecordsUntouched', 0, () => {
      const r1: CollaborationRecord = createSendingRecord(makeInput('r1', 1000));
      const r2: CollaborationRecord = createSendingRecord(makeInput('r2', 2000));
      const records: Array<CollaborationRecord> = [r1, r2];
      const updated: Array<CollaborationRecord> = updateCollaborationRecord('r2', records, {
        status: CollaborationRecordStatus.SYNCED,
        summary: '完成'
      });

      expect(updated.length).assertEqual(2);
      expect(updated[0].id).assertEqual('r1');
      expect(updated[0].status).assertEqual(CollaborationRecordStatus.SENDING);
      expect(updated[0].summary).assertEqual('');
      expect(updated[1].id).assertEqual('r2');
      expect(updated[1].status).assertEqual(CollaborationRecordStatus.SYNCED);
      expect(updated[1].summary).assertEqual('完成');

      // Input must remain unchanged.
      expect(records[1].status).assertEqual(CollaborationRecordStatus.SENDING);
      expect(records[1].summary).assertEqual('');
    });

    it('selectCollaborationRecordReturnsIdWhenFound', 0, () => {
      const r1: CollaborationRecord = createSendingRecord(makeInput('r1', 1000));
      const r2: CollaborationRecord = createSendingRecord(makeInput('r2', 2000));
      const records: Array<CollaborationRecord> = [r1, r2];

      expect(selectCollaborationRecord('r2', records, '')).assertEqual('r2');
      expect(selectCollaborationRecord('r1', records, 'r2')).assertEqual('r1');
    });

    it('selectCollaborationRecordIsNoOpForUnknownId', 0, () => {
      const r1: CollaborationRecord = createSendingRecord(makeInput('r1', 1000));
      const records: Array<CollaborationRecord> = [r1];

      const before: string = 'r1';
      const after: string = selectCollaborationRecord('missing', records, before);
      expect(after).assertEqual(before);
    });

    it('sortCollaborationRecordsReturnsNewestFirstAndPreservesInput', 0, () => {
      const r1: CollaborationRecord = createSendingRecord(makeInput('r1', 1000));
      const r2: CollaborationRecord = createSendingRecord(makeInput('r2', 2000));
      const r3: CollaborationRecord = createSendingRecord(makeInput('r3', 1500));
      const records: Array<CollaborationRecord> = [r1, r2, r3];

      const sorted: Array<CollaborationRecord> = sortCollaborationRecords(records);
      expect(sorted.length).assertEqual(3);
      expect(sorted[0].id).assertEqual('r2');
      expect(sorted[1].id).assertEqual('r3');
      expect(sorted[2].id).assertEqual('r1');

      // Input array order must remain unchanged.
      expect(records[0].id).assertEqual('r1');
      expect(records[1].id).assertEqual('r2');
      expect(records[2].id).assertEqual('r3');
    });

    it('updateCollaborationRecordIsNoOpForUnknownId', 0, () => {
      const r1: CollaborationRecord = createSendingRecord(makeInput('r1', 1000));
      const updated: Array<CollaborationRecord> = updateCollaborationRecord(
        'missing', [r1], { summary: '不应被写入' }
      );
      expect(updated.length).assertEqual(1);
      expect(updated[0].summary).assertEqual('');
      expect(updated[0].status).assertEqual(CollaborationRecordStatus.SENDING);
    });

    it('statusEnumValuesAreStableForUiMapping', 0, () => {
      // The UI statusLabel/statusColor switch statements depend on each enum value
      // being a unique stable string. Verify each value matches its expected literal.
      // Since all five expected literals are different, these assertions implicitly
      // verify pairwise uniqueness — if two members shared a value, one would fail.
      expect(CollaborationRecordStatus.SENDING).assertEqual('SENDING');
      expect(CollaborationRecordStatus.SYNCED).assertEqual('SYNCED');
      expect(CollaborationRecordStatus.OFFLINE).assertEqual('OFFLINE');
      expect(CollaborationRecordStatus.FAILED).assertEqual('FAILED');
      expect(CollaborationRecordStatus.TIMEOUT).assertEqual('TIMEOUT');
    });

    it('updateCollaborationRecordPreservesIdentityFields', 0, () => {
      const record: CollaborationRecord = createSendingRecord(makeInput('r1', 1000));
      const updated: Array<CollaborationRecord> = updateCollaborationRecord('r1', [record], {
        status: CollaborationRecordStatus.SYNCED,
        summary: '新摘要',
        evidenceCount: 5,
        errorMessage: '错误信息'
      });
      expect(updated.length).assertEqual(1);
      // Identity fields must be preserved (not overwritten by the update).
      expect(updated[0].id).assertEqual('r1');
      expect(updated[0].question).assertEqual('项目状态');
      expect(updated[0].sourceDeviceName).assertEqual('本机');
      expect(updated[0].targetDeviceName).assertEqual('MatePad');
      expect(updated[0].createdAt).assertEqual(1000);
      // Mutable fields should reflect the update.
      expect(updated[0].status).assertEqual(CollaborationRecordStatus.SYNCED);
      expect(updated[0].summary).assertEqual('新摘要');
      expect(updated[0].evidenceCount).assertEqual(5);
      expect(updated[0].errorMessage).assertEqual('错误信息');
      // The original record must remain unchanged (immutable).
      expect(record.status).assertEqual(CollaborationRecordStatus.SENDING);
      expect(record.summary).assertEqual('');
      expect(record.evidenceCount).assertEqual(0);
      expect(record.errorMessage).assertEqual('');
    });

    it('sortCollaborationRecordsIsStableForEqualTimestamps', 0, () => {
      const r1: CollaborationRecord = createSendingRecord(makeInput('r1', 1000));
      const r2: CollaborationRecord = createSendingRecord(makeInput('r2', 1000));
      const r3: CollaborationRecord = createSendingRecord(makeInput('r3', 1000));
      const records: Array<CollaborationRecord> = [r3, r1, r2];
      const sorted: Array<CollaborationRecord> = sortCollaborationRecords(records);
      expect(sorted.length).assertEqual(3);
      // Equal timestamps sort by id ascending (stable tiebreaker).
      expect(sorted[0].id).assertEqual('r1');
      expect(sorted[1].id).assertEqual('r2');
      expect(sorted[2].id).assertEqual('r3');
      // Input array order must remain unchanged.
      expect(records[0].id).assertEqual('r3');
      expect(records[1].id).assertEqual('r1');
      expect(records[2].id).assertEqual('r2');
    });
  });
}
