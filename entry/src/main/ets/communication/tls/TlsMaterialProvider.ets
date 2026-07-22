import { common } from '@kit.AbilityKit';
import { decodeUtf8 } from './Utf8Codec';

export interface TlsMaterial {
  ca: string;
  cert?: string;
  key?: string;
}

export interface TlsMaterialProvider {
  getClientMaterial(): TlsMaterial;
  getServerMaterial(): TlsMaterial;
}

export class InMemoryTlsMaterialProvider implements TlsMaterialProvider {
  private readonly material: TlsMaterial;

  constructor(material: TlsMaterial) {
    this.material = material;
  }

  getClientMaterial(): TlsMaterial { return this.material; }
  getServerMaterial(): TlsMaterial { return this.material; }
}

export class RawfileTlsMaterialProvider implements TlsMaterialProvider {
  private readonly material: TlsMaterial;

  constructor(context: common.UIAbilityContext, directory: string = 'demo_tls') {
    const resourceManager = context.resourceManager;
    const ca = decodeUtf8(resourceManager.getRawFileContentSync(directory + '/ca-cert.pem'));
    const cert = decodeUtf8(resourceManager.getRawFileContentSync(directory + '/server-cert.pem'));
    const key = decodeUtf8(resourceManager.getRawFileContentSync(directory + '/server-key.pem'));
    this.material = { ca: ca, cert: cert, key: key };
  }

  getClientMaterial(): TlsMaterial { return this.material; }
  getServerMaterial(): TlsMaterial { return this.material; }
}
