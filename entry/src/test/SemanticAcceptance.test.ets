import { describe, expect, it } from '@ohos/hypium';
import { KnowledgePayloadValidator } from '../main/ets/contracts/knowledge/KnowledgePayloadValidator';
import { EvidenceUnit } from '../main/ets/contracts/semantic/SemanticModels';
import { EvidenceUnitFactory } from '../main/ets/knowledge/evidence/EvidenceUnitFactory';
import { L1PayloadBuilder } from '../main/ets/knowledge/payload/L1PayloadBuilder';
import { L2PayloadBuilder } from '../main/ets/knowledge/payload/L2PayloadBuilder';
import { utf8ByteLength } from '../main/ets/knowledge/payload/Utf8Sizer';
import { KnowledgeProfileBuilder } from '../main/ets/knowledge/profile/KnowledgeProfileBuilder';
import { KeywordRetrievalEngine } from '../main/ets/knowledge/retrieval/KeywordRetrievalEngine';
import { ArkDataLocalKnowledgeService } from '../main/ets/knowledge/service/ArkDataLocalKnowledgeService';
import { InMemoryBenchmarkRepository } from './benchmark/InMemoryBenchmarkRepository';
import {
  SEMANTIC_ACCEPTANCE_CASES,
  SEMANTIC_ACCEPTANCE_CHUNKS,
  SEMANTIC_ACCEPTANCE_DOCUMENTS,
  SemanticAcceptanceCase
} from './support/SemanticFixtures';

function provider(): ArkDataLocalKnowledgeService {
  return new ArkDataLocalKnowledgeService(
    new InMemoryBenchmarkRepository(SEMANTIC_ACCEPTANCE_DOCUMENTS, SEMANTIC_ACCEPTANCE_CHUNKS),
    new KeywordRetrievalEngine(), new L1PayloadBuilder(), new L2PayloadBuilder(),
    new KnowledgeProfileBuilder(), new KnowledgePayloadValidator(), new EvidenceUnitFactory(), 'fixture-device'
  );
}

function caseById(queryId: string): SemanticAcceptanceCase {
  for (const fixture of SEMANTIC_ACCEPTANCE_CASES) {
    if (fixture.queryId === queryId) {
      return fixture;
    }
  }
  throw new Error('Missing semantic fixture ' + queryId);
}

function sortedUniqueDocumentIds(units: EvidenceUnit[]): string[] {
  const unique: Set<string> = new Set<string>();
  for (const unit of units) {
    unique.add(unit.sourceDocId);
  }
  const result: string[] = [];
  unique.forEach((value: string): void => { result.push(value); });
  result.sort();
  return result;
}

function sorted(values: string[]): string[] {
  const copy: string[] = values.slice();
  copy.sort();
  return copy;
}

function levels(units: EvidenceUnit[]): string[] {
  return units.map((unit: EvidenceUnit): string => unit.level);
}

function covered(units: EvidenceUnit[]): string[] {
  const values: string[] = [];
  for (const unit of units) {
    for (const concept of unit.coveredConcepts) {
      if (values.indexOf(concept) < 0) {
        values.push(concept);
      }
    }
  }
  values.sort();
  return values;
}

function normalizedConcept(value: string): string {
  return value.toLowerCase().replace(/\s+/g, ' ').trim();
}

function aggregatedCoverage(units: EvidenceUnit[], fixture: SemanticAcceptanceCase): number {
  const aggregatedCoveredConcepts: string[] = covered(units);
  let coveredRequiredConcepts = 0;
  for (const requiredConcept of fixture.task.requiredConcepts) {
    if (aggregatedCoveredConcepts.indexOf(normalizedConcept(requiredConcept)) >= 0) {
      coveredRequiredConcepts += 1;
    }
  }
  return coveredRequiredConcepts / Math.max(1, fixture.task.requiredConcepts.length);
}

function containsLevel(units: EvidenceUnit[], level: 'L1' | 'L2'): boolean {
  for (const unit of units) {
    if (unit.level === level) {
      return true;
    }
  }
  return false;
}

function documentHasDomain(documentId: string, domain: string): boolean {
  for (const document of SEMANTIC_ACCEPTANCE_DOCUMENTS) {
    if (document.documentId === documentId && document.tags.indexOf(domain) >= 0) {
      return true;
    }
  }
  return false;
}

