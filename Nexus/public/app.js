// Nexus - Automation Sequencer Frontend

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

// ===== SCRIPTS =====
let currentScriptType = 'powershell';

document.querySelectorAll('.script-tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.script-tab').forEach(t => {
            t.classList.remove('active');
            t.classList.remove('btn-primary');
            t.classList.add('btn-secondary');
        });
        tab.classList.add('active');
        tab.classList.remove('btn-secondary');
        tab.classList.add('btn-primary');
        currentScriptType = tab.dataset.type;
        document.getElementById('upload-type-label').textContent =
            tab.textContent.trim();
        loadScripts();
    });
});

async function loadScripts() {
    const listEl = document.getElementById('script-list');
    const emptyEl = document.getElementById('script-list-empty');
    listEl.innerHTML = '';

    try {
        const r = await fetch(`/api/scripts/${currentScriptType}`);
        const data = await r.json();
        if (data.success && data.scripts && data.scripts.length > 0) {
            emptyEl.style.display = 'none';
            data.scripts.forEach(s => {
                const item = document.createElement('div');
                item.className = 'script-item';
                item.innerHTML = `
                    <span class="script-item-name">${s.name}</span>
                    <div style="display: flex; gap: 6px;">
                        <button class="btn btn-secondary btn-sm" onclick="previewScript('${currentScriptType}', '${s.name}')">Preview</button>
                        <button class="btn btn-danger btn-sm" onclick="deleteScript('${currentScriptType}', '${s.name}')">Delete</button>
                    </div>
                `;
                listEl.appendChild(item);
            });
        } else {
            emptyEl.style.display = 'block';
        }
    } catch (err) {
        showMessage('scripts-message', 'error', 'Error loading scripts: ' + err.message);
    }
}

async function deleteScript(type, name) {
    if (!confirm(`Delete script "${name}"?`)) return;
    try {
        const r = await fetch(`/api/scripts/${type}/${encodeURIComponent(name)}`, { method: 'DELETE' });
        const data = await r.json();
        showMessage('scripts-message', data.success ? 'success' : 'error', data.message);
        loadScripts();
    } catch (err) {
        showMessage('scripts-message', 'error', 'Error: ' + err.message);
    }
}

async function previewScript(type, name) {
    const modal = document.getElementById('preview-modal');
    const titleEl = document.getElementById('preview-modal-title');
    const contentEl = document.getElementById('preview-modal-content');
    titleEl.textContent = name;
    contentEl.innerHTML = '<p style="color: var(--text-secondary);">Loading...</p>';
    modal.style.display = 'flex';
    try {
        const r = await fetch(`/api/scripts/${encodeURIComponent(type)}/${encodeURIComponent(name)}/content`);
        const data = await r.json();
        if (data.success) {
            renderHighlighted(contentEl, data.content, type);
        } else {
            contentEl.innerHTML = `<p style="color: var(--error-color);">${escHtml(data.message)}</p>`;
        }
    } catch (err) {
        contentEl.innerHTML = `<p style="color: var(--error-color);">Error: ${escHtml(err.message)}</p>`;
    }
}

// Upload handling
const uploadArea = document.getElementById('upload-area');
const fileInput = document.getElementById('script-file-input');

uploadArea.addEventListener('click', () => fileInput.click());
uploadArea.addEventListener('dragover', (e) => { e.preventDefault(); uploadArea.style.borderColor = '#ff6600'; });
uploadArea.addEventListener('dragleave', () => { uploadArea.style.borderColor = '#cbd5e0'; });
uploadArea.addEventListener('drop', (e) => {
    e.preventDefault();
    uploadArea.style.borderColor = '#cbd5e0';
    if (e.dataTransfer.files.length > 0) uploadFile(e.dataTransfer.files[0]);
});
fileInput.addEventListener('change', () => {
    if (fileInput.files.length > 0) uploadFile(fileInput.files[0]);
});

async function uploadFile(file) {
    const formData = new FormData();
    formData.append('file', file);
    try {
        const r = await fetch(`/api/scripts/${currentScriptType}`, {
            method: 'POST',
            body: formData
        });
        const data = await r.json();
        showMessage('scripts-message', data.success ? 'success' : 'error', data.message);
        loadScripts();
    } catch (err) {
        showMessage('scripts-message', 'error', 'Upload error: ' + err.message);
    }
    fileInput.value = '';
}

// ===== WEBHOOKS =====
async function loadWebhookList() {
    const listEl = document.getElementById('webhook-list');
    const emptyEl = document.getElementById('webhook-list-empty');
    listEl.innerHTML = '';

    try {
        const r = await fetch('/api/webhooks');
        const data = await r.json();
        if (data.success && data.webhooks && data.webhooks.length > 0) {
            emptyEl.style.display = 'none';
            data.webhooks.forEach(wh => {
                const card = document.createElement('div');
                card.className = 'script-item';
                card.innerHTML = `
                    <div>
                        <span style="font-weight: 500; font-size: 13px;">${wh.name}</span>
                        <span style="font-size: 11px; color: var(--text-secondary); margin-left: 8px;">${wh.authType === 'oauth' ? 'OAuth' : 'Direct'}</span>
                    </div>
                    <button class="btn btn-danger btn-sm" onclick="deleteWebhook('${wh.name}')">Delete</button>
                `;
                listEl.appendChild(card);
            });
        } else {
            emptyEl.style.display = 'block';
        }
    } catch (err) {
        showMessage('webhooks-message', 'error', 'Error: ' + err.message);
    }
}

async function deleteWebhook(name) {
    if (!confirm(`Delete webhook "${name}"?`)) return;
    try {
        const r = await fetch(`/api/webhooks/${encodeURIComponent(name)}`, { method: 'DELETE' });
        const data = await r.json();
        showMessage('webhooks-message', data.success ? 'success' : 'error', data.message);
        loadWebhookList();
    } catch (err) {
        showMessage('webhooks-message', 'error', 'Error: ' + err.message);
    }
}

