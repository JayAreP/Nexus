// Nexus - Runner (run, live console, engine logs, schedules)

// ===== RUN / SCHEDULE =====
async function loadWorkflowDropdowns() {
    try {
        const r = await fetch('/api/workflows');
        const data = await r.json();
        const selects = [
            document.getElementById('run-workflow-select'),
            document.getElementById('schedule-workflow-select'),
            document.getElementById('logs-workflow-select'),
            document.getElementById('test-workflow-select')
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

    // Show console
    consoleOut.textContent = 'Waiting for output...\n';
    document.getElementById('live-console-title').textContent = `Console — ${name}`;
    consoleEl.classList.add('open');
    document.getElementById('live-console-backdrop').classList.add('active');

    // Fire the run — returns immediately now
    try {
        const r = await fetch(`/api/workflows/${encodeURIComponent(name)}/run`, { method: 'POST' });
        const data = await r.json();
        if (!data.success) {
            showMessage('runner-message', 'error', data.message);
            btn.disabled = false;
            btn.textContent = 'Run Now';
            return;
        }
    } catch (err) {
        showMessage('runner-message', 'error', 'Error: ' + err.message);
        btn.disabled = false;
        btn.textContent = 'Run Now';
        return;
    }

    // Poll console until workflow finishes
    const poll = async () => {
        while (true) {
            await new Promise(r => setTimeout(r, 2000));
            try {
                const cr = await fetch(`/api/workflows/${encodeURIComponent(name)}/console`);
                const cd = await cr.json();
                if (cd.output) {
                    consoleOut.textContent = cd.output;
                    consoleOut.scrollTop = consoleOut.scrollHeight;
                }
                if (!cd.running) {
                    // Workflow finished — show final status
                    const status = cd.status || 'unknown';
                    const msg = cd.message || `Workflow "${name}" finished (${status})`;
                    showMessage('runner-message', status === 'success' ? 'success' : 'error', msg);
                    break;
                }
            } catch (_) { }
        }
    };
    await poll();
    btn.disabled = false;
    btn.textContent = 'Run Now';
});

document.getElementById('close-console-btn').addEventListener('click', () => {
    document.getElementById('live-console').classList.remove('open');
    document.getElementById('live-console-backdrop').classList.remove('active');
});

document.getElementById('live-console-backdrop').addEventListener('click', () => {
    document.getElementById('live-console').classList.remove('open');
    document.getElementById('live-console-backdrop').classList.remove('active');
});

// ===== TEST STEP =====
document.getElementById('test-workflow-select').addEventListener('change', async () => {
    const name = document.getElementById('test-workflow-select').value;
    const stepSel = document.getElementById('test-step-select');
    const runBtn = document.getElementById('test-step-btn');
    stepSel.innerHTML = '<option value="">-- Select a step --</option>';
    stepSel.disabled = true;
    runBtn.disabled = true;
    if (!name) return;
    try {
        const r = await fetch(`/api/workflows/${encodeURIComponent(name)}`);
        const data = await r.json();
        if (data.success && data.workflow && data.workflow.steps) {
            data.workflow.steps.forEach((s, idx) => {
                const label = s.script || s.webhook || s.filecheck || s.type;
                const opt = document.createElement('option');
                opt.value = idx;
                opt.textContent = `Step ${idx + 1}: [${s.type}] ${label}`;
                stepSel.appendChild(opt);
            });
            stepSel.disabled = false;
        }
    } catch (err) { }
});

document.getElementById('test-step-select').addEventListener('change', () => {
    document.getElementById('test-step-btn').disabled =
        document.getElementById('test-step-select').value === '';
});

document.getElementById('test-step-btn').addEventListener('click', async () => {
    const name = document.getElementById('test-workflow-select').value;
    const stepIndex = parseInt(document.getElementById('test-step-select').value, 10);
    if (!name || isNaN(stepIndex)) {
        showMessage('runner-message', 'error', 'Select a workflow and step first');
        return;
    }
    const btn = document.getElementById('test-step-btn');
    const stepLabel = document.getElementById('test-step-select').selectedOptions[0].textContent;
    const consoleEl = document.getElementById('live-console');
    const consoleOut = document.getElementById('live-console-output');

    btn.disabled = true;
    btn.textContent = 'Running...';
    showMessage('runner-message', 'info', `Testing ${stepLabel} of "${name}"...`);

    consoleOut.textContent = 'Waiting for output...\n';
    document.getElementById('live-console-title').textContent = `Console — ${name} — ${stepLabel}`;
    consoleEl.classList.add('open');
    document.getElementById('live-console-backdrop').classList.add('active');

    try {
        const r = await fetch(`/api/workflows/${encodeURIComponent(name)}/run-step`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ stepIndex })
        });
        const data = await r.json();
        if (!data.success) {
            showMessage('runner-message', 'error', data.message);
            btn.disabled = false;
            btn.textContent = 'Run Step';
            return;
        }
    } catch (err) {
        showMessage('runner-message', 'error', 'Error: ' + err.message);
        btn.disabled = false;
        btn.textContent = 'Run Step';
        return;
    }

    // Poll console until finished (same console endpoint — uses same temp file)
    while (true) {
        await new Promise(r => setTimeout(r, 2000));
        try {
            const cr = await fetch(`/api/workflows/${encodeURIComponent(name)}/console`);
            const cd = await cr.json();
            if (cd.output) {
                consoleOut.textContent = cd.output;
                consoleOut.scrollTop = consoleOut.scrollHeight;
            }
            if (!cd.running) {
                const status = cd.status || 'unknown';
                const msg = cd.message || `${stepLabel} finished (${status})`;
                showMessage('runner-message', status === 'success' ? 'success' : 'error', msg);
                break;
            }
        } catch (_) { }
    }
    btn.disabled = false;
    btn.textContent = 'Run Step';
});

