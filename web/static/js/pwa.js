const SOONLINK_PWA = {
    deferredPrompt: null,
    installButton: null,
    note: null,
    shell: null,
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
    refreshPwaSurface();
    showPwaToast('网络已恢复，SoonLink 应用壳重新联通。', 'success');
});

window.addEventListener('offline', () => {
    refreshPwaSurface();
    showPwaToast('网络暂时不可用，应用壳会保留最近打开的页面。', 'warning');
});

function mountPwaSurface() {
    SOONLINK_PWA.shell = document.getElementById('soonlink-pwa-shell');
    SOONLINK_PWA.installButton = document.getElementById('soonlink-pwa-install-btn');
    SOONLINK_PWA.statusChip = document.getElementById('soonlink-pwa-status');
    SOONLINK_PWA.note = document.getElementById('soonlink-pwa-note');

    if (SOONLINK_PWA.installButton && SOONLINK_PWA.installButton.dataset.bound !== 'true') {
        SOONLINK_PWA.installButton.addEventListener('click', handlePwaInstallClick);
        SOONLINK_PWA.installButton.dataset.bound = 'true';
    }
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

function isIosFamily() {
    return /iphone|ipad|ipod/i.test(navigator.userAgent || '');
}

function isCompactViewport() {
    return !!(window.matchMedia && window.matchMedia('(max-width: 991.98px)').matches);
}

function updatePwaNote(message) {
    if (SOONLINK_PWA.note) {
        SOONLINK_PWA.note.textContent = String(message || '');
    }
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
        updatePwaNote('当前已经在 SoonLink 应用模式中打开，可从桌面或主屏幕再次进入。');
        return;
    }

    const canPromptInstall = !!SOONLINK_PWA.deferredPrompt;
    const offline = !navigator.onLine;
    const compactViewport = isCompactViewport();

    statusChip.hidden = false;
    if (offline) {
        statusChip.textContent = '离线中 · 可使用最近缓存';
    } else if (canPromptInstall) {
        statusChip.textContent = '可安装应用壳';
    } else if (isIosFamily()) {
        statusChip.textContent = '可添加到主屏幕';
    } else {
        statusChip.textContent = '安装入口已收纳到设置页';
    }

    button.hidden = false;
    button.textContent = canPromptInstall ? '安装应用' : (isIosFamily() ? '主屏安装指引' : '安装指引');
    button.classList.toggle('btn-outline-secondary', !canPromptInstall);
    button.classList.toggle('btn-primary', canPromptInstall);

    if (offline) {
        updatePwaNote('离线时会优先使用最近缓存的页面资源；联网恢复后会继续检查新版应用壳。');
    } else if (canPromptInstall) {
        updatePwaNote(compactViewport
            ? '手机版和平板版不再显示全局浮层；如需安装，请在设置页点击“安装应用”。'
            : '当前浏览器支持直接安装 SoonLink 应用壳，安装后可像独立应用一样打开。');
    } else if (isIosFamily()) {
        updatePwaNote('Safari 中请使用“分享”菜单里的“添加到主屏幕”；移动端安装入口已统一收纳到这里。');
    } else {
        updatePwaNote(compactViewport
            ? '手机版和平板版不再显示全局浮层；浏览器若不弹出确认，请从菜单手动执行安装。'
            : '如果浏览器没有弹出安装确认，请使用浏览器菜单中的“安装应用”或“添加到主屏幕”。');
    }
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
    if (isIosFamily()) {
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