document.getElementById('add-webhook-btn').addEventListener('click', () => {
    document.getElementById('webhook-form').style.display = 'block';
    document.getElementById('webhook-name').value = '';
    document.getElementById('webhook-uri').value = '';
    document.getElementById('webhook-auth-type').value = 'none';
    document.getElementById('webhook-oauth-fields').style.display = 'none';
    document.getElementById('webhook-tenant-id').value = '';
    document.getElementById('webhook-client-id').value = '';
    document.getElementById('webhook-client-secret').value = '';
});

document.getElementById('cancel-webhook-btn').addEventListener('click', () => {
    document.getElementById('webhook-form').style.display = 'none';
});

document.getElementById('webhook-auth-type').addEventListener('change', (e) => {
    document.getElementById('webhook-oauth-fields').style.display =
        e.target.value === 'oauth' ? 'block' : 'none';
});

document.getElementById('save-webhook-btn').addEventListener('click', async () => {
    const payload = {
        name: document.getElementById('webhook-name').value.trim(),
        uri: document.getElementById('webhook-uri').value.trim(),
        authType: document.getElementById('webhook-auth-type').value,
        tenantId: document.getElementById('webhook-tenant-id').value.trim(),
        clientId: document.getElementById('webhook-client-id').value.trim(),
        clientSecret: document.getElementById('webhook-client-secret').value.trim()
    };
    if (!payload.name || !payload.uri) {
        showMessage('webhooks-message', 'error', 'Name and URI are required');
        return;
    }
    try {
        const r = await fetch('/api/webhooks', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await r.json();
        showMessage('webhooks-message', data.success ? 'success' : 'error', data.message);
        if (data.success) {
            document.getElementById('webhook-form').style.display = 'none';
            loadWebhookList();
        }
    } catch (err) {
        showMessage('webhooks-message', 'error', 'Error: ' + err.message);
    }
});

// ===== FILE CHECKS =====
async function loadFileCheckList() {
    const listEl = document.getElementById('filecheck-list');
    const emptyEl = document.getElementById('filecheck-list-empty');
    listEl.innerHTML = '';

    try {
        const r = await fetch('/api/filechecks');
        const data = await r.json();
        if (data.success && data.filechecks && data.filechecks.length > 0) {
            emptyEl.style.display = 'none';
            data.filechecks.forEach(fc => {
                const card = document.createElement('div');
                card.className = 'script-item';
                card.innerHTML = `
                    <div>
                        <span style="font-weight: 500; font-size: 13px;">${fc.name}</span>
                        <span style="font-size: 11px; color: var(--text-secondary); margin-left: 8px;">${fc.storageAccount}</span>
                        <span style="font-size: 11px; color: var(--text-secondary); margin-left: 8px;">${fc.authType === 'sas' ? 'SAS' : 'RBAC'}</span>
                    </div>
                    <button class="btn btn-danger btn-sm" onclick="deleteFileCheck('${fc.name}')">Delete</button>
                `;
                listEl.appendChild(card);
            });
        } else {
            emptyEl.style.display = 'block';
        }
    } catch (err) {
        showMessage('filechecks-message', 'error', 'Error: ' + err.message);
    }
}

async function deleteFileCheck(name) {
    if (!confirm(`Delete file check "${name}"?`)) return;
    try {
        const r = await fetch(`/api/filechecks/${encodeURIComponent(name)}`, { method: 'DELETE' });
        const data = await r.json();
        showMessage('filechecks-message', data.success ? 'success' : 'error', data.message);
        loadFileCheckList();
    } catch (err) {
        showMessage('filechecks-message', 'error', 'Error: ' + err.message);
    }
}

document.getElementById('add-filecheck-btn').addEventListener('click', () => {
    document.getElementById('filecheck-form').style.display = 'block';
    document.getElementById('filecheck-name').value = '';
    document.getElementById('filecheck-storage-account').value = '';
    document.getElementById('filecheck-auth-type').value = 'rbac';
    document.getElementById('filecheck-sas-fields').style.display = 'none';
    document.getElementById('filecheck-sas-token').value = '';
});

document.getElementById('cancel-filecheck-btn').addEventListener('click', () => {
    document.getElementById('filecheck-form').style.display = 'none';
});

document.getElementById('filecheck-auth-type').addEventListener('change', (e) => {
    document.getElementById('filecheck-sas-fields').style.display =
        e.target.value === 'sas' ? 'block' : 'none';
});

document.getElementById('save-filecheck-btn').addEventListener('click', async () => {
    const payload = {
        name: document.getElementById('filecheck-name').value.trim(),
        storageAccount: document.getElementById('filecheck-storage-account').value.trim(),
        authType: document.getElementById('filecheck-auth-type').value,
        sasToken: document.getElementById('filecheck-sas-token').value.trim()
    };
    if (!payload.name || !payload.storageAccount) {
        showMessage('filechecks-message', 'error', 'Name and Storage Account are required');
        return;
    }
    if (payload.authType === 'sas' && !payload.sasToken) {
        showMessage('filechecks-message', 'error', 'SAS token is required for SAS auth type');
        return;
    }
    try {
        const r = await fetch('/api/filechecks', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await r.json();
        showMessage('filechecks-message', data.success ? 'success' : 'error', data.message);
        if (data.success) {
            document.getElementById('filecheck-form').style.display = 'none';
            loadFileCheckList();
        }
    } catch (err) {
        showMessage('filechecks-message', 'error', 'Error: ' + err.message);
    }
});

// ===== WORKFLOW BUILDER =====
let currentWorkflow = { name: '', steps: [] };
let editingWorkflowName = null;

async function loadWorkflowList() {
    const listEl = document.getElementById('workflow-list');
    const emptyEl = document.getElementById('workflow-list-empty');
    listEl.innerHTML = '';

    try {
        const r = await fetch('/api/workflows');
        const data = await r.json();
        if (data.success && data.workflows && data.workflows.length > 0) {
            emptyEl.style.display = 'none';
            data.workflows.forEach(wf => {
                const card = document.createElement('div');
                card.className = 'workflow-card';
                card.innerHTML = `
                    <div>
                        <h4>${wf.name}</h4>
                        <span class="step-count">${wf.stepCount || 0} step(s)</span>
                    </div>
                    <div style="display: flex; gap: 8px;">
                        <button class="btn btn-secondary btn-sm" onclick="openExportModal('${wf.name}')">Export</button>
                        <button class="btn btn-primary btn-sm" onclick="editWorkflow('${wf.name}')">Edit</button>
                        <button class="btn btn-danger btn-sm" onclick="deleteWorkflow('${wf.name}')">Delete</button>
                    </div>
                `;
                listEl.appendChild(card);
            });
        } else {
            emptyEl.style.display = 'block';
        }
    } catch (err) {
        showMessage('workflow-message', 'error', 'Error: ' + err.message);
    }
}

async function editWorkflow(name) {
    try {
        const r = await fetch(`/api/workflows/${encodeURIComponent(name)}`);
        const data = await r.json();
        if (data.success) {
            editingWorkflowName = name;
            currentWorkflow = data.workflow;
            document.getElementById('workflow-name').value = currentWorkflow.name;
            renderLadder();
            document.getElementById('workflow-editor').style.display = 'block';
        }
    } catch (err) {
        showMessage('workflow-message', 'error', 'Error: ' + err.message);
    }
}

async function deleteWorkflow(name) {
    if (!confirm(`Delete workflow "${name}"?`)) return;
    try {
        const r = await fetch(`/api/workflows/${encodeURIComponent(name)}`, { method: 'DELETE' });
        const data = await r.json();
        showMessage('workflow-message', data.success ? 'success' : 'error', data.message);
        loadWorkflowList();
    } catch (err) {
        showMessage('workflow-message', 'error', 'Error: ' + err.message);
    }
}

document.getElementById('new-workflow-btn').addEventListener('click', () => {
    editingWorkflowName = null;
    currentWorkflow = { name: '', steps: [] };
    document.getElementById('workflow-name').value = '';
    renderLadder();
    document.getElementById('workflow-editor').style.display = 'block';
});

document.getElementById('cancel-workflow-btn').addEventListener('click', () => {
    document.getElementById('workflow-editor').style.display = 'none';
    editingWorkflowName = null;
});

document.getElementById('save-workflow-btn').addEventListener('click', async () => {
    const name = document.getElementById('workflow-name').value.trim();
    if (!name) {
        showMessage('workflow-message', 'error', 'Workflow name is required');
        return;
    }
    // Read current state from DOM
    currentWorkflow.name = name;
    readLadderState();

    try {
        const r = await fetch('/api/workflows', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(currentWorkflow)
        });
        const data = await r.json();
        showMessage('workflow-message', data.success ? 'success' : 'error', data.message);
        if (data.success) {
            document.getElementById('workflow-editor').style.display = 'none';
            editingWorkflowName = null;
            loadWorkflowList();
        }
    } catch (err) {
        showMessage('workflow-message', 'error', 'Error: ' + err.message);
    }
});

// ===== LADDER RENDERING =====
function renderLadder() {
    const ladder = document.getElementById('workflow-ladder');
    const emptyEl = document.getElementById('ladder-empty');
    ladder.innerHTML = '';

    if (currentWorkflow.steps.length === 0) {
        emptyEl.style.display = 'block';
        return;
    }
    emptyEl.style.display = 'none';

    currentWorkflow.steps.forEach((step, idx) => {
        // Connector between steps
        if (idx > 0) {
            const connector = document.createElement('div');
            connector.className = 'ladder-connector';
            ladder.appendChild(connector);
        }

        const stepEl = document.createElement('div');
        stepEl.className = 'ladder-step';
        stepEl.dataset.index = idx;

        const badgeClass = 'badge-' + step.type;
        const typeLabel = step.type.charAt(0).toUpperCase() + step.type.slice(1);

        let kvHtml = '';
        (step.params || []).forEach((kv, ki) => {
            kvHtml += `
                <div class="kv-pair" data-kv-index="${ki}">
                    <input type="text" class="kv-key" placeholder="Key" value="${escHtml(kv.key || '')}">
                    <input type="text" class="kv-value" placeholder="Value" value="${escHtml(kv.value || '')}">
                    <button class="kv-remove" onclick="removeKV(${idx}, ${ki})">×</button>
                </div>
            `;
        });

        // Breakpoint check fields
        let breakpointHtml = '';
        (step.breakpointChecks || []).forEach((bp, bi) => {
            breakpointHtml += `
                <div class="kv-pair" data-bp-index="${bi}">
                    <input type="text" class="kv-key" placeholder="JSON property name" value="${escHtml(bp.key || '')}">
                    <input type="text" class="kv-value" placeholder="Expected value" value="${escHtml(bp.value || '')}">
                    <button class="kv-remove" onclick="removeBreakpoint(${idx}, ${bi})">×</button>
                </div>
            `;
        });

        // Input mapping (from prior step outputs)
        let inputHtml = '';
        (step.inputMapping || []).forEach((im, ii) => {
            inputHtml += `
                <div class="kv-pair" data-im-index="${ii}">
                    <input type="text" class="kv-key" placeholder="Param key" value="${escHtml(im.key || '')}">
                    <input type="text" class="kv-value" placeholder="From variable (e.g. step1.runId)" value="${escHtml(im.from || '')}">
                    <button class="kv-remove" onclick="removeInputMapping(${idx}, ${ii})">×</button>
                </div>
            `;
        });

        stepEl.innerHTML = `
            <div class="step-header">
                <div>
                    <span class="step-number">${idx + 1}</span>
                    <span class="step-type-badge ${badgeClass}">${typeLabel}</span>
                    <span style="margin-left: 8px; font-size: 13px; font-weight: 500; color: var(--text-primary);">${escHtml(step.script || step.webhook || step.filecheck || '')}</span>
                </div>
                <div style="display: flex; gap: 6px;">
                    ${idx > 0 ? `<button class="btn btn-secondary btn-sm" onclick="moveStepUp(${idx})">↑</button>` : ''}
                    ${idx < currentWorkflow.steps.length - 1 ? `<button class="btn btn-secondary btn-sm" onclick="moveStepDown(${idx})">↓</button>` : ''}
                    <button class="btn btn-secondary btn-sm" onclick="previewStep(${idx})">Preview</button>
                    <button class="btn btn-danger btn-sm" onclick="removeStep(${idx})">Remove</button>
                </div>
            </div>
            <div class="step-body">
                ${idx > 0 ? `
                <div class="output-capture" style="margin-bottom: 10px;">
                    <label>Input Mapping (from prior step outputs)</label>
                    <div class="input-mapping-list">${inputHtml}</div>
                    <button class="add-kv-btn" onclick="addInputMapping(${idx})">+ Add Input Mapping</button>
                </div>
                ` : ''}
                <label style="font-size: 12px; color: var(--text-secondary); font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; display: block; margin-bottom: 6px;">Parameters</label>
                <div class="kv-list">${kvHtml}</div>
                <button class="add-kv-btn" onclick="addKV(${idx})">+ Add Key/Value</button>

                <div class="output-capture" style="margin-top: 12px;">
                    <label>Breakpoint Checks (halt if value doesn't match)</label>
                    <div class="breakpoint-list">${breakpointHtml}</div>
                    <button class="add-kv-btn" onclick="addBreakpoint(${idx})">+ Add Breakpoint Check</button>
                </div>
            </div>
        `;

        ladder.appendChild(stepEl);
    });
}

function escHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function readLadderState() {
    const stepEls = document.querySelectorAll('.ladder-step');
    stepEls.forEach((stepEl, idx) => {
        if (!currentWorkflow.steps[idx]) return;

        // Read params
        const kvPairs = stepEl.querySelectorAll('.kv-list .kv-pair');
        currentWorkflow.steps[idx].params = [];
        kvPairs.forEach(kv => {
            const key = kv.querySelector('.kv-key').value.trim();
            const value = kv.querySelector('.kv-value').value.trim();
            if (key) currentWorkflow.steps[idx].params.push({ key, value });
        });

        // Read breakpoint checks
        const bpPairs = stepEl.querySelectorAll('.breakpoint-list .kv-pair');
        currentWorkflow.steps[idx].breakpointChecks = [];
        bpPairs.forEach(bp => {
            const key = bp.querySelector('.kv-key').value.trim();
            const value = bp.querySelector('.kv-value').value.trim();
            if (key) currentWorkflow.steps[idx].breakpointChecks.push({ key, value });
        });

        // Read input mappings
        const imPairs = stepEl.querySelectorAll('.input-mapping-list .kv-pair');
        currentWorkflow.steps[idx].inputMapping = [];
        if (imPairs) {
            imPairs.forEach(im => {
                const key = im.querySelector('.kv-key').value.trim();
                const from = im.querySelector('.kv-value').value.trim();
                if (key) currentWorkflow.steps[idx].inputMapping.push({ key, from });
            });
        }
    });
}

function addKV(stepIdx) {
    readLadderState();
    if (!currentWorkflow.steps[stepIdx].params) currentWorkflow.steps[stepIdx].params = [];
    currentWorkflow.steps[stepIdx].params.push({ key: '', value: '' });
    renderLadder();
}

function removeKV(stepIdx, kvIdx) {
    readLadderState();
    currentWorkflow.steps[stepIdx].params.splice(kvIdx, 1);
    renderLadder();
}

function addBreakpoint(stepIdx) {
    readLadderState();
    if (!currentWorkflow.steps[stepIdx].breakpointChecks) currentWorkflow.steps[stepIdx].breakpointChecks = [];
    currentWorkflow.steps[stepIdx].breakpointChecks.push({ key: '', value: '' });
    renderLadder();
}

function removeBreakpoint(stepIdx, bpIdx) {
    readLadderState();
    currentWorkflow.steps[stepIdx].breakpointChecks.splice(bpIdx, 1);
    renderLadder();
}

function addInputMapping(stepIdx) {
    readLadderState();
    if (!currentWorkflow.steps[stepIdx].inputMapping) currentWorkflow.steps[stepIdx].inputMapping = [];
    currentWorkflow.steps[stepIdx].inputMapping.push({ key: '', from: '' });
    renderLadder();
}

function removeInputMapping(stepIdx, imIdx) {
    readLadderState();
    currentWorkflow.steps[stepIdx].inputMapping.splice(imIdx, 1);
    renderLadder();
}

function removeStep(idx) {
    readLadderState();
    currentWorkflow.steps.splice(idx, 1);
    renderLadder();
}

function moveStepUp(idx) {
    if (idx === 0) return;
    readLadderState();
    const temp = currentWorkflow.steps[idx];
    currentWorkflow.steps[idx] = currentWorkflow.steps[idx - 1];
    currentWorkflow.steps[idx - 1] = temp;
    renderLadder();
}

function moveStepDown(idx) {
    if (idx >= currentWorkflow.steps.length - 1) return;
    readLadderState();
    const temp = currentWorkflow.steps[idx];
    currentWorkflow.steps[idx] = currentWorkflow.steps[idx + 1];
    currentWorkflow.steps[idx + 1] = temp;
    renderLadder();
}

// ===== ADD STEP MODAL =====
document.getElementById('add-step-btn').addEventListener('click', () => {
    readLadderState();
    document.getElementById('step-type-select').value = '';
    document.getElementById('step-script-group').style.display = 'none';
    document.getElementById('add-step-modal').style.display = 'flex';
});

document.getElementById('close-step-modal').addEventListener('click', () => {
    document.getElementById('add-step-modal').style.display = 'none';
});

document.getElementById('step-type-select').addEventListener('change', async (e) => {
    const type = e.target.value;
    const scriptGroup = document.getElementById('step-script-group');
    const scriptSelect = document.getElementById('step-script-select');
    scriptSelect.innerHTML = '<option value="">-- Select --</option>';

    if (type === 'webhook') {
        scriptGroup.style.display = 'block';
        scriptGroup.querySelector('label').textContent = 'Webhook';
        try {
            const r = await fetch('/api/webhooks');
            const data = await r.json();
            if (data.success && data.webhooks) {
                data.webhooks.forEach(wh => {
                    const opt = document.createElement('option');
                    opt.value = wh.name;
                    opt.textContent = wh.name;
                    scriptSelect.appendChild(opt);
                });
            }
        } catch (err) { }
    } else if (type === 'filecheck') {
        scriptGroup.style.display = 'block';
        scriptGroup.querySelector('label').textContent = 'File Check';
        try {
            const r = await fetch('/api/filechecks');
            const data = await r.json();
            if (data.success && data.filechecks) {
                data.filechecks.forEach(fc => {
                    const opt = document.createElement('option');
                    opt.value = fc.name;
                    opt.textContent = `${fc.name} (${fc.storageAccount})`;
                    scriptSelect.appendChild(opt);
                });
            }
        } catch (err) { }
    } else if (type) {
        scriptGroup.style.display = 'block';
        scriptGroup.querySelector('label').textContent = 'Script';
        try {
            const r = await fetch(`/api/scripts/${type}`);
            const data = await r.json();
            if (data.success && data.scripts) {
                data.scripts.forEach(s => {
                    const opt = document.createElement('option');
                    opt.value = s.name;
                    opt.textContent = s.name;
                    scriptSelect.appendChild(opt);
                });
            }
        } catch (err) { }
    } else {
        scriptGroup.style.display = 'none';
    }
});

document.getElementById('confirm-add-step-btn').addEventListener('click', () => {
    const type = document.getElementById('step-type-select').value;
    const resource = document.getElementById('step-script-select').value;
    if (!type) return;

    const newStep = {
        type: type,
        params: [],
        breakpointChecks: [],
        inputMapping: []
    };
    if (type === 'webhook') {
        newStep.webhook = resource;
    } else if (type === 'filecheck') {
        newStep.filecheck = resource;
        // Pre-populate typical filecheck params
        newStep.params = [
            { key: 'container', value: '' },
            { key: 'folderPath', value: '' },
            { key: 'timeout', value: '5' }
        ];
    } else {
        newStep.script = resource;
    }

    currentWorkflow.steps.push(newStep);
    renderLadder();
    document.getElementById('add-step-modal').style.display = 'none';
});

// ===== RUN / SCHEDULE =====
async function loadWorkflowDropdowns() {
    try {
        const r = await fetch('/api/workflows');
        const data = await r.json();
        const selects = [
            document.getElementById('run-workflow-select'),
            document.getElementById('schedule-workflow-select'),
            document.getElementById('logs-workflow-select')
        ];
        selects.forEach(sel => {
            if (!sel) return;
            const current = sel.value;
            sel.innerHTML = '<option value="">-- Select a workflow --</option>';
            if (data.success && data.workflows) {
                data.workflows.forEach(wf => {
                    const opt = document.createElement('option');
                    opt.value = wf.name;
                    opt.textContent = wf.name;
                    sel.appendChild(opt);
                });
            }
            sel.value = current;
        });
    } catch (err) { }
}

document.getElementById('run-workflow-btn').addEventListener('click', async () => {
    const name = document.getElementById('run-workflow-select').value;
    if (!name) {
        showMessage('runner-message', 'error', 'Select a workflow first');
        return;
    }
    const btn = document.getElementById('run-workflow-btn');
    const consoleEl = document.getElementById('live-console');
    const consoleOut = document.getElementById('live-console-output');

    btn.disabled = true;
    btn.textContent = 'Running...';
    showMessage('runner-message', 'info', `Starting workflow "${name}"...`);

    // Show console and start polling
    consoleOut.textContent = 'Waiting for output...\n';
    document.getElementById('live-console-title').textContent = `Console — ${name}`;
    consoleEl.classList.add('open');
    document.getElementById('live-console-backdrop').classList.add('active');

    let polling = true;
    const pollConsole = async () => {
        while (polling) {
            try {
                const cr = await fetch(`/api/workflows/${encodeURIComponent(name)}/console`);
                const cd = await cr.json();
                if (cd.output) {
                    consoleOut.textContent = cd.output;
                    consoleOut.scrollTop = consoleOut.scrollHeight;
                }
            } catch (_) { }
            await new Promise(r => setTimeout(r, 2000));
        }
    };
    const pollPromise = pollConsole();

    try {
        const r = await fetch(`/api/workflows/${encodeURIComponent(name)}/run`, { method: 'POST' });
        const data = await r.json();
        showMessage('runner-message', data.success ? 'success' : 'error', data.message);
    } catch (err) {
        showMessage('runner-message', 'error', 'Error: ' + err.message);
    } finally {
        // Stop polling and do one final fetch
        polling = false;
        await pollPromise;
        try {
            const cr = await fetch(`/api/workflows/${encodeURIComponent(name)}/console`);
            const cd = await cr.json();
            if (cd.output) {
                consoleOut.textContent = cd.output;
                consoleOut.scrollTop = consoleOut.scrollHeight;
            }
        } catch (_) { }
        btn.disabled = false;
        btn.textContent = 'Run Now';
    }
});

document.getElementById('close-console-btn').addEventListener('click', () => {
    document.getElementById('live-console').classList.remove('open');
    document.getElementById('live-console-backdrop').classList.remove('active');
});

document.getElementById('live-console-backdrop').addEventListener('click', () => {
    document.getElementById('live-console').classList.remove('open');
    document.getElementById('live-console-backdrop').classList.remove('active');
});

// Schedules
async function loadScheduleList() {
    const listEl = document.getElementById('schedule-list');
    const emptyEl = document.getElementById('schedule-list-empty');
    listEl.innerHTML = '';

    try {
        const r = await fetch('/api/schedules');
        const data = await r.json();
        if (data.success && data.schedules && data.schedules.length > 0) {
            emptyEl.style.display = 'none';
            data.schedules.forEach(sch => {
                const card = document.createElement('div');
                card.className = 'schedule-card';
                card.innerHTML = `
                    <div class="schedule-info">
                        <h4>${escHtml(sch.workflow)}</h4>
                        <p>${sch.interval} — next: ${sch.nextRun ? new Date(sch.nextRun).toLocaleString() : 'N/A'}</p>
                    </div>
                    <div class="schedule-actions">
                        <label class="toggle-switch">
                            <input type="checkbox" ${sch.enabled ? 'checked' : ''} onchange="toggleSchedule('${sch.name}', this.checked)">
                            <span class="toggle-slider"></span>
                        </label>
                        <button class="btn btn-danger btn-sm" onclick="deleteSchedule('${sch.name}')">Delete</button>
                    </div>
                `;
                listEl.appendChild(card);
            });
        } else {
            emptyEl.style.display = 'block';
        }
    } catch (err) {
        showMessage('runner-message', 'error', 'Error: ' + err.message);
    }
}

async function toggleSchedule(name, enabled) {
    try {
        // Re-save with enabled toggled
        const r = await fetch('/api/schedules', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name, toggleEnabled: enabled })
        });
        await r.json();
    } catch (err) { }
}

