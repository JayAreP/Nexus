// Nexus - Core (navigation, helpers, config, sandbox, init)

// ===== NAVIGATION =====
document.querySelectorAll('.nav-link').forEach(link => {
    link.addEventListener('click', (e) => {
        e.preventDefault();
        document.querySelectorAll('.nav-link').forEach(l => l.classList.remove('active'));
        link.classList.add('active');
        const panelId = link.dataset.panel;
        document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
        document.getElementById(panelId + '-panel').classList.add('active');

        // Refresh data when switching panels
        if (panelId === 'workflows') loadWorkflowList();
        if (panelId === 'scripts') loadScripts();
        if (panelId === 'webhooks') loadWebhookList();
        if (panelId === 'filechecks') loadFileCheckList();
        if (panelId === 'credentials') loadCredentialList();
        if (panelId === 'runner') { loadWorkflowDropdowns(); loadScheduleList(); }
        if (panelId === 'logs') loadWorkflowDropdowns();
        if (panelId === 'modules') { document.getElementById('modules-output').innerHTML = ''; document.getElementById('modules-empty').style.display = 'block'; }
        if (panelId === 'config') loadConfig();
    });
});

// ===== HELPERS =====
const langMap = { powershell: 'powershell', python: 'python', shell: 'bash', terraform: 'hcl', webhook: 'json', filecheck: 'json' };

function renderHighlighted(container, code, type) {
    const lang = langMap[type] || 'plaintext';
    const pre = document.createElement('pre');
    pre.style.cssText = 'font-size: 12px; padding: 16px; overflow-x: auto; white-space: pre-wrap; max-height: 70vh; overflow-y: auto; margin: 0;';
    const codeEl = document.createElement('code');
    codeEl.className = `language-${lang}`;
    codeEl.textContent = code;
    pre.appendChild(codeEl);
    container.innerHTML = '';
    container.appendChild(pre);
    hljs.highlightElement(codeEl);
}

function showMessage(elementId, type, text) {
    const el = document.getElementById(elementId);
    el.className = 'message ' + type;
    el.textContent = text;
    if (type === 'success' || type === 'info') {
        setTimeout(() => { el.className = 'message'; el.textContent = ''; }, 5000);
    }
}

function clearMessage(elementId) {
    const el = document.getElementById(elementId);
    el.className = 'message';
    el.textContent = '';
}

function escHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

// ===== CONFIGURATION =====
async function loadConfig() {
    try {
        const r = await fetch('/api/config');
        const data = await r.json();
        if (data.success) {
            document.getElementById('config-storage-account').value = data.storageAccount || '';
            document.getElementById('config-key').value = data.key || '';
            document.getElementById('config-resource-group').value = data.resourceGroup || '';
        }
    } catch (err) {
        showMessage('config-message', 'error', 'Failed to load config: ' + err.message);
    }
}

document.getElementById('config-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    try {
        const r = await fetch('/api/config', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                storageAccount: document.getElementById('config-storage-account').value,
                key: document.getElementById('config-key').value,
                resourceGroup: document.getElementById('config-resource-group').value
            })
        });
        const data = await r.json();
        showMessage('config-message', data.success ? 'success' : 'error', data.message);
    } catch (err) {
        showMessage('config-message', 'error', 'Error saving config: ' + err.message);
    }
});

document.getElementById('prepare-containers-btn').addEventListener('click', async () => {
    const btn = document.getElementById('prepare-containers-btn');
    btn.disabled = true;
    btn.textContent = 'Preparing...';
    try {
        const r = await fetch('/api/config/prepare', { method: 'POST' });
        const data = await r.json();
        showMessage('config-message', data.success ? 'success' : 'error', data.message);
    } catch (err) {
        showMessage('config-message', 'error', 'Error: ' + err.message);
    } finally {
        btn.disabled = false;
        btn.textContent = 'Prepare Containers';
    }
});

// ===== SANDBOX =====
document.getElementById('sandbox-open-btn').addEventListener('click', () => {
    const ttydUrl = `${window.location.protocol}//${window.location.hostname}:7681`;
    window.open(ttydUrl, '_blank');
});

document.getElementById('sandbox-reset-btn').addEventListener('click', async () => {
    if (!confirm('Reset sandbox? This will delete all files in /home/sandbox/workspace.')) return;
    try {
        const r = await fetch('/api/sandbox/reset', { method: 'POST' });
        const data = await r.json();
        showMessage('sandbox-message', data.success ? 'success' : 'error', data.message);
    } catch (err) {
        showMessage('sandbox-message', 'error', 'Error: ' + err.message);
    }
});

// ===== INIT =====
let serverTimeOffset = 0;

async function loadVersion() {
    try {
        const r = await fetch('/api/version');
        const data = await r.json();
        document.getElementById('version-number').textContent = data.version || 'unknown';
        if (data.serverTime) {
            serverTimeOffset = new Date(data.serverTime).getTime() - Date.now();
        }
    } catch (err) {
        document.getElementById('version-number').textContent = 'error';
    }
}

function tickServerTime() {
    const now = new Date(Date.now() + serverTimeOffset);
    const pad = n => String(n).padStart(2, '0');
    document.getElementById('server-time').textContent =
        `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
}

document.addEventListener('DOMContentLoaded', () => {
    loadVersion();
    loadWorkflowList();
    setInterval(tickServerTime, 1000);
});
