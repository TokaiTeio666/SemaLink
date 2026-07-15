import { describe, expect, it } from '@ohos/hypium';
import { abilityAccessCtrl, common, PermissionRequestResult, Permissions }
  from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  DistributedPermissionController,
  PermissionRequester
} from '../main/ets/permission/DistributedPermissionController';

const MOCK_CONTEXT: common.UIAbilityContext =
  { applicationInfo: { name: 'com.example.test' } } as common.UIAbilityContext;

const PERMISSION_DS: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC' as Permissions;

class FakePermissionRequester implements PermissionRequester {
  private readonly result: PermissionRequestResult | null;
  private readonly error: BusinessError | null;

  constructor(result: PermissionRequestResult | null,
    error: BusinessError | null) {
    this.result = result;
    this.error = error;
  }

  request(_context: common.UIAbilityContext, _permissions: Array<Permissions>):
    Promise<PermissionRequestResult> {
    if (this.result !== null) {
      return Promise.resolve(this.result);
    }
    const err: BusinessError = this.error as BusinessError;
    return Promise.reject(err);
  }
}

function makeResult(authResults: Array<number>): PermissionRequestResult {
  return {
    permissions: ['ohos.permission.DISTRIBUTED_DATASYNC'],
    authResults: authResults
  } as PermissionRequestResult;
}

function makeError(code: number, message: string): BusinessError {
  return { code: code, name: 'BusinessError', message: message } as BusinessError;
}

export default function distributedPermissionControllerTest(): void {
  describe('DistributedPermissionController', () => {

    it('permissionGranted_setsStateTrue', 0, async () => {
      const controller = new DistributedPermissionController(
        new FakePermissionRequester(makeResult([0]), null)
      );
      const granted: boolean = await controller.request(
        MOCK_CONTEXT, [PERMISSION_DS]
      );
      expect(granted).assertTrue();
      expect(controller.isGranted()).assertTrue();
      expect(controller.isFinished()).assertTrue();
    });

    it('permissionDenied_setsStateFalse', 0, async () => {
      const controller = new DistributedPermissionController(
        new FakePermissionRequester(makeResult([-1]), null)
      );
      const granted: boolean = await controller.request(
        MOCK_CONTEXT, [PERMISSION_DS]
      );
      expect(granted).assertFalse();
      expect(controller.isGranted()).assertFalse();
      expect(controller.isFinished()).assertTrue();
    });

    it('emptyAuthResults_setsStateFalse', 0, async () => {
      const controller = new DistributedPermissionController(
        new FakePermissionRequester(makeResult([]), null)
      );
      const granted: boolean = await controller.request(
        MOCK_CONTEXT, [PERMISSION_DS]
      );
      expect(granted).assertFalse();
      expect(controller.isGranted()).assertFalse();
      expect(controller.isFinished()).assertTrue();
    });

    it('businessError_setsStateFalse', 0, async () => {
      const controller = new DistributedPermissionController(
        new FakePermissionRequester(null, makeError(201, 'permission denied'))
      );
      const granted: boolean = await controller.request(
        MOCK_CONTEXT, [PERMISSION_DS]
      );
      expect(granted).assertFalse();
      expect(controller.isGranted()).assertFalse();
      expect(controller.isFinished()).assertTrue();
    });

    it('notFinished_returnsFalse', 0, () => {
      const controller = new DistributedPermissionController();
      expect(controller.isFinished()).assertFalse();
    });

    it('notGranted_returnsFalse', 0, () => {
      const controller = new DistributedPermissionController();
      expect(controller.isGranted()).assertFalse();
    });

    it('evaluateResultGranted_setsGrantedTrue', 0, () => {
      const controller = new DistributedPermissionController();
      const decision: boolean = controller.evaluateResult(makeResult([0]));
      expect(decision).assertTrue();
      expect(controller.isGranted()).assertTrue();
      expect(controller.isFinished()).assertTrue();
    });

    it('evaluateResultDenied_setsGrantedFalse', 0, () => {
      const controller = new DistributedPermissionController();
      const decision: boolean = controller.evaluateResult(makeResult([-1]));
      expect(decision).assertFalse();
      expect(controller.isGranted()).assertFalse();
      expect(controller.isFinished()).assertTrue();
    });

    it('setDenied_setsStateFalse', 0, () => {
      const controller = new DistributedPermissionController();
      controller.setDenied();
      expect(controller.isGranted()).assertFalse();
      expect(controller.isFinished()).assertTrue();
    });
  });
}