async function deleteSchedule(name) {
    if (!confirm(`Delete schedule "${name}"?`)) return;
    try {
        const r = await fetch(`/api/schedules/${encodeURIComponent(name)}`, { method: 'DELETE' });
        const data = await r.json();
        showMessage('runner-message', data.success ? 'success' : 'error', data.message);
        loadScheduleList();
    } catch (err) {
        showMessage('runner-message', 'error', 'Error: ' + err.message);
    }
}

document.getElementById('add-schedule-btn').addEventListener('click', () => {
    document.getElementById('schedule-form').style.display = 'block';
    loadWorkflowDropdowns();
    // Default first run to tomorrow 2am
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(2, 0, 0, 0);
    document.getElementById('schedule-first-run').value =
        tomorrow.toISOString().slice(0, 16);
});

document.getElementById('cancel-schedule-btn').addEventListener('click', () => {
    document.getElementById('schedule-form').style.display = 'none';
});

document.getElementById('save-schedule-btn').addEventListener('click', async () => {
    const workflow = document.getElementById('schedule-workflow-select').value;
    const interval = document.getElementById('schedule-interval').value;
    const firstRun = document.getElementById('schedule-first-run').value;

    if (!workflow || !firstRun) {
        showMessage('runner-message', 'error', 'Workflow and first run time are required');
        return;
    }

    try {
        const r = await fetch('/api/schedules', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                name: workflow + '-' + interval,
                workflow,
                interval,
                nextRun: new Date(firstRun).toISOString(),
                enabled: true
            })
        });
        const data = await r.json();
        showMessage('runner-message', data.success ? 'success' : 'error', data.message);
        if (data.success) {
            document.getElementById('schedule-form').style.display = 'none';
            loadScheduleList();
        }
    } catch (err) {
        showMessage('runner-message', 'error', 'Error: ' + err.message);
    }
});

