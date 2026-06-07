document.addEventListener('DOMContentLoaded', function() {
    applyLoginTheme();
    bindLoginForm();
    loadLoginContext();
    setInterval(applyLoginTheme, 60000);
    document.addEventListener('visibilitychange', function() {
        if (!document.hidden) {
            applyLoginTheme();
            loadLoginContext();
        }
    });
});

function bindLoginForm() {
    const form = document.getElementById('login-password-form');
    if (form) {
        form.addEventListener('submit', async function(event) {
            event.preventDefault();
            await submitAdminPassword();
        });
    }

    const logoutButton = document.getElementById('login-logout-button');
    if (logoutButton) {
        logoutButton.addEventListener('click', async function() {
            await logoutAdminSession();
        });
    }
}

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
    const auth = context.auth || {};
    const passwordConfigured = !!auth.passwordConfigured;
    const sessionAuthenticated = !!auth.sessionAuthenticated;
    const adminAccessAllowed = !!auth.adminAccessAllowed;
    document.body.dataset.roleVariant = isLocalAdmin ? 'admin' : 'remote';

    if (passwordConfigured) {
        setText('login-mode-pill', adminAccessAllowed ? '管理员会话已建立' : '需要管理员认证');
        setText('login-summary', adminAccessAllowed
            ? '当前请求已通过管理员会话或 Bearer Token 验证。'
            : '当前实例已配置管理员密码或 Bearer Token，管理面板不再仅凭本机 IP 放行。');
        setText('login-detail', sessionAuthenticated
            ? '你可以进入管理台；会话仅保存在本机 Cookie 中。'
            : '请输入运行时环境变量 `SOONLINK_ADMIN_PASSWORD` 对应的密码建立会话。');
    } else {
        setText('login-mode-pill', isLocalAdmin ? '本机无缝管理入口' : '远程普通能力入口');
        setText('login-summary', isLocalAdmin
            ? '当前访问来自本机，SoonLink 会沿用兼容的本机管理员能力。'
            : '当前访问来自远程设备；未配置管理员认证时不会获得管理权限。');
        setText('login-detail', isLocalAdmin
            ? '你可以直接返回主页或进入管理台；建议生产环境配置 `SOONLINK_ADMIN_PASSWORD`。'
            : '如需远程管理，请先在服务端配置管理员密码或 Bearer Token。');
    }

    setText('login-access-mode', context.accessMode || '-');
    setText('login-is-local-admin', isLocalAdmin ? '是' : '否');
    setText('login-auth-policy', auth.policy || '-');
    setText('login-auth-provider', auth.provider || '-');
    setText('login-runtime-label', context.product?.displayName || context.product?.edition || '-');
    setText(
        'login-network-origin',
        `${context.network?.resolvedIp || '-'} (client ${context.network?.clientIp || '-'})`
    );

    const form = document.getElementById('login-password-form');
    if (form) {
        form.style.display = passwordConfigured ? '' : 'none';
    }
    const logoutButton = document.getElementById('login-logout-button');
    if (logoutButton) {
        logoutButton.style.display = sessionAuthenticated ? '' : 'none';
    }
    setText('login-form-status', sessionAuthenticated
        ? '当前密码会话已生效；退出后需要重新输入密码。'
        : '密码只用于换取临时会话，不会写入 SoonLink 配置文件。');

    const adminLink = document.getElementById('login-admin-link');
    if (adminLink) {
        adminLink.style.display = adminAccessAllowed ? '' : 'none';
    }

    const caps = Array.isArray(auth.capabilities) ? auth.capabilities : [];
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

async function submitAdminPassword() {
    const input = document.getElementById('login-password-input');
    const password = input ? input.value : '';
    setText('login-form-status', '正在验证管理员密码...');
    try {
        const response = await fetch('/api/session/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ password })
        });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok || !payload.success) {
            throw new Error(payload.error || '管理员登录失败');
        }
        if (input) {
            input.value = '';
        }
        setText('login-form-status', '管理员会话已建立。');
        await loadLoginContext();
    } catch (error) {
        console.error('管理员登录失败:', error);
        setText('login-form-status', error.message || '管理员登录失败');
    }
}

async function logoutAdminSession() {
    setText('login-form-status', '正在退出管理员会话...');
    try {
        await fetch('/api/session/logout', { method: 'POST' });
        setText('login-form-status', '管理员会话已退出。');
        await loadLoginContext();
    } catch (error) {
        console.error('管理员退出失败:', error);
        setText('login-form-status', '退出失败，请稍后重试。');
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
