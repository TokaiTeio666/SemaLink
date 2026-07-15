import abilityTest from './Ability.test';
import knowledgeDatabaseTest from './KnowledgeDatabase.test';
import deviceLocalRetrievalBenchmarkTest from './DeviceLocalRetrievalBenchmark.test';

export default function testsuite() {
  abilityTest();
  knowledgeDatabaseTest();
  deviceLocalRetrievalBenchmarkTest();
}
