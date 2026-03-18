// Nexus - Credentials panel
// ===== CREDENTIALS =====
let credentialTypes = {};
let editingCredentialName = null;

async function loadCredentialTypes() {
    if (Object.keys(credentialTypes).length > 0) return;
    try {
        const r = await fetch('/api/credentials/types');
        const data = await r.json();
        if (data.success && data.types) {
            credentialTypes = data.types;
        }
    } catch (err) { }
}

async function loadCredentialList() {
    await loadCredentialTypes();
    const listEl = document.getElementById('credential-list');
    const emptyEl = document.getElementById('credential-list-empty');
    listEl.innerHTML = '';

    try {
        const r = await fetch('/api/credentials');
        const data = await r.json();
        if (data.success && data.credentials && data.credentials.length > 0) {
            emptyEl.style.display = 'none';
            data.credentials.forEach(cred => {
                const typeLabel = credentialTypes[cred.type] ? credentialTypes[cred.type].label : cred.type;
                const card = document.createElement('div');
                card.className = 'feature-item';
                card.innerHTML = `
                    <div>
                        <span class="feature-item-name">${escHtml(cred.name)}</span>
                        <span class="feature-item-meta">${escHtml(typeLabel)}</span>
                        ${cred.description ? `<span class="feature-item-desc">— ${escHtml(cred.description)}</span>` : ''}
                    </div>
                    <div class="feature-item-actions">
                        <button class="btn btn-secondary btn-sm" onclick="showCredentialHelp('${escHtml(cred.name)}', '${escHtml(cred.type)}')">Help</button>
                        <button class="btn btn-secondary btn-sm" onclick="copyCredential('${escHtml(cred.name)}')">Copy</button>
                        <button class="btn btn-secondary btn-sm" onclick="editCredential('${escHtml(cred.name)}')">Edit</button>
                        <button class="btn btn-danger btn-sm" onclick="deleteCredential('${escHtml(cred.name)}')">Delete</button>
                    </div>
                `;
                listEl.appendChild(card);
            });
        } else {
            emptyEl.style.display = 'block';
        }
    } catch (err) {
        showMessage('credentials-message', 'error', 'Error: ' + err.message);
    }
}

async function deleteCredential(name) {
    if (!confirm(`Delete credential "${name}"?`)) return;
    try {
        const r = await fetch(`/api/credentials/${encodeURIComponent(name)}`, { method: 'DELETE' });
        const data = await r.json();
        showMessage('credentials-message', data.success ? 'success' : 'error', data.message);
        loadCredentialList();
    } catch (err) {
        showMessage('credentials-message', 'error', 'Error: ' + err.message);
    }
}

async function copyCredential(name) {
    const newName = prompt(`Copy "${name}" — enter new credential name:`, name + '-copy');
    if (!newName || newName === name) return;
    try {
        const r = await fetch(`/api/credentials/${encodeURIComponent(name)}/copy`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ newName })
        });
        const data = await r.json();
        showMessage('credentials-message', data.success ? 'success' : 'error', data.message);
        if (data.success) loadCredentialList();
    } catch (err) {
        showMessage('credentials-message', 'error', 'Error: ' + err.message);
    }
}

function showCredentialHelp(name, type) {
    const modal = document.getElementById('preview-modal');
    document.getElementById('preview-modal-title').textContent = `Using Credential: ${name}`;
    const contentEl = document.getElementById('preview-modal-content');

    const psVar = /^[a-zA-Z_][a-zA-Z0-9_]*$/.test(name) ? '$' + name : '${' + name + '}';
    const pyVar = name.replace(/[^a-zA-Z0-9_]/g, '_').replace(/^(\d)/, '_$1');
    const typeLabel = credentialTypes[type] ? credentialTypes[type].label : type;

    const sections = buildCredentialHelpSections(name, type, psVar, pyVar);

    let html = '<div style="font-size: 13px; line-height: 1.7; color: var(--text-primary); padding: 4px;">';
    html += `<p style="margin: 0 0 12px 0; color: var(--text-secondary);">Usage examples for <strong>${escHtml(name)}</strong> (${escHtml(typeLabel)}). Copy these snippets directly into your scripts.</p>`;
    sections.forEach(s => {
        html += `<h3 style="margin: 16px 0 8px 0; font-size: 15px;">${escHtml(s.title)}</h3>`;
        html += `<pre style="background: #1a202c; color: #e2e8f0; padding: 12px; overflow-x: auto; white-space: pre-wrap; font-size: 12px; margin: 0 0 6px 0;"><code>${escHtml(s.code)}</code></pre>`;
    });
    html += '</div>';

    contentEl.innerHTML = html;
    modal.style.display = 'flex';
}

