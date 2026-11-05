'use strict';
(() => {
  const $ = (q, root = document) => root.querySelector(q);
  const $$ = (q, root = document) => [...root.querySelectorAll(q)];
  const store = { get(k) { try { return localStorage.getItem(k); } catch { return null; } }, set(k, v) { try { localStorage.setItem(k, v); } catch {} } };
  const theme = store.get('pulse-theme') || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  document.documentElement.dataset.theme = theme;
  $('#theme-toggle')?.addEventListener('click', () => {
    const next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
    document.documentElement.dataset.theme = next;
    store.set('pulse-theme', next);
    $('#theme-toggle').setAttribute('aria-label', `Switch to ${next === 'dark' ? 'light' : 'dark'} theme`);
  });
  function toast(message) {
    const box = document.createElement('div'); box.className = 'toast'; box.setAttribute('role', 'status'); box.textContent = message;
    document.body.append(box); setTimeout(() => box.remove(), 4500);
  }
  $$('time[datetime]').forEach(el => {
    const date = new Date(el.dateTime);
    if (!Number.isNaN(date.getTime())) { el.textContent = date.toLocaleString(undefined, {month:'short', day:'numeric', hour:'2-digit', minute:'2-digit'}); el.title = date.toISOString(); }
  });
  const search = $('#monitor-search'), project = $('#project-filter'), status = $('#status-filter');
  function filter() {
    let visible = 0;
    $$('[data-monitor]').forEach(row => {
      const match = (!search?.value || row.dataset.search.includes(search.value.toLowerCase())) && (!project?.value || row.dataset.project === project.value) && (!status?.value || row.dataset.status === status.value);
      row.hidden = !match; if (match) visible++;
    });
    if ($('#filter-count')) $('#filter-count').textContent = `${visible} monitor${visible === 1 ? '' : 's'}`;
    if ($('#filter-empty')) $('#filter-empty').hidden = visible > 0;
  }
  [search, project, status].forEach(el => el?.addEventListener('input', filter));
  if (search) filter();
  document.addEventListener('keydown', event => {
    if (event.key === '/' && !['INPUT','TEXTAREA','SELECT'].includes(document.activeElement?.tagName)) { event.preventDefault(); search?.focus(); }
    if (event.key === 'Escape' && document.activeElement === search) { search.value = ''; filter(); search.blur(); }
  });
  $$('form[data-confirm]').forEach(form => form.addEventListener('submit', event => { if (!confirm(form.dataset.confirm)) event.preventDefault(); }));
  $$('form').forEach(form => form.addEventListener('submit', event => {
    if (event.defaultPrevented || form.id === 'playground') return;
    const button = $('button[type=submit]', form); if (button) { button.disabled = true; button.textContent = 'Working…'; }
  }));
  $$('[data-copy]').forEach(button => button.addEventListener('click', async () => { try { await navigator.clipboard.writeText(button.dataset.copy); toast('URL copied'); } catch { toast('Clipboard unavailable. Select and copy the URL.'); } }));
  const refresh = $('#auto-refresh');
  if (refresh) {
    refresh.checked = store.get('pulse-refresh') === 'true';
    refresh.addEventListener('change', () => store.set('pulse-refresh', String(refresh.checked)));
    setInterval(() => { if (refresh.checked && !document.hidden && !['INPUT','TEXTAREA','SELECT'].includes(document.activeElement?.tagName)) location.reload(); }, 60000);
  }
  const samples = {
    health: { contract:{type:'object',required:{status:{type:'string',enum:['ok']},version:{type:'string'}},allow_extra_fields:true}, response:{status:'ok',version:'1.4.0',region:'eu'} },
    users: { contract:{type:'array',items:{type:'object',required:{id:{type:'integer',minimum:1},name:{type:'string',min_length:1}},optional:{email:{type:'string',nullable:true}},allow_extra_fields:false}}, response:[{id:1,name:'Alex',email:null},{id:2,name:'Sam',email:'sam@example.test'}] },
    drift: { contract:{type:'object',required:{id:{type:'integer'},active:{type:'boolean'}},allow_extra_fields:false}, response:{id:'42',extra:'unexpected'} }
  };
  $$('[data-preset]').forEach(button => button.addEventListener('click', () => {
    const sample = samples[button.dataset.preset]; if (!sample) return;
    $('#contract').value = JSON.stringify(sample.contract,null,2);
    if ($('#response')) $('#response').value = JSON.stringify(sample.response,null,2);
    if ($('#playground-result')) $('#playground-result').textContent = 'Example loaded. Run validation to inspect the result.';
  }));
  $$('[data-format]').forEach(button => button.addEventListener('click', () => {
    const target = document.getElementById(button.dataset.format);
    try { target.value = JSON.stringify(JSON.parse(target.value),null,2); toast('JSON formatted'); }
    catch (error) { toast(`Invalid JSON: ${error.message}`); }
  }));
  $('#playground')?.addEventListener('submit', async event => {
    event.preventDefault();
    const result = $('#playground-result'), button = $('#validate-contract');
    try {
      const contract = JSON.parse($('#contract').value), response = JSON.parse($('#response').value);
      button.disabled = true; result.textContent = 'Validating…';
      const res = await fetch('/api/validate', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({contract,response})});
      if (!res.ok) throw new Error(res.status === 413 ? 'Input is too large (maximum 128 KiB).' : `Validation request failed (${res.status}).`);
      const data = await res.json();
      result.textContent = data.valid ? '✓ Contract matched. All checks passed.' : data.errors.map(error => `${error.path}  →  ${error.message}`).join('\n');
      result.classList.toggle('negative', !data.valid); result.classList.toggle('positive', data.valid);
    } catch (error) { result.textContent = error.message; result.classList.add('negative'); }
    finally { button.disabled = false; }
  });
})();
