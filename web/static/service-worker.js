const SOONLINK_SHELL_CACHE = 'soonlink-app-shell-v20260508-1';
const SOONLINK_STATIC_ASSETS = [
    '/manifest.webmanifest',
    '/static/css/style.css',
    '/static/js/icons.js',
    '/static/js/pwa.js',
    '/static/js/main.js',
    '/static/js/login.js',
    '/static/js/admin.js',
    '/static/js/dashboard.js',
    '/static/icons/sprite.svg',
    '/static/icons/app-icon.svg',
    '/static/offline.html',
];

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(SOONLINK_SHELL_CACHE)
            .then((cache) => cache.addAll(SOONLINK_STATIC_ASSETS))
            .then(() => self.skipWaiting())
    );
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((keys) =>
            Promise.all(
                keys
                    .filter((key) => key !== SOONLINK_SHELL_CACHE)
                    .map((key) => caches.delete(key))
            )
        ).then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', (event) => {
    const request = event.request;
    if (request.method !== 'GET') {
        return;
    }

    const url = new URL(request.url);

    if (request.mode === 'navigate') {
        event.respondWith(handleNavigationRequest(request));
        return;
    }

    if (url.origin !== self.location.origin) {
        if (request.destination === 'style' || request.destination === 'script' || request.destination === 'font') {
            event.respondWith(handleRuntimeCache(request));
        }
        return;
    }

    if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/admin/api/') || url.pathname === '/health') {
        return;
    }

    if (url.pathname.startsWith('/static/') || url.pathname === '/manifest.webmanifest') {
        event.respondWith(handleStaticAssetRequest(request));
    }
});

async function handleNavigationRequest(request) {
    try {
        const response = await fetch(request);
        if (response.ok) {
            const cache = await caches.open(SOONLINK_SHELL_CACHE);
            cache.put(request, response.clone());
        }
        return response;
    } catch (_error) {
        const cached = await caches.match(request);
        if (cached) {
            return cached;
        }
        const home = await caches.match('/');
        if (home) {
            return home;
        }
        return caches.match('/static/offline.html');
    }
}

async function handleStaticAssetRequest(request) {
    const cached = await caches.match(request);
    if (cached) {
        fetchAndRefresh(request);
        return cached;
    }

    try {
        const response = await fetch(request);
        if (response.ok) {
            const cache = await caches.open(SOONLINK_SHELL_CACHE);
            cache.put(request, response.clone());
        }
        return response;
    } catch (_error) {
        return caches.match('/static/offline.html');
    }
}

async function handleRuntimeCache(request) {
    const cached = await caches.match(request);
    if (cached) {
        fetchAndRefresh(request);
        return cached;
    }
    return fetchAndCache(request);
}

async function fetchAndRefresh(request) {
    try {
        await fetchAndCache(request);
    } catch (_error) {}
}

async function fetchAndCache(request) {
    const response = await fetch(request);
    if (response && response.ok) {
        const cache = await caches.open(SOONLINK_SHELL_CACHE);
        cache.put(request, response.clone());
    }
    return response;
}
