// Nexus - Logs & Modules

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
                            ${step.command ? `<div style="font-size: 12px; font-family: monospace; background: #2d3748; color: #68d391; padding: 6px 10px; margin-bottom: 8px; border-left: 3px solid #68d391;">&gt; ${escHtml(step.command)}</div>` : ''}
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
        document.getElementById('apt-warning').style.display = currentModuleType === 'apt' ? 'block' : 'none';
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
                html += '<thead><tr style="border-bottom: 2px solid #e2e8f0; text-align: left;"><th style="padding: 8px 12px;">Name</th><th style="padding: 8px 12px;">Version</th><th style="padding: 8px 12px;">Path</th><th style="padding: 8px 12px;"></th></tr></thead><tbody>';
                data.modules.forEach(m => {
                    html += `<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 8px 12px; font-weight: 500;">${escHtml(m.name)}</td><td style="padding: 8px 12px;">${escHtml(m.version)}</td><td style="padding: 8px 12px; font-size: 11px; color: var(--text-secondary); font-family: monospace;">${escHtml(m.path)}</td><td style="padding: 8px 12px;"><button class="btn btn-danger" style="font-size:0.75rem; padding:2px 8px;" onclick="removeModule('${escHtml(m.name)}')">Remove</button></td></tr>`;
                });
                html += '</tbody></table>';
                outputEl.innerHTML = html;
            } else if (currentModuleType === 'python' && data.output) {
                outputEl.innerHTML = `<pre style="font-size: 12px; background: #1a202c; color: #e2e8f0; padding: 16px; overflow-x: auto; white-space: pre-wrap; max-height: 70vh; overflow-y: auto;">${escHtml(data.output)}</pre>`;
            } else if (currentModuleType === 'apt' && data.packages) {
                const missing = data.packages.filter(p => !p.installed && p.source === 'apt');
                let html = '';
                if (missing.length > 0) {
                    html += '<div style="background: rgba(234,88,12,0.15); border: 1px solid #ea580c; color: #fdba74; padding: 12px 14px; border-radius: 6px; margin-bottom: 16px; font-size: 13px;">';
                    html += `<strong>${missing.length} package(s) missing after rebuild:</strong>`;
                    html += '<div style="margin-top: 8px; display: flex; flex-direction: column; gap: 6px;">';
                    missing.forEach(p => {
                        html += `<div style="display: flex; align-items: center; gap: 8px;">`;
                        html += `<span style="font-weight: 500;">${escHtml(p.name)}</span>`;
                        if (p.note) html += `<span style="font-size: 11px; opacity: 0.8;">${escHtml(p.note)}</span>`;
                        html += `<button class="btn btn-primary btn-sm" onclick="reinstallAptPackage(this, '${escHtml(p.name)}')" style="margin-left: auto; padding: 2px 10px; font-size: 11px;">Install</button>`;
                        html += `</div>`;
                    });
                    html += '</div></div>';
                }
                html += '<table style="width: 100%; font-size: 13px; border-collapse: collapse;">';
                html += '<thead><tr style="border-bottom: 2px solid #e2e8f0; text-align: left;"><th style="padding: 8px 12px;">Package</th><th style="padding: 8px 12px;">Version</th><th style="padding: 8px 12px;">Source</th><th style="padding: 8px 12px;">Note</th><th style="padding: 8px 12px;">Status</th></tr></thead><tbody>';
                data.packages.forEach(p => {
                    const sourceStyle = p.source === 'manual' ? 'color: var(--text-secondary); font-style: italic;' : '';
                    const statusHtml = p.installed
                        ? '<span style="color: #48bb78;">Installed</span>'
                        : '<span style="color: #f56565;">Missing</span>';
                    html += `<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 8px 12px; font-weight: 500;">${escHtml(p.name)}</td><td style="padding: 8px 12px; font-family: monospace;">${escHtml(p.installed ? (p.version || '') : '')}</td><td style="padding: 8px 12px; ${sourceStyle}">${escHtml(p.source)}</td><td style="padding: 8px 12px; color: var(--text-secondary); font-size:12px;">${escHtml(p.note || '')}</td><td style="padding: 8px 12px;">${statusHtml}</td></tr>`;
                });
                html += '</tbody></table>';
                outputEl.innerHTML = html;
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
        btn.textContent = 'Show';
    }
});

document.getElementById('add-module-btn').addEventListener('click', () => {
    const form = document.getElementById('module-install-form');
    form.style.display = 'block';
    document.getElementById('module-name-input').value = '';
    document.getElementById('module-github-input').value = '';
    // Show/hide GitHub section based on module type
    const ghSection = document.getElementById('github-install-section');
    const galleryLabel = document.getElementById('module-gallery-label');
    if (currentModuleType === 'powershell') {
        ghSection.style.display = 'block';
        galleryLabel.textContent = 'PowerShell Gallery';
    } else if (currentModuleType === 'python') {
        ghSection.style.display = 'none';
        galleryLabel.textContent = 'PyPI (pip)';
    } else {
        ghSection.style.display = 'none';
        galleryLabel.textContent = 'Package Name (apt-get)';
    }
    document.getElementById('module-name-input').focus();
});

document.getElementById('cancel-module-btn').addEventListener('click', () => {
    document.getElementById('module-install-form').style.display = 'none';
});

// Install from Gallery / PyPI
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

async function removeModule(name) {
    if (!confirm(`Remove module "${name}"?`)) return;
    clearMessage('modules-message');
    try {
        const r = await fetch(`/api/modules/${encodeURIComponent(name)}`, { method: 'DELETE' });
        const data = await r.json();
        showMessage('modules-message', data.success ? 'success' : 'error', data.message);
        if (data.success) document.getElementById('show-modules-btn').click();
    } catch (err) {
        showMessage('modules-message', 'error', 'Error: ' + err.message);
    }
}

async function reinstallAptPackage(btn, name) {
    const origText = btn.textContent;
    btn.disabled = true;
    btn.textContent = 'Installing...';
    try {
        const r = await fetch('/api/modules/apt', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name })
        });
        const data = await r.json();
        if (data.success) {
            showMessage('modules-message', 'success', data.message);
            document.getElementById('show-modules-btn').click();
        } else {
            showMessage('modules-message', 'error', data.message);
            btn.disabled = false;
            btn.textContent = origText;
        }
    } catch (err) {
        showMessage('modules-message', 'error', 'Error: ' + err.message);
        btn.disabled = false;
        btn.textContent = origText;
    }
}

// Install from GitHub
document.getElementById('install-github-btn').addEventListener('click', async () => {
    const ghUrl = document.getElementById('module-github-input').value.trim();
    if (!ghUrl) {
        showMessage('modules-message', 'error', 'GitHub URL is required');
        return;
    }
    const btn = document.getElementById('install-github-btn');
    btn.disabled = true;
    btn.textContent = 'Installing...';
    clearMessage('modules-message');

    try {
        const r = await fetch('/api/modules/github', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ url: ghUrl })
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
