# API 24 Native Contract Audit

Recorded 2026-07-22 from the local DevEco Studio API 24 declarations.

## Crypto Architecture Kit

- Module: `@ohos.security.cryptoFramework`
- `DataBlob.data` is `Uint8Array`.
- `createMd('SHA256')` returns `Md`.
- `Md.update({ data: Uint8Array })` and `Md.digest()` are promise-based APIs.
- `createRandom().generateRandom(16)` returns a `DataBlob` whose `data` is `Uint8Array`.

The production code must pass the returned byte arrays directly to the digest and token encoders. It must not log digest input, output, tokens, or certificate contents.

## NetworkKit

- Module: `@ohos.net.socket`
- `constructTLSSocketInstance()` is available for the client API.
- `TLSSocket.connect(TLSConnectOptions)` accepts the address and TLS material.
- `TLSSocket.getRemoteCertificate()` returns `X509CertRawData`.
- API 24 provides `constructTLSSocketServerInstance()` and `TLSSocketServer.listen()` for the responder endpoint.
- TLS send payloads use `string | ArrayBuffer`.

The TLS channel remains responsible for the encrypted byte stream; `TlsFrameCodec` owns application message boundaries. Certificate pinning compares the SHA-256 digest of the peer certificate bytes with the DSK endpoint offer before sending application data.

## Verification Environment

- SDK declarations: `D:\Program Files\DevEco Studio\sdk\default\openharmony\ets\api`
- Project: `C:\Users\admin\DevEcoStudioProjects\SemaLink`
- Recorded date: 2026-07-22
- Hardware verification remains pending until at least two API 24 devices are online through HDC.
