/* =====================================================================
   WAFA — wafa-verify  (2026-11-18)

   앱에서 결제가 끝나면 앱이 영수증을 이 함수로 보냅니다.
     body: { productId, purchaseToken }
       · 안드로이드: purchaseToken = 구글 구매 토큰, productId = 'wafa_plan'(구독) 또는 소모성 상품 번호
       · 아이폰:     purchaseToken = 'apple:<거래번호>', productId = 'wafa_1m' 같은 애플 상품 번호
   이 함수가 스토어에 직접 물어보고 진짜일 때만 드립니다.
     구독 → wafa_sub_apply (+ 첫 구독이면 앱이 이어서 wafa_claim_free 로 무료 번호를 고름)
     보충권 → wafa_addon_paid (수량은 구글 답으로만 셈)
     번호 → wafa_number_paid (잡아 둔 번호에 붙이거나, 고르기권으로 남김)

   🔴 산 사람 확인
     · 구글: 앱이 결제할 때 obfuscatedAccountId = 로그인한 사람 id 로 넣어야 합니다(구독).
     · 애플: 앱이 결제할 때 appAccountToken = 로그인한 사람 id 로 넣어야 합니다.
     남의 영수증으로 받아 가는 일을 막습니다.
   ⚠ Verify JWT 켜 둡니다(로그인한 손님이 부름).
   ===================================================================== */

/* ────────── 아래는 공용 코드(두 함수에 똑같이 들어 있음) ────────── */
/* =====================================================================
   WAFA — 스토어 확인 공용 코드 (wafa-verify · wafa-store-notify 가 함께 씀)
   2026-11-18

   부름 alias-plan-google-verify 와 같은 방식입니다.
     · 구글: 서비스 계정으로 출입증을 받아 Google Play Developer API 에 직접 물어봄
     · 애플: App Store Server API 에 거래번호로 직접 물어봄
   앱이나 알림이 보낸 내용은 믿지 않고, 늘 스토어에 다시 물어본 답만 씁니다.

   필요한 비밀값 (부름 프로젝트에 이미 있음 — 새로 넣을 것 없음)
     GOOGLE_PLAY_SERVICE_ACCOUNT · APPLE_IAP_KEY_ID · APPLE_IAP_ISSUER_ID · APPLE_IAP_KEY_P8
   새로 넣을 값 (Edge Functions → Secrets)
     WAFA_ANDROID_PACKAGE   예: com.weaveapp.wafa  (플레이 콘솔에 앱을 만들 때 정한 이름)
     WAFA_IOS_BUNDLE        예: com.weaveapp.wafa  (App Store Connect 의 번들 ID)
     WAFA_NOTIFY_KEY        스토어 알림 주소 끝에 붙일 아무 긴 글자(남이 가짜 알림을 못 보내게)
   ⚠ 구글 서비스 계정은 플레이 콘솔 → 사용자 및 권한 에서 WAFA 앱에도 "재무 데이터 보기 ·
     주문 및 구독 관리" 권한을 줘야 합니다. 안 주면 401 이 납니다.
   ===================================================================== */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ANDROID_PACKAGE = Deno.env.get('WAFA_ANDROID_PACKAGE') || 'com.weaveapp.wafa';
const IOS_BUNDLE = Deno.env.get('WAFA_IOS_BUNDLE') || 'com.weaveapp.wafa';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

