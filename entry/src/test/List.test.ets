import localUnitTest from './LocalUnit.test';
import knowledgePayloadValidatorTest from './KnowledgePayloadValidator.test';
import knowledgeCoreLogicTest from './KnowledgeCoreLogic.test';
import knowledgeQueryDisplayStateTest from './KnowledgeQueryDisplayState.test';
import userDocumentImportLogicTest from './UserDocumentImportLogic.test';
import userDocumentStabilityTest from './UserDocumentStability.test';
import localRetrievalBenchmarkTest from './LocalRetrievalBenchmark.test';
import localRetrievalFullBenchmarkTest from './LocalRetrievalFullBenchmark.test';

export default function testsuite() {
  localUnitTest();
  knowledgePayloadValidatorTest();
  knowledgeCoreLogicTest();
  knowledgeQueryDisplayStateTest();
  userDocumentImportLogicTest();
  userDocumentStabilityTest();
  localRetrievalBenchmarkTest();
  localRetrievalFullBenchmarkTest();
}
