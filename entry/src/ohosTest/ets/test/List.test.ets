import abilityTest from './Ability.test';
import collaborationAbilityTest from './CollaborationAbility.test';
import indexPageTest from './IndexPage.test';
import knowledgeDatabaseTest from './KnowledgeDatabase.test';
import deviceLocalRetrievalBenchmarkTest from './DeviceLocalRetrievalBenchmark.test';
import semanticKnowledgeProviderDeviceTest from './SemanticKnowledgeProvider.test';
import rdbCandidateSearchTest from './RdbCandidateSearch.test';
import knowledgeDatabaseIndexTest from './KnowledgeDatabaseIndex.test';
import rdbDocumentRepositoryTransactionTest from './RdbDocumentRepositoryTransaction.test';

export default function testsuite() {
  abilityTest();
  collaborationAbilityTest();
  indexPageTest();
  knowledgeDatabaseTest();
  deviceLocalRetrievalBenchmarkTest();
  semanticKnowledgeProviderDeviceTest();
  rdbCandidateSearchTest();
  knowledgeDatabaseIndexTest();
  rdbDocumentRepositoryTransactionTest();
}
