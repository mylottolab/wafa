/* =====================================================================
   와파 첫 화면 고르기 (2026-11-22) — ☎ 다이얼 첫 화면 시험
   · 'classic' = 지금 첫 화면(번호판 · 최근 · 연락처)   · 'dial' = 큰 다이얼 첫 화면(wafa_home_dial.html)
   · 모든 분을 한 번에 바꾸려면 아래 ALL 한 글자만 'dial' 로, 되돌리려면 'classic' 으로 (앱 업데이트 필요 없음)
   · 이 폰만 시험: wafa_home_dial.html?try=1 을 한 번 열면 이 폰만 다이얼 첫 화면이 됩니다.
     다이얼 화면 아래 [원래 첫 화면으로] 를 누르면 이 폰은 바로 원래대로.
   ===================================================================== */
(function(){
  var ALL = 'dial';   // 2026-11-22 개편 — 다이얼 첫 화면(되돌리려면 'classic')   // ← 전체 전환 스위치: 'classic' | 'dial'
  var m = ALL;
  try { var l = localStorage.getItem('wafa_home_mode'); if (l === 'dial' || l === 'classic') m = l; } catch (e) {}
  window.WAFA_HOME = m;
  window.WAFA_HOME_ALL = ALL;
  window.WAFA_HOME_URL = m === 'dial' ? 'wafa_home_dial.html' : 'wafa_dial.html';
})();
