// Audiobookshelf — 前端占位页（实际 UI 内嵌于上游单文件二进制，
// 经 TOS nginx /audiobookshelf/ 路由访问；本页仅满足 webui.bz2 规范，
// 并附隐私政策入口（坑 21：可达性）
(function () {
  var target = '/audiobookshelf/';
  document.getElementById('link').href = target;
  setTimeout(function () { window.location.replace(target); }, 800);
})();