function buildCredentialHelpSections(name, type, ps, py) {
    const sections = [];
    let psCode = 'Import-Module NLS\n';
    let pyCode = 'import nls\n';
    let nativeTitle = null;
    let nativeCode = null;

    switch (type) {
        case 'usernamepassword':
            psCode += `${ps} = Get-NLSCredential -Name '${name}'\n`;
            psCode += `$cred = New-Object PSCredential ${ps}.username, (ConvertTo-SecureString ${ps}.password -AsPlainText -Force)`;
            pyCode += `${py} = nls.get_credential("${name}")\n`;
            pyCode += `username = ${py}["username"]\n`;
            pyCode += `password = ${py}["password"]  # decrypted`;
            break;

        case 'azureserviceprincipal':
            psCode += 'Import-Module Az.Accounts\n';
            psCode += `${ps} = Get-NLSCredential -Name '${name}'\n`;
            psCode += `$secPwd = ConvertTo-SecureString ${ps}.clientSecret -AsPlainText -Force\n`;
            psCode += `$psCred = [PSCredential]::new(${ps}.clientId, $secPwd)\n`;
            psCode += `Connect-AzAccount -ServicePrincipal -Tenant ${ps}.tenantId -Credential $psCred`;
            pyCode += 'from azure.identity import ClientSecretCredential\n\n';
            pyCode += `${py} = nls.get_credential("${name}")\n`;
            pyCode += `credential = ClientSecretCredential(\n`;
            pyCode += `    tenant_id=${py}["tenantId"],\n`;
            pyCode += `    client_id=${py}["clientId"],\n`;
            pyCode += `    client_secret=${py}["clientSecret"],\n`;
            pyCode += `)`;
            nativeTitle = 'Azure CLI';
            nativeCode = `Import-Module NLS\n`;
            nativeCode += `${ps} = Get-NLSCredential -Name '${name}'\n`;
            nativeCode += `az login --service-principal -u ${ps}.clientId -p ${ps}.clientSecret --tenant ${ps}.tenantId`;
            break;

        case 'apikey':
            psCode += `${ps} = Get-NLSCredential -Name '${name}'\n`;
            psCode += `$headers = @{ ${ps}.headerName = ${ps}.key }\n`;
            psCode += `Invoke-RestMethod -Uri 'https://api.example.com/endpoint' -Headers $headers`;
            pyCode += 'import requests\n\n';
            pyCode += `${py} = nls.get_credential("${name}")\n`;
            pyCode += `headers = {${py}["headerName"]: ${py}["key"]}\n`;
            pyCode += `response = requests.get("https://api.example.com/endpoint", headers=headers)`;
            break;

        case 'oauth2':
            psCode += `${ps} = Get-NLSCredential -Name '${name}'\n`;
            psCode += `$body = @{\n`;
            psCode += `    grant_type    = 'client_credentials'\n`;
            psCode += `    client_id     = ${ps}.clientId\n`;
            psCode += `    client_secret = ${ps}.clientSecret\n`;
            psCode += `    scope         = ${ps}.scope\n`;
            psCode += `}\n`;
            psCode += `$token = Invoke-RestMethod -Method Post -Uri ${ps}.tokenUrl -Body $body\n`;
            psCode += `$headers = @{ Authorization = "Bearer $($token.access_token)" }`;
            pyCode += 'import requests\n\n';
            pyCode += `${py} = nls.get_credential("${name}")\n`;
            pyCode += `token_resp = requests.post(${py}["tokenUrl"], data={\n`;
            pyCode += `    "grant_type": "client_credentials",\n`;
            pyCode += `    "client_id": ${py}["clientId"],\n`;
            pyCode += `    "client_secret": ${py}["clientSecret"],\n`;
            pyCode += `    "scope": ${py}["scope"],\n`;
            pyCode += `})\n`;
            pyCode += `access_token = token_resp.json()["access_token"]`;
            break;

        case 'aws':
            psCode += 'Import-Module AWSPowerShell.NetCore\n';
            psCode += `${ps} = Get-NLSCredential -Name '${name}'\n`;
            psCode += `Set-AWSCredential -AccessKey ${ps}.accessKeyId -SecretKey ${ps}.secretAccessKey -SessionToken ${ps}.sessionToken\n`;
            psCode += `Set-DefaultAWSRegion -Region ${ps}.region`;
            pyCode += 'import boto3\n\n';
            pyCode += `${py} = nls.get_credential("${name}")\n`;
            pyCode += `session = boto3.Session(\n`;
            pyCode += `    aws_access_key_id=${py}["accessKeyId"],\n`;
            pyCode += `    aws_secret_access_key=${py}["secretAccessKey"],\n`;
            pyCode += `    aws_session_token=${py}.get("sessionToken"),\n`;
            pyCode += `    region_name=${py}.get("region", "us-east-1"),\n`;
            pyCode += `)`;
            nativeTitle = 'AWS CLI';
            nativeCode = `Import-Module NLS\n`;
            nativeCode += `${ps} = Get-NLSCredential -Name '${name}'\n`;
            nativeCode += `$env:AWS_ACCESS_KEY_ID = ${ps}.accessKeyId\n`;
            nativeCode += `$env:AWS_SECRET_ACCESS_KEY = ${ps}.secretAccessKey\n`;
            nativeCode += `$env:AWS_SESSION_TOKEN = ${ps}.sessionToken\n`;
            nativeCode += `$env:AWS_DEFAULT_REGION = ${ps}.region\n\n`;
            nativeCode += `# AWS CLI commands will now use these credentials\naws sts get-caller-identity`;
            break;

        case 'gcp':
            psCode += `${ps} = Get-NLSCredential -Name '${name}'\n`;
            psCode += `${ps}.privateKey | Set-Content /tmp/gcp-key.json\n`;
            psCode += `gcloud auth activate-service-account ${ps}.clientEmail \`\n`;
            psCode += `    --key-file=/tmp/gcp-key.json --project=${ps}.projectId`;
            pyCode += 'import json\nfrom google.oauth2 import service_account\n\n';
            pyCode += `${py} = nls.get_credential("${name}")\n`;
            pyCode += `key_data = json.loads(${py}["privateKey"])\n`;
            pyCode += `credentials = service_account.Credentials.from_service_account_info(key_data)`;
            nativeTitle = 'gcloud CLI';
            nativeCode = `Import-Module NLS\n`;
            nativeCode += `${ps} = Get-NLSCredential -Name '${name}'\n`;
            nativeCode += `${ps}.privateKey | Set-Content /tmp/gcp-key.json\n`;
            nativeCode += `gcloud auth activate-service-account ${ps}.clientEmail \`\n`;
            nativeCode += `    --key-file=/tmp/gcp-key.json --project=${ps}.projectId`;
            break;

        case 'connectionstring':
            psCode += `${ps} = Get-NLSCredential -Name '${name}'\n`;
            psCode += `$connStr = ${ps}.connectionString\n\n`;
            psCode += `# Example: SQL Server\n`;
            psCode += `$conn = New-Object System.Data.SqlClient.SqlConnection($connStr)`;
            pyCode += `${py} = nls.get_credential("${name}")\n`;
            pyCode += `conn_str = ${py}["connectionString"]\n\n`;
            pyCode += `# Example: pyodbc\nimport pyodbc\nconn = pyodbc.connect(conn_str)`;
            break;

        case 'token':
            psCode += `${ps} = Get-NLSCredential -Name '${name}'\n`;
            psCode += `$headers = @{ Authorization = "Bearer $(${ps}.token)" }\n`;
            psCode += `Invoke-RestMethod -Uri 'https://api.example.com/endpoint' -Headers $headers`;
            pyCode += 'import requests\n\n';
            pyCode += `${py} = nls.get_credential("${name}")\n`;
            pyCode += `headers = {"Authorization": f"Bearer {${py}['token']}"}\n`;
            pyCode += `response = requests.get("https://api.example.com/endpoint", headers=headers)`;
            break;

        default:
            psCode += `${ps} = Get-NLSCredential -Name '${name}'`;
            pyCode += `${py} = nls.get_credential("${name}")`;
    }

    sections.push({ title: 'PowerShell', code: psCode });
    sections.push({ title: 'Python', code: pyCode });
    if (nativeTitle && nativeCode) {
        sections.push({ title: nativeTitle, code: nativeCode });
    }

    let apiCode = `# PowerShell — direct REST call (no module needed)\n`;
    apiCode += `$resp = Invoke-RestMethod -Uri 'http://localhost:8080/api/credentials/${name}/resolve'\n`;
    apiCode += `$resp.credential.values\n\n`;
    apiCode += `# curl\ncurl -s http://localhost:8080/api/credentials/${name}/resolve | jq '.credential.values'`;
    sections.push({ title: 'REST API', code: apiCode });

    return sections;
}

