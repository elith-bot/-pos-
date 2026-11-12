// Browser downloads need no directory picker. Keep only session metadata.
(() => {
  const files = new Map();
  const folder = 'تنزيلات المتصفح';
  const validName = name => /^pos-[a-z0-9-]+\.(pdf|xlsx|csv|json)$/.test(name);
  function checkScope(scope) {
    if (!/^[a-zA-Z0-9_-]+$/.test(scope)) throw new Error('Invalid export scope');
  }
  async function prepare(scope) { checkScope(scope); return folder; }
  async function save(scope, encoded, name, mime) {
    checkScope(scope);
    if (!validName(name)) throw new Error('Invalid export filename');
    const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
    const url = URL.createObjectURL(new Blob([bytes], {type: mime}));
    const link = document.createElement('a');
    try {
      link.href = url;
      link.download = name;
      document.body.appendChild(link);
      link.click();
    } finally {
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    }
    const entry = {filename:name, size:bytes.length, modified:Date.now(), folder, mime, download:true};
    const history = files.get(scope) || [];
    history.unshift(entry);
    files.set(scope, history.slice(0, 100));
    return JSON.stringify(entry);
  }
  async function list(scope) { checkScope(scope); return JSON.stringify(files.get(scope) || []); }
  async function open(scope, name) {
    checkScope(scope);
    if (!validName(name)) throw new Error('Invalid export filename');
    throw new Error('افتح قائمة التنزيلات في المتصفح ثم اختر إظهار الملف في المجلد.');
  }
  window.posExportStorage = {prepare, save, list, open};
})();
