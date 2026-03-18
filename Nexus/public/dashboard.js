// Nexus - Dashboard panel
// ===== DASHBOARD =====

let dashboardChartDonut = null;
let dashboardChartTrend = null;

function navigateToPanel(panelName) {
    const link = document.querySelector(`.nav-link[data-panel="${panelName}"]`);
    if (link) link.click();
}

async function loadDashboard(forceRefresh) {
    const msg = document.getElementById('dashboard-message');
    msg.className = 'message'; msg.textContent = '';

    try {
        const url = forceRefresh ? '/api/dashboard?refresh=true' : '/api/dashboard';
        const r = await fetch(url);
        const d = await r.json();
        if (!d.success) {
            msg.className = 'message error';
            msg.textContent = d.message || 'Failed to load dashboard';
            return;
        }

        // ── Summary cards ────────────────────────────────────
        document.getElementById('dash-workflows').textContent   = d.counts.workflows;
        document.getElementById('dash-scripts').textContent     = d.counts.scripts;
        document.getElementById('dash-schedules').textContent   = d.counts.schedules;
        document.getElementById('dash-webhooks').textContent    = d.counts.webhooks;
        document.getElementById('dash-filechecks').textContent  = d.counts.filechecks;
        document.getElementById('dash-credentials').textContent = d.counts.credentials;

        // ── Running jobs ─────────────────────────────────────
        const runEl = document.getElementById('dash-running-list');
        const runCountEl = document.getElementById('dash-running-count');
        if (d.running && d.running.length > 0) {
            runCountEl.textContent = d.running.length;
            runCountEl.classList.add('pulse');
            runEl.innerHTML = d.running.map(n =>
                `<div class="dash-running-item"><span class="dash-running-dot"></span><a href="#" onclick="navigateToPanel('runner'); return false;">${escHtml(n)}</a></div>`
            ).join('');
        } else {
            runCountEl.textContent = '0';
            runCountEl.classList.remove('pulse');
            runEl.innerHTML = '<span class="text-muted">No jobs running</span>';
        }

        // ── 24h stats ────────────────────────────────────────
        document.getElementById('dash-24h-total').textContent      = d.last24h.total;
        document.getElementById('dash-24h-success').textContent    = d.last24h.success;
        document.getElementById('dash-24h-failed').textContent     = d.last24h.failed;
        document.getElementById('dash-24h-rate').textContent       = d.last24h.successRate + '%';
        document.getElementById('dash-24h-avg').textContent        = formatDuration(d.last24h.avgDuration);

        const longestEl = document.getElementById('dash-24h-longest');
        if (d.last24h.longestRun) {
            longestEl.innerHTML = `<a href="#" onclick="navigateToPanel('logs'); return false;">${escHtml(d.last24h.longestRun.workflow)}</a> (${formatDuration(d.last24h.longestRun.duration)})`;
        } else {
            longestEl.textContent = '—';
        }

        // ── Donut chart ──────────────────────────────────────
        renderDonut(d.last24h.success, d.last24h.failed);

        // ── 7-day trend ──────────────────────────────────────
        renderTrend(d.trend);

        // ── Leaderboards ─────────────────────────────────────
        renderTable('dash-most-run', d.mostRun, ['workflow', 'count'], [
            { label: 'Workflow', key: 'workflow', link: true },
            { label: 'Runs', key: 'count' }
        ]);
        renderTable('dash-most-failing', d.mostFailing, ['workflow', 'failures', 'rate'], [
            { label: 'Workflow', key: 'workflow', link: true },
            { label: 'Fails', key: 'failures' },
            { label: 'Rate', key: 'rate', suffix: '%' }
        ]);
        renderTable('dash-slowest', d.slowest, ['workflow', 'avgDuration'], [
            { label: 'Workflow', key: 'workflow', link: true },
            { label: 'Avg Duration', key: 'avgDuration', format: 'duration' }
        ]);
        renderTable('dash-recent-failures', d.recentFailures, ['workflow', 'when'], [
            { label: 'Workflow', key: 'workflow', link: true },
            { label: 'When', key: 'when' }
        ]);

        // ── Step type stats ──────────────────────────────────
        renderTable('dash-step-stats', d.stepTypeStats, ['type', 'total', 'failures'], [
            { label: 'Type', key: 'type' },
            { label: 'Total', key: 'total' },
            { label: 'Failures', key: 'failures' }
        ]);

        // If we got cached data on initial load, silently refresh in background
        if (d.cached && !forceRefresh) {
            setTimeout(() => loadDashboard(true), 100);
        }

    } catch (err) {
        msg.className = 'message error';
        msg.textContent = 'Error: ' + err.message;
    }
}

