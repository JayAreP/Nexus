// Nexus - Scripts panel
// ===== SCRIPTS =====
let currentScriptType = 'powershell';

// Script Output Help
document.getElementById('script-help-btn').addEventListener('click', () => {
    const modal = document.getElementById('preview-modal');
    document.getElementById('preview-modal-title').textContent = 'Script Output & Workflow Chaining Guide';
    const contentEl = document.getElementById('preview-modal-content');
    contentEl.innerHTML = `
<div style="font-size: 13px; line-height: 1.7; color: var(--text-primary); padding: 4px;">
<h3 style="margin: 0 0 8px 0; font-size: 15px;">How Output Chaining Works</h3>
<p style="margin: 0 0 12px 0;">When a workflow runs, each step's <strong>entire STDOUT</strong> is captured after the script exits.
The engine then scans the output for valid JSON &mdash; first trying the full output, then scanning backward
from the end to find the <strong>last JSON object or array</strong>. This means progress messages, banners, and other
text printed before your final JSON are automatically ignored.</p>

<p style="margin: 0 0 12px 0;">If valid JSON is found, every top-level property is registered as <code>step{N}.{key}</code>
and can be mapped as input to subsequent steps via <strong>Input Mapping</strong>.
If no JSON is found and the step has <strong>breakpoint checks</strong>, the step fails with:
<em>&ldquo;expected a JSON response but none was found&rdquo;</em>.</p>

<h3 style="margin: 16px 0 8px 0; font-size: 15px;">When Do I Need JSON Output?</h3>
<table style="width:100%; border-collapse:collapse; font-size:12px; margin-bottom:16px;">
<thead><tr style="border-bottom:2px solid #e2e8f0; text-align:left;">
<th style="padding:6px 10px;">Scenario</th>
<th style="padding:6px 10px;">Pure JSON Required?</th>
</tr></thead><tbody>
<tr style="border-bottom:1px solid #edf2f7;"><td style="padding:6px 10px;">Standalone script, no downstream steps use its output</td><td style="padding:6px 10px;"><strong>No</strong> &mdash; output anything you like</td></tr>
<tr style="border-bottom:1px solid #edf2f7;"><td style="padding:6px 10px;">Script output is mapped to a later step's input</td><td style="padding:6px 10px;"><strong>Yes</strong> &mdash; JSON must appear as the last block in output (other text before it is OK)</td></tr>
<tr style="border-bottom:1px solid #edf2f7;"><td style="padding:6px 10px;">Breakpoint checks on output properties</td><td style="padding:6px 10px;"><strong>Yes</strong> &mdash; if no JSON is found at all, the step fails</td></tr>
</tbody></table>

<h3 style="margin: 16px 0 8px 0; font-size: 15px;">PowerShell</h3>
<p style="margin: 0 0 6px 0;"><code>Write-Output</code>, <code>return</code>, and bare expressions go to STDOUT and <strong>are captured</strong>.<br>
<code>Write-Host</code> in PowerShell 7 writes to the Information stream but is <strong>also captured</strong> in the workflow engine via <code>2>&amp;1</code> redirection, meaning it will pollute your JSON output.</p>

<p style="margin: 0 0 4px 0;"><strong>Suppressing unwanted output:</strong></p>
<pre style="background: #1a202c; color: #e2e8f0; padding: 12px; overflow-x: auto; white-space: pre-wrap; font-size: 12px; margin: 0 0 12px 0;"><code># Suppress noisy cmdlet output
Connect-AzAccount ... | Out-Null
$result = Some-Command 6>&1  # redirect info stream away

# Global preference to silence verbose/progress
$VerbosePreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# Safe pattern: do all work, emit JSON last
Write-Host "Working..."   # will pollute STDOUT!
$ProgressPreference = 'SilentlyContinue'

# Instead, write progress to stderr:
[Console]::Error.WriteLine("Working...")

# Then emit clean JSON as the final output
[PSCustomObject]@{ id = $result.Id; status = "done" } | ConvertTo-Json -Compress</code></pre>

<h3 style="margin: 16px 0 8px 0; font-size: 15px;">Python</h3>
<p style="margin: 0 0 6px 0;"><code>print()</code> goes to STDOUT and is captured. Use <code>sys.stderr</code> for progress messages.</p>
<pre style="background: #1a202c; color: #e2e8f0; padding: 12px; overflow-x: auto; white-space: pre-wrap; font-size: 12px; margin: 0 0 12px 0;"><code>import sys, json

# Progress to stderr (not captured as output)
print("Working...", file=sys.stderr)

# Final JSON result to stdout
result = {"id": 123, "status": "done"}
print(json.dumps(result))</code></pre>

<h3 style="margin: 16px 0 8px 0; font-size: 15px;">Shell (Bash)</h3>
<p style="margin: 0 0 6px 0;"><code>echo</code> and general output goes to STDOUT. Use <code>&gt;&amp;2</code> for progress lines.</p>
<pre style="background: #1a202c; color: #e2e8f0; padding: 12px; overflow-x: auto; white-space: pre-wrap; font-size: 12px; margin: 0 0 12px 0;"><code>#!/bin/bash

# Progress to stderr
echo "Working..." >&2

# Final JSON output to stdout
echo '{"id": 123, "status": "done"}'</code></pre>

<h3 style="margin: 16px 0 8px 0; font-size: 15px;">Terraform</h3>
<p style="margin: 0 0 6px 0;">Terraform steps are handled differently. After <code>terraform apply</code>, the engine automatically runs
<code>terraform output -json</code> and appends it. All Terraform outputs are captured as step variables.
You don't need to manage STDOUT &mdash; just define your <code>output</code> blocks in HCL.</p>
<pre style="background: #1a202c; color: #e2e8f0; padding: 12px; overflow-x: auto; white-space: pre-wrap; font-size: 12px; margin: 0 0 12px 0;"><code># In your .tf file — these become step variables automatically
output "resource_id" {
  value = azurerm_resource.example.id
}
output "ip_address" {
  value = azurerm_public_ip.example.ip_address
}</code></pre>

<h3 style="margin: 16px 0 8px 0; font-size: 15px;">Quick Reference: STDOUT vs STDERR</h3>
<table style="width:100%; border-collapse:collapse; font-size:12px; margin-bottom:8px;">
<thead><tr style="border-bottom:2px solid #e2e8f0; text-align:left;">
<th style="padding:6px 10px;">Language</th>
<th style="padding:6px 10px;">STDOUT (captured)</th>
<th style="padding:6px 10px;">STDERR (safe for progress)</th>
<th style="padding:6px 10px;">Suppress noisy commands</th>
</tr></thead><tbody>
<tr style="border-bottom:1px solid #edf2f7;"><td style="padding:6px 10px;">PowerShell</td><td style="padding:6px 10px;"><code>Write-Output</code>, <code>return</code></td><td style="padding:6px 10px;"><code>[Console]::Error.WriteLine()</code></td><td style="padding:6px 10px;"><code>| Out-Null</code>, <code>$null = ...</code></td></tr>
<tr style="border-bottom:1px solid #edf2f7;"><td style="padding:6px 10px;">Python</td><td style="padding:6px 10px;"><code>print()</code></td><td style="padding:6px 10px;"><code>print(..., file=sys.stderr)</code></td><td style="padding:6px 10px;">Don't <code>print()</code> until the end</td></tr>
<tr style="border-bottom:1px solid #edf2f7;"><td style="padding:6px 10px;">Shell</td><td style="padding:6px 10px;"><code>echo</code></td><td style="padding:6px 10px;"><code>echo ... >&amp;2</code></td><td style="padding:6px 10px;">Redirect: <code>cmd > /dev/null</code></td></tr>
<tr style="border-bottom:1px solid #edf2f7;"><td style="padding:6px 10px;">Terraform</td><td style="padding:6px 10px;">Automatic (<code>output</code> blocks)</td><td style="padding:6px 10px;">N/A</td><td style="padding:6px 10px;">N/A &mdash; managed by engine</td></tr>
</tbody></table>
</div>`;
    contentEl.style.whiteSpace = 'normal';
    modal.style.display = 'flex';
});

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
                        <button class="btn btn-secondary btn-sm" onclick="editScript('${currentScriptType}', '${s.name}')">Edit</button>
                        <button class="btn btn-secondary btn-sm" onclick="previewScript('${currentScriptType}', '${s.name}')">Preview</button>
                        <button class="btn btn-secondary btn-sm" onclick="copyScript('${currentScriptType}', '${s.name}')">Copy</button>
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