// ===== LOGS =====
document.getElementById('load-logs-btn').addEventListener('click', () => {
    const workflow = document.getElementById('logs-workflow-select').value;
    if (!workflow) {
        showMessage('logs-message', 'error', 'Select a workflow first');
        return;
    }
    loadLogs(workflow);
});

async function loadLogs(workflow) {
    const listEl = document.getElementById('logs-list');
    const emptyEl = document.getElementById('logs-empty');
    listEl.innerHTML = '';

    try {
        const r = await fetch(`/api/logs/${encodeURIComponent(workflow)}`);
        const data = await r.json();
        if (data.success && data.logs && data.logs.length > 0) {
            emptyEl.style.display = 'none';
            data.logs.forEach(log => {
                const row = document.createElement('div');
                row.className = 'log-file-row';
                row.innerHTML = `
                    <span class="log-file-name">${log.name}</span>
                    <span class="log-file-meta">${log.lastModified || ''}</span>
                `;
                row.addEventListener('click', () => viewLogDetail(workflow, log.name));
                listEl.appendChild(row);
            });
        } else {
            emptyEl.style.display = 'block';
            emptyEl.querySelector('p').textContent = 'No logs found for this workflow.';
        }
    } catch (err) {
        showMessage('logs-message', 'error', 'Error: ' + err.message);
    }
}