/* ── 상품 번호 — 앱 화면 · 플레이 콘솔 · App Store Connect 와 같아야 합니다 ─────────────
   구독(자동 갱신)
     구글: 구독 상품 하나 'wafa_plan' 안에 기본 요금제 4개(wafa-1m · wafa-3m · wafa-6m · wafa-12m)
           → 같은 구독 안이라 기간 바꾸기를 구글이 처리합니다
     애플: 구독 그룹 하나에 상품 4개(wafa_1m · wafa_3m · wafa_6m · wafa_12m)
   소모성
     wafa_addon           보충권 1,100원 (구글은 수량 여러 개 켜기)
     wafa_number_5/4/3    좋은 번호 110,000 · 55,000 · 11,000원
     wafa_number_extra    번호 하나 더 3,300원
------------------------------------------------------------------------------------- */
const GOOGLE_SUB_ID = 'wafa_plan';
const PLAN_BY_BASEPLAN: Record<string, string> = {
  'wafa-1m': 'wafa_1m', 'wafa-3m': 'wafa_3m', 'wafa-6m': 'wafa_6m', 'wafa-12m': 'wafa_12m',
};
const PLAN_PRODUCTS = ['wafa_1m', 'wafa_3m', 'wafa_6m', 'wafa_12m'];
const ADDON_SKU = 'wafa_addon';
const NUMBER_SKUS: Record<string, { kind: string; krw: number }> = {
  wafa_number_5: { kind: '5', krw: 110000 },
  wafa_number_4: { kind: '4', krw: 55000 },
  wafa_number_3: { kind: '3', krw: 11000 },
  wafa_number_extra: { kind: 'extra', krw: 3300 },
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(o: unknown, status = 200) {
  return new Response(JSON.stringify(o), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

function isAppleToken(t: string) { return String(t || '').startsWith('apple:'); }

function b64url(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64urlDecode(part: string): Uint8Array {
  const b = part.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((part.length + 3) % 4);
  return Uint8Array.from(atob(b), (c) => c.charCodeAt(0));
}
/* JWS 가운데 부분만 읽기 — 읽은 내용은 "어느 거래인지" 찾는 데만 쓰고, 진짜 내용은 다시 물어봅니다 */
function jwsPayload(jws: string): any {
  const part = String(jws || '').split('.')[1] || '';
  return JSON.parse(new TextDecoder().decode(b64urlDecode(part)));
}

/* ── 구글 출입증 (한 시간짜리 — 받아 두고 다시 씀) ──────────────────────── */
let gToken: string | null = null;
let gUntil = 0;
async function googleToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (gToken && now < gUntil) return gToken;
  const raw = Deno.env.get('GOOGLE_PLAY_SERVICE_ACCOUNT');
  if (!raw) throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT 비밀값이 없습니다');
  const sa = JSON.parse(raw);
  const enc = new TextEncoder();
  const unsigned = b64url(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))) + '.' +
    b64url(enc.encode(JSON.stringify({
      iss: sa.client_email, scope: 'https://www.googleapis.com/auth/androidpublisher',
      aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600,
    })));
  const body = String(sa.private_key).replace(/-----[A-Z ]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der.buffer, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(unsigned));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: unsigned + '.' + b64url(new Uint8Array(sig)) }),
  });
  const out = await res.json();
  if (!out.access_token) throw new Error('구글 출입증 실패: ' + JSON.stringify(out).slice(0, 200));
  gToken = out.access_token;
  gUntil = now + 3300;
  return gToken!;
}
const GAPI = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/';

/* 구글 구독 상태 (v2) */
async function googleSub(purchaseToken: string) {
  const t = await googleToken();
  const res = await fetch(GAPI + ANDROID_PACKAGE + '/purchases/subscriptionsv2/tokens/' + encodeURIComponent(purchaseToken),
    { headers: { Authorization: 'Bearer ' + t } });
  return { res, info: res.ok ? await res.json() : { error: (await res.text()).slice(0, 300) } };
}
async function googleSubAck(subscriptionId: string, purchaseToken: string) {
  const t = await googleToken();
  const r = await fetch(GAPI + ANDROID_PACKAGE + '/purchases/subscriptions/' + encodeURIComponent(subscriptionId) +
    '/tokens/' + encodeURIComponent(purchaseToken) + ':acknowledge',
    { method: 'POST', headers: { Authorization: 'Bearer ' + t, 'Content-Type': 'application/json' }, body: '{}' });
  if (!r.ok) console.error('[wafa] 🔴 구독 잘 받았다고 알리기 실패 — 사흘 뒤 환불될 수 있습니다', (await r.text()).slice(0, 200));
}
/* 구글 한 번 사는 상품 */
async function googleProduct(productId: string, purchaseToken: string) {
  const t = await googleToken();
  const url = GAPI + ANDROID_PACKAGE + '/purchases/products/' + encodeURIComponent(productId) + '/tokens/' + encodeURIComponent(purchaseToken);
  const res = await fetch(url, { headers: { Authorization: 'Bearer ' + t } });
  return { res, url, token: t, info: res.ok ? await res.json() : { error: (await res.text()).slice(0, 300) } };
}
async function googleProductAck(url: string, token: string) {
  const r = await fetch(url + ':acknowledge', { method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: '{}' });
  if (!r.ok) console.error('[wafa] 🔴 잘 받았다고 알리기 실패 — 사흘 뒤 환불될 수 있습니다', (await r.text()).slice(0, 200));
}

/* 구글 구독 답 → WAFA 상태
   ACTIVE 사용 중 · IN_GRACE_PERIOD 결제 실패 유예 · CANCELED 해지(기간 끝까지 사용) · 나머지 끝 */
function googleState(s: string): string | null {
  switch (s) {
    case 'SUBSCRIPTION_STATE_ACTIVE': return 'active';
    case 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD': return 'grace';
    case 'SUBSCRIPTION_STATE_CANCELED': return 'canceled';
    case 'SUBSCRIPTION_STATE_ON_HOLD':
    case 'SUBSCRIPTION_STATE_PAUSED':
    case 'SUBSCRIPTION_STATE_EXPIRED': return 'expired';
    default: return null;          // PENDING 등 — 아직 아무것도 하지 않음
  }
}