export default function semanticAcceptanceTest(): void {
  describe('SemanticAcceptance', () => {
    it('defines twenty-four effective tasks with the required domain and terminal metadata counts', 0, () => {
      let effective = 0;
      let localDomains = 0;
      let remoteDomains = 0;
      let l1Sufficient = 0;
      let l2Insufficient = 0;
      for (const fixture of SEMANTIC_ACCEPTANCE_CASES) {
        expect(fixture.queryId).assertEqual(fixture.task.taskId);
        if (fixture.expectedDocumentIds.length > 0) {
          effective += 1;
          if (fixture.expectedDomain === '操作系统' || fixture.expectedDomain === '数据库') {
            localDomains += 1;
          }
          if (fixture.expectedDomain === '网络' || fixture.expectedDomain === '软件测试') {
            remoteDomains += 1;
          }
        }
        if (fixture.expectedTerminalState === 'L1_SUFFICIENT') {
          l1Sufficient += 1;
        }
        if (fixture.expectedTerminalState === 'L2_INSUFFICIENT') {
          l2Insufficient += 1;
        }
      }
      expect(effective).assertEqual(24);
      expect(localDomains >= 8).assertTrue();
      expect(remoteDomains >= 8).assertTrue();
      expect(l1Sufficient >= 2).assertTrue();
      expect(l2Insufficient >= 2).assertTrue();
    });

    it('matches every expected document set and complete level sequence exactly', 0, async () => {
      const service = provider();
      for (const fixture of SEMANTIC_ACCEPTANCE_CASES) {
        const units = await service.searchEvidence(fixture.task);
        expect(JSON.stringify(sortedUniqueDocumentIds(units)))
          .assertEqual(JSON.stringify(sorted(fixture.expectedDocumentIds)));
        expect(JSON.stringify(levels(units))).assertEqual(JSON.stringify(fixture.expectedLevels));
        for (const documentId of fixture.expectedDocumentIds) {
          expect(documentHasDomain(documentId, fixture.expectedDomain)).assertTrue();
        }
      }
    });

    it('keeps order ids hashes byte costs and L1 L2 parent links stable for every effective task', 0, async () => {
      const service = provider();
      for (const fixture of SEMANTIC_ACCEPTANCE_CASES) {
        if (fixture.expectedDocumentIds.length === 0) {
          continue;
        }
        const first = await service.searchEvidence(fixture.task);
        const second = await service.searchEvidence(fixture.task);
        expect(JSON.stringify(first)).assertEqual(JSON.stringify(second));
        const ids: Set<string> = new Set<string>();
        for (const unit of first) {
          ids.add(unit.evidenceId);
          expect(unit.sourceDeviceId).assertEqual('fixture-device');
          expect(unit.byteCost).assertEqual(utf8ByteLength(JSON.stringify(unit)));
          if (unit.level === 'L2') {
            expect(unit.parentEvidenceId).assertEqual('ev-l1-' + unit.sourceDocId);
          }
        }
        expect(ids.size).assertEqual(first.length);
      }
    });

    it('keeps terminal-state metadata semantically consistent with aggregate evidence coverage', 0, async () => {
      const service = provider();
      for (const fixture of SEMANTIC_ACCEPTANCE_CASES) {
        const units = await service.searchEvidence(fixture.task);
        const coverage = aggregatedCoverage(units, fixture);
        if (fixture.expectedTerminalState === 'L1_SUFFICIENT') {
          expect(units.length > 0).assertTrue();
          expect(containsLevel(units, 'L1')).assertTrue();
          expect(coverage >= fixture.task.coverageThreshold).assertTrue();
        } else if (fixture.expectedTerminalState === 'L2_INSUFFICIENT') {
          expect(units.length > 0).assertTrue();
          expect(containsLevel(units, 'L2')).assertTrue();
          expect(coverage < fixture.task.coverageThreshold).assertTrue();
        } else if (fixture.expectedTerminalState === 'NO_MATCH') {
          expect(units.length).assertEqual(0);
        } else {
          expect(JSON.stringify(sortedUniqueDocumentIds(units)))
            .assertEqual(JSON.stringify(sorted(fixture.expectedDocumentIds)));
          expect(JSON.stringify(levels(units))).assertEqual(JSON.stringify(fixture.expectedLevels));
        }
      }
    });

    it('produces deterministic covered concept differences for distinct required concepts', 0, async () => {
      const service = provider();
      const scheduling = await service.searchEvidence(caseById('os-covered-scheduling').task);
      const aging = await service.searchEvidence(caseById('os-covered-aging').task);
      const schedulingConcepts = covered(scheduling);
      const agingConcepts = covered(aging);
      expect(JSON.stringify(schedulingConcepts) === JSON.stringify(agingConcepts)).assertFalse();
      expect(schedulingConcepts.indexOf('进程调度') >= 0).assertTrue();
      expect(agingConcepts.indexOf('老化') >= 0).assertTrue();
    });

    it('preserves privacy and all four fixed filter dimensions', 0, async () => {
      const service = provider();
      const privateGroup = await service.searchEvidence(caseById('privacy-private-group').task);
      const localOnly = await service.searchEvidence(caseById('privacy-local-only').task);
      expect(JSON.stringify(sortedUniqueDocumentIds(privateGroup))).assertEqual(JSON.stringify(['doc-os']));
      expect(JSON.stringify(sortedUniqueDocumentIds(localOnly)))
        .assertEqual(JSON.stringify(['doc-local-os', 'doc-os']));
      const serialized = JSON.stringify(SEMANTIC_ACCEPTANCE_CASES);
      expect(serialized.includes('documentIds')).assertTrue();
      expect(serialized.includes('tags')).assertTrue();
      expect(serialized.includes('modalities')).assertTrue();
      expect(serialized.includes('updatedAfter')).assertTrue();
    });
  });
}
