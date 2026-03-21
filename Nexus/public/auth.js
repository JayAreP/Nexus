// Nexus — Auth (token management, fetch wrapper, session guard)

(function () {
    const TOKEN_KEY = 'nexus_auth_token';
    const USER_KEY  = 'nexus_auth_user';

    window.NexusAuth = {
        getToken()  { return localStorage.getItem(TOKEN_KEY); },
        getUser()   { try { return JSON.parse(localStorage.getItem(USER_KEY)); } catch { return null; } },

        setSession(token, user) {
            localStorage.setItem(TOKEN_KEY, token);
            localStorage.setItem(USER_KEY, JSON.stringify(user));
        },

        clear() {
            localStorage.removeItem(TOKEN_KEY);
            localStorage.removeItem(USER_KEY);
        },

        async logout() {
            const token = this.getToken();
            if (token) {
                try { await fetch('/api/auth/logout', { method: 'POST', headers: { 'Authorization': 'Bearer ' + token } }); } catch {}
            }
            this.clear();
            window.location.href = '/login';
        }
    };

    // Wrap global fetch — inject auth header and redirect on 401
    const _origFetch = window.fetch;
    window.fetch = function (url, opts) {
        opts = opts || {};
        const token = NexusAuth.getToken();
        if (token) {
            if (!opts.headers) opts.headers = {};
            if (opts.headers instanceof Headers) {
                if (!opts.headers.has('Authorization')) opts.headers.set('Authorization', 'Bearer ' + token);
            } else {
                if (!opts.headers['Authorization']) opts.headers['Authorization'] = 'Bearer ' + token;
            }
        }
        return _origFetch.call(this, url, opts).then(res => {
            if (res.status === 401 && typeof url === 'string' && !url.includes('/api/auth/login') && !url.includes('/api/auth/session')) {
                NexusAuth.clear();
                window.location.href = '/login';
            }
            return res;
        });
    };

    // Session guard — if no token, bounce to login immediately
    if (!localStorage.getItem(TOKEN_KEY)) {
        window.location.href = '/login';
    }
})();
