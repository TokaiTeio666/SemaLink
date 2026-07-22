import { AppSnapshot, INITIAL_SNAPSHOT } from '../model/AppModels';

export type StateListener = (snapshot: AppSnapshot) => void;
export interface StateUpdate extends Partial<AppSnapshot> {
  clearError?: boolean;
}

export class AppStateStore {
  private listeners: Array<StateListener> = [];
  private current: AppSnapshot = INITIAL_SNAPSHOT;

  snapshot(): AppSnapshot {
    return this.current;
  }

  subscribe(listener: StateListener): () => void {
    this.listeners.push(listener);
    listener(this.current);
    return () => {
      this.listeners = this.listeners.filter((item: StateListener) => item !== listener);
    };
  }

  update(next: StateUpdate): void {
    const updated: AppSnapshot = {
      peerStatuses: next.peerStatuses ?? this.current.peerStatuses,
      activePeerCount: next.activePeerCount ?? this.current.activePeerCount,
      evidenceSourceDeviceIds: next.evidenceSourceDeviceIds ?? this.current.evidenceSourceDeviceIds,
      evidenceConflictCount: next.evidenceConflictCount ?? this.current.evidenceConflictCount,
      finalSufficiency: next.finalSufficiency ?? this.current.finalSufficiency,
      totalTaskMs: next.totalTaskMs ?? this.current.totalTaskMs,
      enteredL2: next.enteredL2 ?? this.current.enteredL2,
      role: next.role ?? this.current.role,
      connectionState: next.connectionState ?? this.current.connectionState,
      question: next.question ?? this.current.question,
      summary: next.summary ?? this.current.summary,
      requestId: next.requestId ?? this.current.requestId,
      roundTripMs: next.roundTripMs ?? this.current.roundTripMs,
      bytesSent: next.bytesSent ?? this.current.bytesSent,
      bytesReceived: next.bytesReceived ?? this.current.bytesReceived,
      peerDeviceName: next.peerDeviceName ?? this.current.peerDeviceName,
      peerDeviceIdMasked: next.peerDeviceIdMasked ?? this.current.peerDeviceIdMasked,
      knowledgeInitialized: next.knowledgeInitialized ?? this.current.knowledgeInitialized,
      knowledgeBusy: next.knowledgeBusy ?? this.current.knowledgeBusy,
      knowledgeIndexState: next.knowledgeIndexState ?? this.current.knowledgeIndexState,
      knowledgeDocumentCount: next.knowledgeDocumentCount ?? this.current.knowledgeDocumentCount,
      knowledgeChunkCount: next.knowledgeChunkCount ?? this.current.knowledgeChunkCount,
      knowledgeMessage: next.knowledgeMessage ?? this.current.knowledgeMessage,
      knowledgeQueryStatus: next.knowledgeQueryStatus ?? this.current.knowledgeQueryStatus,
      knowledgeLevel: next.knowledgeLevel ?? this.current.knowledgeLevel,
      knowledgeItems: next.knowledgeItems ?? this.current.knowledgeItems,
      knowledgeRetrievalMs: next.knowledgeRetrievalMs ?? this.current.knowledgeRetrievalMs,
      knowledgeTruncated: next.knowledgeTruncated ?? this.current.knowledgeTruncated,
      knowledgeError: next.knowledgeError ?? this.current.knowledgeError,
      collaborationRecords: next.collaborationRecords ?? this.current.collaborationRecords,
      selectedCollaborationRecordId: next.selectedCollaborationRecordId ?? this.current.selectedCollaborationRecordId,
      taskId: next.taskId ?? this.current.taskId,
      taskPhase: next.taskPhase ?? this.current.taskPhase,
      taskRound: next.taskRound ?? this.current.taskRound,
      taskFeedback: next.taskFeedback ?? this.current.taskFeedback,
      taskCoverage: next.taskCoverage ?? this.current.taskCoverage,
      taskConfidence: next.taskConfidence ?? this.current.taskConfidence,
      taskMissingConcepts: next.taskMissingConcepts ?? this.current.taskMissingConcepts,
      selectedDeviceId: next.selectedDeviceId ?? this.current.selectedDeviceId,
      evidenceBytes: next.evidenceBytes ?? this.current.evidenceBytes,
      taskPrivacyLevel: next.taskPrivacyLevel ?? this.current.taskPrivacyLevel,
      routeScore: next.routeScore ?? this.current.routeScore,
      routeSemanticMatch: next.routeSemanticMatch ?? this.current.routeSemanticMatch,
      routeFilterMatch: next.routeFilterMatch ?? this.current.routeFilterMatch,
      routeFreshness: next.routeFreshness ?? this.current.routeFreshness,
      routeNormalizedRtt: next.routeNormalizedRtt ?? this.current.routeNormalizedRtt,
      routeLoad: next.routeLoad ?? this.current.routeLoad,
      routePrivacyRisk: next.routePrivacyRisk ?? this.current.routePrivacyRisk,
      firstResultLatencyMs: next.firstResultLatencyMs ?? this.current.firstResultLatencyMs,
      completionLatencyMs: next.completionLatencyMs ?? this.current.completionLatencyMs,
      latencySamplesMs: next.latencySamplesMs ?? this.current.latencySamplesMs,
      protocolBytes: next.protocolBytes ?? this.current.protocolBytes,
      error: this.current.error
    };
    if (next.clearError === true) {
      updated.error = undefined;
    } else if (next.error !== undefined) {
      updated.error = next.error;
    }
    this.current = updated;
    this.listeners.forEach((listener: StateListener) => listener(this.current));
  }
}
