import commonModelsTest from './CommonModels.test';
import protocolCodecTest from './ProtocolCodec.test';
import mockSummaryServiceTest from './MockSummaryService.test';
import trustedDeviceResolverTest from './TrustedDeviceResolver.test';
import transportContractTest from './TransportContract.test';
import localUnitTest from './LocalUnit.test';

export default function testsuite(): void {
  commonModelsTest();
  protocolCodecTest();
  mockSummaryServiceTest();
  trustedDeviceResolverTest();
  transportContractTest();
  localUnitTest();
}
