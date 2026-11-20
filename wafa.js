/* =====================================================================
   와파 WAFA — 와파 화면 공통 (2026-11-19)
   부름 화면 코드(alias_common.js) 다음에 부릅니다. 로그인 · 서버(AL.sb)는 부름 것을 그대로 씁니다.
   ■ 언어: 부름과 같은 칸(alias_lang_v1 = 'kr' | 'en') → 대화 · 통화 화면도 함께 바뀜
   ■ 결제: 앱(안드로이드)의 AliasNative 로 결제창을 열고, 영수증은 서버(wafa-verify)가 스토어에 직접 확인
   ===================================================================== */
(function(){
  'use strict';
  var LK = 'alias_lang_v1';
  function get(k){ try { return localStorage.getItem(k); } catch (e) { return null; } }
  function set(k, v){ try { localStorage.setItem(k, v); } catch (e) {} }
  var pref = get(LK);
  var EN = pref === 'en' || (pref !== 'kr' && !/^ko/i.test(navigator.language || 'ko'));
  document.documentElement.lang = EN ? 'en' : 'ko';
  /* 🔴 2026-11-20 주간 · 야간 — 고른 것을 이 폰에 기억(wafa_theme = 'light' | 'dark'). 고른 적 없으면 폰 설정을 따름 */
  var TH = get('wafa_theme');
  if (TH === 'light' || TH === 'dark') document.documentElement.setAttribute('data-theme', TH);

  var S = {
    appName: ['와파', 'WAFA'],
    back: ['‹ 뒤로', '‹ Back'], home: ['와파 홈', 'WAFA Home'],
    login: ['가입 · 로그인', 'Sign up · Log in'],
    welcomeT: ['와이파이만 있으면 걸고 받는 비상폰', 'The backup phone that works on Wi-Fi'],
    welcomeD: ['유심이 없어도, 해외에서도. 와파 번호로 문자 · 음성 · 영상 통화를 이어 가세요.', 'No SIM, no roaming. Keep texting and calling with your WAFA number.'],
    setupT: ['주로 어떻게 쓰실까요?', 'How will you mostly use WAFA?'],
    setupD: ['메인으로 정한 쪽이 첫 화면에 크게 보입니다. 언제든 바꿀 수 있고, 둘 다 쓸 수 있어요.', 'Your main choice shows first. You can change it anytime and use both.'],
    openN: ['📞 번호 전화', '📞 Open Line'], openD: ['4-3-3 번호로 바로 연결 · 어르신 · 가족 · 일상 연락에', 'A 4-3-3 number that rings right away. For family and everyday calls.'],
    privN: ['💬 별칭 전화', '💬 Private Line'], privD: ['상대가 수락해야 연결되는 별칭(부캐) 전화 · 모임 · 거래 · 일에', 'Alias calls that connect after accept. For groups, deals and work.'],
    mainTag: ['메인', 'Main'],
    myNumber: ['내 번호', 'My number'], noNumber: ['아직 번호가 없어요', 'No number yet'],
    getNumber: ['번호 받기', 'Get a number'],
    numbersD: ['내 번호 · 좋은 번호 · 가족 번호', 'My numbers · Premium · Family'],
    contactsD: ['별칭 연락처 · 대화 · 통화', 'Alias contacts · chat · calls'],
    planN: ['💳 요금 · 보충', '💳 Plan · Top-up'], planD: ['구독 · 보충권 나눠 담기', 'Subscription · split top-up'],
    usageN: ['📊 내 사용량', '📊 My usage'], usageD: ['이번 달 남은 시간 · 지난 기록', 'This month · history'],
    dialN: ['☎️ 번호판', '☎️ Keypad'], dialD: ['와파 번호로 걸기 · 연락처', 'Call a WAFA number · contacts'],
    switchMain: ['메인 바꾸기', 'Change main'],
    subActive: ['구독 중 · {d}까지', 'Subscribed · until {d}'], subCanceled: ['해지됨 · {d}까지 사용', 'Canceled · usable until {d}'],
    subGrace: ['결제 확인 중 · {d}까지', 'Payment issue · until {d}'], subNone: ['구독 전 — 문자와 전화 받기는 무료', 'No plan — texting and answering are free'],
    textFree: ['문자 · 전화 받기는 언제나 무료', 'Texting and answering are always free'],
    /* 번호 */
    numTitle: ['번호', 'Numbers'], mine: ['내 번호', 'My numbers'],
    kind_free: ['무료', 'Free'], kind_bought: ['구매', 'Purchased'], kind_extra: ['하나 더', 'Extra'], kind_given: ['선물', 'Gift'],
    freeReady: ['구독 중이라 일반 번호 하나를 무료로 받을 수 있어요. 아래에서 골라 [무료로 받기]를 누르세요.', 'With your plan, one standard number is free. Pick one below and tap [Get free].'],
    needPlanFree: ['일반 번호 무료 받기는 구독 뒤에 됩니다.', 'Subscribe first to get your free number.'],
    goSub: ['구독하러 가기 ›', 'Subscribe ›'],
    logout: ['로그아웃', 'Log out'], logoutAgain: ['한 번 더 누르면 로그아웃', 'Tap again to log out'],
    terms: ['이용약관(EULA)', 'Terms of Use (EULA)'], privacy: ['개인정보처리방침', 'Privacy Policy'], refund: ['취소 · 환불', 'Cancellation · Refunds'],
    toLight: ['주간으로 바꾸기', 'Switch to light'], toDark: ['야간으로 바꾸기', 'Switch to dark'],
    getNumBtn: ['📞 내 와파 번호 받기 ›', '📞 Get my WAFA number ›'],
    getNumSub: ['번호가 있어야 다른 분이 나에게 걸 수 있어요 · 구독하면 일반 번호 하나 무료', 'Others can call you once you have a number · one standard number is free with a plan'],
    credits: ['고르기권 {n}장이 있어요. 해당 등급 번호에서 [고르기권 쓰기]를 누르세요.', 'You have {n} pick pass(es). Tap [Use pass] on a number of that grade.'],
    tabN: ['일반', 'Standard'], tab3: ['★★★ 3 Stars', '★★★ 3 Stars'], tab4: ['★★★★ 4 Stars', '★★★★ 4 Stars'], tab5: ['★★★★★ 5 Stars', '★★★★★ 5 Stars'],
    rN: ['일반 번호: 구독하면 하나 무료 · 하나 더 3,300원', 'Standard: one free with a plan · extra ₩3,300'],
    r3: ['끝 3자리 777·888·999·000, 끝 4자리 또는 앞 4자리 연속', 'Ends in 777·888·999·000, or the first/last 4 digits run in order'],
    r4: ['앞 4자리 같은 숫자 · 가운데=끝(051 051) · 가운데·끝 같은 숫자 · 뒤 6자리 연속', 'First 4 repeat · middle = last · both repeat · last 6 run in order'],
    r5: ['뒤 6자리가 모두 같은 숫자. 10자리 · 9자리 같은 번호는 회사 보유', 'Last 6 digits identical. 9–10 identical digits are held by WAFA'],
    getFree: ['무료로 받기', 'Get free'], useCredit: ['고르기권 쓰기', 'Use pass'], buy: ['구매', 'Buy'], more: ['다른 번호 더 보기', 'Show more'],
    free: ['무료', 'Free'], won: ['원', ''],
    findT: ['생각해 둔 번호가 있으세요?', 'Have a number in mind?'], find: ['찾기', 'Search'],
    st_free: ['고를 수 있어요', 'Available'], st_taken: ['이미 쓰는 번호예요', 'Already taken'], st_company: ['회사 보유 번호라 판매하지 않습니다 (SOLD OUT)', 'Held by WAFA — not for sale (SOLD OUT)'],
    st_held: ['다른 분이 잠시 잡아 둔 번호예요', 'Someone is holding this number'], st_mine: ['내 번호예요', 'This is yours'], st_held_mine: ['내가 잡아 둔 번호예요', 'You are holding this number'],
    badNum: ['숫자 10자리로 넣어 주세요. 맨 앞은 1~9입니다.', 'Enter 10 digits. The first is 1–9.'],
    famT: ['가족 번호', 'Family numbers'], famD: ['가족이 같은 3자리를 나눠 가진 번호를 7일간 예약하고, 가족마다 초대 코드를 보냅니다.', 'Hold numbers that share 3 digits for 7 days and send each family member a code.'],
    famMid: ['가운데 3자리', 'Middle 3'], famLast: ['끝 3자리', 'Last 3'], famBad: ['숫자 3자리로 넣어 주세요.', 'Enter 3 digits.'],
    famHold: ['이 번호들을 7일간 예약하기', 'Hold these for 7 days'], famDone: ['예약했어요. 아래 코드를 가족에게 보내 주세요.', 'Held. Send these codes to your family.'],
    famCodeT: ['가족에게 받은 코드가 있으세요?', 'Got a family code?'], famCodeGo: ['번호 받기', 'Claim'],
    holds: ['예약 · 결제 중인 번호', 'Held numbers'],
    copied: ['복사했어요', 'Copied'],
    /* 요금 */
    planTitle: ['요금 · 보충', 'Plan · Top-up'], planNow: ['지금 요금제', 'Current plan'],
    p1: ['1개월', '1 month'], p3: ['3개월', '3 months'], p6: ['6개월', '6 months'], p12: ['12개월', '12 months'],
    perMonth: ['한 달 {p}', '{p} / month'], subscribe: ['구독하기', 'Subscribe'], change: ['이 요금제로 바꾸기', 'Switch to this plan'],
    planInc: ['달마다 음성 300분 · 영상 100분 · 보관 1GB · 문자 무제한. 남은 음성 · 영상은 다음 달 한정 이월. 번호가 여러 개여도 사용량은 한 계정에서 합쳐서 셉니다.', 'Each month: 300 voice min · 100 video min · 1 GB · unlimited texts. Unused minutes carry over one month. With several numbers, usage is counted together for your account.'],
    autoNote: ['자동으로 갱신됩니다. 해지는 [구독 관리]에서 언제든 할 수 있고, 낸 기간이 끝날 때까지 쓸 수 있어요.', 'Renews automatically. Cancel anytime in [Manage subscription]; you keep access until the period ends.'],
    manage: ['구독 관리', 'Manage subscription'],
    addonT: ['보충권 1,100원', 'Top-up ₩1,100'], addonD: ['1장 = 11칸. 1칸(100원)에 음성 30분 · 영상 10분 · 보관 100MB 중 원하는 대로 나눠 담아요.', '1 top-up = 11 units. Each unit (₩100): 30 voice min · 10 video min · or 100 MB.'],
    buyAddon: ['보충권 구매', 'Buy top-up'], units: ['담을 칸 {n}칸 남음', '{n} units left to assign'],
    voiceU: ['음성 (+30분)', 'Voice (+30 min)'], videoU: ['영상 (+10분)', 'Video (+10 min)'], storeU: ['보관 (+100MB)', 'Storage (+100 MB)'],
    allocate: ['이대로 담기', 'Assign'], allocated: ['담았어요', 'Assigned'],
    webOnly: ['결제는 와파 앱에서 할 수 있어요.', 'Purchases are available in the WAFA app.'],
    paying: ['결제창을 여는 중…', 'Opening payment…'], payOk: ['결제가 확인됐어요', 'Payment confirmed'], payFail: ['결제를 확인하지 못했어요. 앱을 다시 열면 한 번 더 확인합니다.', 'Could not confirm. We will retry when you reopen the app.'],
    payCancel: ['결제를 그만두었어요', 'Payment canceled'], payPending: ['결제가 아직 끝나지 않았어요', 'Payment pending'],
    /* 사용량 */
    usageTitle: ['내 사용량', 'My usage'], voice: ['음성', 'Voice'], video: ['영상', 'Video'], storage: ['보관 공간', 'Storage'],
    left: ['{n}분 남음', '{n} min left'], ofTotal: ['{u} / {t}분', '{u} / {t} min'],
    lgBase: ['기본', 'Plan'], lgRoll: ['이월 쿠폰', 'Carry-over'], lgAddon: ['보충', 'Top-up'],
    storeTotal: ['쓸 수 있는 공간 {g}', 'Available space {g}'],
    hist: ['지난 기록', 'History'], month: ['달', 'Month'],
    noPlanUse: ['구독하면 달마다 음성 300분 · 영상 100분이 생겨요.', 'Subscribe to get 300 voice and 100 video minutes each month.'],
    err: ['잠시 문제가 생겼어요. 다시 시도해 주세요.', 'Something went wrong. Please try again.'],
  };

  var WF = window.WF = window.WF || {};
  WF.en = EN;
  WF.t = function(k, v){
    var a = S[k]; var s = a ? a[EN ? 1 : 0] : '[[' + k + ']]';
    if (v) Object.keys(v).forEach(function(x){ s = s.split('{' + x + '}').join(v[x]); });
    return s;
  };
  WF.paint = function(root){
    (root || document).querySelectorAll('[data-w]').forEach(function(e){ e.textContent = WF.t(e.getAttribute('data-w')); });
  };
  WF.setLang = function(en){ set(LK, en ? 'en' : 'kr'); location.reload(); };
  WF.langSwitch = function(host){
    var d = document.createElement('div'); d.className = 'wf-lang';
    d.innerHTML = '<button data-l="kr" aria-label="한국어">한</button><button data-l="en" aria-label="English">EN</button>';   // 🔴 2026-11-20 좁게 — 제목이 잘리지 않게
    d.querySelector('[data-l="' + (EN ? 'en' : 'kr') + '"]').classList.add('on');
    d.onclick = function(e){ var b = e.target.closest('button'); if (b) WF.setLang(b.dataset.l === 'en'); };
    host.appendChild(d);
  };
  WF.shown = function(n){ return n.slice(0,4) + ' ' + n.slice(4,7) + ' ' + n.slice(7); };
  WF.price = function(g){ var p = { '5':110000, '4':55000, '3':11000, 'N':0 }[g] || 0;
    if (!p) return WF.t('free'); return EN ? '₩' + p.toLocaleString('en-US') : p.toLocaleString('ko-KR') + '원'; };
  WF.krw = function(p){ return EN ? '₩' + p.toLocaleString('en-US') : p.toLocaleString('ko-KR') + '원'; };
  WF.badge = function(g){ return (g === '5' || g === '4' || g === '3') ? '<span class="badge g' + g + '">' + '★'.repeat(+g) + '</span>' : ''; };
  WF.date = function(iso){ try { var d = new Date(iso); return EN ? d.toLocaleDateString('en-US', { year:'numeric', month:'short', day:'numeric' })
    : d.getFullYear() + '년 ' + (d.getMonth() + 1) + '월 ' + d.getDate() + '일'; } catch (e) { return iso; } };
  WF.toast = function(msg){ var t = document.createElement('div'); t.className = 'toast'; t.textContent = msg; document.body.appendChild(t);
    setTimeout(function(){ t.remove(); }, 2600); };
  WF.esc = function(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, function(c){ return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]; }); };
  WF.rpc = async function(fn, args){
    var r = await AL.sb.rpc(fn, args || {});
    if (r.error) { console.error('[wafa]', fn, r.error); throw r.error; }
    return r.data;
  };
  WF.me = async function(){ return await WF.rpc('wafa_me'); };
  WF.header = function(title, backTo){
    var h = document.querySelector('.wf-top'); if (!h) return;
    if (backTo) { var b = document.createElement('button'); b.className = 'wf-back'; b.textContent = WF.t('back');
      b.onclick = function(){ location.href = backTo; }; h.appendChild(b); }
    else { var l = document.createElement('div'); l.className = 'wf-logo'; l.innerHTML = '<i>W</i>WAFA'; h.appendChild(l); }
    if (title) { var t = document.createElement('h1'); t.className = 'wf-title'; t.textContent = title; h.appendChild(t); }
    var sp = document.createElement('div'); sp.className = 'wf-sp'; h.appendChild(sp);
    WF.themeBtn(h);
    WF.langSwitch(h);
  };
  /* 주간 · 야간 단추 — 지금 보이는 것과 반대로 바꿉니다 */
  WF.isDark = function(){ var a = document.documentElement.getAttribute('data-theme'); return a ? a === 'dark' : !!(window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches); };
  WF.themeBtn = function(host){
    var b = document.createElement('button'); b.type = 'button'; b.className = 'wf-theme';
    var paint = function(){ var d = WF.isDark(); b.textContent = d ? '☀️' : '🌙'; b.title = d ? WF.t('toLight') : WF.t('toDark'); b.setAttribute('aria-label', b.title); };
    b.onclick = function(){ var to = WF.isDark() ? 'light' : 'dark'; document.documentElement.setAttribute('data-theme', to); set('wafa_theme', to); paint(); if (WF.onTheme) WF.onTheme(to); };
    paint(); host.appendChild(b); return b;
  };
  /* 🔴 2026-11-20 약관 링크 — 자동 갱신 구독을 파는 화면에는 이용약관 · 개인정보처리방침이 꼭 보여야 합니다(애플 3.1.2) */
  WF.legal = function(host){
    if (!host) return;
    var p = document.createElement('p'); p.className = 'muted wf-legal';
    p.style.cssText = 'text-align:center;font-size:12.5px;margin:8px 0 0';
    p.innerHTML = '<a href="wafa_terms.html" style="color:inherit">' + WF.t('terms') + '</a> · ' +
      '<a href="wafa_privacy.html" style="color:inherit">' + WF.t('privacy') + '</a> · ' +
      '<a href="wafa_refund.html" style="color:inherit">' + WF.t('refund') + '</a>';
    host.appendChild(p);
  };
  /* 🔴 2026-11-20 로그아웃 — 한 번 누르면 「한 번 더 누르면 로그아웃」, 3초 안에 다시 누르면 로그아웃(실수 막기) */
  WF.logoutBtn = function(host){
    if (!host) return;
    var b = document.createElement('button'); b.type = 'button'; b.className = 'btn ghost wf-logout';
    b.style.marginTop = '6px'; b.textContent = WF.t('logout');
    var armed = false, tm;
    b.onclick = async function(){
      if (!armed) { armed = true; b.textContent = WF.t('logoutAgain'); tm = setTimeout(function(){ armed = false; b.textContent = WF.t('logout'); }, 3000); return; }
      clearTimeout(tm); b.disabled = true;
      try { await AL.signOut(); } catch (e) { location.href = 'alias_auth.html'; }
    };
    host.appendChild(b); return b;
  };
  WF.subLine = function(me){
    var s = me && me.sub;
    if (!s || s.status === 'expired' || s.status === 'refunded' || new Date(s.until) < new Date()) return WF.t('subNone');
    var d = WF.date(s.until);
    return s.status === 'canceled' ? WF.t('subCanceled', { d:d }) : s.status === 'grace' ? WF.t('subGrace', { d:d }) : WF.t('subActive', { d:d });
  };

  /* ── 결제 ─────────────────────────────────────────────────────
     구독: 구글은 구독 상품 하나(wafa_plan) 안의 기본 요금제(wafa-1m …)를 고릅니다.
           앱(BillingBridge)이 obfuscatedAccountId = 로그인한 사람 id 로 결제창을 엽니다.
     한 번 사는 것: wafa_addon · wafa_number_5/4/3 · wafa_number_extra */
  WF.PLANS = [
    { id:'wafa_1m', base:'wafa-1m', k:'p1', price:1500, months:1 },
    { id:'wafa_3m', base:'wafa-3m', k:'p3', price:3300, months:3 },
    { id:'wafa_6m', base:'wafa-6m', k:'p6', price:5500, months:6 },
    { id:'wafa_12m', base:'wafa-12m', k:'p12', price:9900, months:12 },
  ];
  WF.native = function(){ return window.AliasNative || null; };
  WF.subscribe = function(plan){
    var n = WF.native();
    if (!(n && typeof n.storeSubscribe === 'function')) { WF.toast(WF.t('webOnly')); return false; }
    /* 🔴 세 번째 값 = 로그인한 사람 id → 구글이 obfuscatedAccountId 로 영수증에 적어 둡니다(서버가 누구 구독인지 확인) */
    AL.sb.auth.getSession().then(function(r){
      var uid = r && r.data && r.data.session && r.data.session.user && r.data.session.user.id;
      if (!uid) { WF.toast(WF.t('err')); return; }
      n.storeSubscribe('wafa_plan', plan.base, uid);
    });
    return true;
  };
  WF.buy = function(sku){
    var n = WF.native();
    if (n && typeof n.storeBuy === 'function') { n.storeBuy(sku); return true; }
    WF.toast(WF.t('webOnly')); return false;
  };
  /* 🔴 2026-11-19 아이폰 앱이면 앱 안에서 애플 구독 관리 창을 엽니다 */
  WF.manage = function(){ var n = WF.native(); if (n && typeof n.storeManage === 'function') { n.storeManage(); return true; } return false; };
  WF.manageUrl = function(){
    if (AL.platform && AL.platform() === 'ios') return 'https://apps.apple.com/account/subscriptions';
    return 'https://play.google.com/store/account/subscriptions?sku=wafa_plan&package=com.weaveapp.wafa';
  };
  WF.onDone = null;      // 화면이 정해 두면 결제 결과를 받음
  /* 부름의 AL.onStoreEvent 를 와파 것으로 바꿉니다 — 영수증은 wafa-verify 로 */
  AL.onStoreEvent = async function(ev){
    ev = ev || {};
    var done = function(o){ if (WF.onDone) WF.onDone(o); else if (o.ok) WF.toast(WF.t('payOk')); };
    if (ev.kind === 'storeCanceled') return done({ ok:false, canceled:true });
    if (ev.kind === 'storePending') return done({ ok:false, pending:true });
    if (ev.kind === 'storeError' || ev.kind === 'storeOwned') return done({ ok:false, error: ev.a || ev.code || '' });
    if (ev.kind !== 'storePurchase') return;
    try {
      var sess = await AL.sb.auth.getSession();
      if (!sess.data.session) throw new Error('login');
      var res = await fetch(AL.SUPABASE_URL + '/functions/v1/wafa-verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + sess.data.session.access_token },
        body: JSON.stringify({ productId: ev.sku, purchaseToken: ev.a }),
      });
      var out = await res.json();
      var consumable = ev.sku !== 'wafa_plan' && !/^wafa_\d+m$/.test(ev.sku || '');
      if (out && out.consume && consumable && WF.native() && WF.native().storeConsume) WF.native().storeConsume(ev.a);
      if (!res.ok || !out.ok) return done({ ok:false, error: out && out.error });
      if (consumable && WF.native() && WF.native().storeConsume) WF.native().storeConsume(ev.a);   // 다시 살 수 있게 정리
      /* 🔴 2026-11-19 아이폰 — 구독도 서버 확인이 끝나면 애플 거래를 정리(finish)해야 다음에 다시 오지 않습니다 */
      else if (/^apple:/.test(ev.a || '') && WF.native() && WF.native().storeConsume) WF.native().storeConsume(ev.a);
      done(Object.assign({ ok:true, sku: ev.sku }, out));
    } catch (e) {
      console.error('[wafa] 결제 확인 실패', e);
      done({ ok:false, error: String(e && e.message || e) });
    }
  };
})();
