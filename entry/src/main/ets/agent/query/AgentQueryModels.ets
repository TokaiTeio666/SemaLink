import { EvidenceUnit, TaskSufficiencyResult } from '../../contracts/semantic/SemanticModels';

export enum AgentQueryScope {
  LOCAL_ONLY = 'LOCAL_ONLY',
  LOCAL_AND_REMOTE = 'LOCAL_AND_REMOTE',
  REMOTE_ONLY = 'REMOTE_ONLY'
}

export class AgentQueryRequest {
  readonly internalTaskId: string;
  readonly queryText: string;
  readonly scope: AgentQueryScope;

  constructor(internalTaskId: string, queryText: string, scope: AgentQueryScope) {
    this.internalTaskId = internalTaskId;
    this.queryText = queryText;
    this.scope = scope;
  }
}

export class AgentQueryResult {
  readonly internalTaskId: string;
  readonly evidence: EvidenceUnit[];
  readonly sufficiency: TaskSufficiencyResult;
  readonly queriedLocal: boolean;
  readonly queriedRemote: boolean;
  readonly remoteAvailable: boolean;
  readonly failedSources: string[];
  readonly elapsedMs: number;
  readonly remoteEvidenceIds: string[];
  readonly scope: AgentQueryScope;

  constructor(internalTaskId: string, evidence: EvidenceUnit[], sufficiency: TaskSufficiencyResult,
    queriedLocal: boolean, queriedRemote: boolean, remoteAvailable: boolean,
    failedSources: string[], elapsedMs: number, remoteEvidenceIds: string[],
    scope: AgentQueryScope = AgentQueryScope.LOCAL_AND_REMOTE) {
    this.internalTaskId = internalTaskId;
    this.evidence = evidence;
    this.sufficiency = sufficiency;
    this.queriedLocal = queriedLocal;
    this.queriedRemote = queriedRemote;
    this.remoteAvailable = remoteAvailable;
    this.failedSources = failedSources;
    this.elapsedMs = elapsedMs;
    this.remoteEvidenceIds = remoteEvidenceIds;
    this.scope = scope;
  }
}