async function viewLogDetail(workflow, logName) {
    try {
        const r = await fetch(`/api/logs/${encodeURIComponent(workflow)}/${encodeURIComponent(logName)}`);
        const data = await r.json();
        if (data.success) {
            document.getElementById('log-detail-title').textContent = logName;
            const contentEl = document.getElementById('log-detail-content');

            if (data.log && data.log.steps) {
                let html = '';
                data.log.steps.forEach((step, idx) => {
                    const statusClass = step.status || 'pending';
                    html += `
                        <div style="margin-bottom: 16px; padding: 12px; background: var(--card-bg); border: 1px solid #e2e8f0;">
                            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                                <div>
                                    <span class="step-number" style="width: 24px; height: 24px; line-height: 24px; font-size: 11px;">${idx + 1}</span>
                                    <span class="step-type-badge badge-${step.type}">${step.type}</span>
                                    <span style="margin-left: 8px; font-size: 13px; font-weight: 500;">${escHtml(step.script || step.webhook || '')}</span>
                                </div>
                                <span class="step-status ${statusClass}">${statusClass}</span>
                            </div>
                            ${step.output ? `<pre style="font-size: 12px; background: #1a202c; color: #e2e8f0; padding: 10px; overflow-x: auto; white-space: pre-wrap; max-height: 300px; overflow-y: auto;">${escHtml(typeof step.output === 'string' ? step.output : JSON.stringify(step.output, null, 2))}</pre>` : ''}
                            ${step.error ? `<pre style="font-size: 12px; background: #fed7d7; color: #c53030; padding: 10px; white-space: pre-wrap;">${escHtml(step.error)}</pre>` : ''}
                            ${step.duration ? `<span style="font-size: 11px; color: var(--text-secondary);">Duration: ${step.duration}s</span>` : ''}
                        </div>
                    `;
                });
                contentEl.innerHTML = html;
            } else {
                contentEl.innerHTML = `<pre style="font-size: 12px; white-space: pre-wrap;">${escHtml(typeof data.log === 'string' ? data.log : JSON.stringify(data.log, null, 2))}</pre>`;
            }

            document.getElementById('log-detail-modal').style.display = 'flex';
        }
    } catch (err) {
        showMessage('logs-message', 'error', 'Error loading log: ' + err.message);
    }
}

