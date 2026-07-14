import commonModelsTest from './CommonModels.test';
import protocolCodecTest from './ProtocolCodec.test';
import mockSummaryServiceTest from './MockSummaryService.test';
import localUnitTest from './LocalUnit.test';

export default function testsuite(): void {
  commonModelsTest();
  protocolCodecTest();
  mockSummaryServiceTest();
  localUnitTest();
}
