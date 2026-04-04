document.addEventListener('DOMContentLoaded', function() {
    applyLoginTheme();
    loadLoginContext();
    setInterval(applyLoginTheme, 60000);
    document.addEventListener('visibilitychange', function() {
        if (!document.hidden) {
            applyLoginTheme();
            loadLoginContext();
        }
    });
});

async function loadLoginContext() {
    try {
        const response = await fetch('/api/session/context');
        if (!response.ok) {
            throw new Error('session context unavailable');
        }
        const context = await response.json();
        applyLoginContext(context);
    } catch (error) {
        console.error('加载登录上下文失败:', error);
        setText('login-mode-pill', '上下文读取失败');
        setText('login-summary', '当前无法读取访问上下文，请稍后重试。');
        setText('login-detail', 'Core 版不会通过此入口为远程访问授予管理员权限。');
    }
}

function applyLoginContext(context) {
    const isLocalAdmin = !!context.isLocalAdmin;
    document.body.dataset.roleVariant = isLocalAdmin ? 'admin' : 'remote';

    setText('login-mode-pill', isLocalAdmin ? '本机无缝管理入口' : '远程普通能力入口');
    setText('login-summary', isLocalAdmin
        ? '当前访问来自本机，SoonLink 会直接为你启用管理员能力。'
        : '当前访问来自远程设备，本期仅展示登录预留能力，不会提权。');
    setText('login-detail', isLocalAdmin
        ? '你可以直接返回主页或进入管理台，无需额外密码。'
        : '后续可在这里接入密码、外部 Provider 或 Pro 版加密认证。');

    setText('login-access-mode', context.accessMode || '-');
    setText('login-is-local-admin', isLocalAdmin ? '是' : '否');
    setText('login-auth-policy', context.auth?.policy || '-');
    setText('login-auth-provider', context.auth?.provider || '-');
    setText('login-auth-edition', context.auth?.edition || '-');
    setText(
        'login-network-origin',
        `${context.network?.resolvedIp || '-'} (client ${context.network?.clientIp || '-'})`
    );

    const adminLink = document.getElementById('login-admin-link');
    if (adminLink) {
        adminLink.style.display = isLocalAdmin ? '' : 'none';
    }

    const caps = Array.isArray(context.auth?.capabilities) ? context.auth.capabilities : [];
    const capWrap = document.getElementById('login-capabilities');
    if (capWrap) {
        capWrap.innerHTML = '';
        if (!caps.length) {
            capWrap.innerHTML = '<span class="login-capability">暂无能力描述</span>';
        } else {
            caps.forEach((cap) => {
                const chip = document.createElement('span');
                chip.className = 'login-capability';
                chip.textContent = cap;
                capWrap.appendChild(chip);
            });
        }
    }
}

function applyLoginTheme() {
    const pref = (window.localStorage && localStorage.getItem('soonlink_theme_preference')) || 'auto';
    let mode = pref;
    if (mode !== 'light' && mode !== 'dark') {
        const hour = new Date().getHours();
        mode = hour >= 7 && hour < 19 ? 'light' : 'dark';
    }
    document.body.dataset.timeMode = mode;
    setText('login-theme-chip', pref === 'auto' ? `主题自动 · ${mode}` : `主题固定 · ${mode}`);
}

function setText(id, value) {
    const node = document.getElementById(id);
    if (node) {
        node.textContent = value;
    }
}
