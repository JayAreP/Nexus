// Nexus - Workflows (builder, ladder, steps, browse, preview, export/import)

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
                        <button class="btn btn-secondary btn-sm" onclick="copyWorkflow('${wf.name}')">Copy</button>
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
            document.getElementById('workflow-editor-title').textContent = `Edit: ${name}`;
            renderLadder();
            document.getElementById('workflow-editor').style.display = 'flex';
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

async function copyWorkflow(name) {
    const newName = prompt(`Copy "${name}" — enter new workflow name:`, name + '-copy');
    if (!newName || newName === name) return;
    try {
        const r = await fetch(`/api/workflows/${encodeURIComponent(name)}/copy`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ newName })
        });
        const data = await r.json();
        showMessage('workflow-message', data.success ? 'success' : 'error', data.message);
        if (data.success) loadWorkflowList();
    } catch (err) {
        showMessage('workflow-message', 'error', 'Error: ' + err.message);
    }
}

document.getElementById('new-workflow-btn').addEventListener('click', () => {
    editingWorkflowName = null;
    currentWorkflow = { name: '', steps: [] };
    document.getElementById('workflow-name').value = '';
    document.getElementById('workflow-editor-title').textContent = 'New Workflow';
    renderLadder();
    document.getElementById('workflow-editor').style.display = 'flex';
});

document.getElementById('cancel-workflow-btn').addEventListener('click', () => {
    document.getElementById('workflow-editor').style.display = 'none';
    editingWorkflowName = null;
});

