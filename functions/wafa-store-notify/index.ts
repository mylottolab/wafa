/* =====================================================================
   WAFA — wafa-store-notify  (2026-11-18)

   자동결제 구독은 손님이 앱을 열지 않아도 갱신 · 해지 · 환불 · 만료가 일어납니다.
   그때마다 스토어가 이 주소로 알려 주고, 이 함수가 스토어에 다시 물어봐 DB 를 고칩니다.

   주소 (둘 다 끝에 ?key=<WAFA_NOTIFY_KEY>)
     구글: 플레이 콘솔 → 수익 창출 설정 → 실시간 개발자 알림 → Pub/Sub 주제
           → Google Cloud 에서 그 주제에 "푸시" 구독을 만들고 엔드포인트를
             https://azredlrnvsssfjytaotb.supabase.co/functions/v1/wafa-store-notify?key=... 로
     애플: App Store Connect → WAFA 앱 → 앱 정보 → App Store 서버 알림(버전 2)
           운영 · 샌드박스 모두 같은 주소

   🔴 알림 내용은 믿지 않습니다. "어느 영수증인지"만 읽고, 상태는 스토어에 다시 물어본 답으로 씁니다.
   ⚠ Verify JWT 는 꺼 둡니다(스토어가 부르므로). 대신 ?key= 로 막습니다.
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



const KEY = Deno.env.get('WAFA_NOTIFY_KEY') || '';

async function userFor(tokenKey: string, hint?: string | null): Promise<string | null> {
  if (hint && /^[0-9a-f-]{36}$/i.test(hint)) return hint.toLowerCase();
  const { data } = await admin.from('wafa_sub_tokens').select('user_id').eq('token', tokenKey).maybeSingle();
  return data?.user_id || null;
}

async function onGoogle(msg: any) {
  const n = msg.subscriptionNotification;
  if (!n) {                                      // 시험 알림 · 한 번 사는 상품 알림 등은 기록만
    console.log('[wafa-notify] 구글 알림(구독 아님):', JSON.stringify(msg).slice(0, 200));
    return;
  }
  if (n.subscriptionId && n.subscriptionId !== GOOGLE_SUB_ID) return;
  const g = await googleSub(n.purchaseToken);
  if (!g.res.ok) { console.error('[wafa-notify] 구글 확인 실패', g.res.status, JSON.stringify(g.info).slice(0, 200)); return; }
  const info = g.info;
  const line = (info.lineItems || [])[0] || {};
  const product = PLAN_BY_BASEPLAN[line.offerDetails?.basePlanId || ''];
  const status = googleState(info.subscriptionState);
  const user = await userFor(n.purchaseToken, info.externalAccountIdentifiers?.obfuscatedExternalAccountId);
  if (!product || !status || !user) { console.log('[wafa-notify] 건너뜀', { product, status, user: !!user }); return; }
  /* 기간 바꾸기 등으로 새 영수증이 생기면 linkedPurchaseToken 이 옛 영수증 — 사람은 같으므로 새 영수증만 반영 */
  await applySub(user, product, status, Date.parse(line.expiryTime || '') || Date.now(),
                 !!line.autoRenewingPlan?.autoRenewEnabled, 'google', n.purchaseToken);
  console.log('[wafa-notify] ✓ 구글', n.notificationType, product, status);
}

async function onApple(signedPayload: string) {
  const p = jwsPayload(signedPayload);                                  // 어느 거래인지만 읽음
  const t = p.data?.signedTransactionInfo ? jwsPayload(p.data.signedTransactionInfo) : null;
  const r = p.data?.signedRenewalInfo ? jwsPayload(p.data.signedRenewalInfo) : null;
  if (!t?.transactionId) { console.log('[wafa-notify] 애플 알림(거래 없음):', p.notificationType); return; }
  const a = await appleTx(String(t.transactionId));                     // 🔴 애플에 다시 물어본 답만 씀
  if (!a.ok) { console.error('[wafa-notify] 애플 확인 실패', a.status, a.error); return; }
  const tx = a.tx;
  if (!PLAN_PRODUCTS.includes(tx.productId)) return;                    // 보충권 · 번호는 앱이 wafa-verify 로 처리
  const key = 'apple:' + tx.originalTransactionId;
  const user = await userFor(key, tx.appAccountToken);
  if (!user) { console.log('[wafa-notify] 애플 — 사람을 못 찾음', key); return; }
  const expired = !tx.expiresDate || tx.expiresDate < Date.now();
  let status = tx.revocationDate ? 'refunded' : expired ? 'expired' : 'active';
  if (status === 'active' && p.subtype === 'GRACE_PERIOD') status = 'grace';
  const autoRenew = r ? r.autoRenewStatus === 1 : true;
  if (status === 'active' && !autoRenew) status = 'canceled';           // 해지 — 기간 끝까지는 사용
  await applySub(user, tx.productId, status, tx.expiresDate || Date.now(), autoRenew, 'apple', key);
  console.log('[wafa-notify] ✓ 애플', p.notificationType, p.subtype || '', tx.productId, status);
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (!KEY || url.searchParams.get('key') !== KEY) return json({ ok: false }, 401);
  try {
    const body = await req.json();
    if (body?.message?.data) {                                            // 구글 Pub/Sub 푸시
      const msg = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(body.message.data), (c) => c.charCodeAt(0))));
      await onGoogle(msg);
    } else if (body?.signedPayload) {                                     // 애플 서버 알림 v2
      await onApple(body.signedPayload);
    }
    return json({ ok: true });                                            // 200 이 아니면 스토어가 계속 다시 보냄
  } catch (e) {
    console.error('[wafa-notify]', e);
    return json({ ok: false }, 500);
  }
});