// Engine Log viewer
// Engine Log — sidebar button opens panel, daily log selection
document.getElementById('engine-log-btn').addEventListener('click', () => {
    // Deactivate all nav links and panels, activate engine-log panel
    document.querySelectorAll('.nav-link').forEach(l => l.classList.remove('active'));
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    document.getElementById('engine-log-panel').classList.add('active');
    loadEngineLogList();
});

async function loadEngineLogList() {
    const sel = document.getElementById('engine-log-select');
    sel.innerHTML = '<option value="">Loading...</option>';
    try {
        const r = await fetch('/api/engine-logs');
        const data = await r.json();
        sel.innerHTML = '';
        if (data.logs && data.logs.length > 0) {
            data.logs.forEach((log, i) => {
                const opt = document.createElement('option');
                opt.value = log.date;
                const sizeKb = (log.size / 1024).toFixed(1);
                opt.textContent = `${log.date}  (${sizeKb} KB)`;
                sel.appendChild(opt);
            });
            // Auto-load the first (most recent) log
            loadEngineLog(data.logs[0].date);
        } else {
            sel.innerHTML = '<option value="">(no logs available)</option>';
            document.getElementById('engine-log-content').textContent = '(no engine logs found)';
        }
    } catch (err) {
        sel.innerHTML = '<option value="">(failed to load list)</option>';
        document.getElementById('engine-log-content').textContent = 'Error: ' + err.message;
    }
}

async function loadEngineLog(date) {
    const el = document.getElementById('engine-log-content');
    el.textContent = 'Loading...';
    try {
        const r = await fetch('/api/engine-log?date=' + encodeURIComponent(date));
        const data = await r.json();
        el.textContent = data.log || '(empty)';
        el.scrollTop = el.scrollHeight;
    } catch (err) {
        el.textContent = 'Failed to load log: ' + err.message;
    }
}

document.getElementById('engine-log-load-btn').addEventListener('click', () => {
    const date = document.getElementById('engine-log-select').value;
    if (date) loadEngineLog(date);
});

document.getElementById('engine-log-refresh-btn').addEventListener('click', () => {
    const date = document.getElementById('engine-log-select').value;
    if (date) loadEngineLog(date);
    else loadEngineLogList();
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