document.getElementById('close-workflow-editor').addEventListener('click', () => {
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
            loadWorkflowDropdowns();
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
            const mandatoryIcon = kv.mandatory ? '<span title="Mandatory" style="position: absolute; left: -20px; color: #e53e3e; font-size: 14px;">⚠</span>' : '';
            const placeholder = kv.type || 'Value';
            let valueField;
            if (kv.type === 'switch') {
                // Switch parameter — checkbox only
                const checked = (kv.value === true || kv.value === 'true') ? 'checked' : '';
                valueField = `<label class="switch-param" style="display: flex; align-items: center; gap: 6px; flex: 1; font-size: 12px; cursor: pointer;"><input type="checkbox" class="kv-switch" ${checked}> Include</label>`;
            } else if (kv.type === 'array') {
                // Multi-value array UI
                const values = Array.isArray(kv.value) ? kv.value : (kv.value ? [kv.value] : ['']);
                const entriesHtml = values.map((v, vi) => `
                    <div class="array-entry">
                        <input type="text" class="array-value" placeholder="Value ${vi + 1}" value="${escHtml(v || '')}">
                        <button class="array-entry-remove" onclick="removeArrayEntry(${idx}, ${ki}, ${vi})" title="Remove">×</button>
                    </div>
                `).join('');
                valueField = `<div class="array-values" data-array="true">${entriesHtml}<button class="array-add-btn" onclick="addArrayEntry(${idx}, ${ki})">+ Add</button></div>`;
            } else if (kv.validateSet && kv.validateSet.length > 0) {
                const opts = kv.validateSet.map(v => `<option value="${escHtml(v)}"${v === (kv.value || '') ? ' selected' : ''}>${escHtml(v)}</option>`).join('');
                valueField = `<select class="kv-value" style="flex: 1; padding: 6px 10px; border: 1px solid #cbd5e0; font-size: 13px; font-family: inherit; color: var(--text-primary);"><option value="">-- select --</option>${opts}</select>`;
            } else {
                valueField = `<input type="text" class="kv-value" placeholder="${escHtml(placeholder)}" value="${escHtml(kv.value || '')}">`;
            }
            // Add Browse button for filecheck container/folderPath params
            let browseBtn = '';
            if (step.type === 'filecheck' && step.filecheck && (kv.key === 'container' || kv.key === 'folderPath')) {
                const browseMode = kv.key === 'container' ? 'container' : 'folder';
                browseBtn = `<button class="btn btn-secondary btn-sm" style="font-size: 10px; padding: 4px 8px; white-space: nowrap;" onclick="openBrowse(${idx}, ${ki}, '${browseMode}')">Browse</button>`;
                // Shorten value field
                valueField = `<input type="text" class="kv-value" style="flex: 1;" placeholder="${escHtml(placeholder)}" value="${escHtml(kv.value || '')}">`;
            }
            // Credential dropdown for cloudformation credential param
            if (step.type === 'cloudformation' && kv.key === 'credential') {
                const opts = (window._awsCredentialCache || []).map(n =>
                    `<option value="${escHtml(n)}"${n === (kv.value || '') ? ' selected' : ''}>${escHtml(n)}</option>`
                ).join('');
                valueField = `<select class="kv-value" style="flex: 1; padding: 6px 10px; border: 1px solid #cbd5e0; font-size: 13px; font-family: inherit; color: var(--text-primary);"><option value="">-- Select AWS Credential --</option>${opts}</select>`;
            }
            kvHtml += `
                <div class="kv-pair${kv.type === 'array' ? ' kv-pair-array' : ''}" data-kv-index="${ki}" style="position: relative;">
                    ${mandatoryIcon}
                    <input type="text" class="kv-key" placeholder="Key" value="${escHtml(kv.key || '')}">
                    ${valueField}
                    ${browseBtn}
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
                <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 6px;">
                    <label style="font-size: 12px; color: var(--text-secondary); font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px;">Parameters</label>
                    ${['powershell','shell','python','terraform','cloudformation'].includes(step.type) && step.script ? `<button class="btn btn-secondary btn-sm" style="font-size: 10px; padding: 2px 8px;" onclick="autoParams(${idx})">Auto</button>` : ''}
                </div>
                <div class="kv-list">${kvHtml}</div>
                <button class="add-kv-btn" onclick="addKV(${idx})">+ Add Key/Value</button>

                <div class="step-options" style="margin-top: 12px; display: flex; gap: 16px; align-items: center;">
                    <label class="step-checkbox"><input type="checkbox" class="halt-on-error" ${step.haltOnError ? 'checked' : ''} /> Halt on any error</label>
                </div>

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

function readLadderState() {
    const stepEls = document.querySelectorAll('.ladder-step');
    stepEls.forEach((stepEl, idx) => {
        if (!currentWorkflow.steps[idx]) return;

        // Read params (preserve mandatory/type/validateSet from auto-detection)
        const kvPairs = stepEl.querySelectorAll('.kv-list .kv-pair');
        const oldParams = currentWorkflow.steps[idx].params || [];
        currentWorkflow.steps[idx].params = [];
        kvPairs.forEach((kv, ki) => {
            const key = kv.querySelector('.kv-key').value.trim();
            const old = oldParams[ki] || {};
            // Read value — switch, array, or text
            const switchCb = kv.querySelector('.kv-switch');
            const arrayContainer = kv.querySelector('.array-values');
            let value;
            if (switchCb) {
                value = switchCb.checked;
            } else if (arrayContainer) {
                value = Array.from(arrayContainer.querySelectorAll('.array-value')).map(el => el.value.trim()).filter(v => v);
            } else {
                value = kv.querySelector('.kv-value').value.trim();
            }
            if (key) currentWorkflow.steps[idx].params.push({
                key, value,
                mandatory: !!old.mandatory,
                type: old.type || '',
                validateSet: old.validateSet || null
            });
        });

        // Read halt-on-error checkbox
        const haltCb = stepEl.querySelector('.halt-on-error');
        currentWorkflow.steps[idx].haltOnError = haltCb ? haltCb.checked : false;

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

function addArrayEntry(stepIdx, kvIdx) {
    readLadderState();
    const param = currentWorkflow.steps[stepIdx].params[kvIdx];
    if (!Array.isArray(param.value)) param.value = param.value ? [param.value] : [];
    param.value.push('');
    renderLadder();
}

function removeArrayEntry(stepIdx, kvIdx, entryIdx) {
    readLadderState();
    const param = currentWorkflow.steps[stepIdx].params[kvIdx];
    if (Array.isArray(param.value) && param.value.length > 1) {
        param.value.splice(entryIdx, 1);
    }
    renderLadder();
}

async function autoParams(stepIdx) {
    readLadderState();
    const step = currentWorkflow.steps[stepIdx];
    if (!step || !step.script || !step.type) return;

    try {
        const r = await fetch(`/api/scripts/${encodeURIComponent(step.type)}/${encodeURIComponent(step.script)}/parameters`);
        const data = await r.json();
        if (!data.success) {
            alert('Failed to detect parameters: ' + (data.message || 'unknown error'));
            return;
        }
        if (!data.params || data.params.length === 0) {
            alert('No parameters detected in this script.');
            return;
        }
        // Build param list — preserve existing values if param already present
        const existingMap = {};
        (step.params || []).forEach(p => { if (p.key) existingMap[p.key] = p.value; });

        const detectedParams = data.params.map(p => ({
            key: p.name,
            value: existingMap[p.name] !== undefined ? existingMap[p.name] : (p.default || ''),
            mandatory: !!p.mandatory,
            type: p.type || '',
            validateSet: p.validateSet || null
        }));

        if (step.type === 'cloudformation') {
            // Preserve reserved CloudFormation params, append template params after
            const reserved = ['credential', 'awsAccountId', 'region', 'stackName'];
            const reservedParams = reserved.map(key => {
                const existing = (step.params || []).find(p => p.key === key);
                return existing || { key, value: '' };
            });
            step.params = [...reservedParams, ...detectedParams];
        } else {
            step.params = detectedParams;
        }
        renderLadder();
    } catch (err) {
        alert('Error detecting parameters: ' + err.message);
    }
}

// ===== STORAGE BROWSE (for filecheck steps) =====
let browseState = { stepIdx: null, kvIdx: null, mode: null, filecheck: null, container: null, prefix: '' };

function openBrowse(stepIdx, kvIdx, mode) {
    readLadderState();
    const step = currentWorkflow.steps[stepIdx];
    if (!step || !step.filecheck) return;

    browseState = { stepIdx, kvIdx, mode, filecheck: step.filecheck, container: null, prefix: '' };
    document.getElementById('browse-modal').style.display = 'flex';
    document.getElementById('browse-select-btn').disabled = true;
    document.getElementById('browse-list').innerHTML = '';

    if (mode === 'container') {
        loadContainerList();
    } else {
        // For folder browsing, read the current container value from the step
        const containerParam = step.params.find(p => p.key === 'container');
        if (!containerParam || !containerParam.value) {
            alert('Please set the container first before browsing folders.');
            document.getElementById('browse-modal').style.display = 'none';
            return;
        }
        browseState.container = containerParam.value;
        loadFolderList('');
    }
}

async function loadContainerList() {
    const listEl = document.getElementById('browse-list');
    const loadEl = document.getElementById('browse-loading');
    const crumbEl = document.getElementById('browse-breadcrumb');
    crumbEl.textContent = `${browseState.filecheck} / containers`;
    loadEl.style.display = 'block';
    listEl.innerHTML = '';

    try {
        const r = await fetch(`/api/filechecks/${encodeURIComponent(browseState.filecheck)}/containers`);
        const data = await r.json();
        loadEl.style.display = 'none';
        if (!data.success) { listEl.innerHTML = `<div style="padding: 12px; color: #e53e3e;">${escHtml(data.message)}</div>`; return; }
        if (!data.containers || data.containers.length === 0) {
            listEl.innerHTML = '<div style="padding: 12px; color: var(--text-secondary);">(no containers found)</div>';
            return;
        }
        listEl.innerHTML = data.containers.map(c => `
            <div class="browse-item" data-value="${escHtml(c.name)}" onclick="selectBrowseItem(this)">
                <span style="margin-right: 8px;">📦</span> ${escHtml(c.name)}
            </div>
        `).join('');
    } catch (err) {
        loadEl.style.display = 'none';
        listEl.innerHTML = `<div style="padding: 12px; color: #e53e3e;">Error: ${escHtml(err.message)}</div>`;
    }
}

async function loadFolderList(prefix) {
    browseState.prefix = prefix;
    const listEl = document.getElementById('browse-list');
    const loadEl = document.getElementById('browse-loading');
    const crumbEl = document.getElementById('browse-breadcrumb');
    crumbEl.textContent = `${browseState.filecheck} / ${browseState.container} / ${prefix || '(root)'}`;
    loadEl.style.display = 'block';
    listEl.innerHTML = '';
    document.getElementById('browse-select-btn').disabled = true;

    try {
        let url = `/api/filechecks/${encodeURIComponent(browseState.filecheck)}/browse?container=${encodeURIComponent(browseState.container)}`;
        if (prefix) url += `&prefix=${encodeURIComponent(prefix)}`;
        const r = await fetch(url);
        const data = await r.json();
        loadEl.style.display = 'none';
        if (!data.success) { listEl.innerHTML = `<div style="padding: 12px; color: #e53e3e;">${escHtml(data.message)}</div>`; return; }

        let html = '';
        // Back button if we're in a subfolder
        if (prefix) {
            const parent = prefix.replace(/[^/]+\/$/, '');
            html += `<div class="browse-item browse-folder" onclick="loadFolderList('${escHtml(parent)}')"><span style="margin-right: 8px;">⬆️</span> ..</div>`;
        }
        // Select current folder
        html += `<div class="browse-item browse-current" data-value="${escHtml(prefix)}" onclick="selectBrowseItem(this)"><span style="margin-right: 8px;">📁</span> <em>(select this folder)</em></div>`;
        // Subfolders
        data.folders.forEach(f => {
            html += `<div class="browse-item browse-folder" onclick="loadFolderList('${escHtml(f.prefix)}')"><span style="margin-right: 8px;">📁</span> ${escHtml(f.name)}/</div>`;
        });
        if (data.folders.length === 0) {
            html += `<div style="padding: 8px 12px; color: var(--text-secondary); font-style: italic;">(no folders)</div>`;
        }
        // Files (display only, not selectable for folderPath)
        data.files.forEach(f => {
            const sizeKb = (f.size / 1024).toFixed(1);
            html += `<div class="browse-item browse-file" style="color: var(--text-secondary);"><span style="margin-right: 8px;">📄</span> ${escHtml(f.name)} <span style="margin-left: auto; font-size: 11px;">${sizeKb} KB</span></div>`;
        });
        listEl.innerHTML = html;
    } catch (err) {
        loadEl.style.display = 'none';
        listEl.innerHTML = `<div style="padding: 12px; color: #e53e3e;">Error: ${escHtml(err.message)}</div>`;
    }
}

function selectBrowseItem(el) {
    document.querySelectorAll('#browse-list .browse-item').forEach(i => i.classList.remove('browse-selected'));
    el.classList.add('browse-selected');
    document.getElementById('browse-select-btn').disabled = false;
}

document.getElementById('browse-select-btn').addEventListener('click', () => {
    const selected = document.querySelector('#browse-list .browse-selected');
    if (!selected) return;
    const value = selected.dataset.value;
    readLadderState();
    currentWorkflow.steps[browseState.stepIdx].params[browseState.kvIdx].value = value;
    renderLadder();
    document.getElementById('browse-modal').style.display = 'none';
});

document.getElementById('close-browse-modal').addEventListener('click', () => {
    document.getElementById('browse-modal').style.display = 'none';
});

// ===== AWS CREDENTIAL CACHE (for cloudformation step dropdowns) =====
window._awsCredentialCache = [];
async function loadAwsCredentialCache() {
    try {
        const r = await fetch('/api/credentials');
        const data = await r.json();
        if (data.success && data.credentials) {
            window._awsCredentialCache = data.credentials.filter(c => c.type === 'aws').map(c => c.name);
        }
    } catch (err) { }
}
// Refresh cache when workflow editor opens
const _origEditWorkflow = editWorkflow;
editWorkflow = async function(name) { await loadAwsCredentialCache(); return _origEditWorkflow(name); };
const _origNewWorkflowBtn = document.getElementById('new-workflow-btn');
_origNewWorkflowBtn.addEventListener('click', () => loadAwsCredentialCache(), true);

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
    } else if (type === 'cloudformation') {
        scriptGroup.style.display = 'block';
        scriptGroup.querySelector('label').textContent = 'Template';
        try {
            const r = await fetch('/api/scripts/cloudformation');
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
        inputMapping: [],
        haltOnError: false
    };
    if (type === 'webhook') {
        newStep.webhook = resource;
    } else if (type === 'filecheck') {
        newStep.filecheck = resource;
        // Pre-populate typical filecheck params
        newStep.params = [
            { key: 'mode', value: 'wait', validateSet: ['wait', 'recent'] },
            { key: 'container', value: '' },
            { key: 'folderPath', value: '' },
            { key: 'minutes', value: '5' }
        ];
    } else if (type === 'cloudformation') {
        newStep.script = resource;
        // Pre-populate CloudFormation step params — credential, account, region, stack name
        newStep.params = [
            { key: 'credential', value: '' },
            { key: 'awsAccountId', value: '' },
            { key: 'region', value: '' },
            { key: 'stackName', value: '' }
        ];
    } else {
        newStep.script = resource;
    }

    currentWorkflow.steps.push(newStep);
    renderLadder();
    document.getElementById('add-step-modal').style.display = 'none';
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