document.getElementById('close-log-modal').addEventListener('click', () => {
    document.getElementById('log-detail-modal').style.display = 'none';
});

// ===== SCRIPT PREVIEW =====
async function previewStep(idx) {
    const step = currentWorkflow.steps[idx];
    if (!step) return;

    const modal = document.getElementById('preview-modal');
    const titleEl = document.getElementById('preview-modal-title');
    const contentEl = document.getElementById('preview-modal-content');
    contentEl.innerHTML = '<p style="color: var(--text-secondary);">Loading...</p>';

    if (step.type === 'webhook') {
        titleEl.textContent = `Webhook: ${step.webhook || '(none)'}`;
        if (!step.webhook) {
            contentEl.innerHTML = '<p>No webhook selected.</p>';
            modal.style.display = 'flex';
            return;
        }
        try {
            const r = await fetch(`/api/webhooks/${encodeURIComponent(step.webhook)}`);
            const data = await r.json();
            if (data.success) {
                renderHighlighted(contentEl, JSON.stringify(data.webhook, null, 2), 'webhook');
            } else {
                contentEl.innerHTML = `<p style="color: var(--error-color);">${escHtml(data.message)}</p>`;
            }
        } catch (err) {
            contentEl.innerHTML = `<p style="color: var(--error-color);">Error: ${escHtml(err.message)}</p>`;
        }
        modal.style.display = 'flex';
    } else if (step.type === 'filecheck') {
        titleEl.textContent = `File Check: ${step.filecheck || '(none)'}`;
        if (!step.filecheck) {
            contentEl.innerHTML = '<p>No file check selected.</p>';
            modal.style.display = 'flex';
            return;
        }
        try {
            const r = await fetch(`/api/filechecks/${encodeURIComponent(step.filecheck)}`);
            const data = await r.json();
            if (data.success) {
                renderHighlighted(contentEl, JSON.stringify(data.filecheck, null, 2), 'filecheck');
            } else {
                contentEl.innerHTML = `<p style="color: var(--error-color);">${escHtml(data.message)}</p>`;
            }
        } catch (err) {
            contentEl.innerHTML = `<p style="color: var(--error-color);">Error: ${escHtml(err.message)}</p>`;
        }
        modal.style.display = 'flex';
    } else {
        // Script types: powershell, terraform, python, shell
        const scriptName = step.script || '';
        titleEl.textContent = scriptName || '(no script selected)';
        if (!scriptName) {
            contentEl.innerHTML = '<p>No script selected.</p>';
            modal.style.display = 'flex';
            return;
        }
        try {
            const r = await fetch(`/api/scripts/${encodeURIComponent(step.type)}/${encodeURIComponent(scriptName)}/content`);
            const data = await r.json();
            if (data.success) {
                renderHighlighted(contentEl, data.content, step.type);
            } else {
                contentEl.innerHTML = `<p style="color: var(--error-color);">${escHtml(data.message)}</p>`;
            }
        } catch (err) {
            contentEl.innerHTML = `<p style="color: var(--error-color);">Error: ${escHtml(err.message)}</p>`;
        }
        modal.style.display = 'flex';
    }
}