function renderCredentialFields(typeName, existingValues) {
    const container = document.getElementById('credential-dynamic-fields');
    container.innerHTML = '';
    if (!typeName || !credentialTypes[typeName]) return;

    const typeDef = credentialTypes[typeName];
    typeDef.fields.forEach(field => {
        const group = document.createElement('div');
        group.className = 'form-group';
        const label = document.createElement('label');
        label.textContent = field.label;
        group.appendChild(label);

        let input;
        if (field.type === 'textarea') {
            input = document.createElement('textarea');
            input.rows = 4;
            input.style.cssText = 'width: 100%; font-family: monospace; font-size: 12px; padding: 8px; border: 1px solid #cbd5e0; background: var(--card-bg); color: var(--text-primary);';
        } else {
            input = document.createElement('input');
            input.type = field.type || 'text';
        }
        input.id = `cred-field-${field.name}`;
        input.placeholder = field.label;
        if (existingValues && existingValues[field.name] !== undefined) {
            input.value = existingValues[field.name];
        }
        group.appendChild(input);
        container.appendChild(group);
    });
}

document.getElementById('add-credential-btn').addEventListener('click', async () => {
    await loadCredentialTypes();
    editingCredentialName = null;
    document.getElementById('credential-form-title').textContent = 'New Credential';
    document.getElementById('credential-name').value = '';
    document.getElementById('credential-name').disabled = false;
    document.getElementById('credential-description').value = '';
    document.getElementById('credential-dynamic-fields').innerHTML = '';
    document.getElementById('credential-form').style.display = 'flex';

    // Populate type dropdown
    const sel = document.getElementById('credential-type-select');
    sel.innerHTML = '<option value="">-- Select type --</option>';
    sel.disabled = false;
    for (const [key, def] of Object.entries(credentialTypes)) {
        const opt = document.createElement('option');
        opt.value = key;
        opt.textContent = def.label;
        sel.appendChild(opt);
    }
});

