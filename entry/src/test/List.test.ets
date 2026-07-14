import commonModelsTest from './CommonModels.test';
import protocolCodecTest from './ProtocolCodec.test';
import localUnitTest from './LocalUnit.test';

export default function testsuite(): void {
  commonModelsTest();
  protocolCodecTest();
  localUnitTest();
}
