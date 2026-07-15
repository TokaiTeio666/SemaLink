import abilityTest from './Ability.test';
import collaborationAbilityTest from './CollaborationAbility.test';
import indexPageTest from './IndexPage.test';
import knowledgeDatabaseTest from './KnowledgeDatabase.test';
import deviceLocalRetrievalBenchmarkTest from './DeviceLocalRetrievalBenchmark.test';

export default function testsuite() {
  abilityTest();
  collaborationAbilityTest();
  indexPageTest();
  knowledgeDatabaseTest();
  deviceLocalRetrievalBenchmarkTest();
}
