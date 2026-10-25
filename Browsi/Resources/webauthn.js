// Browsi built-in passkeys: routes WebAuthn `publicKey` requests to the native authenticator.
(() => {
  if (window.__browsiWebAuthn) return;
  window.__browsiWebAuthn = true;
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.browsiWebAuthn;
  const cc = navigator.credentials;
  if (!handler || !cc) return;

  const bytes = (x) => x instanceof ArrayBuffer ? new Uint8Array(x) : new Uint8Array(x.buffer, x.byteOffset, x.byteLength);
  const toB64u = (x) => {
    if (x == null) return null;
    let s = ''; for (const c of bytes(x)) s += String.fromCharCode(c);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  };
  const fromB64u = (s) => {
    s = s.replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '=';
    const bin = atob(s), out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out.buffer;
  };
  const domError = (name, message) => new DOMException(message || name, name);
  const withAbort = (signal, promise) => {
    if (!signal) return promise;
    if (signal.aborted) return Promise.reject(domError('AbortError', 'The operation was aborted.'));
    return new Promise((resolve, reject) => {
      signal.addEventListener('abort', () => reject(domError('AbortError', 'The operation was aborted.')), { once: true });
      promise.then(resolve, reject);
    });
  };
  const call = async (msg) => {
    const r = await handler.postMessage(msg);
    if (!r || r.error) throw domError((r && r.error) || 'UnknownError', r && r.message);
    return r;
  };
  const define = (o, props) => {
    for (const [k, v] of Object.entries(props)) Object.defineProperty(o, k, { value: v, enumerable: true, configurable: true });
    return o;
  };
  const adopt = (o, proto) => { try { if (proto) Object.setPrototypeOf(o, proto.prototype); } catch (e) {} return o; };

  const credential = (r, kind) => {
    const response = {};
    if (kind === 'create') {
      const authData = fromB64u(r.authenticatorData), spki = fromB64u(r.publicKey);
      define(response, {
        clientDataJSON: fromB64u(r.clientDataJSON),
        attestationObject: fromB64u(r.attestationObject),
        getTransports: () => ['internal'],
        getAuthenticatorData: () => authData,
        getPublicKey: () => spki,
        getPublicKeyAlgorithm: () => -7,
        toJSON: () => ({ clientDataJSON: r.clientDataJSON, attestationObject: r.attestationObject,
          authenticatorData: r.authenticatorData, transports: ['internal'], publicKey: r.publicKey, publicKeyAlgorithm: -7 }),
      });
      adopt(response, window.AuthenticatorAttestationResponse);
    } else {
      define(response, {
        clientDataJSON: fromB64u(r.clientDataJSON),
        authenticatorData: fromB64u(r.authenticatorData),
        signature: fromB64u(r.signature),
        userHandle: r.userHandle ? fromB64u(r.userHandle) : null,
        toJSON: () => ({ clientDataJSON: r.clientDataJSON, authenticatorData: r.authenticatorData,
          signature: r.signature, userHandle: r.userHandle || undefined }),
      });
      adopt(response, window.AuthenticatorAssertionResponse);
    }
    const ext = r.credProps ? { credProps: { rk: true } } : {};
    const cred = define({}, {
      id: r.id, rawId: fromB64u(r.id), type: 'public-key', authenticatorAttachment: 'platform', response,
      getClientExtensionResults: () => ext,
      toJSON: () => ({ id: r.id, rawId: r.id, type: 'public-key', authenticatorAttachment: 'platform',
        response: response.toJSON(), clientExtensionResults: ext }),
    });
    return adopt(cred, window.PublicKeyCredential);
  };

  // Patch the prototype (not just this instance) so code calling
  // CredentialsContainer.prototype.get/create directly can't fall through to WebKit's native path,
  // which without Apple's entitlement waits until the site's timeout.
  const proto = Object.getPrototypeOf(cc);
  const nativeCreate = proto.create.bind(cc), nativeGet = proto.get.bind(cc);
  const browsiCreate = function (options) {
    if (!options || !options.publicKey) return nativeCreate(options);
    const pk = options.publicKey, user = pk.user || {};
    return withAbort(options.signal, call({
      type: 'create', challenge: toB64u(pk.challenge), rpId: pk.rp && pk.rp.id,
      userId: toB64u(user.id), userName: user.name || '', displayName: user.displayName || '',
      algs: (pk.pubKeyCredParams || []).map((p) => p.alg),
      exclude: (pk.excludeCredentials || []).map((c) => toB64u(c.id)),
      credProps: !!(pk.extensions && pk.extensions.credProps),
    }).then((r) => credential(r, 'create')));
  };

  const browsiGet = function (options) {
    if (!options || !options.publicKey) return nativeGet(options);
    // Passkey autofill isn't offered; keep conditional requests pending (until aborted).
    if (options.mediation === 'conditional') return withAbort(options.signal, new Promise(() => {}));
    const pk = options.publicKey;
    return withAbort(options.signal, call({
      type: 'get', challenge: toB64u(pk.challenge), rpId: pk.rpId,
      allow: (pk.allowCredentials || []).map((c) => toB64u(c.id)),
    }).then((r) => credential(r, 'get')));
  };

  for (const [name, fn] of [['create', browsiCreate], ['get', browsiGet]]) {
    try { Object.defineProperty(proto, name, { value: fn, configurable: true, writable: true }); } catch (e) {}
    try { Object.defineProperty(cc, name, { value: fn, configurable: true, writable: true }); } catch (e) {}
  }

  const PKC = window.PublicKeyCredential;
  if (PKC) {
    PKC.isUserVerifyingPlatformAuthenticatorAvailable = () => Promise.resolve(true);
    PKC.isConditionalMediationAvailable = () => Promise.resolve(false);
    PKC.getClientCapabilities = () => Promise.resolve({
      conditionalCreate: false, conditionalGet: false, hybridTransport: false,
      passkeyPlatformAuthenticator: true, userVerifyingPlatformAuthenticator: true, relatedOrigins: false,
      signalAllAcceptedCredentials: false, signalCurrentUserDetails: false, signalUnknownCredential: false,
    });
  }
})();
