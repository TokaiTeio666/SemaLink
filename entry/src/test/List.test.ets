import commonModelsTest from './CommonModels.test';
import protocolCodecTest from './ProtocolCodec.test';
import mockSummaryServiceTest from './MockSummaryService.test';
import trustedDeviceResolverTest from './TrustedDeviceResolver.test';
import transportContractTest from './TransportContract.test';
import collaborationTransportTest from './CollaborationTransport.test';
import sessionManagerTest from './SessionManager.test';
import queryCoordinatorTest from './QueryCoordinator.test';
import distributedPermissionControllerTest from './DistributedPermissionController.test';
import localUnitTest from './LocalUnit.test';
import appRuntimeTest from './AppRuntime.test';
import knowledgePayloadValidatorTest from './KnowledgePayloadValidator.test';
import knowledgeCoreLogicTest from './KnowledgeCoreLogic.test';
import knowledgeQueryDisplayStateTest from './KnowledgeQueryDisplayState.test';
import userDocumentImportLogicTest from './UserDocumentImportLogic.test';
import userDocumentStabilityTest from './UserDocumentStability.test';
import localRetrievalBenchmarkTest from './LocalRetrievalBenchmark.test';
import localRetrievalFullBenchmarkTest from './LocalRetrievalFullBenchmark.test';

export default function testsuite(): void {
  commonModelsTest();
  protocolCodecTest();
  mockSummaryServiceTest();
  trustedDeviceResolverTest();
  transportContractTest();
  collaborationTransportTest();
  sessionManagerTest();
  queryCoordinatorTest();
  distributedPermissionControllerTest();
  localUnitTest();
  appRuntimeTest();
  knowledgePayloadValidatorTest();
  knowledgeCoreLogicTest();
  knowledgeQueryDisplayStateTest();
  userDocumentImportLogicTest();
  userDocumentStabilityTest();
  localRetrievalBenchmarkTest();
  localRetrievalFullBenchmarkTest();
}
