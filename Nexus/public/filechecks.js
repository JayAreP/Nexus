// Nexus - File Checks panel
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
