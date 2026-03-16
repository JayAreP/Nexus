// Nexus - Webhooks panel
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
                card.className = 'feature-item';
                card.innerHTML = `
                    <div>
                        <span class="feature-item-name">${wh.name}</span>
                        <span class="feature-item-meta">${wh.authType === 'oauth' ? 'OAuth' : 'Direct'}</span>
                    </div>
                    <div class="feature-item-actions">
                        <button class="btn btn-danger btn-sm" onclick="deleteWebhook('${wh.name}')">Delete</button>
                    </div>
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
