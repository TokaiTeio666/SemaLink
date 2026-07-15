import { KnowledgeDomain, KnowledgeProfile } from '../../contracts/knowledge/KnowledgeModels';
import { KnowledgeMetadata, RepositoryStatistics } from '../storage/DocumentRepository';

export class KnowledgeProfileBuilder {
  buildProfile(statistics: RepositoryStatistics, metadata: KnowledgeMetadata): KnowledgeProfile {
    const domains: KnowledgeDomain[] = [];
    let maximum = 0;
    for (const domain of statistics.domainCounts) {
      maximum = Math.max(maximum, domain.documentCount);
    }
    for (const domain of statistics.domainCounts) {
      domains.push({
        tag: domain.tag,
        weight: maximum === 0 ? 0 : Math.round(domain.documentCount / maximum * 10000) / 10000,
        documentCount: domain.documentCount
      });
    }
    domains.sort((left: KnowledgeDomain, right: KnowledgeDomain): number => {
      if (right.weight !== left.weight) {
        return right.weight - left.weight;
      }
      return left.tag.localeCompare(right.tag);
    });
    return {
      contractVersion: '1.0',
      profileVersion: metadata.profileVersion,
      indexState: statistics.documentCount === 0 && metadata.indexState === 'READY' ? 'EMPTY' : metadata.indexState,
      knowledgeDomains: domains.slice(0, 20),
      documentCount: statistics.documentCount,
      chunkCount: statistics.chunkCount,
      modalities: statistics.modalities,
      retrievalModes: ['keyword'],
      supportedLevels: ['L1', 'L2'],
      indexVersion: metadata.indexVersion,
      embeddingModelVersion: '',
      updatedAt: metadata.updatedAt
    };
  }
}
