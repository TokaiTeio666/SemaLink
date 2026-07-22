import { LocalKnowledgeQuery, LocalKnowledgeResult, KnowledgeProfile } from './KnowledgeModels';

export interface LocalKnowledgeGateway {
  query(request: LocalKnowledgeQuery): Promise<LocalKnowledgeResult>;
  getKnowledgeProfile(): Promise<KnowledgeProfile>;
}
