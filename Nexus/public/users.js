// Nexus — Users & API Tokens management

// ===== USERS =====
async function loadUsers() {
    const list = document.getElementById('users-list');
    const empty = document.getElementById('users-empty');
    try {
        const r = await fetch('/api/auth/users');
        const data = await r.json();
        if (!data.success) { list.innerHTML = ''; empty.style.display = 'block'; return; }

        const users = data.users || [];
        if (users.length === 0) { list.innerHTML = ''; empty.style.display = 'block'; return; }
        empty.style.display = 'none';

        list.innerHTML = users.map(u => `
            <div class="item-row">
                <div class="item-info">
                    <strong>${escHtml(u.username)}</strong>
                    <span class="badge badge-${u.role === 'admin' ? 'accent' : 'muted'}">${escHtml(u.role)}</span>
                </div>
                <div class="item-actions">
                    <button class="btn btn-secondary btn-sm" onclick="openEditUser('${escHtml(u.username)}', '${escHtml(u.role)}')">Edit</button>
                    <button class="btn btn-danger btn-sm" onclick="deleteUser('${escHtml(u.username)}')">Delete</button>
                </div>
            </div>
        `).join('');
    } catch (err) {
        showMessage('users-message', 'error', 'Failed to load users: ' + err.message);
    }
}

document.getElementById('add-user-btn').addEventListener('click', () => {
    document.getElementById('user-form-title').textContent = 'New User';
    document.getElementById('user-form-username').value = '';
    document.getElementById('user-form-username').disabled = false;
    document.getElementById('user-form-password').value = '';
    document.getElementById('user-form-password').placeholder = 'Password';
    document.getElementById('user-form-role').value = 'user';
    document.getElementById('user-form-section').style.display = 'block';
    document.getElementById('user-form-section').dataset.mode = 'create';
});

function openEditUser(username, role) {
    document.getElementById('user-form-title').textContent = 'Edit User';
    document.getElementById('user-form-username').value = username;
    document.getElementById('user-form-username').disabled = true;
    document.getElementById('user-form-password').value = '';
    document.getElementById('user-form-password').placeholder = 'Leave blank to keep current';
    document.getElementById('user-form-role').value = role;
    document.getElementById('user-form-section').style.display = 'block';
    document.getElementById('user-form-section').dataset.mode = 'edit';
}

document.getElementById('user-form-cancel').addEventListener('click', () => {
    document.getElementById('user-form-section').style.display = 'none';
});

document.getElementById('user-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const mode = document.getElementById('user-form-section').dataset.mode;
    const username = document.getElementById('user-form-username').value.trim();
    const password = document.getElementById('user-form-password').value;
    const role = document.getElementById('user-form-role').value;

    if (!username) { showMessage('users-message', 'error', 'Username is required'); return; }
    if (mode === 'create' && !password) { showMessage('users-message', 'error', 'Password is required for new users'); return; }

    try {
        const payload = { role };
        if (password) payload.password = password;

        let r;
        if (mode === 'create') {
            payload.username = username;
            payload.password = password;
            r = await fetch('/api/auth/users', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        } else {
            r = await fetch('/api/auth/users/' + encodeURIComponent(username), { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
        }
        const data = await r.json();
        showMessage('users-message', data.success ? 'success' : 'error', data.message);
        if (data.success) {
            document.getElementById('user-form-section').style.display = 'none';
            loadUsers();
        }
    } catch (err) {
        showMessage('users-message', 'error', 'Error: ' + err.message);
    }
});

async function deleteUser(username) {
    if (!confirm(`Delete user "${username}"? This will also revoke their sessions and API tokens.`)) return;
    try {
        const r = await fetch('/api/auth/users/' + encodeURIComponent(username), { method: 'DELETE' });
        const data = await r.json();
        showMessage('users-message', data.success ? 'success' : 'error', data.message);
        if (data.success) loadUsers();
    } catch (err) {
        showMessage('users-message', 'error', 'Error: ' + err.message);
    }
}

// ===== API TOKENS =====
async function loadApiTokens() {
    const list = document.getElementById('api-tokens-list');
    const empty = document.getElementById('api-tokens-empty');
    try {
        const r = await fetch('/api/auth/tokens');
        const data = await r.json();
        if (!data.success) { list.innerHTML = ''; empty.style.display = 'block'; return; }

        const tokens = data.tokens || [];
        if (tokens.length === 0) { list.innerHTML = ''; empty.style.display = 'block'; return; }
        empty.style.display = 'none';

        list.innerHTML = tokens.map(t => `
            <div class="item-row">
                <div class="item-info">
                    <strong>${escHtml(t.name)}</strong>
                    <code class="token-preview">${escHtml(t.tokenPreview)}</code>
                    <span class="text-muted" style="font-size: 12px;">by ${escHtml(t.createdBy)} &middot; ${new Date(t.createdAt).toLocaleDateString()}</span>
                </div>
                <div class="item-actions">
                    <button class="btn btn-danger btn-sm" onclick="deleteApiToken('${escHtml(t.id)}')">Revoke</button>
                </div>
            </div>
        `).join('');
    } catch (err) {
        showMessage('users-message', 'error', 'Failed to load API tokens: ' + err.message);
    }
}

document.getElementById('create-token-btn').addEventListener('click', async () => {
    const name = document.getElementById('new-token-name').value.trim();
    if (!name) { showMessage('users-message', 'error', 'Token name is required'); return; }

    try {
        const r = await fetch('/api/auth/tokens', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name })
        });
        const data = await r.json();
        if (data.success) {
            // Show the token value once
            const display = document.getElementById('new-token-display');
            display.style.display = 'block';
            document.getElementById('new-token-value').value = data.token;
            document.getElementById('new-token-name').value = '';
            loadApiTokens();
        } else {
            showMessage('users-message', 'error', data.message);
        }
    } catch (err) {
        showMessage('users-message', 'error', 'Error: ' + err.message);
    }
});

document.getElementById('copy-token-btn').addEventListener('click', () => {
    const input = document.getElementById('new-token-value');
    navigator.clipboard.writeText(input.value).then(() => {
        showMessage('users-message', 'success', 'Token copied to clipboard');
    });
});

document.getElementById('dismiss-token-btn').addEventListener('click', () => {
    document.getElementById('new-token-display').style.display = 'none';
});

async function deleteApiToken(id) {
    if (!confirm('Revoke this API token? Any integrations using it will stop working.')) return;
    try {
        const r = await fetch('/api/auth/tokens/' + encodeURIComponent(id), { method: 'DELETE' });
        const data = await r.json();
        showMessage('users-message', data.success ? 'success' : 'error', data.message);
        if (data.success) loadApiTokens();
    } catch (err) {
        showMessage('users-message', 'error', 'Error: ' + err.message);
    }
}