document.getElementById('close-preview-modal').addEventListener('click', () => {
    document.getElementById('preview-modal').style.display = 'none';
});

// ===== EXPORT / IMPORT WORKFLOWS =====
let exportWorkflowName = '';

function openExportModal(name) {
    exportWorkflowName = name;
    document.getElementById('export-workflow-name').textContent = name;
    document.getElementById('export-include-webhooks').checked = false;
    document.getElementById('export-include-filechecks').checked = false;
    clearMessage('export-message');
    document.getElementById('export-modal').style.display = 'flex';
}

document.getElementById('close-export-modal').addEventListener('click', () => {
    document.getElementById('export-modal').style.display = 'none';
});

document.getElementById('confirm-export-btn').addEventListener('click', async () => {
    const includeWebhooks = document.getElementById('export-include-webhooks').checked;
    const includeFilechecks = document.getElementById('export-include-filechecks').checked;
    const btn = document.getElementById('confirm-export-btn');
    btn.disabled = true;
    btn.textContent = 'Exporting...';
    clearMessage('export-message');

    try {
        const params = new URLSearchParams();
        if (includeWebhooks) params.set('webhooks', 'true');
        if (includeFilechecks) params.set('filechecks', 'true');

        const r = await fetch(`/api/workflows/${encodeURIComponent(exportWorkflowName)}/export?${params}`);
        const data = await r.json();
        if (data.success) {
            const json = JSON.stringify(data.export, null, 2);
            const blob = new Blob([json], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `${exportWorkflowName}.json`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
            document.getElementById('export-modal').style.display = 'none';
        } else {
            showMessage('export-message', 'error', data.message);
        }
    } catch (err) {
        showMessage('export-message', 'error', 'Error: ' + err.message);
    } finally {
        btn.disabled = false;
        btn.textContent = 'Export';
    }
});

// Import
document.getElementById('import-workflow-btn').addEventListener('click', () => {
    document.getElementById('import-file-input').value = '';
    document.getElementById('import-include-webhooks').checked = false;
    document.getElementById('import-include-filechecks').checked = false;
    clearMessage('import-message');
    document.getElementById('import-modal').style.display = 'flex';
});

document.getElementById('close-import-modal').addEventListener('click', () => {
    document.getElementById('import-modal').style.display = 'none';
});

document.getElementById('confirm-import-btn').addEventListener('click', async () => {
    const fileInput = document.getElementById('import-file-input');
    if (!fileInput.files || fileInput.files.length === 0) {
        showMessage('import-message', 'error', 'Please select a JSON file');
        return;
    }

    const btn = document.getElementById('confirm-import-btn');
    btn.disabled = true;
    btn.textContent = 'Importing...';
    clearMessage('import-message');

    try {
        const text = await fileInput.files[0].text();
        let payload;
        try {
            payload = JSON.parse(text);
        } catch (e) {
            showMessage('import-message', 'error', 'Invalid JSON file');
            return;
        }

        if (!payload.workflow) {
            showMessage('import-message', 'error', 'Invalid export file: missing workflow data');
            return;
        }

        const importWebhooks = document.getElementById('import-include-webhooks').checked;
        const importFilechecks = document.getElementById('import-include-filechecks').checked;

        const r = await fetch('/api/workflows/import', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                payload,
                importWebhooks,
                importFilechecks
            })
        });
        const data = await r.json();
        if (data.success) {
            document.getElementById('import-modal').style.display = 'none';
            showMessage('workflow-message', 'success', data.message);
            loadWorkflowList();
        } else {
            showMessage('import-message', 'error', data.message);
        }
    } catch (err) {
        showMessage('import-message', 'error', 'Error: ' + err.message);
    } finally {
        btn.disabled = false;
        btn.textContent = 'Import';
    }
});