document.getElementById('credential-type-select').addEventListener('change', (e) => {
    renderCredentialFields(e.target.value, null);
});

async function editCredential(name) {
    await loadCredentialTypes();
    try {
        const r = await fetch(`/api/credentials/${encodeURIComponent(name)}`);
        const data = await r.json();
        if (!data.success) {
            showMessage('credentials-message', 'error', data.message);
            return;
        }
        const cred = data.credential;
        editingCredentialName = name;
        document.getElementById('credential-form-title').textContent = 'Edit Credential';
        document.getElementById('credential-name').value = cred.name;
        document.getElementById('credential-name').disabled = true;
        document.getElementById('credential-description').value = cred.description || '';
        document.getElementById('credential-form').style.display = 'flex';

        // Populate and lock type
        const sel = document.getElementById('credential-type-select');
        sel.innerHTML = '<option value="">-- Select type --</option>';
        for (const [key, def] of Object.entries(credentialTypes)) {
            const opt = document.createElement('option');
            opt.value = key;
            opt.textContent = def.label;
            sel.appendChild(opt);
        }
        sel.value = cred.type;
        sel.disabled = true;

        renderCredentialFields(cred.type, cred.values);
    } catch (err) {
        showMessage('credentials-message', 'error', 'Error: ' + err.message);
    }
}

document.getElementById('cancel-credential-btn').addEventListener('click', () => {
    document.getElementById('credential-form').style.display = 'none';
    document.getElementById('credential-type-select').disabled = false;
    document.getElementById('credential-name').disabled = false;
    editingCredentialName = null;
});

document.getElementById('close-credential-form').addEventListener('click', () => {
    document.getElementById('credential-form').style.display = 'none';
    document.getElementById('credential-type-select').disabled = false;
    document.getElementById('credential-name').disabled = false;
    editingCredentialName = null;
});