/* ── 애플 ─────────────────────────────────────────────────────────────── */
let aJwt: string | null = null;
let aAt = 0;
async function appleJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (aJwt && now - aAt < 15 * 60) return aJwt;
  const p8 = Deno.env.get('APPLE_IAP_KEY_P8') || '';
  const kid = (Deno.env.get('APPLE_IAP_KEY_ID') || '').replace(/[^A-Za-z0-9]/g, '');
  const iss = (Deno.env.get('APPLE_IAP_ISSUER_ID') || '').replace(/[^A-Za-z0-9-]/g, '');
  if (!p8 || !kid || !iss) throw new Error('APPLE_IAP_KEY_P8 · APPLE_IAP_KEY_ID · APPLE_IAP_ISSUER_ID 비밀값이 없습니다');
  const raw = Uint8Array.from(atob(p8.replace(/-----[A-Z ]+-----/g, '').replace(/[^A-Za-z0-9+/=]/g, '')), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', raw.buffer, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const enc = new TextEncoder();
  const unsigned = b64url(enc.encode(JSON.stringify({ alg: 'ES256', kid, typ: 'JWT' }))) + '.' +
    b64url(enc.encode(JSON.stringify({ iss, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1', bid: IOS_BUNDLE })));
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(unsigned));
  aJwt = unsigned + '.' + b64url(new Uint8Array(sig));
  aAt = now;
  return aJwt;
}
/* 거래번호로 애플에 직접 물어봄 (정식 → 시험 창구 순서) */
async function appleTx(transactionId: string): Promise<{ ok: boolean; status: number; tx?: any; error?: string }> {
  const id = String(transactionId).replace(/[^0-9]/g, '');
  const jwt = await appleJwt();
  let last = 0, text = '';
  for (const host of ['https://api.storekit.itunes.apple.com', 'https://api.storekit-sandbox.itunes.apple.com']) {
    const r = await fetch(host + '/inApps/v1/transactions/' + id, { headers: { Authorization: 'Bearer ' + jwt } });
    if (r.ok) {
      const tx = jwsPayload((await r.json()).signedTransactionInfo);
      if (tx.bundleId !== IOS_BUNDLE) return { ok: false, status: 400, error: '다른 앱의 결제입니다' };
      return { ok: true, status: 200, tx };
    }
    last = r.status; text = (await r.text()).slice(0, 200);
  }
  return { ok: false, status: last || 500, error: '애플 확인 실패 ' + last + ' ' + text };
}

/* 구독 반영 (DB) */
async function applySub(userId: string, product: string, status: string, expiresMs: number,
                               autoRenew: boolean, store: 'google' | 'apple', tokenKey: string) {
  const { data, error } = await admin.rpc('wafa_sub_apply', {
    p_user: userId, p_product: product, p_status: status, p_expires: new Date(expiresMs).toISOString(),
    p_auto: autoRenew, p_store: store, p_tx: tokenKey,
  });
  if (error) throw new Error('wafa_sub_apply 실패: ' + error.message);
  await admin.from('wafa_sub_tokens').upsert({ token: tokenKey, user_id: userId }, { onConflict: 'token' });
  return data;
}

/* ────────── 공용 코드 끝 ────────── */



Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: u } = await admin.auth.getUser(jwt);
    const userId = u?.user?.id;
    if (!userId) return json({ ok: false, error: 'login' }, 401);

    const { productId, purchaseToken } = await req.json();
    if (!productId || !purchaseToken) return json({ ok: false, error: 'bad_request' }, 400);
    const apple = isAppleToken(purchaseToken);

    /* ── 1. 구독 ─────────────────────────────────────────────── */
    if (productId === GOOGLE_SUB_ID || PLAN_PRODUCTS.includes(productId)) {
      if (apple) {
        const a = await appleTx(purchaseToken.slice(6));
        if (!a.ok) return json({ ok: false, error: a.error }, a.status);
        const tx = a.tx;
        if (!PLAN_PRODUCTS.includes(tx.productId)) return json({ ok: false, error: '상품 번호가 다릅니다' }, 400);
        if (String(tx.appAccountToken || '').toLowerCase() !== userId.toLowerCase()) return json({ ok: false, error: '다른 계정으로 산 결제입니다' }, 403);
        const expired = !tx.expiresDate || tx.expiresDate < Date.now();
        const status = tx.revocationDate ? 'refunded' : expired ? 'expired' : 'active';
        await applySub(userId, tx.productId, status, tx.expiresDate || Date.now(), true, 'apple', 'apple:' + tx.originalTransactionId);
        return json({ ok: true, status, product: tx.productId, until: new Date(tx.expiresDate || Date.now()).toISOString() });
      }
      const g = await googleSub(purchaseToken);
      if (g.res.status === 410) return json({ ok: false, canceled: true, error: '없는 영수증입니다' });
      if (!g.res.ok) return json({ ok: false, error: '구글 확인 실패: ' + JSON.stringify(g.info).slice(0, 200) }, 502);
      const info = g.info;
      const owner = info.externalAccountIdentifiers?.obfuscatedExternalAccountId;
      if (!owner || owner.toLowerCase() !== userId.toLowerCase()) return json({ ok: false, error: '다른 계정으로 산 결제입니다' }, 403);
      const line = (info.lineItems || [])[0] || {};
      const product = PLAN_BY_BASEPLAN[line.offerDetails?.basePlanId || ''];
      const status = googleState(info.subscriptionState);
      if (!product) return json({ ok: false, error: '요금제 번호가 다릅니다: ' + (line.offerDetails?.basePlanId || '?') }, 400);
      if (!status) return json({ ok: false, pending: true, error: '아직 결제가 끝나지 않았습니다' });
      const until = Date.parse(line.expiryTime || '') || Date.now();
      await applySub(userId, product, status, until, !!line.autoRenewingPlan?.autoRenewEnabled, 'google', purchaseToken);
      if (info.acknowledgementState !== 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED') await googleSubAck(GOOGLE_SUB_ID, purchaseToken);
      return json({ ok: true, status, product, until: new Date(until).toISOString() });
    }

    /* ── 2. 보충권 · 번호 (한 번 사는 상품) ─────────────────────── */
    const item = NUMBER_SKUS[productId];
    if (productId !== ADDON_SKU && !item) return json({ ok: false, error: '모르는 상품입니다: ' + productId }, 400);

    let qty = 1, ackUrl = '', ackToken = '', txKey = purchaseToken;
    if (apple) {
      const a = await appleTx(purchaseToken.slice(6));
      if (!a.ok) return json({ ok: false, error: a.error }, a.status);
      const tx = a.tx;
      if (tx.productId !== productId) return json({ ok: false, error: '상품 번호가 다릅니다' }, 400);
      if (String(tx.appAccountToken || '').toLowerCase() !== userId.toLowerCase()) return json({ ok: false, error: '다른 계정으로 산 결제입니다' }, 403);
      if (tx.revocationDate) return json({ ok: false, consume: true, canceled: true, error: '취소되었거나 환불된 결제입니다' });
      qty = Math.max(1, Math.min(Number(tx.quantity) || 1, 10));
      txKey = 'apple:' + tx.transactionId;
    } else {
      const g = await googleProduct(productId, purchaseToken);
      if (g.res.status === 410 || g.info.purchaseState === 1) return json({ ok: false, consume: true, canceled: true, error: '취소되었거나 환불된 결제입니다' });
      if (!g.res.ok) return json({ ok: false, error: '구글 확인 실패: ' + JSON.stringify(g.info).slice(0, 200) }, 502);
      if (g.info.purchaseState !== 0) return json({ ok: false, pending: true, error: '아직 결제가 끝나지 않았습니다' });
      qty = Math.max(1, Math.min(Math.floor(Number(g.info.quantity) || 1), 10));     // 🔴 수량은 구글 답으로만
      if (!g.info.acknowledgementState) { ackUrl = g.url; ackToken = g.token; }
    }

    let out: any;
    if (productId === ADDON_SKU) {
      const { data, error } = await admin.rpc('wafa_addon_paid', { p_user: userId, p_tx: txKey, p_count: qty });
      if (error || !data?.ok) return json({ ok: false, error: '보충권을 넣지 못했습니다. 잠시 뒤 다시 열어 주세요.' }, 500);   // 🔴 알리지 않음 → 앱이 다시 보냄
      out = { ok: true, units: data.units, dup: !!data.dup };
    } else {
      const got: any[] = [];
      for (let i = 0; i < qty; i++) {
        const { data, error } = await admin.rpc('wafa_number_paid', { p_user: userId, p_kind: item.kind, p_tx: i === 0 ? txKey : txKey + '#' + i });
        if (error || !data?.ok) return json({ ok: false, error: '번호를 넣지 못했습니다. 잠시 뒤 다시 열어 주세요.' }, 500);
        got.push(data);
      }
      out = { ok: true, kind: item.kind, number: got[0].number || null, shown: got[0].shown || null, credits: got.filter((x) => x.credit).length };
    }
    if (ackUrl) await googleProductAck(ackUrl, ackToken);       // 🔴 빼면 구글이 사흘 뒤 자동 환불
    return json(out);
  } catch (e) {
    console.error('[wafa-verify]', e);
    return json({ ok: false, error: String((e as Error).message || e) }, 500);
  }
});