// ===== MODULES =====
let currentModuleType = 'powershell';

document.querySelectorAll('.module-tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.module-tab').forEach(t => {
            t.classList.remove('active');
            t.classList.remove('btn-primary');
            t.classList.add('btn-secondary');
        });
        tab.classList.add('active');
        tab.classList.remove('btn-secondary');
        tab.classList.add('btn-primary');
        currentModuleType = tab.dataset.type;
        document.getElementById('modules-output').innerHTML = '';
        document.getElementById('modules-empty').style.display = 'block';
        document.getElementById('module-install-form').style.display = 'none';
        clearMessage('modules-message');
    });
});

document.getElementById('show-modules-btn').addEventListener('click', async () => {
    const btn = document.getElementById('show-modules-btn');
    const outputEl = document.getElementById('modules-output');
    const emptyEl = document.getElementById('modules-empty');
    btn.disabled = true;
    btn.textContent = 'Loading...';
    outputEl.innerHTML = '';
    emptyEl.style.display = 'none';
    clearMessage('modules-message');

    try {
        const r = await fetch(`/api/modules/${currentModuleType}`);
        const data = await r.json();
        if (data.success) {
            if (currentModuleType === 'powershell' && data.modules && data.modules.length > 0) {
                let html = '<table style="width: 100%; font-size: 13px; border-collapse: collapse;">';
                html += '<thead><tr style="border-bottom: 2px solid #e2e8f0; text-align: left;"><th style="padding: 8px 12px;">Name</th><th style="padding: 8px 12px;">Version</th><th style="padding: 8px 12px;">Path</th></tr></thead><tbody>';
                data.modules.forEach(m => {
                    html += `<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 8px 12px; font-weight: 500;">${escHtml(m.name)}</td><td style="padding: 8px 12px;">${escHtml(m.version)}</td><td style="padding: 8px 12px; font-size: 11px; color: var(--text-secondary); font-family: monospace;">${escHtml(m.path)}</td></tr>`;
                });
                html += '</tbody></table>';
                outputEl.innerHTML = html;
            } else if (currentModuleType === 'python' && data.output) {
                outputEl.innerHTML = `<pre style="font-size: 12px; background: #1a202c; color: #e2e8f0; padding: 16px; overflow-x: auto; white-space: pre-wrap; max-height: 70vh; overflow-y: auto;">${escHtml(data.output)}</pre>`;
            } else {
                emptyEl.style.display = 'block';
                emptyEl.querySelector('p').textContent = 'No modules found.';
            }
        } else {
            showMessage('modules-message', 'error', data.message || 'Failed to list modules');
        }
    } catch (err) {
        showMessage('modules-message', 'error', 'Error: ' + err.message);
    } finally {
        btn.disabled = false;
        btn.textContent = 'Show Modules';
    }
});

document.getElementById('add-module-btn').addEventListener('click', () => {
    document.getElementById('module-install-form').style.display = 'block';
    document.getElementById('module-name-input').value = '';
    document.getElementById('module-name-input').focus();
});

document.getElementById('cancel-module-btn').addEventListener('click', () => {
    document.getElementById('module-install-form').style.display = 'none';
});

document.getElementById('install-module-btn').addEventListener('click', async () => {
    const moduleName = document.getElementById('module-name-input').value.trim();
    if (!moduleName) {
        showMessage('modules-message', 'error', 'Module name is required');
        return;
    }
    const btn = document.getElementById('install-module-btn');
    btn.disabled = true;
    btn.textContent = 'Installing...';
    clearMessage('modules-message');

    try {
        const r = await fetch(`/api/modules/${currentModuleType}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name: moduleName })
        });
        const data = await r.json();
        showMessage('modules-message', data.success ? 'success' : 'error', data.message);
        if (data.success) {
            document.getElementById('module-install-form').style.display = 'none';
        }
    } catch (err) {
        showMessage('modules-message', 'error', 'Error: ' + err.message);
    } finally {
        btn.disabled = false;
        btn.textContent = 'Install';
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
