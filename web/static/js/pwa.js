const SOONLINK_PWA = {
    deferredPrompt: null,
    installButton: null,
    statusChip: null,
    registration: null,
};

document.addEventListener('DOMContentLoaded', () => {
    mountPwaSurface();
    refreshPwaSurface();
    bindPwaDisplayModeWatcher();
    registerSoonLinkServiceWorker();
});

window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    SOONLINK_PWA.deferredPrompt = event;
    refreshPwaSurface();
});

window.addEventListener('appinstalled', () => {
    SOONLINK_PWA.deferredPrompt = null;
    refreshPwaSurface();
    showPwaToast('SoonLink 应用已安装，可从桌面或主屏幕直接打开。', 'success');
});

window.addEventListener('online', () => {
    showPwaToast('网络已恢复，SoonLink 应用壳重新联通。', 'success');
});

window.addEventListener('offline', () => {
    showPwaToast('网络暂时不可用，应用壳会保留最近打开的页面。', 'warning');
});

function mountPwaSurface() {
    if (document.getElementById('soonlink-pwa-shell')) {
        SOONLINK_PWA.installButton = document.getElementById('soonlink-pwa-install-btn');
        SOONLINK_PWA.statusChip = document.getElementById('soonlink-pwa-status');
        return;
    }

    const shell = document.createElement('div');
    shell.id = 'soonlink-pwa-shell';
    shell.className = 'soonlink-pwa-shell';

    const statusChip = document.createElement('div');
    statusChip.id = 'soonlink-pwa-status';
    statusChip.className = 'soonlink-pwa-status';
    shell.appendChild(statusChip);

    const installButton = document.createElement('button');
    installButton.id = 'soonlink-pwa-install-btn';
    installButton.type = 'button';
    installButton.className = 'btn btn-primary btn-sm soonlink-pwa-install-btn';
    installButton.addEventListener('click', handlePwaInstallClick);
    shell.appendChild(installButton);

    document.body.appendChild(shell);
    SOONLINK_PWA.installButton = installButton;
    SOONLINK_PWA.statusChip = statusChip;
}

function bindPwaDisplayModeWatcher() {
    if (typeof window.matchMedia !== 'function') {
        return;
    }
    const media = window.matchMedia('(display-mode: standalone)');
    const handler = () => refreshPwaSurface();
    if (typeof media.addEventListener === 'function') {
        media.addEventListener('change', handler);
    } else if (typeof media.addListener === 'function') {
        media.addListener(handler);
    }
}

function isStandaloneMode() {
    if (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) {
        return true;
    }
    return !!window.navigator.standalone;
}

function refreshPwaSurface() {
    const button = SOONLINK_PWA.installButton;
    const statusChip = SOONLINK_PWA.statusChip;
    if (!button || !statusChip) {
        return;
    }

    if (isStandaloneMode()) {
        statusChip.hidden = false;
        statusChip.textContent = '应用模式已启用';
        button.hidden = true;
        return;
    }

    statusChip.hidden = false;
    statusChip.textContent = navigator.onLine ? '可安装应用壳' : '离线中 · 可使用最近缓存';
    button.hidden = false;
    button.textContent = SOONLINK_PWA.deferredPrompt ? '安装应用' : '安装指引';
    button.classList.toggle('btn-outline-secondary', !SOONLINK_PWA.deferredPrompt);
    button.classList.toggle('btn-primary', !!SOONLINK_PWA.deferredPrompt);
}

async function handlePwaInstallClick() {
    if (isStandaloneMode()) {
        showPwaToast('当前已经在 SoonLink 应用模式中打开。', 'info');
        return;
    }

    if (SOONLINK_PWA.deferredPrompt) {
        const prompt = SOONLINK_PWA.deferredPrompt;
        SOONLINK_PWA.deferredPrompt = null;
        refreshPwaSurface();
        await prompt.prompt();
        try {
            await prompt.userChoice;
        } catch (_error) {}
        return;
    }

    showPwaInstallGuide();
}

function showPwaInstallGuide() {
    const ua = navigator.userAgent || '';
    const isIOS = /iphone|ipad|ipod/i.test(ua);
    if (isIOS) {
        window.alert('Safari 中请使用“分享”菜单，再选择“添加到主屏幕”，即可把 SoonLink staticWeb 作为应用安装。');
        return;
    }
    window.alert('如果浏览器没有弹出安装确认，请使用浏览器菜单中的“安装应用”或“添加到主屏幕”。');
}

async function registerSoonLinkServiceWorker() {
    if (!('serviceWorker' in navigator)) {
        showPwaToast('当前浏览器不支持离线应用壳，仍可直接使用网页模式。', 'warning');
        return;
    }

    try {
        const registration = await navigator.serviceWorker.register('/service-worker.js', {
            scope: '/',
        });
        SOONLINK_PWA.registration = registration;
        bindServiceWorkerUpdateHints(registration);
    } catch (error) {
        console.error('SoonLink PWA 注册失败:', error);
        showPwaToast('应用壳注册失败，当前先继续使用网页模式。', 'warning');
    }
}

function bindServiceWorkerUpdateHints(registration) {
    if (registration.waiting) {
        showPwaToast('检测到新版应用壳，刷新页面后即可生效。', 'info');
    }

    registration.addEventListener('updatefound', () => {
        const worker = registration.installing;
        if (!worker) {
            return;
        }
        worker.addEventListener('statechange', () => {
            if (worker.state === 'installed' && navigator.serviceWorker.controller) {
                showPwaToast('SoonLink 应用壳已更新，刷新页面后生效。', 'info');
            }
        });
    });
}

function ensurePwaToastHost() {
    let host = document.getElementById('soonlink-pwa-toast-host');
    if (!host) {
        host = document.createElement('div');
        host.id = 'soonlink-pwa-toast-host';
        host.className = 'soonlink-pwa-toast-host';
        document.body.appendChild(host);
    }
    return host;
}

function showPwaToast(message, tone = 'info') {
    const host = ensurePwaToastHost();
    const toast = document.createElement('div');
    toast.className = `soonlink-pwa-toast soonlink-pwa-toast-${tone}`;
    toast.textContent = String(message || '');
    host.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));
    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 220);
    }, 3200);
}
