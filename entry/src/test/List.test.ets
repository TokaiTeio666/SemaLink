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
}