async function copyScript(type, name) {
    const newName = prompt(`Copy "${name}" — enter new filename:`, name);
    if (!newName || newName === name) return;
    try {
        const r = await fetch(`/api/scripts/${type}/${encodeURIComponent(name)}/copy`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ newName })
        });
        const data = await r.json();
        showMessage('scripts-message', data.success ? 'success' : 'error', data.message);
        if (data.success) loadScripts();
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

// ===== SCRIPT EDITOR =====
const aceModeMap = { powershell: 'powershell', python: 'python', shell: 'sh', terraform: 'terraform', webhook: 'json', filecheck: 'json', cloudformation: 'yaml', armtemplate: 'json' };
let aceEditor = null;
let editorScriptType = '';
let editorScriptName = '';

async function editScript(type, name) {
    editorScriptType = type;
    editorScriptName = name;
    document.getElementById('editor-modal-title').textContent = name;
    document.getElementById('editor-status').textContent = 'Loading...';
    document.getElementById('editor-modal').style.display = 'flex';

    // Init or reuse Ace editor
    if (!aceEditor) {
        aceEditor = ace.edit('editor-container', {
            fontSize: 13,
            theme: 'ace/theme/monokai',
            showPrintMargin: false,
            wrap: true,
            tabSize: 4,
            useSoftTabs: true
        });
    }
    aceEditor.setValue('');
    aceEditor.setReadOnly(true);

    try {
        const r = await fetch(`/api/scripts/${encodeURIComponent(type)}/${encodeURIComponent(name)}/content`);
        const data = await r.json();
        if (data.success) {
            const mode = aceModeMap[type] || 'text';
            aceEditor.session.setMode('ace/mode/' + mode);
            aceEditor.setValue(data.content, -1);
            aceEditor.setReadOnly(false);
            aceEditor.focus();
            document.getElementById('editor-status').textContent = '';
        } else {
            document.getElementById('editor-status').textContent = data.message || 'Failed to load';
        }
    } catch (err) {
        document.getElementById('editor-status').textContent = 'Error: ' + err.message;
    }
}

document.getElementById('editor-save-btn').addEventListener('click', async () => {
    const content = aceEditor.getValue();
    const statusEl = document.getElementById('editor-status');
    statusEl.textContent = 'Saving...';
    try {
        const r = await fetch(`/api/scripts/${encodeURIComponent(editorScriptType)}/${encodeURIComponent(editorScriptName)}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ content })
        });
        const data = await r.json();
        if (data.success) {
            statusEl.textContent = 'Saved.';
            setTimeout(() => {
                document.getElementById('editor-modal').style.display = 'none';
                showMessage('scripts-message', 'success', `Script "${editorScriptName}" saved.`);
            }, 500);
        } else {
            statusEl.textContent = 'Save failed: ' + (data.message || 'Unknown error');
        }
    } catch (err) {
        statusEl.textContent = 'Save error: ' + err.message;
    }
});

document.getElementById('editor-cancel-btn').addEventListener('click', () => {
    document.getElementById('editor-modal').style.display = 'none';
});

document.getElementById('close-editor-modal').addEventListener('click', () => {
    document.getElementById('editor-modal').style.display = 'none';
});

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
