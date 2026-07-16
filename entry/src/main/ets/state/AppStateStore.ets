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