function formatDuration(seconds) {
    if (!seconds || seconds === 0) return '—';
    if (seconds < 60) return seconds + 's';
    const m = Math.floor(seconds / 60);
    const s = Math.round(seconds % 60);
    return m + 'm ' + s + 's';
}

function renderDonut(success, failed) {
    const ctx = document.getElementById('dash-donut-chart');
    if (!ctx) return;

    const total = success + failed;
    if (total === 0) {
        if (dashboardChartDonut) { dashboardChartDonut.destroy(); dashboardChartDonut = null; }
        ctx.getContext('2d').clearRect(0, 0, ctx.width, ctx.height);
        return;
    }

    // Update in place to avoid re-animation
    if (dashboardChartDonut) {
        dashboardChartDonut.data.datasets[0].data = [success, failed];
        dashboardChartDonut.update();
        return;
    }

    dashboardChartDonut = new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: ['Success', 'Failed'],
            datasets: [{
                data: [success, failed],
                backgroundColor: ['#10b981', '#f43f5e'],
                borderColor: ['transparent', 'transparent'],
                borderWidth: 0,
                hoverBackgroundColor: ['#34d399', '#fb7185'],
                hoverOffset: 6
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            cutout: '65%',
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: { color: '#94a3b8', font: { size: 12 } }
                },
                tooltip: {
                    callbacks: {
                        label: function(c) {
                            const pct = Math.round((c.parsed / total) * 100);
                            return c.label + ': ' + c.parsed + ' (' + pct + '%)';
                        }
                    }
                }
            }
        }
    });
}

function renderTrend(trend) {
    const ctx = document.getElementById('dash-trend-chart');
    if (!ctx || !trend || trend.length === 0) return;

    // Update in place to avoid re-animation
    if (dashboardChartTrend) {
        dashboardChartTrend.data.labels = trend.map(d => d.label);
        dashboardChartTrend.data.datasets[0].data = trend.map(d => d.success);
        dashboardChartTrend.data.datasets[1].data = trend.map(d => d.failed);
        dashboardChartTrend.update();
        return;
    }

    dashboardChartTrend = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: trend.map(d => d.label),
            datasets: [
                {
                    label: 'Success',
                    data: trend.map(d => d.success),
                    backgroundColor: 'rgba(16, 185, 129, 0.8)',
                    hoverBackgroundColor: '#10b981',
                    borderRadius: 4,
                    barPercentage: 0.65
                },
                {
                    label: 'Failed',
                    data: trend.map(d => d.failed),
                    backgroundColor: 'rgba(244, 63, 94, 0.8)',
                    hoverBackgroundColor: '#f43f5e',
                    borderRadius: 4,
                    barPercentage: 0.65
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
                x: {
                    stacked: true,
                    ticks: { color: '#94a3b8' },
                    grid: { display: false }
                },
                y: {
                    stacked: true,
                    beginAtZero: true,
                    ticks: { color: '#94a3b8', stepSize: 1 },
                    grid: { color: 'rgba(148,163,184,0.1)' }
                }
            },
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: { color: '#94a3b8', font: { size: 12 } }
                }
            }
        }
    });
}

function renderTable(containerId, data, _keys, columns) {
    const el = document.getElementById(containerId);
    if (!el) return;

    if (!data || data.length === 0) {
        el.innerHTML = '<span class="text-muted">No data</span>';
        return;
    }

    let html = '<table class="dash-table"><thead><tr>';
    columns.forEach(c => { html += `<th>${c.label}</th>`; });
    html += '</tr></thead><tbody>';

    data.forEach(row => {
        html += '<tr>';
        columns.forEach(c => {
            let val = row[c.key];
            if (c.format === 'duration') val = formatDuration(val);
            if (c.suffix) val = val + c.suffix;
            if (c.link) {
                html += `<td><a href="#" onclick="navigateToPanel('logs'); return false;">${escHtml(String(val))}</a></td>`;
            } else {
                html += `<td>${escHtml(String(val))}</td>`;
            }
        });
        html += '</tr>';
    });

    html += '</tbody></table>';
    el.innerHTML = html;
}

// Auto-refresh every 30 seconds when dashboard is visible
let dashboardRefreshInterval = null;
function startDashboardRefresh() {
    stopDashboardRefresh();
    dashboardRefreshInterval = setInterval(() => {
        if (document.getElementById('dashboard-panel').classList.contains('active')) {
            loadDashboard();
        }
    }, 30000);
}
function stopDashboardRefresh() {
    if (dashboardRefreshInterval) {
        clearInterval(dashboardRefreshInterval);
        dashboardRefreshInterval = null;
    }
}
