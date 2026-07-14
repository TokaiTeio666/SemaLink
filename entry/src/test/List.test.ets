import commonModelsTest from './CommonModels.test';
import localUnitTest from './LocalUnit.test';

export default function testsuite(): void {
  commonModelsTest();
  localUnitTest();
}