document.getElementById('save-credential-btn').addEventListener('click', async () => {
    const name = document.getElementById('credential-name').value.trim();
    const type = document.getElementById('credential-type-select').value;
    const description = document.getElementById('credential-description').value.trim();

    if (!name) { showMessage('credentials-message', 'error', 'Name is required'); return; }
    if (!type) { showMessage('credentials-message', 'error', 'Type is required'); return; }

    // Gather field values
    const values = {};
    if (credentialTypes[type]) {
        credentialTypes[type].fields.forEach(field => {
            const el = document.getElementById(`cred-field-${field.name}`);
            if (el) values[field.name] = el.value;
        });
    }

    try {
        const r = await fetch('/api/credentials', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name, type, description, values })
        });
        const data = await r.json();
        showMessage('credentials-message', data.success ? 'success' : 'error', data.message);
        if (data.success) {
            document.getElementById('credential-form').style.display = 'none';
            document.getElementById('credential-type-select').disabled = false;
            document.getElementById('credential-name').disabled = false;
            editingCredentialName = null;
            loadCredentialList();
        }
    } catch (err) {
        showMessage('credentials-message', 'error', 'Error: ' + err.message);
    }
});

// Credential Help
document.getElementById('credential-help-btn').addEventListener('click', () => {
    const modal = document.getElementById('preview-modal');
    document.getElementById('preview-modal-title').textContent = 'NLS Credential Store — Usage Guide';
    const contentEl = document.getElementById('preview-modal-content');
    contentEl.innerHTML = `
<div style="font-size: 13px; line-height: 1.7; color: var(--text-primary); padding: 4px;">
<h3 style="margin: 0 0 8px 0; font-size: 15px;">Overview</h3>
<p style="margin: 0 0 12px 0;">Credentials are stored encrypted (AES-256) in the <code>nexus-credentials</code> blob container.
Secret fields are encrypted at rest and only decrypted when resolved via the API.
Scripts running in workflows can retrieve credentials using the <strong>NLS</strong> module
(Nexus Ladder Scheduler) for PowerShell or Python, or via a direct API call.</p>

<h3 style="margin: 16px 0 8px 0; font-size: 15px;">PowerShell — NLS Module</h3>
<pre style="background: #1a202c; color: #e2e8f0; padding: 12px; overflow-x: auto; white-space: pre-wrap; font-size: 12px; margin: 0 0 6px 0;"><code># The NLS module is pre-installed in the Nexus container
Import-Module NLS

# Retrieve a credential (returns a hashtable)
$creds = Get-NLSCredential -Name 'prod-db-login'
$creds.username    # plaintext
$creds.password    # decrypted

# Use with Azure Service Principal
$sp = Get-NLSCredential -Name 'azure-sp-prod'
$secPwd = ConvertTo-SecureString $sp.clientSecret -AsPlainText -Force
$psCred = [PSCredential]::new($sp.clientId, $secPwd)
Connect-AzAccount -ServicePrincipal -Tenant $sp.tenantId -Credential $psCred

# Use with AWS
$aws = Get-NLSCredential -Name 'aws-production'
Set-AWSCredential -AccessKey $aws.accessKeyId -SecretKey $aws.secretAccessKey -SessionToken $aws.sessionToken

# Use with GCP
$gcp = Get-NLSCredential -Name 'gcp-project'
$gcp.privateKey | Set-Content /tmp/gcp-key.json
gcloud auth activate-service-account $gcp.clientEmail \`
    --key-file=/tmp/gcp-key.json --project=$gcp.projectId

# Return as PSCustomObject instead of hashtable
$obj = Get-NLSCredential -Name 'prod-db-login' -AsObject
$obj.username

# Point to a different Nexus server (default: http://localhost:8080)
Set-NLSServer -Url 'http://nexus-app:8080'</code></pre>

<h3 style="margin: 16px 0 8px 0; font-size: 15px;">Python — nls Package</h3>
<pre style="background: #1a202c; color: #e2e8f0; padding: 12px; overflow-x: auto; white-space: pre-wrap; font-size: 12px; margin: 0 0 6px 0;"><code># The nls package is pre-installed in the Nexus container
import nls

# Retrieve a credential (returns a dict)
creds = nls.get_credential("prod-db-login")
print(creds["username"])
print(creds["password"])   # decrypted

# Use with boto3 (AWS)
import boto3
aws = nls.get_credential("aws-production")
session = boto3.Session(
    aws_access_key_id=aws["accessKeyId"],
    aws_secret_access_key=aws["secretAccessKey"],
    aws_session_token=aws.get("sessionToken"),
    region_name=aws.get("region", "us-east-1"),
)

# Use with Azure SDK
from azure.identity import ClientSecretCredential
sp = nls.get_credential("azure-sp-prod")
credential = ClientSecretCredential(
    tenant_id=sp["tenantId"],
    client_id=sp["clientId"],
    client_secret=sp["clientSecret"],
)

# Point to a different Nexus server
nls.set_server("http://nexus-app:8080")</code></pre>

<h3 style="margin: 16px 0 8px 0; font-size: 15px;">Direct API Call</h3>
<pre style="background: #1a202c; color: #e2e8f0; padding: 12px; overflow-x: auto; white-space: pre-wrap; font-size: 12px; margin: 0 0 6px 0;"><code># PowerShell — direct REST call (no module needed)
$resp = Invoke-RestMethod -Uri 'http://localhost:8080/api/credentials/prod-db-login/resolve'
$resp.credential.values.username
$resp.credential.values.password

# curl / shell
curl -s http://localhost:8080/api/credentials/prod-db-login/resolve | jq '.credential.values'</code></pre>

<h3 style="margin: 16px 0 8px 0; font-size: 15px;">API Endpoints</h3>
<table style="width: 100%; font-size: 12px; border-collapse: collapse; margin: 0 0 12px 0;">
<tr style="border-bottom: 2px solid #e2e8f0; text-align: left;">
    <th style="padding: 6px 8px;">Method</th><th style="padding: 6px 8px;">Route</th><th style="padding: 6px 8px;">Purpose</th>
</tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;"><code>GET</code></td><td style="padding: 6px 8px;"><code>/api/credentials/types</code></td><td style="padding: 6px 8px;">Credential type definitions</td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;"><code>GET</code></td><td style="padding: 6px 8px;"><code>/api/credentials</code></td><td style="padding: 6px 8px;">List all (no secrets)</td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;"><code>GET</code></td><td style="padding: 6px 8px;"><code>/api/credentials/:name</code></td><td style="padding: 6px 8px;">Get one (secrets masked)</td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;"><code>POST</code></td><td style="padding: 6px 8px;"><code>/api/credentials</code></td><td style="padding: 6px 8px;">Create / update</td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;"><code>DELETE</code></td><td style="padding: 6px 8px;"><code>/api/credentials/:name</code></td><td style="padding: 6px 8px;">Delete</td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;"><code>GET</code></td><td style="padding: 6px 8px;"><code>/api/credentials/:name/resolve</code></td><td style="padding: 6px 8px;">Decrypt &amp; return values</td></tr>
</table>

<h3 style="margin: 16px 0 8px 0; font-size: 15px;">Credential Types</h3>
<p style="margin: 0 0 8px 0;">The following types are available. Each type defines specific fields; secret fields are encrypted at rest.</p>
<table style="width: 100%; font-size: 12px; border-collapse: collapse;">
<tr style="border-bottom: 2px solid #e2e8f0; text-align: left;">
    <th style="padding: 6px 8px;">Type</th><th style="padding: 6px 8px;">Fields</th>
</tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;">Username / Password</td><td style="padding: 6px 8px;">username, <em>password</em></td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;">Azure Service Principal</td><td style="padding: 6px 8px;">tenantId, clientId, <em>clientSecret</em></td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;">API Key</td><td style="padding: 6px 8px;">headerName, <em>key</em></td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;">OAuth2 Client Credentials</td><td style="padding: 6px 8px;">tokenUrl, clientId, <em>clientSecret</em>, scope</td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;">AWS Credentials</td><td style="padding: 6px 8px;">accessKeyId, <em>secretAccessKey</em>, <em>sessionToken</em>, region</td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;">GCP Service Account</td><td style="padding: 6px 8px;">projectId, clientEmail, <em>privateKey</em></td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;">Connection String</td><td style="padding: 6px 8px;"><em>connectionString</em></td></tr>
<tr style="border-bottom: 1px solid #edf2f7;"><td style="padding: 6px 8px;">Bearer Token</td><td style="padding: 6px 8px;"><em>token</em></td></tr>
</table>
<p style="margin: 8px 0 0 0; font-size: 11px; color: var(--text-secondary);"><em>Italic</em> fields are encrypted at rest.</p>
</div>
    `;
    modal.style.display = 'flex';
});
