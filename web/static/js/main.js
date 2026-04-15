const APP_STATE = {
    accessContext: {
        isLocalAdmin: false,
        accessMode: 'remote',
        themeVariant: 'remote',
    },
    productContext: {
        runtimeLabel: 'SoonLink',
        productName: 'SoonLink',
        capabilities: {
            passiveDiscovery: true,
            activeDiscovery: true,
            mdnsDiscovery: false,
            peerTransfer: false,
            relay: true,
            whitelist: false,
            favorites: false,
            advancedSecurity: false,
        },
    },
    activePageId: 'devices-page',
    pendingPageFromUrl: null,
    pendingDeviceFromUrl: null,
    pendingPathFromUrl: null,
    navCollapsed: false,
    navCompact: false,
    lastScrollY: 0,
    themePreference: 'auto',
    themeTimer: null,
    taskTimer: null,
    allDevices: [],
    connectorCatalog: [],
    connectorBindings: [],
    allTasks: [],
    allRelayJobs: [],
    relaySelectedIds: [],
    relayPreview: null,
    allFiles: [],
    fileSortBy: 'name',
    fileSortOrder: 'asc',
    lastValidPath: '/',
    favorites: [],
    favoritesMode: 'cache',
    navDockSide: 'left',
    navDesktop: false,
    relayUiTimer: null,
    transferSource: null,
    transferPreview: null,
    adminSystemSummary: null,
    manualDeviceEditingId: '',
    fileListMeta: {
        loaded: 0,
        total: 0,
        truncated: false,
    },
};

const THEME_PREF_KEY = 'soonlink_theme_preference';
const NAV_DOCK_KEY = 'soonlink_nav_dock_side';
const FAVORITES_KEY = 'soonlink_path_favorites';
const DEFAULT_CHUNK_SIZE = 2 * 1024 * 1024;
const DOUBLE_ACTIVATE_WINDOW_MS = 420;

const PAGE_ID_MAP = {
    'devices': 'devices-page',
    'files': 'files-page',
    'transfers': 'transfers-page',
    'settings': 'settings-page',
    'admin': 'admin-page',
};

const PAGE_ID_REVERSE_MAP = {
    'devices-page': 'devices',
    'files-page': 'files',
    'transfers-page': 'transfers',
    'settings-page': 'settings',
    'admin-page': 'admin',
};

function setIconOnTarget(target, classNames) {
    if (!target) {
        return null;
    }
    if (window.SoonLinkIcons && typeof window.SoonLinkIcons.setIcon === 'function') {
        return window.SoonLinkIcons.setIcon(target, classNames);
    }
    const host = (target.matches && (target.matches('svg.sl-icon') || target.matches('i.bi')))
        ? target
        : target.querySelector?.('svg.sl-icon, i.bi');
    if (host && host.classList && host.classList.contains('bi')) {
        host.className = `bi ${classNames}`;
        return host;
    }
    return host;
}

function getThemeButtonMeta(preference, appliedMode) {
    if (preference === 'light') {
        return {
            icon: 'bi-sun',
            label: '',
        };
    }
    if (preference === 'dark') {
        return {
            icon: 'bi-moon-stars',
            label: '',
        };
    }
    return {
        icon: 'bi-circle-half',
        label: ``,
    };
}

function getSortButtonMeta(order) {
    return order === 'asc'
        ? { icon: 'bi-sort-up', label: '升序' }
        : { icon: 'bi-sort-down', label: '降序' };
}

function getUrlParams() {
    const params = new URLSearchParams(window.location.search);
    return {
        page: params.get('page'),
        device: params.get('device'),
        path: params.get('path'),
    };
}

function updateUrlParams(updates = {}) {
    const params = new URLSearchParams(window.location.search);
    if (updates.page !== undefined) {
        if (updates.page) {
            params.set('page', updates.page);
        } else {
            params.delete('page');
        }
    }
    if (updates.device !== undefined) {
        if (updates.device) {
            params.set('device', updates.device);
        } else {
            params.delete('device');
        }
    }
    if (updates.path !== undefined) {
        if (updates.path) {
            params.set('path', updates.path);
        } else {
            params.delete('path');
        }
    }
    const queryString = params.toString();
    const newUrl = queryString ? `${window.location.pathname}?${queryString}` : window.location.pathname;
    history.replaceState(null, '', newUrl);
}

function parseInitialUrlState() {
    const params = getUrlParams();
    if (params.page && PAGE_ID_MAP[params.page]) {
        APP_STATE.pendingPageFromUrl = PAGE_ID_MAP[params.page];
    }
    if (params.device) {
        APP_STATE.pendingDeviceFromUrl = params.device;
    }
    if (params.path) {
        APP_STATE.pendingPathFromUrl = decodeURIComponent(params.path);
    }
}

function defaultProductContext() {
    return {
        runtimeLabel: 'SoonLink',
        productName: 'SoonLink',
        capabilities: {
            passiveDiscovery: true,
            activeDiscovery: true,
            mdnsDiscovery: false,
            peerTransfer: false,
            relay: true,
            whitelist: false,
            favorites: false,
            advancedSecurity: false,
        },
    };
}

function normalizeProductContext(product) {
    const defaults = defaultProductContext();
    const capabilities = {
        ...defaults.capabilities,
        ...(product && product.capabilities ? product.capabilities : {}),
    };

    return {
        runtimeLabel: product?.runtimeLabel || product?.displayName || product?.productName || defaults.runtimeLabel,
        productName: product?.productName || product?.displayName || defaults.productName,
        capabilities,
    };
}

function hasCapability(name) {
    return !!APP_STATE.productContext?.capabilities?.[name];
}

function defaultConnectorCatalog() {
    return [
        {
            id: 'local-fs',
            displayName: 'Local FileSystem',
            category: 'local',
            supportsListDir: true,
            supportsReadRange: true,
            supportsCreateDir: true,
            supportsChunkUpload: true,
        },
        {
            id: 'soonlink-http',
            displayName: 'SoonLink Node HTTP',
            category: 'soonlink',
            supportsListDir: true,
            supportsReadRange: true,
            supportsCreateDir: true,
            supportsChunkUpload: true,
        },
    ];
}

function guessConnectorType(device) {
    const explicit = String(device?.connectorType || '').trim();
    if (explicit) {
        return explicit;
    }
    if (device?.id === 'local' || device?.type === 'local' || device?.deviceType === 'local') {
        return 'local-fs';
    }
    if (device?.ip && Number(device?.port || 0) > 0) {
        return 'soonlink-http';
    }
    return 'manual';
}

function getConnectorDescriptor(connectorType) {
    const normalized = String(connectorType || '').trim() || 'manual';
    const live = APP_STATE.connectorCatalog.find((item) => item.id === normalized);
    if (live) {
        return live;
    }
    return defaultConnectorCatalog().find((item) => item.id === normalized) || null;
}

function normalizeEndpointSchemeValue(raw, connectorType = '') {
    const normalized = String(raw || '').trim().toLowerCase();
    if (normalized === 'tls' || normalized === 'ssl') {
        return 'https';
    }
    if (normalized) {
        return normalized;
    }
    if (connectorType === 'local-fs') {
        return 'local';
    }
    if (connectorType === 'soonlink-http') {
        return 'http';
    }
    return '';
}

function normalizeEndpointBasePathValue(raw) {
    let out = String(raw || '').trim();
    if (!out || out === '/') {
        return '';
    }
    if (!out.startsWith('/')) {
        out = `/${out}`;
    }
    out = out.replace(/\/{2,}/g, '/');
    if (out.length > 1 && out.endsWith('/')) {
        out = out.slice(0, -1);
    }
    return out;
}

function buildEndpointOrigin(scheme, host, port, basePath) {
    if (scheme === 'local') {
        return 'local://';
    }
    if (!host) {
        return '';
    }
    const portPart = port > 0 ? `:${port}` : '';
    const suffix = basePath || '';
    if (scheme) {
        return `${scheme}://${host}${portPart}${suffix}`;
    }
    return `${host}${portPart}${suffix}`;
}

function buildEndpointInfo(source = {}, connectorType = guessConnectorType(source)) {
    const endpoint = source?.endpoint || {};
    const host = String(endpoint.host ?? source?.ip ?? '').trim();
    const port = Number(endpoint.port ?? source?.port ?? 0);
    const basePath = normalizeEndpointBasePathValue(endpoint.basePath ?? source?.endpointBasePath ?? '');
    const scheme = normalizeEndpointSchemeValue(endpoint.scheme ?? source?.endpointScheme ?? '', connectorType);
    const origin = String(endpoint.origin || '').trim() || buildEndpointOrigin(scheme, host, port, basePath);
    return {
        scheme,
        host,
        port,
        basePath,
        origin,
    };
}

function synthesizeConnectorBindings(devices = []) {
    return (Array.isArray(devices) ? devices : []).map((device) => {
        const connectorType = guessConnectorType(device);
        const connector = getConnectorDescriptor(connectorType);
        const endpoint = buildEndpointInfo(device, connectorType);
        return {
            id: device.id,
            name: device.name,
            deviceType: device.type || device.deviceType || '',
            connectorType,
            endpointScheme: endpoint.scheme,
            endpointBasePath: endpoint.basePath,
            ip: device.ip || '',
            port: Number(device.port || 0),
            online: !!device.online,
            driverAvailable: connectorType !== 'manual' && !!connector,
            connector,
            endpoint,
        };
    });
}

function applyConnectorSnapshot(snapshot, devices = APP_STATE.allDevices) {
    APP_STATE.connectorCatalog = Array.isArray(snapshot?.connectors) && snapshot.connectors.length > 0
        ? snapshot.connectors
        : defaultConnectorCatalog();
    APP_STATE.connectorBindings = Array.isArray(snapshot?.devices) && snapshot.devices.length > 0
        ? snapshot.devices
        : synthesizeConnectorBindings(devices);
}

function getConnectorBinding(deviceId) {
    const device = APP_STATE.allDevices.find((item) => item.id === deviceId);
    const liveBinding = APP_STATE.connectorBindings.find((item) => item.id === deviceId);
    const connectorType = liveBinding?.connectorType || guessConnectorType(device);
    const connector = liveBinding?.connector || getConnectorDescriptor(connectorType);
    const endpoint = buildEndpointInfo(liveBinding || device || {}, connectorType);
    return {
        id: deviceId,
        name: liveBinding?.name || device?.name || deviceId || '',
        deviceType: liveBinding?.deviceType || device?.type || device?.deviceType || '',
        connectorType,
        endpointScheme: liveBinding?.endpointScheme || device?.endpointScheme || endpoint.scheme,
        endpointBasePath: liveBinding?.endpointBasePath || device?.endpointBasePath || endpoint.basePath,
        ip: liveBinding?.ip || device?.ip || '',
        port: Number(liveBinding?.port || device?.port || 0),
        online: liveBinding?.online ?? !!device?.online,
        driverAvailable: liveBinding?.driverAvailable ?? (connectorType !== 'manual' && !!connector),
        connector,
        endpoint,
    };
}

function getConnectorDisplayName(binding) {
    if (binding?.connector?.displayName) {
        return binding.connector.displayName;
    }
    switch (binding?.connectorType) {
        case 'local-fs':
            return 'Local FileSystem';
        case 'soonlink-http':
            return 'SoonLink HTTP';
        case 'manual':
            return 'Manual / 未声明';
        default:
            return binding?.connectorType || '未声明';
    }
}

function getConnectorShortName(binding) {
    switch (binding?.connectorType) {
        case 'local-fs':
            return 'Local FS';
        case 'soonlink-http':
            return 'SoonLink HTTP';
        case 'manual':
            return 'Manual';
        default:
            return getConnectorDisplayName(binding);
    }
}

function getEndpointDisplayText(binding) {
    const endpoint = binding?.endpoint || buildEndpointInfo(binding || {}, binding?.connectorType || '');
    if (endpoint?.origin) {
        return endpoint.origin;
    }
    if (binding?.connectorType === 'local-fs') {
        return 'local://';
    }
    const host = String(binding?.ip || '').trim();
    const port = Number(binding?.port || 0);
    if (!host) {
        return '未声明';
    }
    return port > 0 ? `${host}:${port}` : host;
}

function getConnectorDriverStateText(binding) {
    return binding?.driverAvailable === false ? '驱动未就绪' : '驱动就绪';
}

function getConnectorDriverStateClass(binding) {
    return binding?.driverAvailable === false ? 'is-missing' : 'is-ready';
}

function normalizeDeviceTrustState(rawState) {
    const normalized = String(rawState || '').trim().toLowerCase();
    if (normalized === 'trusted' || normalized === 'blocked') {
        return normalized;
    }
    return 'unknown';
}

function isTrustManagedDevice(device) {
    return !!device && device.id !== 'local' && (device.ip || Number(device.port || 0) > 0);
}

function isDeviceTrustedForRemoteActions(device) {
    if (!isTrustManagedDevice(device)) {
        return true;
    }
    return normalizeDeviceTrustState(device.trustState) === 'trusted';
}

function getDeviceTrustLabel(device) {
    switch (normalizeDeviceTrustState(device?.trustState)) {
        case 'trusted':
            return '已授信';
        case 'blocked':
            return '已拉黑';
        default:
            return '待授信';
    }
}

function getDeviceTrustClass(device) {
    switch (normalizeDeviceTrustState(device?.trustState)) {
        case 'trusted':
            return 'is-ready';
        case 'blocked':
            return 'is-missing';
        default:
            return 'is-warning';
    }
}

function getDeviceById(deviceId) {
    return APP_STATE.allDevices.find((item) => item.id === deviceId) || null;
}

function isRememberedDevice(device) {
    return device?.remembered !== false;
}

function getDeviceTrustGuardMessage(deviceId, actionLabel) {
    const device = getDeviceById(deviceId);
    if (!device || !isTrustManagedDevice(device)) {
        return '';
    }
    const trustState = normalizeDeviceTrustState(device.trustState);
    if (trustState === 'trusted') {
        return '';
    }
    const name = device.name || deviceId || '目标设备';
    if (trustState === 'blocked') {
        return `${name} 已拉黑，当前不能${actionLabel}`;
    }
    return `${name} 仍是待授信状态，请先授信或完成 PIN 配对后再${actionLabel}`;
}

async function updateDeviceTrustState(deviceId, state) {
    if (!APP_STATE.accessContext.isLocalAdmin) {
        showAlert('仅本机管理员可维护设备授信', 'warning');
        return false;
    }
    try {
        const response = await fetch(`/api/devices/${encodeURIComponent(deviceId)}/trust`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ state }),
        });
        const result = await response.json().catch(() => ({}));
        if (!response.ok || result.success === false) {
            showAlert(result.error || '设备授信状态更新失败', 'danger');
            return false;
        }
        showAlert(result.message || '设备授信状态已更新', 'success');
        await loadDevices();
        return true;
    } catch (error) {
        console.error('更新设备授信状态失败:', error);
        showAlert('更新设备授信状态失败', 'danger');
        return false;
    }
}

async function rememberDiscoveredDevice(deviceId) {
    if (!APP_STATE.accessContext.isLocalAdmin) {
        showAlert('仅本机管理员可记住已发现设备', 'warning');
        return false;
    }
    try {
        const response = await fetch(`/api/devices/${encodeURIComponent(deviceId)}/remember`, {
            method: 'POST',
        });
        const result = await response.json().catch(() => ({}));
        if (!response.ok || result.success === false) {
            showAlert(result.error || '记住设备失败', 'danger');
            return false;
        }
        showAlert(result.message || '设备已记住', 'success');
        await loadDevices();
        return true;
    } catch (error) {
        console.error('记住设备失败:', error);
        showAlert('记住设备失败', 'danger');
        return false;
    }
}

async function startDevicePinPairing(deviceId) {
    if (!APP_STATE.accessContext.isLocalAdmin) {
        showAlert('仅本机管理员可执行 PIN 配对', 'warning');
        return;
    }
    try {
        const response = await fetch(`/api/devices/${encodeURIComponent(deviceId)}/pairing/pin`, {
            method: 'POST',
        });
        const result = await response.json().catch(() => ({}));
        if (!response.ok || result.success === false) {
            showAlert(result.error || 'PIN 配对创建失败', 'danger');
            return;
        }
        const pairing = result.pairing || {};
        const input = window.prompt(`设备 ${deviceId} 的 PIN：${pairing.pin || '------'}\n请在确认后输入该 PIN 完成授信。`, pairing.pin || '');
        if (!input) {
            showAlert('PIN 配对已生成，未执行确认', 'info');
            return;
        }
        const confirmResponse = await fetch(`/api/devices/${encodeURIComponent(deviceId)}/pairing/confirm`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ pin: input.trim() }),
        });
        const confirmResult = await confirmResponse.json().catch(() => ({}));
        if (!confirmResponse.ok || confirmResult.success === false) {
            showAlert(confirmResult.error || 'PIN 配对确认失败', 'danger');
            return;
        }
        showAlert(confirmResult.message || 'PIN 配对成功，设备已授信', 'success');
        await loadDevices();
    } catch (error) {
        console.error('设备 PIN 配对失败:', error);
        showAlert('设备 PIN 配对失败', 'danger');
    }
}

function getCurrentFileWorkspace() {
    const deviceId = document.getElementById('device-selector')?.value || '';
    const currentPath = normalizePath(document.getElementById('current-path')?.value || '/');
    const device = APP_STATE.allDevices.find((item) => item.id === deviceId);
    return {
        deviceId,
        currentPath,
        deviceName: device?.name || deviceId || '未选择设备',
    };
}

function renderRelayRestoreHint() {
    const hint = document.getElementById('relay-restore-hint');
    if (!hint) {
        return;
    }
    const workspace = getCurrentFileWorkspace();
    hint.textContent = workspace.deviceId
        ? `回流默认写回 ${workspace.deviceName} 的 ${workspace.currentPath}`
        : '回流默认复用当前文件页的设备与目录';
}

function renderTransferTargetSummary() {
    const hint = document.getElementById('transfer-target-summary');
    const transferBtn = document.getElementById('transfer-btn');
    const sourceDevice = document.getElementById('source-device')?.value || '';
    const targetDevice = document.getElementById('transfer-target-device')?.value || '';
    const targetPath = normalizePath(document.getElementById('transfer-target-path')?.value || '/');
    const sourcePath = document.getElementById('source-path')?.value || '';
    const sourceDeviceNode = APP_STATE.allDevices.find((item) => item.id === sourceDevice);
    const device = APP_STATE.allDevices.find((item) => item.id === targetDevice);
    const sourceBinding = getConnectorBinding(sourceDevice);
    const targetBinding = getConnectorBinding(targetDevice);
    const targetName = device?.name || targetDevice || '未选择设备';
    const sourceName = sourceDeviceNode?.name || sourceDevice || '源设备';
    const sourceLabel = basenamePath(sourcePath || '/');
    const sourceIsDir = !!APP_STATE.transferSource?.isDir;
    const sourceConnectorNode = document.getElementById('transfer-info-source-connector');
    const targetConnectorNode = document.getElementById('transfer-info-target-connector');
    const sourceConnectorText = sourceDevice
        ? `${getConnectorDisplayName(sourceBinding)} · ${getConnectorDriverStateText(sourceBinding)}`
        : '-';
    const targetConnectorText = targetDevice
        ? `${getConnectorDisplayName(targetBinding)} · ${getConnectorDriverStateText(targetBinding)}`
        : '-';
    const sourceConnectorBadge = sourceDevice ? getConnectorShortName(sourceBinding) : '未选择';
    const targetConnectorBadge = targetDevice ? getConnectorShortName(targetBinding) : '未选择';
    const sourceConnectorState = sourceDevice ? getConnectorDriverStateText(sourceBinding) : '选择设备';
    const targetConnectorState = targetDevice ? getConnectorDriverStateText(targetBinding) : '选择设备';
    const sourceConnectorClass = sourceDevice ? getConnectorDriverStateClass(sourceBinding) : '';
    const targetConnectorClass = targetDevice ? getConnectorDriverStateClass(targetBinding) : '';
    const sourceTrustMessage = sourceDevice ? getDeviceTrustGuardMessage(sourceDevice, '发起传输') : '';
    const targetTrustMessage = targetDevice ? getDeviceTrustGuardMessage(targetDevice, '接收传输') : '';
    const sourceBlocked = (sourceDevice && sourceBinding.driverAvailable === false) || !!sourceTrustMessage;
    const targetBlocked = (targetDevice && targetBinding.driverAvailable === false) || !!targetTrustMessage;

    if (sourceConnectorNode) {
        sourceConnectorNode.textContent = sourceTrustMessage || sourceConnectorText;
        sourceConnectorNode.title = sourceTrustMessage || sourceConnectorText;
    }
    if (targetConnectorNode) {
        targetConnectorNode.textContent = targetTrustMessage || targetConnectorText;
        targetConnectorNode.title = targetTrustMessage || targetConnectorText;
    }

    if (hint) {
        if (sourceBlocked) {
            hint.textContent = sourceTrustMessage || `源设备 ${sourceName} 的连接器 ${getConnectorShortName(sourceBinding)} 当前未就绪，本节点暂不能发起该类传输。`;
        } else if (targetBlocked) {
            hint.textContent = targetTrustMessage || `目标设备 ${targetName} 的连接器 ${getConnectorShortName(targetBinding)} 当前未就绪，本节点暂不能写入该设备。`;
        } else {
            hint.textContent = sourceIsDir
                ? `目录任务会保留 ${sourceLabel} 的目录树结构，并写入 ${targetName} 的 ${targetPath}`
                : `将把 ${sourceLabel} 写入 ${targetName} 的 ${targetPath}`;
        }
    }

    const accordionSummary = document.getElementById('transfer-accordion-summary');
    if (accordionSummary) {
        accordionSummary.innerHTML = `
            <span class="transfer-summary-route">
                <span class="transfer-summary-item">
                    <i class="bi bi-devices"></i>
                    <span class="transfer-summary-text">
                        <span class="transfer-summary-label">源</span>
                        <span class="transfer-summary-title">${escapeHtml(sourceName)}</span>
                        <span class="transfer-summary-path">${escapeHtml(sourcePath || sourceLabel || '/')}</span>
                        <span class="transfer-summary-meta">
                            <span class="connector-pill ${escapeAttr(sourceConnectorClass)}">${escapeHtml(sourceConnectorBadge)}</span>
                            <span class="connector-inline-state">${escapeHtml(sourceConnectorState)}</span>
                        </span>
                    </span>
                </span>
                <i class="bi bi-arrow-right transfer-summary-arrow"></i>
                <span class="transfer-summary-item">
                    <i class="bi bi-hdd"></i>
                    <span class="transfer-summary-text">
                        <span class="transfer-summary-label">目标</span>
                        <span class="transfer-summary-title">${escapeHtml(targetName)}</span>
                        <span class="transfer-summary-path">${escapeHtml(targetPath)}</span>
                        <span class="transfer-summary-meta">
                            <span class="connector-pill ${escapeAttr(targetConnectorClass)}">${escapeHtml(targetConnectorBadge)}</span>
                            <span class="connector-inline-state">${escapeHtml(targetConnectorState)}</span>
                        </span>
                    </span>
                </span>
            </span>
        `;
        if (window.SoonLinkIcons && typeof window.SoonLinkIcons.upgrade === 'function') {
            window.SoonLinkIcons.upgrade(accordionSummary);
        }
    }

    if (transferBtn) {
        const blocked = sourceBlocked || targetBlocked || !sourceDevice || !targetDevice || !sourcePath;
        transferBtn.disabled = blocked;
        transferBtn.title = sourceBlocked || targetBlocked
            ? (sourceTrustMessage || targetTrustMessage || '当前所选设备连接器未就绪')
            : '';
    }
}

function updateTransferDownloadAction() {
    const downloadBtn = document.getElementById('transfer-download-btn');
    const note = document.getElementById('transfer-download-note');
    if (!downloadBtn) {
        return;
    }
    const source = APP_STATE.transferSource;
    const isDir = !!source?.isDir;
    downloadBtn.disabled = !source?.deviceId || !source?.path || isDir;
    downloadBtn.innerHTML = isDir
        ? '<i class="bi bi-download me-1"></i>目录暂不直下'
        : '<i class="bi bi-download me-1"></i>下载原文件';
    if (note) {
        note.textContent = isDir
            ? '目录暂不提供浏览器直下，请直接创建传输任务并保留完整目录树结构。'
            : `可直接下载 ${basenamePath(source?.path || '/') || '当前文件'}，也可以展开后分发到其他设备目录。`;
    }
    if (window.SoonLinkIcons && typeof window.SoonLinkIcons.upgrade === 'function') {
        window.SoonLinkIcons.upgrade(downloadBtn);
    }
}

function triggerTransferSourceDownload() {
    const source = APP_STATE.transferSource;
    if (!source?.deviceId || !source?.path) {
        showAlert('当前没有可下载的源项', 'warning');
        return;
    }
    if (source.isDir) {
        showAlert('目录暂不支持直接下载，请使用传输任务', 'info');
        return;
    }
    window.open(`/api/fs/download?device=${encodeURIComponent(source.deviceId)}&path=${encodeURIComponent(source.path)}`);
}

function hideTransferPreviewSlots() {
    const emptyNode = document.getElementById('transfer-preview-empty');
    const textNode = document.getElementById('transfer-preview-text');
    const imageNode = document.getElementById('transfer-preview-image');
    const videoNode = document.getElementById('transfer-preview-video');
    const audioNode = document.getElementById('transfer-preview-audio');
    const frameNode = document.getElementById('transfer-preview-frame');

    if (emptyNode) {
        emptyNode.hidden = true;
    }
    if (textNode) {
        textNode.hidden = true;
        textNode.textContent = '';
    }
    if (imageNode) {
        imageNode.hidden = true;
        imageNode.removeAttribute('src');
    }
    if (videoNode) {
        videoNode.pause?.();
        videoNode.hidden = true;
        videoNode.removeAttribute('src');
        videoNode.load?.();
    }
    if (audioNode) {
        audioNode.pause?.();
        audioNode.hidden = true;
        audioNode.removeAttribute('src');
        audioNode.load?.();
    }
    if (frameNode) {
        frameNode.hidden = true;
        frameNode.removeAttribute('src');
    }
}

function resetTransferPreview() {
    APP_STATE.transferPreview = null;
    const wrap = document.getElementById('transfer-preview-wrap');
    const metaNode = document.getElementById('transfer-preview-meta');
    const openBtn = document.getElementById('transfer-preview-open-btn');
    if (wrap) {
        wrap.hidden = false;
    }
    hideTransferPreviewSlots();
    if (metaNode) {
        metaNode.textContent = '选择单个文件后显示真实预览内容';
    }
    const emptyNode = document.getElementById('transfer-preview-empty');
    if (emptyNode) {
        emptyNode.hidden = false;
        emptyNode.textContent = '选择单个文件后可在这里查看预览内容。';
    }
    if (openBtn) {
        openBtn.hidden = true;
    }
}

function showTransferPreviewMessage(message, meta = '') {
    APP_STATE.transferPreview = null;
    const wrap = document.getElementById('transfer-preview-wrap');
    const emptyNode = document.getElementById('transfer-preview-empty');
    const metaNode = document.getElementById('transfer-preview-meta');
    const openBtn = document.getElementById('transfer-preview-open-btn');
    if (wrap) {
        wrap.hidden = false;
    }
    hideTransferPreviewSlots();
    if (emptyNode) {
        emptyNode.hidden = false;
        emptyNode.textContent = message;
    }
    if (metaNode) {
        metaNode.textContent = meta || '当前源项暂无可展示的预览内容';
    }
    if (openBtn) {
        openBtn.hidden = true;
    }
}

function buildTransferPreviewMeta(preview) {
    const parts = [];
    parts.push(humanizePreviewKind(preview.kind));
    if (preview.language) {
        parts.push(String(preview.language));
    }
    if (preview.encoding) {
        parts.push(String(preview.encoding).toUpperCase());
    }
    if (Number(preview.size || 0) > 0) {
        parts.push(formatSize(Number(preview.size || 0)));
    }
    if (Number(preview.lineCount || 0) > 0) {
        parts.push(`${Number(preview.lineCount || 0)} 行`);
    }
    if (preview.truncated) {
        parts.push('已截断');
    }
    return parts.filter(Boolean).join(' · ');
}

function renderTransferPreview(preview) {
    APP_STATE.transferPreview = preview || null;
    const wrap = document.getElementById('transfer-preview-wrap');
    const metaNode = document.getElementById('transfer-preview-meta');
    const openBtn = document.getElementById('transfer-preview-open-btn');
    const emptyNode = document.getElementById('transfer-preview-empty');
    const textNode = document.getElementById('transfer-preview-text');
    const imageNode = document.getElementById('transfer-preview-image');
    const videoNode = document.getElementById('transfer-preview-video');
    const audioNode = document.getElementById('transfer-preview-audio');
    const frameNode = document.getElementById('transfer-preview-frame');
    const previewUrl = preview?.previewUrl || '';

    if (wrap) {
        wrap.hidden = false;
    }
    hideTransferPreviewSlots();

    if (metaNode) {
        metaNode.textContent = buildTransferPreviewMeta(preview);
    }
    if (openBtn) {
        openBtn.hidden = !previewUrl;
    }

    switch (preview?.kind) {
        case 'text':
        case 'code':
            if (textNode) {
                textNode.hidden = false;
                textNode.textContent = preview.content || '';
            }
            break;
        case 'image':
            if (imageNode) {
                imageNode.hidden = false;
                imageNode.src = previewUrl;
            }
            break;
        case 'video':
            if (videoNode) {
                videoNode.hidden = false;
                videoNode.src = previewUrl;
                videoNode.load?.();
            }
            break;
        case 'audio':
            if (audioNode) {
                audioNode.hidden = false;
                audioNode.src = previewUrl;
                audioNode.load?.();
            }
            break;
        case 'pdf':
            if (frameNode) {
                frameNode.hidden = false;
                frameNode.src = previewUrl;
            }
            break;
        default:
            if (emptyNode) {
                emptyNode.hidden = false;
                emptyNode.textContent = preview?.message || '当前类型暂不支持预览';
            }
            break;
    }
}

async function loadTransferPreview(deviceId, filePath, isDir = false) {
    if (!deviceId || !filePath) {
        resetTransferPreview();
        return;
    }
    if (isDir) {
        showTransferPreviewMessage('目录暂不提供内容预览', '目录任务会保留完整目录树结构');
        return;
    }

    showTransferPreviewMessage('正在加载预览...', '读取真实文件内容中');
    try {
        const response = await fetch(buildFsApiUrl('/api/fs/preview', deviceId, filePath));
        const data = await response.json();
        if (!response.ok || data.success === false) {
            throw new Error(data.error || data.message || '预览加载失败');
        }
        renderTransferPreview(data);
    } catch (error) {
        console.error('加载文件预览失败:', error);
        showTransferPreviewMessage(error.message || '预览加载失败', '可以继续创建传输任务或直接下载原文件');
    }
}

function resetTransferModalState() {
    APP_STATE.transferSource = null;
    document.getElementById('source-path').value = '';
    document.getElementById('transfer-info-name').textContent = '-';
    document.getElementById('transfer-info-path').textContent = '-';
    document.getElementById('transfer-info-size').textContent = '-';
    document.getElementById('transfer-info-type').textContent = '-';
    document.getElementById('transfer-info-entries').textContent = '-';
    document.getElementById('transfer-info-modified').textContent = '-';
    document.getElementById('transfer-info-source-connector').textContent = '-';
    document.getElementById('transfer-info-target-connector').textContent = '-';
    resetTransferPreview();
    updateTransferDownloadAction();
    renderTransferTargetSummary();
}

function initHeaderMotion() {
    const header = document.getElementById('main-app-header');
    if (!header) {
        return;
    }

    let ticking = false;
    const applyState = () => {
        header.classList.toggle('is-condensed', (window.scrollY || 0) > 18);
    };

    applyState();
    window.addEventListener('scroll', () => {
        if (ticking) {
            return;
        }
        ticking = true;
        window.requestAnimationFrame(() => {
            applyState();
            ticking = false;
        });
    }, { passive: true });
}

document.addEventListener('DOMContentLoaded', async function() {
    parseInitialUrlState();
    loadFavorites();
    initHeaderMotion();
    initNavigation();
    initFloatNav();
    initRefreshAction();
    initFileExplorer();
    initUploadModal();
    initTransferModal();
    initSettingsForm();
    initAdminPanel();
    initThemeAutomation();
    initEnhancedToolbar();
    initRelayPanel();

    await loadSessionContext();
    applyAccessContext();
    await syncFavoritesFromServer();
    refreshFavoritesUI();
    renderFileWorkspaceMeta();
    initFavoritesMenu();
    initManualDeviceManager();

    await loadDevices();

    if (APP_STATE.pendingPageFromUrl) {
        const targetPage = APP_STATE.pendingPageFromUrl;
        if (targetPage === 'admin-page' && !APP_STATE.accessContext.isLocalAdmin) {
            showPage('devices-page');
        } else {
            showPage(targetPage);
        }
        APP_STATE.pendingPageFromUrl = null;
    } else {
        showPage(APP_STATE.activePageId);
    }

    const discoverBtn = document.getElementById('discover-btn');
    if (discoverBtn) {
        discoverBtn.addEventListener('click', loadDevices);
    }

    const openTransferModalBtn = document.getElementById('open-transfer-modal');
    if (openTransferModalBtn) {
        openTransferModalBtn.addEventListener('click', function() {
            resetTransferModalState();
            new bootstrap.Modal(document.getElementById('transfer-modal')).show();
        });
    }

    APP_STATE.taskTimer = setInterval(() => {
        if (APP_STATE.activePageId === 'transfers-page') {
            loadTasks();
            if (hasCapability('relay')) {
                loadRelayJobs();
            }
        }
    }, 5000);
});

async function loadSessionContext() {
    try {
        const response = await fetch('/api/session/context');
        if (!response.ok) {
            throw new Error('session context not available');
        }
        const data = await response.json();
        APP_STATE.accessContext = data || {};
        APP_STATE.productContext = normalizeProductContext(data?.product);
    } catch (_error) {
        APP_STATE.accessContext = {
            isLocalAdmin: false,
            accessMode: 'remote',
            themeVariant: 'remote',
        };
        APP_STATE.productContext = defaultProductContext();
    }
}

function applyAccessContext() {
    const body = document.body;
    const modePill = document.getElementById('mode-pill');
    const runtimePill = document.getElementById('runtime-pill');
    const isAdmin = !!APP_STATE.accessContext.isLocalAdmin;

    body.dataset.roleVariant = isAdmin ? 'admin' : 'remote';
    body.dataset.productLine = 'soonlink';
    modePill.textContent = isAdmin ? '本机管理模式' : '普通访问';
    if (runtimePill) {
        runtimePill.textContent = APP_STATE.productContext.runtimeLabel || APP_STATE.productContext.productName || 'SoonLink';
    }

    document.querySelectorAll('.admin-only').forEach((node) => {
        node.style.display = isAdmin ? '' : 'none';
    });

    applyCapabilityContext();

    if (!isAdmin && APP_STATE.activePageId === 'admin-page') {
        showPage('devices-page');
    }

    if (isAdmin) {
        loadAdminConfig();
        loadAdminSystemSummary();
        loadAdminLogs();
    }

    updateManualDeviceFormState();
}

function applyCapabilityContext() {
    document.querySelectorAll('[data-capability]').forEach((node) => {
        const capability = node.dataset.capability;
        const requiresAdmin = node.classList.contains('admin-only');
        const canShow = hasCapability(capability) && (!requiresAdmin || !!APP_STATE.accessContext.isLocalAdmin);
        node.style.display = canShow ? '' : 'none';
    });

    const activeDiscoveryDisabledPanel = document.getElementById('admin-active-discovery-disabled-panel');
    if (activeDiscoveryDisabledPanel) {
        activeDiscoveryDisabledPanel.style.display = hasCapability('activeDiscovery') ? 'none' : '';
    }

    const discoverBtn = document.getElementById('discover-btn');
    if (discoverBtn) {
        discoverBtn.innerHTML = hasCapability('activeDiscovery')
            ? '<i class="bi bi-broadcast"></i> 刷新发现'
            : '<i class="bi bi-arrow-repeat"></i> 刷新设备';
    }

    if (!hasCapability('favorites')) {
        APP_STATE.favorites = [];
        APP_STATE.favoritesMode = 'disabled';
    }

    if (!hasCapability('relay')) {
        APP_STATE.allRelayJobs = [];
        APP_STATE.relaySelectedIds = [];
        updateRelayStats([]);
    }

    if (!hasCapability('peerTransfer')) {
        const enableEncryption = document.getElementById('enable-encryption');
        if (enableEncryption) {
            enableEncryption.checked = false;
        }
    }

    renderRelayRestoreHint();
    refreshAdminDiscoveryHint();
}

function initThemeAutomation() {
    const persisted = (window.localStorage && localStorage.getItem(THEME_PREF_KEY)) || 'auto';
    if (persisted === 'light' || persisted === 'dark' || persisted === 'auto') {
        APP_STATE.themePreference = persisted;
    } else {
        APP_STATE.themePreference = 'auto';
    }

    const toggleBtn = document.getElementById('theme-toggle-btn');
    if (toggleBtn) {
        toggleBtn.addEventListener('click', cycleThemePreference);
    }

    applyTimeTheme();

    if (APP_STATE.themeTimer) {
        clearInterval(APP_STATE.themeTimer);
    }

    APP_STATE.themeTimer = setInterval(applyTimeTheme, 60000);

    document.addEventListener('visibilitychange', function() {
        if (!document.hidden) {
            applyTimeTheme();
        }
    });
}

function applyTimeTheme() {
    let timeMode = APP_STATE.themePreference;
    if (timeMode === 'auto') {
        const now = new Date();
        const hour = now.getHours();
        timeMode = hour >= 7 && hour < 19 ? 'light' : 'dark';
    }
    document.body.dataset.timeMode = timeMode;
    document.body.dataset.themePreference = APP_STATE.themePreference;

    const themeToggleLabel = document.getElementById('theme-toggle-label');
    const themeToggleBtn = document.getElementById('theme-toggle-btn');
    const themeMeta = getThemeButtonMeta(APP_STATE.themePreference, timeMode);
    if (themeToggleLabel) {
        themeToggleLabel.textContent = themeMeta.label;
    }
    if (themeToggleBtn) {
        setIconOnTarget(themeToggleBtn, themeMeta.icon);
        //themeToggleBtn.title = `切换主题模式（当前${themeMeta.label}）`;
    }
}

function cycleThemePreference() {
    const order = ['auto', 'light', 'dark'];
    const currentIndex = order.indexOf(APP_STATE.themePreference);
    APP_STATE.themePreference = order[(currentIndex + 1) % order.length];
    if (window.localStorage) {
        localStorage.setItem(THEME_PREF_KEY, APP_STATE.themePreference);
    }
    applyTimeTheme();
}

function getThemePreferenceLabel(pref) {
    switch (pref) {
        case 'light':
            return '浅色';
        case 'dark':
            return '深色';
        default:
            return '自动';
    }
}

function updateSortOrderButton() {
    const sortOrderBtn = document.getElementById('file-sort-order-btn');
    if (!sortOrderBtn) {
        return;
    }
    const isAsc = APP_STATE.fileSortOrder === 'asc';
    const meta = getSortButtonMeta(APP_STATE.fileSortOrder);
    sortOrderBtn.dataset.order = APP_STATE.fileSortOrder;
    sortOrderBtn.innerHTML = `<i class="bi ${meta.icon}"></i>`;
    sortOrderBtn.title = isAsc ? '当前按升序排列' : '当前按降序排列';
    sortOrderBtn.setAttribute('aria-label', sortOrderBtn.title);
    if (window.SoonLinkIcons && typeof window.SoonLinkIcons.upgrade === 'function') {
        window.SoonLinkIcons.upgrade(sortOrderBtn);
    }
}

function basenamePath(path) {
    const normalized = normalizePath(path || '/');
    const parts = normalized.split('/').filter(Boolean);
    return parts[parts.length - 1] || '/';
}

function buildFsApiUrl(route, deviceId, path) {
    return `${route}?device=${encodeURIComponent(deviceId || '')}&path=${encodeURIComponent(path || '')}`;
}

function humanizePreviewKind(kind) {
    switch (kind) {
        case 'image':
            return '图片';
        case 'video':
            return '视频';
        case 'audio':
            return '音频';
        case 'pdf':
            return 'PDF';
        case 'code':
            return '代码';
        case 'text':
            return '文本';
        case 'directory':
            return '目录';
        default:
            return '预览';
    }
}

function bindDoubleActivate(node, onActivate) {
    if (!node) {
        return;
    }
    let armed = false;
    let timer = null;
    const clearArmed = () => {
        armed = false;
        node.classList.remove('is-armed');
        if (timer) {
            clearTimeout(timer);
            timer = null;
        }
    };

    node.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        if (armed) {
            clearArmed();
            onActivate();
            return;
        }
        armed = true;
        node.classList.add('is-armed');
        timer = setTimeout(clearArmed, DOUBLE_ACTIVATE_WINDOW_MS);
    });

    node.addEventListener('dblclick', (event) => {
        event.preventDefault();
        event.stopPropagation();
        clearArmed();
        onActivate();
    });
}

function initNavigation() {
    document.querySelectorAll('.float-nav-item[data-target]').forEach((item) => {
        item.addEventListener('click', function() {
            const targetId = this.dataset.target;
            if (targetId === 'admin-page' && !APP_STATE.accessContext.isLocalAdmin) {
                showAlert('仅本机访问可用管理员模块', 'warning');
                return;
            }
            showPage(targetId);
            showFilesSubmenu(false);
        });
    });
}

function showPage(pageId) {
    const target = document.getElementById(pageId);
    if (!target) {
        return;
    }

    document.querySelectorAll('.page-content').forEach((page) => {
        page.classList.remove('is-active');
    });
    target.classList.add('is-active');

    APP_STATE.activePageId = pageId;

    document.querySelectorAll('.float-nav-item').forEach((item) => {
        const active = item.dataset.target === pageId;
        item.classList.toggle('active', active);
    });

    const pageKey = PAGE_ID_REVERSE_MAP[pageId] || '';
    updateUrlParams({ page: pageKey || null });

    switch (pageId) {
        case 'devices-page':
            loadDevices();
            break;
        case 'files-page':
            refreshFavoritesUI();
            loadFiles();
            updateFilesPageUrl();
            break;
        case 'transfers-page':
            loadTasks();
            if (hasCapability('relay')) {
                loadRelayJobs();
            }
            if (APP_STATE.accessContext.isLocalAdmin && hasCapability('whitelist')) {
                loadWhitelistRules();
            }
            break;
        case 'admin-page':
            if (APP_STATE.accessContext.isLocalAdmin) {
                loadAdminConfig();
                loadAdminLogs();
            }
            break;
        default:
            break;
    }
}

function updateFilesPageUrl() {
    const selector = document.getElementById('device-selector');
    const pathInput = document.getElementById('current-path');
    const deviceId = selector?.value || '';
    const currentPath = normalizePath(pathInput?.value || '/');
    updateUrlParams({
        device: deviceId || null,
        path: (deviceId && currentPath !== '/') ? currentPath : null,
    });
}

function initRefreshAction() {
    const refreshBtn = document.getElementById('refresh-btn');
    if (!refreshBtn) {
        return;
    }

    refreshBtn.addEventListener('click', function() {
        switch (APP_STATE.activePageId) {
            case 'devices-page':
                loadDevices();
                break;
            case 'files-page':
                loadFiles();
                break;
            case 'transfers-page':
                loadTasks();
                if (hasCapability('relay')) {
                    loadRelayJobs();
                }
                if (APP_STATE.accessContext.isLocalAdmin && hasCapability('whitelist')) {
                    loadWhitelistRules();
                }
                break;
            case 'admin-page':
                loadAdminConfig();
                loadAdminSystemSummary();
                loadAdminLogs();
                break;
            default:
                break;
        }
    });
}

function initEnhancedToolbar() {
    const deviceSearch = document.getElementById('device-search-input');
    const deviceStatus = document.getElementById('device-status-filter');
    const taskSearch = document.getElementById('task-search-input');
    const taskStatus = document.getElementById('task-status-filter');

    if (deviceSearch) {
        deviceSearch.addEventListener('input', renderDeviceList);
    }
    if (deviceStatus) {
        deviceStatus.addEventListener('change', renderDeviceList);
    }
    if (taskSearch) {
        taskSearch.addEventListener('input', renderTaskList);
    }
    if (taskStatus) {
        taskStatus.addEventListener('change', renderTaskList);
    }
}

function initFloatNav() {
    const wrap = document.querySelector('.float-nav-wrap');
    const nav = document.getElementById('float-nav');
    const trigger = document.getElementById('float-nav-trigger');
    const dockToggleBtn = document.getElementById('nav-dock-toggle-btn');

    const storedDock = (window.localStorage && localStorage.getItem(NAV_DOCK_KEY)) || 'left';
    APP_STATE.navDockSide = storedDock === 'right' ? 'right' : 'left';

    if (trigger) {
        trigger.addEventListener('click', () => {
            if (!APP_STATE.navDesktop) {
                return;
            }
            setFloatNavCollapsed(!APP_STATE.navCollapsed);
        });
    }

    if (dockToggleBtn) {
        dockToggleBtn.addEventListener('click', () => {
            APP_STATE.navDockSide = APP_STATE.navDockSide === 'left' ? 'right' : 'left';
            if (window.localStorage) {
                localStorage.setItem(NAV_DOCK_KEY, APP_STATE.navDockSide);
            }
            applyNavDockSide();
        });
    }

    function detectMode() {
        APP_STATE.navDesktop = window.innerWidth >= 992;
        nav.classList.toggle('desktop-mode', APP_STATE.navDesktop);
        nav.classList.toggle('mobile-mode', !APP_STATE.navDesktop);
        if (APP_STATE.navDesktop) {
            APP_STATE.navCompact = false;
            nav.classList.remove('collapsed');
            nav.classList.remove('mobile-compact');
            nav.classList.add('expanded');
            nav.classList.toggle('desktop-collapsed', APP_STATE.navCollapsed);
        } else {
            nav.classList.remove('desktop-collapsed');
            nav.classList.remove('collapsed');
            nav.classList.add('expanded');
            setMobileNavCompact((window.scrollY || 0) > 42);
        }
        syncFloatNavLabels();
    }

    function applyNavDockSide() {
        if (!wrap) {
            return;
        }
        wrap.classList.toggle('dock-right', APP_STATE.navDockSide === 'right');
        if (dockToggleBtn) {
            const isRight = APP_STATE.navDockSide === 'right';
            dockToggleBtn.classList.toggle('is-right', isRight);
            const nextSide = isRight ? '左侧' : '右侧';
            const currentSide = isRight ? '贴右' : '贴左';
            dockToggleBtn.title = `导航当前${currentSide}，点击切到${nextSide}`;
            dockToggleBtn.setAttribute('aria-label', dockToggleBtn.title);
        }
    }

    applyNavDockSide();
    detectMode();

    window.addEventListener('resize', () => {
        detectMode();
    });

    APP_STATE.lastScrollY = window.scrollY || 0;

    window.addEventListener('scroll', () => {
        if (APP_STATE.navDesktop) {
            return;
        }
        const currentY = window.scrollY || 0;
        const delta = currentY - APP_STATE.lastScrollY;

        if (currentY > 42 && delta > 10) {
            setMobileNavCompact(true);
        } else if (currentY < 24 || delta < -8) {
            setMobileNavCompact(false);
        }

        APP_STATE.lastScrollY = currentY;
    }, { passive: true });

    if (nav) {
        nav.addEventListener('mouseenter', () => {
            if (APP_STATE.navCollapsed && !APP_STATE.navDesktop && window.innerWidth > 767) {
                setFloatNavCollapsed(false);
            }
        });
    }
}

function syncFloatNavLabels() {
    document.querySelectorAll('.float-nav-item[data-full-label]').forEach((item) => {
        const label = item.querySelector('.float-nav-label');
        if (!label) {
            return;
        }
        const fullLabel = item.dataset.fullLabel || label.textContent || '';
        const shortLabel = item.dataset.shortLabel || fullLabel;
        label.textContent = (!APP_STATE.navDesktop && APP_STATE.navCompact) ? shortLabel : fullLabel;
    });
}

function setMobileNavCompact(compact) {
    APP_STATE.navCompact = compact;
    const nav = document.getElementById('float-nav');
    if (!nav || APP_STATE.navDesktop) {
        return;
    }
    nav.classList.toggle('mobile-compact', compact);
    syncFloatNavLabels();
}

function setFloatNavCollapsed(collapsed) {
    APP_STATE.navCollapsed = collapsed;
    const nav = document.getElementById('float-nav');
    if (!nav) {
        return;
    }
    if (APP_STATE.navDesktop) {
        nav.classList.toggle('desktop-collapsed', collapsed);
        nav.classList.remove('collapsed');
    } else {
        setMobileNavCompact(collapsed);
        nav.classList.remove('collapsed');
    }
    nav.classList.toggle('expanded', !collapsed);
    if (collapsed) {
        showFilesSubmenu(false);
    }
}

async function loadDevices() {
    try {
        const [response, connectorResponse] = await Promise.all([
            fetch('/api/devices/'),
            fetch('/api/connectors').catch(() => null),
        ]);
        const devices = await response.json();
        APP_STATE.allDevices = Array.isArray(devices) ? devices : [];
        if (connectorResponse && connectorResponse.ok) {
            const connectorSnapshot = await connectorResponse.json();
            applyConnectorSnapshot(connectorSnapshot, APP_STATE.allDevices);
        } else {
            applyConnectorSnapshot(null, APP_STATE.allDevices);
        }
        updateDeviceSelectors(APP_STATE.allDevices);
        updateDeviceStats(APP_STATE.allDevices);
        refreshFavoritesUI();
        if (APP_STATE.activePageId === 'transfers-page' && APP_STATE.accessContext.isLocalAdmin) {
            loadWhitelistRules();
        }
        renderDeviceList();
        syncManualDeviceConnectorOptions();
        if (APP_STATE.manualDeviceEditingId) {
            if (APP_STATE.allDevices.some((item) => item.id === APP_STATE.manualDeviceEditingId)) {
                prefillManualDeviceForm(APP_STATE.manualDeviceEditingId, false);
            } else {
                resetManualDeviceForm(false);
            }
        } else {
            updateManualDeviceFormState();
        }
        applyPendingDeviceAndPath();
    } catch (error) {
        console.error('加载设备列表失败:', error);
        showAlert('加载设备列表失败', 'danger');
    }
}

function applyPendingDeviceAndPath() {
    if (APP_STATE.pendingDeviceFromUrl) {
        const selector = document.getElementById('device-selector');
        if (selector && APP_STATE.allDevices.some(d => d.id === APP_STATE.pendingDeviceFromUrl)) {
            selector.value = APP_STATE.pendingDeviceFromUrl;
        }
        APP_STATE.pendingDeviceFromUrl = null;
    }
    if (APP_STATE.pendingPathFromUrl) {
        const pathInput = document.getElementById('current-path');
        if (pathInput) {
            pathInput.value = APP_STATE.pendingPathFromUrl;
        }
        APP_STATE.pendingPathFromUrl = null;
    }
}

function renderDeviceList() {
    const devicesList = document.getElementById('devices-list');
    if (!devicesList) {
        return;
    }

    const keyword = (document.getElementById('device-search-input')?.value || '').trim().toLowerCase();
    const status = document.getElementById('device-status-filter')?.value || 'all';

    const filtered = APP_STATE.allDevices.filter((device) => {
        const onlineMatch = status === 'all' || (status === 'online' && device.online) || (status === 'offline' && !device.online);
        if (!onlineMatch) {
            return false;
        }
        if (!keyword) {
            return true;
        }
        const binding = getConnectorBinding(device.id);
        const target = `${device.name} ${device.id} ${device.ip} ${binding.connectorType} ${getConnectorDisplayName(binding)} ${getEndpointDisplayText(binding)}`.toLowerCase();
        return target.includes(keyword);
    });

    devicesList.innerHTML = '';

    if (filtered.length === 0) {
        devicesList.innerHTML = '<div class="alert alert-info">没有匹配设备</div>';
        return;
    }

    filtered.forEach((device) => {
        const binding = getConnectorBinding(device.id);
        const connectorName = getConnectorDisplayName(binding);
        const connectorState = getConnectorDriverStateText(binding);
        const endpointText = getEndpointDisplayText(binding);
        const trustLabel = getDeviceTrustLabel(device);
        const trustClass = getDeviceTrustClass(device);
        const trustState = normalizeDeviceTrustState(device.trustState);
        const remembered = isRememberedDevice(device);
        const memoryLabel = remembered ? '已记住' : '临时发现';
        const memoryClass = remembered ? 'is-ready' : 'is-warning';
        const canBrowse = isDeviceTrustedForRemoteActions(device);
        const capabilityText = Array.isArray(device.capability) && device.capability.length > 0
            ? device.capability.join(' · ')
            : '未声明';
        const manageButton = APP_STATE.accessContext.isLocalAdmin && device.id !== 'local'
            ? `<button class="btn btn-sm btn-outline-primary device-manage" data-device-id="${escapeAttr(device.id)}">维护端点</button>`
            : '';
        const rememberButton = APP_STATE.accessContext.isLocalAdmin && device.id !== 'local' && !remembered
            ? `<button class="btn btn-sm btn-outline-primary device-remember-action" data-device-id="${escapeAttr(device.id)}">记住设备</button>`
            : '';
        const trustActions = APP_STATE.accessContext.isLocalAdmin && device.id !== 'local'
            ? `
                ${rememberButton}
                <button class="btn btn-sm btn-outline-success device-trust-action" data-state="trusted" data-device-id="${escapeAttr(device.id)}">授信</button>
                <button class="btn btn-sm btn-outline-secondary device-pin-action" data-device-id="${escapeAttr(device.id)}">PIN</button>
                <button class="btn btn-sm btn-outline-danger device-trust-action" data-state="${trustState === 'blocked' ? 'unknown' : 'blocked'}" data-device-id="${escapeAttr(device.id)}">
                    ${trustState === 'blocked' ? '解除拉黑' : '拉黑'}
                </button>
            `
            : '';
        const deviceCard = document.createElement('div');
        deviceCard.className = 'card device-card';
        deviceCard.innerHTML = `
            <div class="card-header d-flex justify-content-between align-items-center">
                <h6 class="mb-0">${escapeHtml(device.name)}
                    <span class="device-status ${device.online ? 'status-online' : 'status-offline'}"></span>
                </h6>
                <span class="badge bg-secondary">${escapeHtml(device.type)}</span>
            </div>
            <div class="card-body">
                <p class="mb-1 small"><strong>ID:</strong> ${escapeHtml(device.id)}</p>
                <p class="mb-1 small"><strong>端点:</strong> ${escapeHtml(endpointText)}</p>
                <div class="device-card-meta">
                    <span class="device-chip">${escapeHtml(connectorName)}</span>
                    <span class="device-chip ${escapeAttr(getConnectorDriverStateClass(binding))}">${escapeHtml(connectorState)}</span>
                    <span class="device-chip ${escapeAttr(memoryClass)}">${escapeHtml(memoryLabel)}</span>
                    <span class="device-chip ${escapeAttr(trustClass)}">${escapeHtml(trustLabel)}</span>
                </div>
                <p class="mb-1 small"><strong>能力:</strong> ${escapeHtml(capabilityText)}</p>
                <p class="mb-2 small"><strong>最后在线:</strong> ${formatDate(device.lastSeen ? device.lastSeen * 1000 : 0)}</p>
                <div class="device-card-actions">
                    <button class="btn btn-sm btn-primary browse-device" data-device-id="${escapeAttr(device.id)}" ${canBrowse ? '' : 'disabled'} title="${canBrowse ? '' : '设备尚未授信，暂不可浏览或传输'}">浏览文件</button>
                    <button class="btn btn-sm btn-outline-secondary device-info" data-device-id="${escapeAttr(device.id)}">详情</button>
                    ${manageButton}
                </div>
                ${trustActions ? `<div class="device-card-actions mt-2">${trustActions}</div>` : ''}
            </div>
        `;
        devicesList.appendChild(deviceCard);
    });

    document.querySelectorAll('.browse-device').forEach((btn) => {
        btn.addEventListener('click', function() {
            const deviceId = this.getAttribute('data-device-id');
            document.getElementById('device-selector').value = deviceId;
            document.getElementById('current-path').value = '/';
            showPage('files-page');
        });
    });

    document.querySelectorAll('.device-info').forEach((btn) => {
        btn.addEventListener('click', function() {
            const id = this.getAttribute('data-device-id');
            const device = APP_STATE.allDevices.find((d) => d.id === id);
            if (device) {
                const binding = getConnectorBinding(id);
                showAlert(
                    `${device.name} · ${isRememberedDevice(device) ? '已记住' : '临时发现'} · ${getConnectorDisplayName(binding)} · ${getConnectorDriverStateText(binding)} · ${getEndpointDisplayText(binding)}`,
                    'info',
                );
            }
        });
    });

    document.querySelectorAll('.device-manage').forEach((btn) => {
        btn.addEventListener('click', function() {
            const id = this.getAttribute('data-device-id');
            prefillManualDeviceForm(id);
        });
    });

    document.querySelectorAll('.device-trust-action').forEach((btn) => {
        btn.addEventListener('click', async function() {
            const id = this.getAttribute('data-device-id');
            const state = this.getAttribute('data-state') || 'unknown';
            await updateDeviceTrustState(id, state);
        });
    });

    document.querySelectorAll('.device-remember-action').forEach((btn) => {
        btn.addEventListener('click', async function() {
            const id = this.getAttribute('data-device-id');
            await rememberDiscoveredDevice(id);
        });
    });

    document.querySelectorAll('.device-pin-action').forEach((btn) => {
        btn.addEventListener('click', async function() {
            const id = this.getAttribute('data-device-id');
            await startDevicePinPairing(id);
        });
    });
}

function updateDeviceStats(devices) {
    const total = devices.length;
    let online = 0;
    for (const device of devices) {
        if (device.online) {
            online += 1;
        }
    }
    const offline = total - online;

    const totalChip = document.getElementById('devices-total-chip');
    const onlineChip = document.getElementById('devices-online-chip');
    const offlineChip = document.getElementById('devices-offline-chip');

    if (totalChip) {
        totalChip.textContent = `总设备 ${total}`;
    }
    if (onlineChip) {
        onlineChip.textContent = `在线 ${online}`;
    }
    if (offlineChip) {
        offlineChip.textContent = `离线 ${offline}`;
    }
}

function initManualDeviceManager() {
    const form = document.getElementById('manual-device-form');
    if (form) {
        form.addEventListener('submit', saveManualDeviceForm);
    }

    const deleteBtn = document.getElementById('manual-device-delete-btn');
    if (deleteBtn) {
        deleteBtn.addEventListener('click', deleteManualDeviceForm);
    }

    const resetBtn = document.getElementById('manual-device-reset-btn');
    if (resetBtn) {
        resetBtn.addEventListener('click', () => resetManualDeviceForm());
    }

    const importApplyBtn = document.getElementById('manual-device-import-apply-btn');
    if (importApplyBtn) {
        importApplyBtn.addEventListener('click', importManualDeviceCommand);
    }

    const importPasteBtn = document.getElementById('manual-device-import-paste-btn');
    if (importPasteBtn) {
        importPasteBtn.addEventListener('click', pasteManualDeviceCommandFromClipboard);
    }

    ['manual-device-id', 'manual-device-name', 'manual-device-type', 'manual-device-connector-type', 'manual-device-endpoint-scheme', 'manual-device-ip', 'manual-device-port', 'manual-device-base-path']
        .forEach((id) => {
            const input = document.getElementById(id);
            if (!input) {
                return;
            }
            input.addEventListener('input', updateManualDeviceFormState);
            input.addEventListener('change', updateManualDeviceFormState);
        });

    syncManualDeviceConnectorOptions();
    updateManualDeviceFormState();
}

function syncManualDeviceConnectorOptions() {
    const datalist = document.getElementById('manual-device-connector-options');
    if (!datalist) {
        return;
    }

    const seen = new Set();
    const options = [];
    const catalog = Array.isArray(APP_STATE.connectorCatalog) && APP_STATE.connectorCatalog.length > 0
        ? APP_STATE.connectorCatalog
        : defaultConnectorCatalog();

    catalog.forEach((item) => {
        const key = String(item?.id || '').trim();
        if (!key || seen.has(key)) {
            return;
        }
        seen.add(key);
        const label = item?.displayName ? `${key} · ${item.displayName}` : key;
        options.push(`<option value="${escapeAttr(key)}" label="${escapeAttr(label)}"></option>`);
    });

    if (!seen.has('manual')) {
        options.push('<option value="manual" label="manual · 未声明"></option>');
    }
    datalist.innerHTML = options.join('');
}

function deriveManualDeviceDisplayName(rawId) {
    const normalized = String(rawId || '').trim().replace(/[_-]+/g, ' ');
    if (!normalized) {
        return '';
    }
    return normalized.replace(/\b[a-z]/g, (letter) => letter.toUpperCase());
}

function tokenizeShellLikeCommand(text) {
    const source = String(text || '').replace(/\\\r?\n/g, ' ');
    const tokens = [];
    let current = '';
    let quote = '';
    let escaping = false;

    for (const char of source) {
        if (escaping) {
            current += char;
            escaping = false;
            continue;
        }
        if (char === '\\' && quote !== "'") {
            escaping = true;
            continue;
        }
        if (quote) {
            if (char === quote) {
                quote = '';
            } else {
                current += char;
            }
            continue;
        }
        if (char === '"' || char === "'") {
            quote = char;
            continue;
        }
        if (/\s/.test(char)) {
            if (current) {
                tokens.push(current);
                current = '';
            }
            continue;
        }
        current += char;
    }

    if (current) {
        tokens.push(current);
    }
    return tokens;
}

function parseManualDeviceImportCommand(commandText) {
    const source = String(commandText || '').trim();
    if (!source) {
        return { error: '请先粘贴登记命令' };
    }

    const tokens = tokenizeShellLikeCommand(source);
    if (!tokens.length) {
        return { error: '未识别到可解析的命令内容' };
    }

    const options = {};
    for (let i = 0; i < tokens.length; i += 1) {
        const token = tokens[i];
        if (!token.startsWith('--')) {
            continue;
        }
        const key = token.slice(2);
        if (!key) {
            continue;
        }
        const next = tokens[i + 1];
        if (next && !next.startsWith('--')) {
            options[key] = next;
            i += 1;
        } else {
            options[key] = 'true';
        }
    }

    const id = String(options.id || '').trim();
    const ip = String(options.ip || options.host || '').trim();
    const portText = String(options.port || '').trim();
    const port = portText ? Number(portText) : 0;
    const connectorType = String(options.connector || options.connectorType || '').trim() || 'soonlink-http';
    const endpointScheme = normalizeEndpointSchemeValue(options.scheme || options.endpointScheme || '', connectorType);
    const endpointBasePath = normalizeEndpointBasePathValue(options['base-path'] || options.basePath || options.endpointBasePath || '');
    const deviceType = String(options['device-type'] || options.deviceType || '').trim() || 'remote';
    const name = String(options.name || '').trim() || deriveManualDeviceDisplayName(id);

    if (!id) {
        return { error: '命令里缺少 --id' };
    }
    if (!ip) {
        return { error: '命令里缺少 --ip' };
    }
    if (portText && (!Number.isFinite(port) || port <= 0)) {
        return { error: '命令里的 --port 无效' };
    }

    return {
        payload: {
            id,
            name,
            deviceType,
            connectorType,
            endpointScheme,
            endpointBasePath,
            ip,
            port: Number.isFinite(port) && port > 0 ? port : '',
        },
    };
}

function applyManualDeviceImportPayload(payload) {
    APP_STATE.manualDeviceEditingId = '';
    setInputValue('manual-device-id', payload.id || '');
    setInputValue('manual-device-name', payload.name || '');
    setInputValue('manual-device-type', payload.deviceType || 'remote');
    setInputValue('manual-device-connector-type', payload.connectorType || 'soonlink-http');
    setInputValue('manual-device-endpoint-scheme', payload.endpointScheme || 'http');
    setInputValue('manual-device-ip', payload.ip || '');
    setInputValue('manual-device-port', payload.port || '');
    setInputValue('manual-device-base-path', payload.endpointBasePath || '');
    updateManualDeviceFormState();
}

function importManualDeviceCommand() {
    const input = document.getElementById('manual-device-import-command');
    if (!input) {
        return;
    }

    const parsed = parseManualDeviceImportCommand(input.value);
    if (parsed.error) {
        showAlert(parsed.error, 'warning');
        return;
    }

    applyManualDeviceImportPayload(parsed.payload);
    showAlert(`已将 ${parsed.payload.id} 的登记命令解析到表单`, 'success');
}

async function pasteManualDeviceCommandFromClipboard() {
    const input = document.getElementById('manual-device-import-command');
    if (!input) {
        return;
    }
    if (!(navigator.clipboard && typeof navigator.clipboard.readText === 'function')) {
        showAlert('当前环境不支持直接读取剪贴板，请手动粘贴命令', 'warning');
        return;
    }

    try {
        const text = await navigator.clipboard.readText();
        if (!String(text || '').trim()) {
            showAlert('剪贴板里没有可解析的登记命令', 'warning');
            return;
        }
        input.value = text;
        importManualDeviceCommand();
    } catch (error) {
        console.error('读取剪贴板失败:', error);
        showAlert('读取剪贴板失败，请手动粘贴命令', 'warning');
    }
}

function updateManualDeviceFormState() {
    const modeChip = document.getElementById('manual-device-mode-chip');
    const driverChip = document.getElementById('manual-device-driver-chip');
    const targetChip = document.getElementById('manual-device-target-chip');
    const deleteBtn = document.getElementById('manual-device-delete-btn');
    const idInput = document.getElementById('manual-device-id');
    if (!modeChip || !driverChip || !targetChip || !deleteBtn || !idInput) {
        return;
    }

    const connectorType = guessConnectorType({
        id: getInputValue('manual-device-id'),
        deviceType: getInputValue('manual-device-type'),
        connectorType: getInputValue('manual-device-connector-type'),
        endpointScheme: getInputValue('manual-device-endpoint-scheme'),
        endpointBasePath: getInputValue('manual-device-base-path'),
        ip: getInputValue('manual-device-ip'),
        port: Number(getInputValue('manual-device-port') || 0),
    });
    const descriptor = getConnectorDescriptor(connectorType);
    const endpoint = buildEndpointInfo({
        connectorType,
        endpointScheme: getInputValue('manual-device-endpoint-scheme'),
        endpointBasePath: getInputValue('manual-device-base-path'),
        ip: getInputValue('manual-device-ip'),
        port: Number(getInputValue('manual-device-port') || 0),
    }, connectorType);
    const binding = {
        connectorType,
        connector: descriptor,
        driverAvailable: connectorType !== 'manual' && !!descriptor,
        endpoint,
    };
    const editingId = APP_STATE.manualDeviceEditingId;

    modeChip.textContent = editingId ? `编辑端点 ${editingId}` : '新建端点';
    modeChip.classList.toggle('is-warning', !!editingId);

    driverChip.textContent = `${getConnectorShortName(binding)} · ${getConnectorDriverStateText(binding)}`;
    driverChip.classList.toggle('is-warning', binding.driverAvailable === false);

    const currentId = getInputValue('manual-device-id').trim();
    targetChip.textContent = currentId
        ? `保存到 ${currentId} · ${getEndpointDisplayText(binding)}`
        : `保存后写入设备注册表 · ${getEndpointDisplayText(binding)}`;

    deleteBtn.disabled = !editingId;
    idInput.readOnly = !!editingId;
}

function resetManualDeviceForm(preserveConnector = true) {
    APP_STATE.manualDeviceEditingId = '';
    setInputValue('manual-device-id', '');
    setInputValue('manual-device-name', '');
    setInputValue('manual-device-type', 'remote');
    setInputValue('manual-device-endpoint-scheme', 'http');
    setInputValue('manual-device-ip', '');
    setInputValue('manual-device-port', '');
    setInputValue('manual-device-base-path', '');
    if (!preserveConnector || !getInputValue('manual-device-connector-type').trim()) {
        setInputValue('manual-device-connector-type', 'soonlink-http');
    }
    updateManualDeviceFormState();
}

function prefillManualDeviceForm(deviceId, notify = true) {
    const device = APP_STATE.allDevices.find((item) => item.id === deviceId);
    if (!device || device.id === 'local') {
        updateManualDeviceFormState();
        return;
    }

    APP_STATE.manualDeviceEditingId = device.id;
    setInputValue('manual-device-id', device.id || '');
    setInputValue('manual-device-name', device.name || '');
    setInputValue('manual-device-type', device.type || device.deviceType || 'remote');
    setInputValue('manual-device-connector-type', guessConnectorType(device));
    setInputValue('manual-device-endpoint-scheme', device.endpoint?.scheme || device.endpointScheme || 'http');
    setInputValue('manual-device-ip', device.ip || '');
    setInputValue('manual-device-port', device.port || '');
    setInputValue('manual-device-base-path', device.endpoint?.basePath || device.endpointBasePath || '');
    updateManualDeviceFormState();

    if (notify) {
        showAlert(`已载入 ${device.name || device.id} 的端点配置`, 'info');
    }
}

function collectManualDevicePayload() {
    return {
        id: getInputValue('manual-device-id').trim(),
        name: getInputValue('manual-device-name').trim(),
        deviceType: getInputValue('manual-device-type').trim() || 'remote',
        connectorType: getInputValue('manual-device-connector-type').trim() || 'soonlink-http',
        endpointScheme: getInputValue('manual-device-endpoint-scheme').trim() || '',
        endpointBasePath: normalizeEndpointBasePathValue(getInputValue('manual-device-base-path')),
        ip: getInputValue('manual-device-ip').trim(),
        port: Number(getInputValue('manual-device-port') || 0),
    };
}

async function saveManualDeviceForm(event) {
    event.preventDefault();
    if (!APP_STATE.accessContext.isLocalAdmin) {
        showAlert('仅本机管理员可维护手动节点', 'warning');
        return;
    }

    const payload = collectManualDevicePayload();
    if (!payload.id) {
        showAlert('请填写设备ID', 'warning');
        return;
    }
    if (!payload.ip) {
        showAlert('请填写主机或 IP', 'warning');
        return;
    }
    if (payload.connectorType === 'soonlink-http' && payload.endpointScheme) {
        const normalizedScheme = normalizeEndpointSchemeValue(payload.endpointScheme, payload.connectorType);
        if (!['http', 'https'].includes(normalizedScheme)) {
            showAlert('SoonLink HTTP 端点当前只支持 http 或 https', 'warning');
            return;
        }
        payload.endpointScheme = normalizedScheme;
    }

    try {
        const response = await fetch(`/api/devices/${encodeURIComponent(payload.id)}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(payload),
        });
        const result = await response.json().catch(() => ({}));
        if (!response.ok || result.success === false) {
            showAlert(result.error || '保存端点失败', 'danger');
            return;
        }

        APP_STATE.manualDeviceEditingId = payload.id;
        showAlert(result.message || '设备端点已保存', 'success');
        await loadDevices();
    } catch (error) {
        console.error('保存端点失败:', error);
        showAlert('保存端点失败', 'danger');
    }
}

async function deleteManualDeviceForm() {
    if (!APP_STATE.accessContext.isLocalAdmin) {
        showAlert('仅本机管理员可维护手动节点', 'warning');
        return;
    }

    const deviceId = APP_STATE.manualDeviceEditingId || getInputValue('manual-device-id').trim();
    if (!deviceId) {
        showAlert('当前没有可删除的手动节点', 'warning');
        return;
    }
    if (!window.confirm(`确定删除手动节点 ${deviceId} 吗？`)) {
        return;
    }

    try {
        const response = await fetch(`/api/devices/${encodeURIComponent(deviceId)}`, {
            method: 'DELETE',
        });
        const result = await response.json().catch(() => ({}));
        if (!response.ok || result.success === false) {
            showAlert(result.error || '删除端点失败', 'danger');
            return;
        }

        resetManualDeviceForm(false);
        showAlert(result.message || '设备端点已删除', 'success');
        await loadDevices();
    } catch (error) {
        console.error('删除端点失败:', error);
        showAlert('删除端点失败', 'danger');
    }
}

function updateDeviceSelectors(devices) {
    const selectors = [
        document.getElementById('device-selector'),
        document.getElementById('target-device'),
        document.getElementById('source-device'),
        document.getElementById('transfer-target-device'),
        document.getElementById('relay-source-device'),
        document.getElementById('relay-target-device'),
        document.getElementById('whitelist-target-device'),
    ];

    selectors.forEach((selector) => {
        if (!selector) {
            return;
        }

        const currentValue = selector.value;
        selector.innerHTML = '';

        devices.forEach((device) => {
            const binding = getConnectorBinding(device.id);
            const option = document.createElement('option');
            option.value = device.id;
            const trustLabel = isTrustManagedDevice(device) ? ` · ${getDeviceTrustLabel(device)}` : '';
            option.textContent = `${device.name} (${device.type} · ${getConnectorShortName(binding)}${trustLabel})`;
            selector.appendChild(option);
        });

        if (currentValue && devices.some((d) => d.id === currentValue)) {
            selector.value = currentValue;
        }
    });

    renderFileWorkspaceMeta();
    renderTransferTargetSummary();
}

function initFileExplorer() {
    const selector = document.getElementById('device-selector');
    if (selector) {
        selector.addEventListener('change', () => {
            refreshFavoritesUI();
            renderFileWorkspaceMeta();
            loadFiles();
        });
    }

    document.getElementById('go-parent-dir').addEventListener('click', navigateParentPath);

    const pathInput = document.getElementById('current-path');
    const pathGoBtn = document.getElementById('path-go-btn');
    if (pathGoBtn) {
        pathGoBtn.addEventListener('click', navigateToInputPath);
    }
    if (pathInput) {
        pathInput.addEventListener('input', renderFileWorkspaceMeta);
        pathInput.addEventListener('keydown', (event) => {
            if (event.key === 'Enter') {
                event.preventDefault();
                navigateToInputPath();
            }
        });
    }

    const sortBy = document.getElementById('file-sort-by');
    const sortOrderBtn = document.getElementById('file-sort-order-btn');
    if (sortBy) {
        sortBy.addEventListener('change', () => {
            APP_STATE.fileSortBy = sortBy.value || 'name';
            renderFileList();
        });
    }
    if (sortOrderBtn) {
        updateSortOrderButton();
        sortOrderBtn.addEventListener('click', () => {
            APP_STATE.fileSortOrder = APP_STATE.fileSortOrder === 'asc' ? 'desc' : 'asc';
            updateSortOrderButton();
            renderFileList();
        });
    }

    const addFavoriteBtn = document.getElementById('add-current-favorite-btn');
    if (addFavoriteBtn) {
        addFavoriteBtn.addEventListener('click', addCurrentPathFavorite);
    }

    initFileDropUpload();
    initPathBackspaceIntercept();
    initPasteUpload();

    document.getElementById('upload-trigger-btn').addEventListener('click', function() {
        const selectedDevice = document.getElementById('device-selector').value;
        const currentPath = document.getElementById('current-path').value;

        if (!selectedDevice) {
            showAlert('请先选择目标设备', 'warning');
            return;
        }

        document.getElementById('target-device').value = selectedDevice;
        document.getElementById('target-path').value = currentPath;
        syncUploadFavoritesSelector();

        new bootstrap.Modal(document.getElementById('upload-modal')).show();
    });
}

async function loadFiles() {
    const deviceId = document.getElementById('device-selector').value;
    const pathInput = document.getElementById('current-path');
    const path = normalizePath(pathInput?.value || '/');
    const fileList = document.getElementById('file-list');
    if (pathInput) {
        pathInput.value = path;
    }

    if (!deviceId) {
        APP_STATE.allFiles = [];
        APP_STATE.fileListMeta = {
            loaded: 0,
            total: 0,
            truncated: false,
        };
        fileList.innerHTML = '<tr><td colspan="2" class="table-empty-cell text-center">请选择设备</td></tr>';
        renderFileWorkspaceMeta();
        return;
    }

    fileList.innerHTML = '<tr><td colspan="2" class="table-empty-cell text-center text-muted"><i class="bi bi-hourglass-split me-2"></i>加载中...</td></tr>';

    try {
        const response = await fetch(`/api/fs/list?device=${encodeURIComponent(deviceId)}&path=${encodeURIComponent(path)}`);
        const data = await response.json();

        if (data.error) {
            fileList.innerHTML = `<tr><td colspan="2" class="table-empty-cell text-center text-danger">${escapeHtml(data.error)}</td></tr>`;
            showAlert(`路径访问失败: ${data.error}`, 'danger');
            document.getElementById('current-path').value = APP_STATE.lastValidPath;
            APP_STATE.allFiles = [];
            APP_STATE.fileListMeta = {
                loaded: 0,
                total: 0,
                truncated: false,
            };
            renderFileWorkspaceMeta();
            return;
        }

        APP_STATE.lastValidPath = normalizePath(path);
        APP_STATE.allFiles = Array.isArray(data.files) ? data.files : [];
        APP_STATE.fileListMeta = {
            loaded: APP_STATE.allFiles.length,
            total: Number(data.total || APP_STATE.allFiles.length),
            truncated: !!data.truncated,
        };
        renderFileWorkspaceMeta();
        renderFileList(data.truncated, data.offset || 0, data.total || APP_STATE.allFiles.length);
        updateFilesPageUrl();
    } catch (error) {
        console.error('加载文件列表失败:', error);
        document.getElementById('file-list').innerHTML = '<tr><td colspan="2" class="table-empty-cell text-center text-danger">加载文件列表失败</td></tr>';
        APP_STATE.allFiles = [];
        APP_STATE.fileListMeta = {
            loaded: 0,
            total: 0,
            truncated: false,
        };
        renderFileWorkspaceMeta();
        showAlert('加载文件列表失败', 'danger');
    }
}

function renderFileList(truncated = false, offset = 0, total = 0) {
    const fileList = document.getElementById('file-list');
    fileList.innerHTML = '';

    if (!APP_STATE.allFiles || APP_STATE.allFiles.length === 0) {
        fileList.innerHTML = '<tr><td colspan="2" class="table-empty-cell text-center">目录为空</td></tr>';
        return;
    }

    const sorted = APP_STATE.allFiles.slice().sort(compareFileEntries);

    sorted.forEach((file) => {
        const row = document.createElement('tr');
        row.className = 'file-row';
        row.dataset.path = file.path;
        row.dataset.isDir = file.isDir ? 'true' : 'false';

        const modifiedDate = formatDate(file.modified * 1000);
        const subInfo = file.isDir
            ? `${file.itemCount || 0} 项`
            : formatSize(file.size);

        const isFavorite = isFavoritePath(file.path);
        const primaryIcon = file.isDir ? 'bi-folder-fill' : 'bi-file-earmark';
        const nameClass = file.isDir ? 'file-name-button folder-name' : 'file-name-button file-transfer-name';
        const actionMarkup = file.isDir
            ? '<span class="file-action-hint">目录</span>'
            : `<button class="btn btn-sm btn-primary download-file" data-path="${escapeAttr(file.path)}">下载</button>`;

        row.innerHTML = `
            <td class="file-info-cell">
                <button type="button" class="file-icon-button favorite-entry ${isFavorite ? 'is-favorite' : ''}" data-path="${escapeAttr(file.path)}" title="${isFavorite ? '取消收藏' : '收藏此项'}">
                    <i class="bi ${primaryIcon} file-icon-large"></i>
                    <span class="file-favorite-badge" ${isFavorite ? '' : 'hidden'}>
                        <i class="bi bi-star-fill"></i>
                    </span>
                </button>
                <div class="file-info-content">
                    <button type="button" class="${nameClass}" data-path="${escapeAttr(file.path)}" data-name="${escapeAttr(file.name)}">
                        ${escapeHtml(file.name)}
                    </button>
                    <div class="file-meta">
                        <span class="file-meta-primary">${escapeHtml(subInfo)}</span>
                        <span class="file-meta-divider">·</span>
                        <span>${escapeHtml(modifiedDate)}</span>
                    </div>
                </div>
            </td>
            <td class="file-action-cell">
                ${actionMarkup}
            </td>
        `;

        fileList.appendChild(row);
    });

    if (truncated) {
        const truncRow = document.createElement('tr');
        const loaded = offset + APP_STATE.allFiles.length;
        truncRow.innerHTML = `<td colspan="2" class="table-empty-cell text-center text-muted small">当前显示 ${loaded}/${total} 项，可使用 limit/offset 查询更多</td>`;
        fileList.appendChild(truncRow);
    }

    bindFileListInteractions();
}

function compareFileEntries(a, b) {
    if (a.isDir && !b.isDir) return -1;
    if (!a.isDir && b.isDir) return 1;

    const field = APP_STATE.fileSortBy;
    const order = APP_STATE.fileSortOrder === 'asc' ? 1 : -1;

    if (field === 'size') {
        const av = Number(a.size || 0);
        const bv = Number(b.size || 0);
        if (av !== bv) return av > bv ? order : -order;
    } else if (field === 'modified') {
        const av = Number(a.modified || 0);
        const bv = Number(b.modified || 0);
        if (av !== bv) return av > bv ? order : -order;
    } else {
        const nameComp = String(a.name || '').localeCompare(String(b.name || ''));
        if (nameComp !== 0) return nameComp * order;
    }

    return String(a.name || '').localeCompare(String(b.name || ''));
}

function bindFileListInteractions() {
    document.querySelectorAll('.folder-name').forEach((folderName) => {
        folderName.addEventListener('click', function(event) {
            event.stopPropagation();
            const dirPath = this.getAttribute('data-path');
            document.getElementById('current-path').value = dirPath;
            loadFiles();
        });
    });

    document.querySelectorAll('.file-transfer-name').forEach((fileNameBtn) => {
        fileNameBtn.addEventListener('click', function(event) {
            event.stopPropagation();
            const path = this.getAttribute('data-path') || '';
            const sourceDevice = document.getElementById('device-selector').value;
            if (!sourceDevice || !path) {
                return;
            }
            showTransferModalWithFile(sourceDevice, path);
        });
    });

    document.querySelectorAll('.download-file').forEach((btn) => {
        btn.addEventListener('click', function(event) {
            event.stopPropagation();
            const filePath = this.getAttribute('data-path');
            const currentDeviceId = document.getElementById('device-selector').value;
            if (!currentDeviceId || !filePath) {
                return;
            }
            window.open(`/api/fs/download?device=${encodeURIComponent(currentDeviceId)}&path=${encodeURIComponent(filePath)}`);
        });
    });

    document.querySelectorAll('.favorite-entry').forEach((btn) => {
        btn.addEventListener('click', function(event) {
            event.stopPropagation();
            const path = this.getAttribute('data-path');
            const deviceId = document.getElementById('device-selector').value;
            const normalized = normalizePath(path || '/');
            const name = normalized.split('/').filter(Boolean).pop() || '/';
            toggleFavorite(path, deviceId, name);
            renderFileList();
        });
    });
}

function normalizePath(path) {
    let value = String(path || '').trim();
    if (!value.startsWith('/')) {
        value = '/' + value;
    }
    value = value.replace(/\/{2,}/g, '/');
    if (value.length > 1 && value.endsWith('/')) {
        value = value.slice(0, -1);
    }
    return value || '/';
}

function navigateParentPath() {
    const currentPath = normalizePath(document.getElementById('current-path').value);
    if (currentPath === '/') {
        showPage('devices-page');
        return;
    }
    const parentPath = currentPath.split('/').filter(Boolean).slice(0, -1).join('/');
    document.getElementById('current-path').value = parentPath ? '/' + parentPath : '/';
    loadFiles();
}

function navigateToInputPath() {
    const input = document.getElementById('current-path');
    const target = normalizePath(input.value);
    input.value = target;
    loadFiles();
}

function initPathBackspaceIntercept() {
    document.addEventListener('keydown', (event) => {
        if (APP_STATE.activePageId !== 'files-page') {
            return;
        }
        if (event.key !== 'Backspace' && event.key !== 'Delete') {
            return;
        }

        const target = event.target;
        const editable = target && (
            target.tagName === 'INPUT' ||
            target.tagName === 'TEXTAREA' ||
            target.isContentEditable
        );
        if (editable) {
            return;
        }

        const currentPath = normalizePath(document.getElementById('current-path').value);
        if (currentPath !== '/') {
            event.preventDefault();
            navigateParentPath();
        }
    });
}

function initFileDropUpload() {
    const dropWrap = document.getElementById('file-table-dropzone');
    const fileInput = document.getElementById('upload-file');
    if (!dropWrap || !fileInput) {
        return;
    }

    dropWrap.addEventListener('dragover', (event) => {
        event.preventDefault();
        dropWrap.classList.add('drag-over');
    });

    dropWrap.addEventListener('dragleave', () => {
        dropWrap.classList.remove('drag-over');
    });

    dropWrap.addEventListener('drop', (event) => {
        event.preventDefault();
        dropWrap.classList.remove('drag-over');

        const files = event.dataTransfer?.files;
        if (!files || files.length === 0) {
            return;
        }

        const selectedDevice = document.getElementById('device-selector').value;
        if (!selectedDevice) {
            showAlert('请先选择目标设备后再拖拽上传', 'warning');
            return;
        }

        fileInput.files = files;
        document.getElementById('target-device').value = selectedDevice;
        document.getElementById('target-path').value = normalizePath(document.getElementById('current-path').value);
        syncUploadFavoritesSelector();
        showAlert(`检测到 ${files.length} 个拖拽文件，请确认上传目标后提交`, 'info');
        new bootstrap.Modal(document.getElementById('upload-modal')).show();
    });
}

function setupLongPressRows() {
    document.querySelectorAll('.file-row').forEach((row) => {
        let pressTimer = null;
        row.addEventListener('pointerdown', () => {
            pressTimer = setTimeout(() => {
                const path = row.dataset.path || '';
                if (!path) {
                    return;
                }
                const sourceDevice = document.getElementById('device-selector').value;
                if (!sourceDevice) {
                    return;
                }
                showTransferModalWithFile(sourceDevice, path);
            }, 400);
        });
        row.addEventListener('pointerup', () => {
            if (pressTimer) {
                clearTimeout(pressTimer);
                pressTimer = null;
            }
        });
        row.addEventListener('pointerleave', () => {
            if (pressTimer) {
                clearTimeout(pressTimer);
                pressTimer = null;
            }
        });
    });
}

async function showTransferModalWithFile(deviceId, filePath) {
    document.getElementById('source-device').value = deviceId;
    document.getElementById('source-path').value = filePath;
    document.getElementById('transfer-target-path').value = normalizePath(document.getElementById('current-path')?.value || '/');
    const targetSelect = document.getElementById('transfer-target-device');
    if (targetSelect && (!targetSelect.value || targetSelect.value === deviceId)) {
        const fallback = Array.from(targetSelect.options || []).find((option) => option.value && option.value !== deviceId);
        if (fallback) {
            targetSelect.value = fallback.value;
        }
    }

    resetTransferPreview();
    document.getElementById('transfer-info-name').textContent = '-';
    document.getElementById('transfer-info-path').textContent = filePath;
    document.getElementById('transfer-info-size').textContent = '-';
    document.getElementById('transfer-info-type').textContent = '-';
    document.getElementById('transfer-info-entries').textContent = '-';
    document.getElementById('transfer-info-modified').textContent = '-';
    APP_STATE.transferSource = {
        deviceId,
        path: filePath,
        isDir: false,
    };
    renderTransferTargetSummary();
    updateTransferDownloadAction();
    const panel = document.getElementById('transfer-options-panel');
    if (panel) {
        bootstrap.Collapse.getOrCreateInstance(panel, { toggle: false }).hide();
    }
    new bootstrap.Modal(document.getElementById('transfer-modal')).show();

    try {
        const response = await fetch(buildFsApiUrl('/api/fs/info', deviceId, filePath));
        const data = await response.json();
        if (!data.error) {
            const isDir = !!data.isDir;
            const resolvedPath = data.path || filePath;
            APP_STATE.transferSource = {
                deviceId,
                path: resolvedPath,
                isDir,
            };
            document.getElementById('transfer-info-name').textContent = data.name || filePath.split('/').pop();
            document.getElementById('transfer-info-path').textContent = resolvedPath;
            document.getElementById('transfer-info-type').textContent = isDir ? '目录' : (data.mimeType || '文件');
            document.getElementById('transfer-info-modified').textContent = data.modified ? formatDate(Number(data.modified) * 1000) : '-';

            if (isDir) {
                const summaryResp = await fetch(buildFsApiUrl('/api/fs/summary', deviceId, resolvedPath));
                const summary = await summaryResp.json();
                if (summaryResp.ok && summary.success) {
                    const totalFiles = Number(summary.totalFiles || 0);
                    const totalDirs = Math.max(Number(summary.totalDirs || 0) - 1, 0);
                    document.getElementById('transfer-info-size').textContent = formatSize(Number(summary.totalBytes || 0));
                    document.getElementById('transfer-info-entries').textContent = `${totalFiles} 文件 · ${totalDirs} 目录`;
                } else {
                    document.getElementById('transfer-info-size').textContent = '-';
                    document.getElementById('transfer-info-entries').textContent = '目录摘要不可用';
                }
                showTransferPreviewMessage('目录暂不提供内容预览', '目录任务会保留完整目录树结构');
            } else {
                document.getElementById('transfer-info-size').textContent = formatSize(Number(data.size || 0));
                document.getElementById('transfer-info-entries').textContent = '1 文件';
                await loadTransferPreview(deviceId, resolvedPath, false);
            }
        } else {
            showTransferPreviewMessage(data.error || '预览暂不可用', '源项信息读取失败');
        }
    } catch (error) {
        console.error('获取文件信息失败:', error);
        showTransferPreviewMessage('预览暂不可用', '文件信息读取失败后仍可继续创建传输任务');
    }

    updateTransferDownloadAction();
    renderTransferTargetSummary();
}

function loadFavorites() {
    const raw = (window.localStorage && localStorage.getItem(FAVORITES_KEY)) || '[]';
    try {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) {
            APP_STATE.favorites = parsed.filter((item) => item && item.path && item.deviceId);
        } else {
            APP_STATE.favorites = [];
        }
    } catch (_error) {
        APP_STATE.favorites = [];
    }
}

async function syncFavoritesFromServer() {
    if (!hasCapability('favorites')) {
        APP_STATE.favorites = [];
        APP_STATE.favoritesMode = 'disabled';
        return;
    }
    try {
        const response = await fetch('/api/favorites/');
        if (!response.ok) {
            return;
        }
        const data = await response.json();
        if (!data.success || !Array.isArray(data.favorites)) {
            return;
        }
        APP_STATE.favoritesMode = data.mode || 'cache';
        APP_STATE.favorites = data.favorites.filter((item) => item && item.path && item.deviceId);
        if (window.localStorage) {
            localStorage.setItem(FAVORITES_KEY, JSON.stringify(APP_STATE.favorites));
        }
    } catch (_error) {
        // fallback keeps local cache only
    }
}

function persistFavorites() {
    if (!hasCapability('favorites')) {
        return;
    }
    if (window.localStorage) {
        localStorage.setItem(FAVORITES_KEY, JSON.stringify(APP_STATE.favorites));
    }
    persistFavoritesToServer().catch(() => {
        // keep local cache when server update fails
    });
}

async function persistFavoritesToServer() {
    if (!hasCapability('favorites')) {
        return;
    }
    await fetch('/api/favorites/', {
        method: 'PUT',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            favorites: APP_STATE.favorites,
        }),
    });
}

function favoriteKey(path, deviceId) {
    return `${deviceId}::${normalizePath(path)}`;
}

function isFavoritePath(path, deviceId = document.getElementById('device-selector')?.value || '') {
    const key = favoriteKey(path, deviceId);
    return APP_STATE.favorites.some((item) => favoriteKey(item.path, item.deviceId) === key);
}

function toggleFavorite(path, deviceId, customName = '') {
    if (!hasCapability('favorites')) {
        showAlert('当前版本未启用收藏能力', 'info');
        return;
    }
    if (!deviceId) {
        showAlert('请先选择设备后再收藏路径', 'warning');
        return;
    }
    const normalizedPath = normalizePath(path);
    const key = favoriteKey(normalizedPath, deviceId);
    const idx = APP_STATE.favorites.findIndex((item) => favoriteKey(item.path, item.deviceId) === key);

    if (idx >= 0) {
        APP_STATE.favorites.splice(idx, 1);
        showAlert('已取消收藏', 'info');
    } else {
        const matchedDevice = APP_STATE.allDevices.find((d) => d.id === deviceId);
        APP_STATE.favorites.push({
            deviceId,
            path: normalizedPath,
            name: customName || `${matchedDevice?.name || deviceId}: ${normalizedPath}`,
            createdAt: Date.now(),
        });
        showAlert('收藏成功，可在主页和文件菜单快速访问', 'success');
    }

    persistFavorites();
    refreshFavoritesUI();
}

function addCurrentPathFavorite() {
    const deviceId = document.getElementById('device-selector').value;
    const path = normalizePath(document.getElementById('current-path').value);
    if (!deviceId) {
        showAlert('请先选择设备后再收藏路径', 'warning');
        return;
    }
    toggleFavorite(path, deviceId);
}

function refreshFavoritesUI() {
    renderFavoritesList('home-favorites-list', true);
    renderFavoritesList('files-favorites-list', false);
    renderFilesSubmenu();
    if (hasCapability('favorites')) {
        syncUploadFavoritesSelector();
    }
    renderFileWorkspaceMeta();
}

function renderFileWorkspaceMeta() {
    const selector = document.getElementById('device-selector');
    const deviceChip = document.getElementById('files-device-chip');
    const connectorChip = document.getElementById('files-connector-chip');
    const pathChip = document.getElementById('files-path-chip');
    const countChip = document.getElementById('files-count-chip');
    const modeChip = document.getElementById('files-favorites-mode-chip');
    const dropHint = document.getElementById('file-drop-hint');

    const deviceId = selector?.value || '';
    const device = APP_STATE.allDevices.find((item) => item.id === deviceId);
    const binding = getConnectorBinding(deviceId);
    const currentPath = normalizePath(document.getElementById('current-path')?.value || '/');
    const loadedCount = Number(APP_STATE.fileListMeta?.loaded || APP_STATE.allFiles.length || 0);
    const totalCount = Number(APP_STATE.fileListMeta?.total || loadedCount);
    const isTruncated = !!APP_STATE.fileListMeta?.truncated;
    const scopedFavorites = APP_STATE.favorites.filter((item) => !deviceId || item.deviceId === deviceId).length;

    if (deviceChip) {
        deviceChip.textContent = `设备 ${device?.name || deviceId || '-'}`;
        deviceChip.title = device?.name || deviceId || '-';
    }
    if (connectorChip) {
        const connectorText = deviceId
            ? `${getConnectorShortName(binding)} · ${getConnectorDriverStateText(binding)}`
            : '连接器 -';
        connectorChip.textContent = deviceId ? `连接 ${connectorText}` : '连接器 -';
        connectorChip.title = connectorText;
        connectorChip.classList.toggle('is-warning', !!deviceId && binding.driverAvailable === false);
    }
    if (pathChip) {
        pathChip.textContent = `路径 ${currentPath}`;
        pathChip.title = currentPath;
    }
    if (countChip) {
        countChip.textContent = isTruncated ? `条目 ${loadedCount}/${totalCount}` : `条目 ${loadedCount}`;
        countChip.title = isTruncated
            ? `当前已加载 ${loadedCount} 项，目录总量约 ${totalCount} 项`
            : `当前目录共 ${loadedCount} 项`;
    }
    if (modeChip) {
        modeChip.textContent = hasCapability('favorites')
            ? `收藏 ${scopedFavorites} · ${APP_STATE.favoritesMode || 'cache'}`
            : '收藏 disabled';
    }
    if (dropHint) {
        const deviceLabel = device?.name || deviceId || '当前设备';
        const connectorCopy = deviceId ? `，当前连接 ${getConnectorShortName(binding)}` : '';
        dropHint.innerHTML = `
            <div class="drop-hint-title">${escapeHtml(deviceLabel)} · ${escapeHtml(currentPath)}</div>
            <div class="drop-hint-copy">拖拽上传到当前目录${escapeHtml(connectorCopy)}，点图标收藏，点名称打开目录或发起传输</div>
        `;
    }
    renderRelayRestoreHint();
}

function renderFavoritesList(containerId, fromHome) {
    const container = document.getElementById(containerId);
    if (!container) {
        return;
    }
    container.innerHTML = '';

    if (!hasCapability('favorites')) {
        container.innerHTML = '<span class="favorite-empty">当前版本未启用收藏能力</span>';
        return;
    }

    const deviceId = document.getElementById('device-selector')?.value || '';
    const favorites = fromHome
        ? APP_STATE.favorites.slice(0, 8)
        : APP_STATE.favorites.filter((item) => !deviceId || item.deviceId === deviceId);

    if (favorites.length === 0) {
        container.innerHTML = '<span class="favorite-empty">暂无收藏路径</span>';
        return;
    }

    for (const fav of favorites) {
        const wrap = document.createElement('div');
        wrap.className = 'favorite-pill';

        const button = document.createElement('button');
        button.className = 'btn btn-link p-0 text-start text-decoration-none favorite-open-btn pd-fl-cc';
        button.type = 'button';
        button.title = '双击或连续点按打开';
        button.innerHTML = `
            <i class="bi bi-star-fill text-warning"></i>
            <span class="favorite-name">${escapeHtml(fav.name || `${fav.deviceId}:${fav.path}`)}</span>
        `;
        bindDoubleActivate(button, () => applyFavorite(fav));

        const removeBtn = document.createElement('button');
        removeBtn.type = 'button';
        removeBtn.className = 'btn btn-link p-0 text-decoration-none favorite-remove-btn';
        removeBtn.innerHTML = '<i class="bi bi-x-circle"></i>';
        removeBtn.addEventListener('click', (event) => {
            event.stopPropagation();
            toggleFavorite(fav.path, fav.deviceId, fav.name);
        });

        wrap.appendChild(button);
        wrap.appendChild(removeBtn);
        container.appendChild(wrap);
    }
}

function initFavoritesMenu() {
    const menuBtn = document.getElementById('nav-files-menu');
    const submenu = document.getElementById('files-submenu');
    const manageBtn = document.getElementById('favorites-manage-btn');

    if (!hasCapability('favorites')) {
        if (submenu) {
            submenu.classList.remove('show');
        }
        return;
    }

    if (manageBtn) {
        manageBtn.addEventListener('click', () => {
            showPage('files-page');
            showFilesSubmenu(true);
        });
    }

    if (!menuBtn || !submenu) {
        return;
    }

    menuBtn.addEventListener('click', (event) => {
        event.stopPropagation();
        showPage('files-page');
        showFilesSubmenu(!submenu.classList.contains('show'));
    });

    document.addEventListener('click', (event) => {
        if (!submenu.contains(event.target) && !menuBtn.contains(event.target)) {
            showFilesSubmenu(false);
        }
    });
}

function showFilesSubmenu(show) {
    const submenu = document.getElementById('files-submenu');
    if (!submenu) {
        return;
    }
    submenu.classList.toggle('show', show);
}

function renderFilesSubmenu() {
    const list = document.getElementById('files-submenu-list');
    if (!list) {
        return;
    }
    list.innerHTML = '';
    if (!hasCapability('favorites')) {
        list.innerHTML = '<span class="favorite-empty">当前版本未启用收藏能力</span>';
        return;
    }
    if (APP_STATE.favorites.length === 0) {
        list.innerHTML = '<span class="favorite-empty">暂无收藏路径</span>';
        return;
    }

    APP_STATE.favorites.slice(0, 12).forEach((fav) => {
        const btn = document.createElement('button');
        btn.className = 'btn btn-sm';
        btn.type = 'button';
        btn.textContent = fav.name || `${fav.deviceId}: ${fav.path}`;
        btn.addEventListener('click', () => {
            applyFavorite(fav);
            showFilesSubmenu(false);
        });
        list.appendChild(btn);
    });
}

function applyFavorite(fav) {
    if (!fav || !fav.deviceId) {
        return;
    }

    if (!APP_STATE.allDevices.some((d) => d.id === fav.deviceId)) {
        showAlert('收藏设备当前不在线，请先刷新设备列表', 'warning');
        return;
    }

    const selector = document.getElementById('device-selector');
    if (selector) {
        selector.value = fav.deviceId;
    }
    document.getElementById('current-path').value = normalizePath(fav.path);
    showPage('files-page');
    loadFiles();
}

function syncUploadFavoritesSelector() {
    const selector = document.getElementById('upload-favorite-selector');
    const useBtn = document.getElementById('use-upload-favorite-btn');
    if (!selector) {
        return;
    }

    if (!hasCapability('favorites')) {
        selector.innerHTML = '<option value="">当前版本未启用收藏</option>';
        return;
    }

    const currentDevice = document.getElementById('target-device')?.value || '';
    selector.innerHTML = '<option value="">选择收藏路径...</option>';
    APP_STATE.favorites
        .filter((fav) => !currentDevice || fav.deviceId === currentDevice)
        .forEach((fav) => {
            const opt = document.createElement('option');
            opt.value = `${fav.deviceId}::${fav.path}`;
            opt.textContent = fav.name || `${fav.deviceId}: ${fav.path}`;
            selector.appendChild(opt);
        });

    if (useBtn && !useBtn.dataset.bound) {
        useBtn.dataset.bound = 'true';
        useBtn.addEventListener('click', () => {
            const value = selector.value;
            if (!value.includes('::')) {
                showAlert('请先选择一个收藏路径', 'warning');
                return;
            }
            const [deviceId, ...rest] = value.split('::');
            const path = rest.join('::');
            document.getElementById('target-device').value = deviceId;
            document.getElementById('target-path').value = normalizePath(path);
            showAlert('已应用收藏上传路径', 'success');
        });
    }
}

function initUploadModal() {
    const uploadDropZone = document.getElementById('upload-drop-zone');
    const fileInput = document.getElementById('upload-file');
    const selectedFilesContainer = document.getElementById('selected-files-container');
    const selectedFilesList = document.getElementById('selected-files-list');
    const targetDeviceSelect = document.getElementById('target-device');

    if (targetDeviceSelect) {
        targetDeviceSelect.addEventListener('change', syncUploadFavoritesSelector);
    }

    syncUploadFavoritesSelector();

    uploadDropZone.addEventListener('click', () => fileInput.click());

    uploadDropZone.addEventListener('dragover', function(e) {
        e.preventDefault();
        this.style.borderColor = '#0d6efd';
    });

    uploadDropZone.addEventListener('dragleave', function(e) {
        e.preventDefault();
        this.style.borderColor = '';
    });

    uploadDropZone.addEventListener('drop', function(e) {
        e.preventDefault();
        this.style.borderColor = '';

        const files = e.dataTransfer.files;
        fileInput.files = files;
        updateSelectedFilesList(files);
    });

    fileInput.addEventListener('change', function() {
        updateSelectedFilesList(this.files);
    });

    function updateSelectedFilesList(files) {
        if (files.length === 0) {
            selectedFilesContainer.style.display = 'none';
            return;
        }

        selectedFilesContainer.style.display = 'block';
        selectedFilesList.innerHTML = '';

        Array.from(files).forEach((file, index) => {
            const fileItem = document.createElement('div');
            fileItem.className = 'd-flex justify-content-between align-items-center py-2 border-bottom';
            fileItem.innerHTML = `
                <div class="d-flex align-items-center">
                    <i class="bi bi-file-earmark me-2"></i>
                    <div>
                        <div class="fw-medium">${escapeHtml(file.name)}</div>
                        <small class="text-muted">${formatSize(file.size)}</small>
                    </div>
                </div>
                <button class="btn btn-sm btn-outline-danger remove-file" data-index="${index}">
                    <i class="bi bi-x"></i>
                </button>
            `;
            selectedFilesList.appendChild(fileItem);
        });

        document.querySelectorAll('.remove-file').forEach((btn) => {
            btn.addEventListener('click', function() {
                const index = parseInt(this.getAttribute('data-index'), 10);
                removeFileFromInput(index);
            });
        });
    }

    function removeFileFromInput(indexToRemove) {
        const dt = new DataTransfer();
        const files = fileInput.files;

        Array.from(files).forEach((file, index) => {
            if (index !== indexToRemove) {
                dt.items.add(file);
            }
        });

        fileInput.files = dt.files;
        updateSelectedFilesList(fileInput.files);
    }

    document.getElementById('upload-btn').addEventListener('click', async function() {
        const files = Array.from(fileInput.files || []);
        const targetDevice = document.getElementById('target-device').value;
        const targetPath = document.getElementById('target-path').value;

        if (files.length === 0) {
            showAlert('请选择要上传的文件', 'warning');
            return;
        }

        if (!targetDevice || !targetPath) {
            showAlert('请选择目标设备并填写路径', 'warning');
            return;
        }
        const trustMessage = getDeviceTrustGuardMessage(targetDevice, '上传内容');
        if (trustMessage) {
            showAlert(trustMessage, 'warning');
            return;
        }

        const uploadBtn = this;
        const originalText = uploadBtn.innerHTML;
        const progressContainer = document.getElementById('upload-progress');
        const progressBar = document.getElementById('upload-progress-bar');
        const progressPercentage = document.getElementById('upload-percentage');

        uploadBtn.innerHTML = '<i class="bi bi-hourglass-split me-1"></i>上传中...';
        uploadBtn.disabled = true;
        progressContainer.style.display = 'block';

        let successCount = 0;
        let failCount = 0;

        try {
            for (let i = 0; i < files.length; i++) {
                const file = files[i];
                const currentProgress = (i / files.length) * 100;
                progressBar.style.width = currentProgress + '%';
                progressPercentage.textContent = `${Math.round(currentProgress)}% (${i}/${files.length})`;

                try {
                    const perFileProgress = (chunkPercent) => {
                        const totalPercent = ((i + chunkPercent / 100) / files.length) * 100;
                        progressBar.style.width = totalPercent + '%';
                        progressPercentage.textContent = `${Math.round(totalPercent)}% (${i + 1}/${files.length})`;
                    };
                    const ok = await uploadSingleFileByChunk(file, targetDevice, targetPath, perFileProgress);
                    if (ok) { successCount += 1; } else { failCount += 1; }
                } catch (_uploadError) {
                    failCount += 1;
                }
            }

            progressBar.style.width = '100%';
            progressPercentage.textContent = '100%';

            if (failCount === 0) {
                showAlert(`所有文件上传成功 (${successCount} 个)`, 'success');
            } else if (successCount === 0) {
                showAlert(`所有文件上传失败 (${failCount} 个)`, 'danger');
            } else {
                showAlert(`部分上传成功，成功 ${successCount}，失败 ${failCount}`, 'warning');
            }

            if (successCount > 0) {
                fileInput.value = '';
                selectedFilesContainer.style.display = 'none';
                setTimeout(() => {
                    const modal = bootstrap.Modal.getInstance(document.getElementById('upload-modal'));
                    if (modal) {
                        modal.hide();
                    }
                }, 500);
                loadFiles();
            }
        } catch (error) {
            console.error('上传过程发生错误:', error);
            showAlert('上传过程发生错误', 'danger');
        } finally {
            uploadBtn.innerHTML = originalText;
            uploadBtn.disabled = false;
            setTimeout(() => {
                progressContainer.style.display = 'none';
                progressBar.style.width = '0%';
                progressPercentage.textContent = '0%';
            }, 1200);
        }
    });
}

async function uploadSingleFileByChunk(file, targetDevice, targetPath, onProgress) {
    const sessionResp = await fetch('/api/transfer/chunk/session', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            sourceDevice: 'web-client',
            targetDevice,
            targetPath,
            fileName: file.name,
            fileSize: file.size,
            chunkSize: DEFAULT_CHUNK_SIZE,
        }),
    });

    if (!sessionResp.ok) {
        return false;
    }
    const sessionData = await sessionResp.json();
    if (!sessionData.success || !sessionData.session || !sessionData.session.id) {
        return false;
    }

    const sessionId = sessionData.session.id;
    const totalChunks = Math.max(1, Math.ceil(file.size / DEFAULT_CHUNK_SIZE));

    for (let index = 0; index < totalChunks; index++) {
        const start = index * DEFAULT_CHUNK_SIZE;
        const end = Math.min(file.size, start + DEFAULT_CHUNK_SIZE);
        const blob = file.slice(start, end);
        const formData = new FormData();
        formData.append('chunk', blob, `${file.name}.part${index}`);

        const uploadResp = await fetch(`/api/transfer/chunk/session/${encodeURIComponent(sessionId)}/chunks/${index}`, {
            method: 'PUT',
            body: formData,
        });
        if (!uploadResp.ok) {
            return false;
        }

        const percent = ((index + 1) / totalChunks) * 100;
        onProgress(percent);
    }

    const completeResp = await fetch(`/api/transfer/chunk/session/${encodeURIComponent(sessionId)}/complete`, {
        method: 'POST',
    });
    if (!completeResp.ok) {
        return false;
    }
    const completeData = await completeResp.json();
    return !!completeData.success;
}

function initRelayPanel() {
    const refreshBtn = document.getElementById('relay-refresh-btn');
    if (refreshBtn) {
        refreshBtn.addEventListener('click', () => {
            loadRelayJobs();
            if (APP_STATE.accessContext.isLocalAdmin) {
                loadWhitelistRules();
            }
        });
    }

    const submitBtn = document.getElementById('relay-submit-btn');
    if (submitBtn) {
        submitBtn.addEventListener('click', submitRelayJob);
    }

    const textInput = document.getElementById('relay-text-content');
    if (textInput) {
        textInput.addEventListener('input', updateRelayTextMeta);
    }
    const textNameInput = document.getElementById('relay-text-name');
    if (textNameInput) {
        textNameInput.addEventListener('input', updateRelayTextMeta);
    }

    const statusFilter = document.getElementById('relay-status-filter');
    const searchInput = document.getElementById('relay-search-input');
    if (statusFilter) {
        statusFilter.addEventListener('change', renderRelayJobs);
    }
    if (searchInput) {
        searchInput.addEventListener('input', renderRelayJobs);
    }

    const selectAll = document.getElementById('relay-select-all');
    if (selectAll) {
        selectAll.addEventListener('change', () => {
            const checked = !!selectAll.checked;
            document.querySelectorAll('.relay-row-select').forEach((box) => {
                box.checked = checked;
                syncRelaySelection(box.dataset.id || '', checked);
            });
        });
    }

    const selectVisibleBtn = document.getElementById('relay-select-visible-btn');
    if (selectVisibleBtn) {
        selectVisibleBtn.addEventListener('click', toggleSelectVisibleRelayRows);
    }

    const retrySelectedBtn = document.getElementById('relay-retry-selected-btn');
    if (retrySelectedBtn) {
        retrySelectedBtn.addEventListener('click', retrySelectedRelayJobs);
    }

    const cancelSelectedBtn = document.getElementById('relay-cancel-selected-btn');
    if (cancelSelectedBtn) {
        cancelSelectedBtn.addEventListener('click', cancelSelectedRelayJobs);
    }
    const deleteSelectedBtn = document.getElementById('relay-delete-selected-btn');
    if (deleteSelectedBtn) {
        deleteSelectedBtn.addEventListener('click', deleteSelectedRelayJobs);
    }
    const cleanupBtn = document.getElementById('relay-cleanup-btn');
    if (cleanupBtn) {
        cleanupBtn.addEventListener('click', cleanupRelayJobs);
    }

    const previewDownloadBtn = document.getElementById('relay-preview-download-btn');
    if (previewDownloadBtn) {
        previewDownloadBtn.addEventListener('click', () => {
            const url = APP_STATE.relayPreview?.downloadUrl || '';
            if (url) {
                window.open(url, '_blank', 'noopener');
            }
        });
    }
    const previewClearBtn = document.getElementById('relay-preview-clear-btn');
    if (previewClearBtn) {
        previewClearBtn.addEventListener('click', clearRelayPreview);
    }

    const whitelistBtn = document.getElementById('whitelist-save-btn');
    if (whitelistBtn) {
        whitelistBtn.addEventListener('click', saveWhitelistRule);
    }
    const whitelistTarget = document.getElementById('whitelist-target-device');
    if (whitelistTarget) {
        whitelistTarget.addEventListener('change', () => {
            if (APP_STATE.accessContext.isLocalAdmin) {
                loadWhitelistRules();
            }
        });
    }

    if (APP_STATE.relayUiTimer) {
        clearInterval(APP_STATE.relayUiTimer);
    }
    APP_STATE.relayUiTimer = setInterval(updateRelayCountdownLabels, 1000);
    updateRelayTextMeta();
}

async function submitRelayJob() {
    if (!hasCapability('relay')) {
        showAlert('当前版本未启用中继能力', 'info');
        return;
    }
    const sourceDevice = document.getElementById('relay-source-device')?.value || '';
    const targetDevice = document.getElementById('relay-target-device')?.value || '';
    const targetPath = document.getElementById('relay-target-path')?.value || '/';
    const input = document.getElementById('relay-file-input');
    const file = input?.files?.[0];
    const textName = (document.getElementById('relay-text-name')?.value || '').trim();
    const textContent = document.getElementById('relay-text-content')?.value || '';
    const hasText = textContent.length > 0;
    const hasFile = !!file;

    if (hasText && hasFile) {
        showAlert('一次只能提交文件或文本，请先清掉其中一项。', 'warning');
        return;
    }

    if (hasText) {
        await submitRelayTextRecord(sourceDevice, textName, textContent);
        return;
    }

    if (!targetDevice) {
        showAlert('请选择中继目标设备', 'warning');
        return;
    }
    const trustMessage = getDeviceTrustGuardMessage(targetDevice, '接收中继内容');
    if (trustMessage) {
        showAlert(trustMessage, 'warning');
        return;
    }
    if (!file) {
        showAlert('请选择要中继的文件', 'warning');
        return;
    }

    const formData = new FormData();
    formData.append('sourceDevice', sourceDevice || 'web-client');
    formData.append('targetDevice', targetDevice);
    formData.append('targetPath', targetPath || '/');
    formData.append('fileName', file.name);
    formData.append('file', file);

    try {
        const resp = await fetch('/api/relay/jobs/', {
            method: 'POST',
            body: formData,
        });
        const data = await resp.json();
        if (!resp.ok || !data.success) {
            showAlert(data.error || '中继任务创建失败', 'danger');
            return;
        }
        showAlert('中继任务已提交', 'success');
        if (input) {
            input.value = '';
        }
        loadRelayJobs();
    } catch (error) {
        console.error('提交中继任务失败:', error);
        showAlert('提交中继任务失败', 'danger');
    }
}

async function submitRelayTextRecord(sourceDevice, fileName, content) {
    const formData = new FormData();
    formData.append('sourceDevice', sourceDevice || 'web-client');
    formData.append('fileName', fileName || '');
    formData.append('content', content);

    try {
        const resp = await fetch('/api/relay/jobs/text', {
            method: 'POST',
            body: formData,
        });
        const data = await resp.json();
        if (!resp.ok || !data.success) {
            showAlert(data.error || '临时文本提交失败', 'danger');
            return;
        }
        showAlert('临时文本已缓存到中继站', 'success');
        resetRelayTextDraft();
        loadRelayJobs();
    } catch (error) {
        console.error('提交临时文本失败:', error);
        showAlert('临时文本提交失败', 'danger');
    }
}

function updateRelayTextMeta() {
    const content = document.getElementById('relay-text-content')?.value || '';
    const name = (document.getElementById('relay-text-name')?.value || '').trim();
    const metaNode = document.getElementById('relay-text-meta');
    if (!metaNode) {
        return;
    }
    const chars = content.length;
    const lines = countTextLines(content);
    const displayName = name ? normalizeRelayTextRecordName(name) : '自动生成 .txt 记录名';
    metaNode.textContent = `${chars} 字符 · ${lines} 行 · ${displayName}。超过预览阈值时自动改为下载查看，避免浏览器卡住。`;
}

function resetRelayTextDraft() {
    const nameInput = document.getElementById('relay-text-name');
    const contentInput = document.getElementById('relay-text-content');
    if (nameInput) {
        nameInput.value = '';
    }
    if (contentInput) {
        contentInput.value = '';
    }
    updateRelayTextMeta();
}

function countTextLines(text) {
    if (!text) {
        return 0;
    }
    return text.split('\n').length;
}

function normalizeRelayTextRecordName(name) {
    const raw = String(name || '').trim();
    if (!raw) {
        return '自动生成 .txt 记录名';
    }
    return /\.txt$/i.test(raw) ? raw : `${raw}.txt`;
}

async function loadRelayJobs() {
    if (!hasCapability('relay')) {
        APP_STATE.allRelayJobs = [];
        APP_STATE.relaySelectedIds = [];
        updateRelayStats([]);
        renderRelayJobs();
        clearRelayPreview();
        return;
    }
    const list = document.getElementById('relay-job-list');
    if (!list) {
        return;
    }
    try {
        const resp = await fetch('/api/relay/jobs/');
        const data = await resp.json();
        APP_STATE.allRelayJobs = (data && Array.isArray(data.jobs)) ? data.jobs : [];
        syncRelaySelectionSet();
        syncRelayPreviewState();
        updateRelayStats(APP_STATE.allRelayJobs);
        renderRelayJobs();
    } catch (error) {
        console.error('加载中继任务失败:', error);
        list.innerHTML = '<tr><td colspan="12" class="table-empty-cell text-center text-danger">加载中继任务失败</td></tr>';
    }
}

function renderRelayJobs() {
    const list = document.getElementById('relay-job-list');
    if (!list) {
        return;
    }
    list.innerHTML = '';

    const statusFilter = document.getElementById('relay-status-filter')?.value || 'all';
    const keyword = (document.getElementById('relay-search-input')?.value || '').trim().toLowerCase();

    const filtered = APP_STATE.allRelayJobs.filter((job) => {
        const status = String(job.status || '');
        if (statusFilter !== 'all' && status !== statusFilter) {
            return false;
        }
        if (!keyword) {
            return true;
        }
        const target = `${job.id || ''} ${job.sourceDevice || ''} ${job.targetDevice || ''} ${job.fileName || ''} ${job.message || ''}`.toLowerCase();
        return target.includes(keyword);
    });

    if (!filtered.length) {
        list.innerHTML = '<tr><td colspan="12" class="table-empty-cell text-center text-muted">暂无匹配中继任务</td></tr>';
        return;
    }

    filtered
        .slice()
        .sort((a, b) => Number(b.updatedAt || 0) - Number(a.updatedAt || 0))
        .forEach((job) => {
            const row = document.createElement('tr');
            const jobId = String(job.id || '');
            const recordKind = String(job.recordKind || 'file');
            const selected = APP_STATE.relaySelectedIds.includes(jobId);
            const cacheActionReady = isRelayCacheActionAvailable(job);
            const allowRetry = recordKind === 'file' && !['delivered', 'expired'].includes(String(job.status || ''));
            const allowCancel = recordKind === 'file' && !['delivered', 'expired'].includes(String(job.status || ''));
            const allowPreview = isRelayTextPreviewAvailable(job);
            const cacheState = job.cacheAvailable
                ? (recordKind === 'text' ? '文本记录缓存可用' : '缓存可用')
                : '缓存缺失';
            row.innerHTML = `
                <td><input class="relay-row-select" type="checkbox" data-id="${escapeAttr(jobId)}" ${selected ? 'checked' : ''}></td>
                <td>${escapeHtml(jobId.slice(0, 12))}</td>
                <td>${escapeHtml(job.sourceDevice || '-')}</td>
                <td>${escapeHtml(job.targetDevice || '-')}</td>
                <td>
                    <div>${escapeHtml(job.fileName || '-')}</div>
                    <div class="section-note">${escapeHtml(recordKind === 'text' ? 'text record' : 'file relay')}</div>
                </td>
                <td><span class="badge status-${escapeAttr(job.status || 'pending')}">${escapeHtml(job.status || '-')}</span></td>
                <td>${formatSize(Number(job.bytes || 0))}</td>
                <td>${escapeHtml(String(job.attempts || 0))}</td>
                <td class="relay-ttl" data-expire="${escapeAttr(String(job.expiresAt || 0))}">${escapeHtml(formatTtlCountdown(Number(job.expiresAt || 0)))}</td>
                <td>${formatDate(Number(job.updatedAt || 0) * 1000)}</td>
                <td class="text-truncate" style="max-width: 220px;">
                    <div>${escapeHtml(job.message || '-')}</div>
                    <div class="relay-cache-meta ${job.cacheAvailable ? 'is-available' : 'is-missing'}">${escapeHtml(cacheState)}</div>
                </td>
                <td>
                    <div class="btn-group btn-group-sm relay-action-group">
                        <button class="btn btn-outline-secondary relay-preview-cache" data-id="${escapeAttr(jobId)}" ${allowPreview && cacheActionReady ? '' : 'disabled'}>查看文本</button>
                        <button class="btn btn-outline-secondary relay-download-cache" data-id="${escapeAttr(jobId)}" ${cacheActionReady ? '' : 'disabled'}>下载缓存</button>
                        <button class="btn btn-outline-primary relay-restore-cache" data-id="${escapeAttr(jobId)}" ${cacheActionReady ? '' : 'disabled'}>回流到当前目录</button>
                        <button class="btn btn-outline-secondary relay-retry" data-id="${escapeAttr(jobId)}" ${allowRetry ? '' : 'disabled'}>重试</button>
                        <button class="btn btn-outline-danger relay-cancel" data-id="${escapeAttr(jobId)}" ${allowCancel ? '' : 'disabled'}>取消</button>
                        <button class="btn btn-outline-danger relay-delete-record" data-id="${escapeAttr(jobId)}">删除记录</button>
                    </div>
                </td>
            `;
            list.appendChild(row);
        });

    const selectAll = document.getElementById('relay-select-all');
    if (selectAll) {
        const visibleIds = filtered.map((job) => String(job.id || ''));
        const allChecked = visibleIds.length > 0 && visibleIds.every((id) => APP_STATE.relaySelectedIds.includes(id));
        selectAll.checked = allChecked;
    }

    document.querySelectorAll('.relay-row-select').forEach((box) => {
        box.addEventListener('change', function() {
            const id = this.dataset.id || '';
            syncRelaySelection(id, !!this.checked);
            const selectAllBox = document.getElementById('relay-select-all');
            if (selectAllBox) {
                const rows = Array.from(document.querySelectorAll('.relay-row-select'));
                selectAllBox.checked = rows.length > 0 && rows.every((item) => item.checked);
            }
        });
    });

    document.querySelectorAll('.relay-retry').forEach((btn) => {
        btn.addEventListener('click', async function() {
            const id = this.getAttribute('data-id');
            await fetch(`/api/relay/jobs/${encodeURIComponent(id)}/retry`, { method: 'POST' });
            loadRelayJobs();
        });
    });
    document.querySelectorAll('.relay-download-cache').forEach((btn) => {
        btn.addEventListener('click', function() {
            const id = this.getAttribute('data-id');
            window.open(`/api/relay/jobs/${encodeURIComponent(id)}/cache`, '_blank', 'noopener');
        });
    });
    document.querySelectorAll('.relay-preview-cache').forEach((btn) => {
        btn.addEventListener('click', async function() {
            const id = this.getAttribute('data-id');
            await loadRelayPreview(id);
        });
    });
    document.querySelectorAll('.relay-restore-cache').forEach((btn) => {
        btn.addEventListener('click', async function() {
            const id = this.getAttribute('data-id');
            await restoreRelayCacheToCurrentDirectory(id);
        });
    });
    document.querySelectorAll('.relay-cancel').forEach((btn) => {
        btn.addEventListener('click', async function() {
            const id = this.getAttribute('data-id');
            await fetch(`/api/relay/jobs/${encodeURIComponent(id)}/cancel`, { method: 'POST' });
            loadRelayJobs();
        });
    });
    document.querySelectorAll('.relay-delete-record').forEach((btn) => {
        btn.addEventListener('click', async function() {
            const id = this.getAttribute('data-id');
            await deleteRelayRecord(id);
        });
    });
}

function updateRelayStats(jobs) {
    const total = jobs.length;
    let cached = 0;
    let pendingApproval = 0;
    let failed = 0;
    for (const job of jobs) {
        const status = String(job.status || '');
        if (status === 'cached' || status === 'dispatching') {
            cached += 1;
        } else if (status === 'pending_approval') {
            pendingApproval += 1;
        } else if (status === 'failed' || status === 'expired') {
            failed += 1;
        }
    }
    const totalChip = document.getElementById('relay-total-chip');
    const cachedChip = document.getElementById('relay-cached-chip');
    const pendingChip = document.getElementById('relay-pending-chip');
    const failedChip = document.getElementById('relay-failed-chip');
    if (totalChip) totalChip.textContent = `总任务 ${total}`;
    if (cachedChip) cachedChip.textContent = `缓存中 ${cached}`;
    if (pendingChip) pendingChip.textContent = `待审批 ${pendingApproval}`;
    if (failedChip) failedChip.textContent = `失败/过期 ${failed}`;
}

function syncRelaySelection(jobId, checked) {
    if (!jobId) {
        return;
    }
    const current = APP_STATE.relaySelectedIds;
    const idx = current.indexOf(jobId);
    if (checked && idx < 0) {
        current.push(jobId);
    } else if (!checked && idx >= 0) {
        current.splice(idx, 1);
    }
}

function syncRelaySelectionSet() {
    const existing = new Set(APP_STATE.allRelayJobs.map((job) => String(job.id || '')));
    APP_STATE.relaySelectedIds = APP_STATE.relaySelectedIds.filter((id) => existing.has(id));
}

function isRelayCacheActionAvailable(job) {
    const status = String(job.status || '');
    return !!job.cacheAvailable && ['cached', 'dispatching', 'pending_approval', 'failed'].includes(status);
}

function isRelayTextPreviewAvailable(job) {
    const recordKind = String(job?.recordKind || 'file');
    if (recordKind === 'text') {
        return true;
    }
    return /\.txt$/i.test(String(job?.fileName || ''));
}

async function restoreRelayCacheToCurrentDirectory(jobId) {
    const targetDevice = document.getElementById('device-selector')?.value || '';
    const targetPath = normalizePath(document.getElementById('current-path')?.value || '/');

    if (!targetDevice) {
        showAlert('请先在文件页选择回流目标设备', 'warning');
        return;
    }

    try {
        const response = await fetch(`/api/relay/jobs/${encodeURIComponent(jobId)}/restore`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                targetDevice,
                targetPath,
            }),
        });
        const data = await response.json();
        if (!response.ok || !data.success) {
            showAlert(data.message || data.error || '中继回流失败', 'danger');
            return;
        }
        showAlert('中继缓存已回流到当前目录', 'success');
        loadRelayJobs();
        if (APP_STATE.activePageId === 'files-page') {
            loadFiles();
        }
    } catch (error) {
        console.error('中继回流失败:', error);
        showAlert('中继回流失败', 'danger');
    }
}

function toggleSelectVisibleRelayRows() {
    const rows = Array.from(document.querySelectorAll('.relay-row-select'));
    if (!rows.length) {
        return;
    }
    const shouldSelect = rows.some((box) => !box.checked);
    rows.forEach((box) => {
        box.checked = shouldSelect;
        syncRelaySelection(box.dataset.id || '', shouldSelect);
    });
    const selectAll = document.getElementById('relay-select-all');
    if (selectAll) {
        selectAll.checked = shouldSelect;
    }
}

async function retrySelectedRelayJobs() {
    if (!hasCapability('relay')) {
        return;
    }
    if (!APP_STATE.relaySelectedIds.length) {
        showAlert('请先选择中继任务', 'warning');
        return;
    }
    try {
        const response = await fetch('/api/relay/jobs/batch-retry', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                ids: APP_STATE.relaySelectedIds,
            }),
        });
        const data = await response.json();
        if (!response.ok || !data.success) {
            showAlert(data.error || '批量重试失败', 'danger');
            return;
        }
        showAlert(`批量重试已处理 ${data.updated || 0} 条任务`, 'success');
        loadRelayJobs();
    } catch (error) {
        console.error('批量重试失败:', error);
        showAlert('批量重试失败', 'danger');
    }
}

async function cancelSelectedRelayJobs() {
    if (!hasCapability('relay')) {
        return;
    }
    if (!APP_STATE.relaySelectedIds.length) {
        showAlert('请先选择中继任务', 'warning');
        return;
    }
    try {
        const response = await fetch('/api/relay/jobs/batch-cancel', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                ids: APP_STATE.relaySelectedIds,
            }),
        });
        const data = await response.json();
        if (!response.ok || !data.success) {
            showAlert(data.error || '批量取消失败', 'danger');
            return;
        }
        APP_STATE.relaySelectedIds = [];
        showAlert(`批量取消已处理 ${data.updated || 0} 条任务`, 'success');
        loadRelayJobs();
    } catch (error) {
        console.error('批量取消失败:', error);
        showAlert('批量取消失败', 'danger');
    }
}

async function deleteSelectedRelayJobs() {
    if (!hasCapability('relay')) {
        return;
    }
    if (!APP_STATE.relaySelectedIds.length) {
        showAlert('请先选择中继记录', 'warning');
        return;
    }
    if (!window.confirm('删除记录只会移除中继记录与临时缓存，不会删除设备上的实际文件。确定继续吗？')) {
        return;
    }
    try {
        const response = await fetch('/api/relay/jobs/batch-delete', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                ids: APP_STATE.relaySelectedIds,
            }),
        });
        const data = await response.json();
        if (!response.ok || !data.success) {
            showAlert(data.error || '批量删除记录失败', 'danger');
            return;
        }
        APP_STATE.relaySelectedIds = [];
        showAlert(`已删除 ${data.updated || 0} 条中继记录`, 'success');
        loadRelayJobs();
    } catch (error) {
        console.error('批量删除记录失败:', error);
        showAlert('批量删除记录失败', 'danger');
    }
}

async function deleteRelayRecord(jobId) {
    if (!jobId) {
        return;
    }
    if (!window.confirm('删除记录只会移除中继记录与临时缓存，不会删除设备上的实际文件。确定删除吗？')) {
        return;
    }
    try {
        const response = await fetch(`/api/relay/jobs/${encodeURIComponent(jobId)}`, {
            method: 'DELETE',
        });
        const data = await response.json();
        if (!response.ok || !data.success) {
            showAlert(data.error || data.message || '删除记录失败', 'danger');
            return;
        }
        showAlert(data.message || '记录已删除', 'success');
        loadRelayJobs();
    } catch (error) {
        console.error('删除中继记录失败:', error);
        showAlert('删除记录失败', 'danger');
    }
}

async function cleanupRelayJobs() {
    if (!hasCapability('relay')) {
        return;
    }
    const status = document.getElementById('relay-cleanup-status')?.value || '';
    const olderThanHours = Number(document.getElementById('relay-cleanup-hours')?.value || '0');
    const payload = {
        status,
    };
    if (olderThanHours > 0) {
        payload.olderThanHours = olderThanHours;
    }

    try {
        const response = await fetch('/api/relay/jobs/cleanup', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(payload),
        });
        const data = await response.json();
        if (!response.ok || !data.success) {
            showAlert(data.error || '中继清理失败', 'danger');
            return;
        }
        showAlert(`中继清理完成，已移除 ${data.removed || 0} 条任务`, 'success');
        loadRelayJobs();
    } catch (error) {
        console.error('中继清理失败:', error);
        showAlert('中继清理失败', 'danger');
    }
}

function updateRelayCountdownLabels() {
    document.querySelectorAll('.relay-ttl').forEach((cell) => {
        const expire = Number(cell.dataset.expire || '0');
        cell.textContent = formatTtlCountdown(expire);
    });
}

function syncRelayPreviewState() {
    const previewId = APP_STATE.relayPreview?.jobId || '';
    if (!previewId) {
        return;
    }
    const current = APP_STATE.allRelayJobs.find((job) => String(job.id || '') === previewId);
    if (!current || !current.cacheAvailable) {
        clearRelayPreview();
    }
}

async function loadRelayPreview(jobId) {
    if (!jobId) {
        clearRelayPreview();
        return;
    }
    try {
        const response = await fetch(`/api/relay/jobs/${encodeURIComponent(jobId)}/preview`);
        const data = await response.json();
        if (!response.ok || !data.success) {
            showAlert(data.error || '文本预览加载失败', 'danger');
            return;
        }
        APP_STATE.relayPreview = data;
        renderRelayPreview(data);
    } catch (error) {
        console.error('加载中继文本预览失败:', error);
        showAlert('文本预览加载失败', 'danger');
    }
}

function clearRelayPreview() {
    APP_STATE.relayPreview = null;
    renderRelayPreview(null);
}

function renderRelayPreview(preview) {
    const wrap = document.getElementById('relay-preview-wrap');
    const metaNode = document.getElementById('relay-preview-meta');
    const emptyNode = document.getElementById('relay-preview-empty');
    const textNode = document.getElementById('relay-preview-text');
    const downloadBtn = document.getElementById('relay-preview-download-btn');
    const clearBtn = document.getElementById('relay-preview-clear-btn');
    if (!wrap || !metaNode || !emptyNode || !textNode || !downloadBtn || !clearBtn) {
        return;
    }

    textNode.hidden = true;
    textNode.textContent = '';
    emptyNode.hidden = false;
    downloadBtn.hidden = true;
    clearBtn.hidden = true;

    if (!preview) {
        metaNode.textContent = '选择一条 `.txt` 记录后在这里查看';
        emptyNode.textContent = '临时文本和 `.txt` 缓存会在这里显示；超过预览阈值时会建议直接下载。';
        return;
    }

    const lineCount = Number(preview.lineCount || 0);
    const metaParts = [
        preview.name || 'relay.txt',
        `${formatSize(Number(preview.size || 0))}`,
    ];
    if (lineCount > 0) {
        metaParts.push(`${lineCount} 行`);
    }
    if (preview.encoding) {
        metaParts.push(String(preview.encoding));
    }
    metaNode.textContent = metaParts.join(' · ');
    downloadBtn.hidden = !preview.downloadUrl;
    clearBtn.hidden = false;

    if (!preview.canPreview) {
        emptyNode.textContent = preview.message || '当前缓存仅支持文本预览，请直接下载查看。';
        return;
    }

    if (!preview.inlineAllowed) {
        emptyNode.textContent = preview.message || '文本超过预览阈值，请直接下载查看。';
        return;
    }

    textNode.hidden = false;
    emptyNode.hidden = true;
    textNode.textContent = preview.content || '';
}

function formatTtlCountdown(expiresAtSec) {
    const expiresAt = Number(expiresAtSec || 0);
    if (!expiresAt) {
        return '-';
    }
    const now = Math.floor(Date.now() / 1000);
    let remain = expiresAt - now;
    if (remain <= 0) {
        return '已过期';
    }
    const days = Math.floor(remain / 86400);
    remain -= days * 86400;
    const hours = Math.floor(remain / 3600);
    remain -= hours * 3600;
    const minutes = Math.floor(remain / 60);
    if (days > 0) {
        return `${days}天${hours}小时`;
    }
    if (hours > 0) {
        return `${hours}小时${minutes}分`;
    }
    return `${minutes}分`;
}

async function loadWhitelistRules() {
    if (!hasCapability('whitelist')) {
        const list = document.getElementById('whitelist-rules-list');
        if (list) {
            list.innerHTML = '<div class="text-muted small">当前版本未启用白名单能力</div>';
        }
        return;
    }
    const list = document.getElementById('whitelist-rules-list');
    if (!list) {
        return;
    }
    try {
        const target = document.getElementById('whitelist-target-device')?.value || '';
        const resp = await fetch(`/api/whitelist/rules?targetDevice=${encodeURIComponent(target)}`);
        const data = await resp.json();
        const rules = (data && Array.isArray(data.rules)) ? data.rules : [];
        if (!rules.length) {
            list.innerHTML = '<div class="text-muted small">暂无白名单规则</div>';
            return;
        }
        list.innerHTML = rules.map((rule) => `
            <div class="small mb-2 whitelist-rule-row">
                <div class="d-flex align-items-center justify-content-between gap-2 flex-wrap">
                    <div>
                        <i class="bi bi-shield-check me-1"></i>
                        ${escapeHtml(rule.sourceDevice || '*')} -> ${escapeHtml(rule.targetDevice || '-')}
                        <span class="badge ${rule.enabled ? 'bg-success' : 'bg-secondary'} ms-1">${rule.enabled ? 'enabled' : 'disabled'}</span>
                    </div>
                    <div class="btn-group btn-group-sm">
                        <button class="btn btn-outline-secondary whitelist-toggle"
                            data-source-device="${escapeAttr(rule.sourceDevice || '*')}"
                            data-target-device="${escapeAttr(rule.targetDevice || '')}"
                            data-enabled="${rule.enabled ? 'true' : 'false'}">
                            ${rule.enabled ? '禁用' : '启用'}
                        </button>
                        <button class="btn btn-outline-danger whitelist-remove"
                            data-source-device="${escapeAttr(rule.sourceDevice || '*')}"
                            data-target-device="${escapeAttr(rule.targetDevice || '')}">
                            删除
                        </button>
                    </div>
                </div>
            </div>
        `).join('');

        document.querySelectorAll('.whitelist-toggle').forEach((btn) => {
            btn.addEventListener('click', async function() {
                const sourceDevice = this.getAttribute('data-source-device') || '*';
                const targetDevice = this.getAttribute('data-target-device') || '';
                const enabled = (this.getAttribute('data-enabled') || 'false') !== 'true';
                await toggleWhitelistRule(sourceDevice, targetDevice, enabled);
            });
        });

        document.querySelectorAll('.whitelist-remove').forEach((btn) => {
            btn.addEventListener('click', async function() {
                const sourceDevice = this.getAttribute('data-source-device') || '*';
                const targetDevice = this.getAttribute('data-target-device') || '';
                await deleteWhitelistRule(sourceDevice, targetDevice);
            });
        });
    } catch (error) {
        console.error('加载白名单失败:', error);
        list.innerHTML = '<div class="text-danger small">加载白名单失败</div>';
    }
}

async function saveWhitelistRule() {
    if (!hasCapability('whitelist')) {
        return;
    }
    if (!APP_STATE.accessContext.isLocalAdmin) {
        showAlert('仅本机管理员可维护白名单', 'warning');
        return;
    }
    const sourceDevice = document.getElementById('whitelist-source-device')?.value || '*';
    const targetDevice = document.getElementById('whitelist-target-device')?.value || '';
    const enabled = !!document.getElementById('whitelist-enabled')?.checked;
    if (!targetDevice) {
        showAlert('请选择白名单目标设备', 'warning');
        return;
    }
    const trustMessage = getDeviceTrustGuardMessage(targetDevice, '进入白名单');
    if (trustMessage) {
        showAlert(trustMessage, 'warning');
        return;
    }

    try {
        const resp = await fetch('/api/whitelist/rules', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                sourceDevice,
                targetDevice,
                enabled,
            }),
        });
        const data = await resp.json();
        if (!resp.ok || !data.success) {
            showAlert(data.error || '保存白名单失败', 'danger');
            return;
        }
        showAlert('白名单规则已保存', 'success');
        loadWhitelistRules();
    } catch (error) {
        console.error('保存白名单失败:', error);
        showAlert('保存白名单失败', 'danger');
    }
}

async function toggleWhitelistRule(sourceDevice, targetDevice, enabled) {
    if (!hasCapability('whitelist')) {
        return;
    }
    if (!APP_STATE.accessContext.isLocalAdmin) {
        showAlert('仅本机管理员可维护白名单', 'warning');
        return;
    }
    try {
        const resp = await fetch('/api/whitelist/rules/toggle', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                sourceDevice,
                targetDevice,
                enabled,
            }),
        });
        const data = await resp.json();
        if (!resp.ok || !data.success) {
            showAlert(data.error || '白名单更新失败', 'danger');
            return;
        }
        showAlert(`白名单规则已${enabled ? '启用' : '禁用'}`, 'success');
        loadWhitelistRules();
    } catch (error) {
        console.error('白名单更新失败:', error);
        showAlert('白名单更新失败', 'danger');
    }
}

async function deleteWhitelistRule(sourceDevice, targetDevice) {
    if (!hasCapability('whitelist')) {
        return;
    }
    if (!APP_STATE.accessContext.isLocalAdmin) {
        showAlert('仅本机管理员可维护白名单', 'warning');
        return;
    }
    try {
        const resp = await fetch('/api/whitelist/rules', {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                sourceDevice,
                targetDevice,
            }),
        });
        const data = await resp.json();
        if (!resp.ok || !data.success) {
            showAlert(data.message || data.error || '白名单删除失败', 'danger');
            return;
        }
        showAlert('白名单规则已删除', 'success');
        loadWhitelistRules();
    } catch (error) {
        console.error('白名单删除失败:', error);
        showAlert('白名单删除失败', 'danger');
    }
}

function initTransferModal() {
    const refreshBtn = document.getElementById('file-inspector-refresh-btn');
    const downloadBtn = document.getElementById('transfer-download-btn');
    const previewOpenBtn = document.getElementById('transfer-preview-open-btn');
    const sourceDevice = document.getElementById('source-device');
    const sourcePath = document.getElementById('source-path');
    const targetDevice = document.getElementById('transfer-target-device');
    const targetPath = document.getElementById('transfer-target-path');
    if (refreshBtn) {
        refreshBtn.addEventListener('click', () => {
            const sourceDevice = document.getElementById('source-device').value;
            const sourcePath = document.getElementById('source-path').value;
            if (sourceDevice && sourcePath) {
                showTransferModalWithFile(sourceDevice, sourcePath);
            }
        });
    }
    if (downloadBtn) {
        downloadBtn.addEventListener('click', triggerTransferSourceDownload);
    }
    if (previewOpenBtn) {
        previewOpenBtn.addEventListener('click', () => {
            const previewUrl = APP_STATE.transferPreview?.previewUrl || '';
            if (!previewUrl) {
                showAlert('当前没有可打开的预览内容', 'warning');
                return;
            }
            window.open(previewUrl, '_blank', 'noopener');
        });
    }
    if (targetDevice) {
        targetDevice.addEventListener('change', renderTransferTargetSummary);
    }
    if (targetPath) {
        targetPath.addEventListener('input', renderTransferTargetSummary);
    }
    if (sourceDevice) {
        sourceDevice.addEventListener('change', () => {
            renderTransferTargetSummary();
            updateTransferDownloadAction();
        });
    }
    if (sourcePath) {
        sourcePath.addEventListener('input', () => {
            renderTransferTargetSummary();
            updateTransferDownloadAction();
        });
    }

    const modalEl = document.getElementById('transfer-modal');
    if (modalEl) {
        modalEl.addEventListener('hidden.bs.modal', resetTransferPreview);
    }

    document.getElementById('transfer-btn').addEventListener('click', async function() {
        const sourceDevice = document.getElementById('source-device').value;
        const sourcePath = document.getElementById('source-path').value;
        const targetDevice = document.getElementById('transfer-target-device').value;
        const targetPath = document.getElementById('transfer-target-path').value;

        if (!sourceDevice || !sourcePath) {
            showAlert('请选择源文件', 'warning');
            return;
        }

        if (!targetDevice) {
            showAlert('请选择目标设备', 'warning');
            return;
        }
        const sourceTrustMessage = getDeviceTrustGuardMessage(sourceDevice, '发起传输');
        if (sourceTrustMessage) {
            showAlert(sourceTrustMessage, 'warning');
            return;
        }
        const targetTrustMessage = getDeviceTrustGuardMessage(targetDevice, '接收传输');
        if (targetTrustMessage) {
            showAlert(targetTrustMessage, 'warning');
            return;
        }

        try {
            const response = await fetch('/api/tasks/', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    sourceDevice,
                    targetDevice,
                    filePath: sourcePath,
                    targetPath,
                }),
            });

            const result = await response.json();

            if (result.error) {
                showAlert(`创建任务失败: ${result.error}`, 'danger');
            } else {
                showAlert('传输任务已创建', 'success');
                const modal = bootstrap.Modal.getInstance(document.getElementById('transfer-modal'));
                if (modal) {
                    modal.hide();
                }
                showPage('transfers-page');
            }
        } catch (error) {
            console.error('创建传输任务失败:', error);
            showAlert('创建传输任务失败', 'danger');
        }
    });
}

async function loadTasks() {
    try {
        const response = await fetch('/api/tasks/');
        const tasks = await response.json();
        APP_STATE.allTasks = Array.isArray(tasks) ? tasks : [];
        updateTaskStats(APP_STATE.allTasks);
        renderTaskList();
    } catch (error) {
        console.error('加载任务列表失败:', error);
        document.getElementById('task-list').innerHTML = '<tr><td colspan="6" class="text-center text-danger">加载任务列表失败</td></tr>';
    }
}

function resolveTaskDownloadPath(task) {
    if (!task || task.sourceIsDir) {
        return '';
    }
    const targetRoot = normalizePath(task.targetPath || '/');
    const fileName = task?.metadata?.name || basenamePath(task.filePath || '');
    if (!fileName) {
        return '';
    }
    const lastSegment = basenamePath(targetRoot);
    if (lastSegment && lastSegment.includes('.')) {
        return targetRoot;
    }
    if (targetRoot === '/') {
        return `/${fileName}`;
    }
    return normalizePath(`${targetRoot}/${fileName}`);
}

function renderTaskList() {
    const taskList = document.getElementById('task-list');
    if (!taskList) {
        return;
    }

    const keyword = (document.getElementById('task-search-input')?.value || '').trim().toLowerCase();
    const statusFilter = document.getElementById('task-status-filter')?.value || 'all';

    const filtered = APP_STATE.allTasks.filter((task) => {
        const statusMatch = statusFilter === 'all' || task.status === statusFilter;
        if (!statusMatch) {
            return false;
        }
        if (!keyword) {
            return true;
        }
        const sourceBinding = getConnectorBinding(task.sourceDevice);
        const targetBinding = getConnectorBinding(task.targetDevice);
        const target = `${task.id} ${task.sourceDevice} ${task.targetDevice} ${task.filePath} ${task.protocol || ''} ${sourceBinding.connectorType} ${targetBinding.connectorType}`.toLowerCase();
        return target.includes(keyword);
    });

    taskList.innerHTML = '';

    if (filtered.length === 0) {
        taskList.innerHTML = '<tr><td colspan="6" class="table-empty-cell text-center">暂无匹配任务</td></tr>';
        return;
    }

    filtered.forEach((task) => {
        const sourceBinding = getConnectorBinding(task.sourceDevice);
        const targetBinding = getConnectorBinding(task.targetDevice);
        const protocolLabel = task.protocol || 'http';
        const row = document.createElement('tr');
        const targetPath = task.targetPath ? `<div class="small text-muted mt-1">目标目录: ${escapeHtml(task.targetPath)}</div>` : '';
        const isDirTask = !!task.sourceIsDir;
        const canDownload = task.status === 'completed' && !isDirTask;
        const downloadPath = canDownload ? resolveTaskDownloadPath(task) : '';
        const progressMeta = isDirTask
            ? `${Number(task.completedEntries || 0)}/${Number(task.totalEntries || 0)} 项 · ${formatSize(Number(task.transferredBytes || 0))}${Number(task.totalBytes || 0) > 0 ? ` / ${formatSize(Number(task.totalBytes || 0))}` : ''}`
            : `${formatSize(Number(task.transferredBytes || 0))}${Number(task.totalBytes || 0) > 0 ? ` / ${formatSize(Number(task.totalBytes || 0))}` : ''}`;
        const currentItem = task.currentItem
            ? `<div class="small text-muted mt-1">当前项: ${escapeHtml(task.currentItem)}</div>`
            : '';
        row.innerHTML = `
            <td><span class="task-id">${escapeHtml(task.id.substring(0, 8))}</span></td>
            <td>
                <div class="transfer-direction">
                    <span class="transfer-device source">${escapeHtml(task.sourceDevice)}</span>
                    <i class="bi bi-arrow-right transfer-arrow"></i>
                    <span class="transfer-device target">${escapeHtml(task.targetDevice)}</span>
                </div>
                <div class="transfer-route-meta">
                    <span class="connector-pill ${escapeAttr(getConnectorDriverStateClass(sourceBinding))}">${escapeHtml(getConnectorShortName(sourceBinding))}</span>
                    <span class="task-kind-chip">${escapeHtml(protocolLabel)}</span>
                    <span class="connector-pill ${escapeAttr(getConnectorDriverStateClass(targetBinding))}">${escapeHtml(getConnectorShortName(targetBinding))}</span>
                </div>
            </td>
            <td>
                <span class="task-file-path">${escapeHtml(task.filePath)}</span>
                <div class="task-kind-chip mt-1">${isDirTask ? '目录任务' : '文件任务'}</div>
                ${targetPath}
                ${currentItem}
            </td>
            <td><span class="badge status-${escapeAttr(task.status)}">${getStatusText(task.status)}</span></td>
            <td>
                <div class="progress">
                    <div class="progress-bar" role="progressbar" style="width: ${task.progress}%">${Math.round(task.progress)}%</div>
                </div>
                <div class="transfer-progress-meta mt-1">${escapeHtml(progressMeta)}</div>
            </td>
            <td>
                <div class="row-action-group justify-content-end">
                    ${canDownload
                        ? `<button class="btn btn-sm btn-primary task-download" data-device="${escapeAttr(task.targetDevice || '')}" data-path="${escapeAttr(downloadPath)}">下载</button>`
                        : ''
                    }
                    ${task.status === 'pending' || task.status === 'running'
                        ? `<button class="btn btn-sm btn-outline-danger cancel-task" data-task-id="${escapeAttr(task.id)}">取消</button>`
                        : (!canDownload ? '<button class="btn btn-sm btn-outline-secondary" disabled>已完成</button>' : '')
                    }
                </div>
            </td>
        `;
        taskList.appendChild(row);
    });

    document.querySelectorAll('.task-download').forEach((btn) => {
        btn.addEventListener('click', function() {
            const deviceId = this.getAttribute('data-device') || '';
            const path = this.getAttribute('data-path') || '';
            if (!deviceId || !path) {
                showAlert('当前任务缺少可下载路径', 'warning');
                return;
            }
            window.open(`/api/fs/download?device=${encodeURIComponent(deviceId)}&path=${encodeURIComponent(path)}`);
        });
    });

    document.querySelectorAll('.cancel-task').forEach((btn) => {
        btn.addEventListener('click', async function() {
            const taskId = this.getAttribute('data-task-id');
            if (!confirm('确定要取消此任务吗？')) {
                return;
            }

            try {
                const response = await fetch(`/api/tasks/${encodeURIComponent(taskId)}`, {
                    method: 'DELETE',
                });
                const result = await response.json();
                if (result.error) {
                    showAlert(`取消任务失败: ${result.error}`, 'danger');
                } else {
                    showAlert('任务已取消', 'success');
                    loadTasks();
                }
            } catch (error) {
                console.error('取消任务失败:', error);
                showAlert('取消任务失败', 'danger');
            }
        });
    });
}

function updateTaskStats(tasks) {
    const total = tasks.length;
    let running = 0;
    let failed = 0;
    for (const task of tasks) {
        if (task.status === 'running') {
            running += 1;
        } else if (task.status === 'failed') {
            failed += 1;
        }
    }

    const totalChip = document.getElementById('tasks-total-chip');
    const runningChip = document.getElementById('tasks-running-chip');
    const failedChip = document.getElementById('tasks-failed-chip');

    if (totalChip) {
        totalChip.textContent = `任务 ${total}`;
    }
    if (runningChip) {
        runningChip.textContent = `运行中 ${running}`;
    }
    if (failedChip) {
        failedChip.textContent = `失败 ${failed}`;
    }
}

function initSettingsForm() {
    const form = document.getElementById('settings-form');
    form.addEventListener('submit', async function(e) {
        e.preventDefault();

        if (!APP_STATE.accessContext.isLocalAdmin) {
            showAlert('当前访问模式仅支持查看，保存配置请在本机访问', 'warning');
            return;
        }

        const payload = {
            tempDir: document.getElementById('temp-dir').value,
            maxConnections: Number(document.getElementById('max-connections').value || '100'),
        };
        if (hasCapability('peerTransfer')) {
            payload.securityMode = document.getElementById('enable-encryption').checked ? 'encrypted' : 'plain';
        }

        try {
            const response = await fetch('/admin/config', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(payload),
            });

            const result = await response.json();
            if (result.success) {
                showAlert('设置已保存（重启后生效）', 'success');
                loadAdminConfig();
            } else {
                showAlert(result.error || '保存设置失败', 'danger');
            }
        } catch (error) {
            console.error('保存设置失败:', error);
            showAlert('保存设置失败', 'danger');
        }
    });
}

function initAdminPanel() {
    const configForm = document.getElementById('admin-config-form');
    if (configForm) {
        configForm.addEventListener('submit', saveAdminConfig);
    }

    [
        'admin-discovery-advertise-ip',
        'admin-discovery-udp-port',
        'admin-enable-mdns',
        'admin-discovery-broadcast-enabled',
    ].forEach((id) => {
        const node = document.getElementById(id);
        if (!node) {
            return;
        }
        const eventName = node.type === 'checkbox' ? 'change' : 'input';
        node.addEventListener(eventName, refreshAdminDiscoveryHint);
    });

    const refreshLogsBtn = document.getElementById('admin-refresh-logs');
    if (refreshLogsBtn) {
        refreshLogsBtn.addEventListener('click', loadAdminLogs);
    }

    const refreshSystemBtn = document.getElementById('admin-refresh-system');
    if (refreshSystemBtn) {
        refreshSystemBtn.addEventListener('click', loadAdminSystemSummary);
    }

    [
        ['admin-copy-local-endpoint', 'endpoint'],
        ['admin-copy-node-id', 'node'],
        ['admin-copy-register-template', 'register'],
    ].forEach(([id, target]) => {
        const node = document.getElementById(id);
        if (!node) {
            return;
        }
        node.addEventListener('click', () => {
            handleAdminDiscoveryCopy(target);
        });
    });
}

function refreshAdminDiscoveryHint() {
    const hint = document.getElementById('admin-discovery-mode-hint');
    if (!hint) {
        return;
    }
    if (!hasCapability('activeDiscovery')) {
        hint.textContent = '当前运行态未启用主动发现，mDNS 与 UDP 广播会保持关闭；请在上方复制本机端点或登记命令发给其他设备手动接入。';
        return;
    }

    const advertiseIp = getInputValue('admin-discovery-advertise-ip').trim();
    const udpPort = getInputValue('admin-discovery-udp-port') || '19090';
    const mdnsSupported = hasCapability('mdnsDiscovery');
    const mdnsEnabled = mdnsSupported && isChecked('admin-enable-mdns');
    const broadcastEnabled = isChecked('admin-discovery-broadcast-enabled');
    const advertiseText = advertiseIp
        ? `通告IP固定为 ${advertiseIp}`
        : '通告IP留空时自动优先选择局域网 IPv4';
    const modeText = broadcastEnabled ? '允许 UDP 广播被发现' : '已关闭 UDP 广播被发现';
    const mdnsText = mdnsSupported
        ? (mdnsEnabled ? 'mDNS 已启用' : 'mDNS 已关闭')
        : 'mDNS 当前未接入';
    hint.textContent = `${advertiseText}，发现端口 ${udpPort}；${modeText}；${mdnsText}；发现到的设备需手动记住后才会登记。`;
}

function setAdminStatusText(id, value, fallback = '-') {
    const node = document.getElementById(id);
    if (!node) {
        return;
    }
    const text = String(value ?? '').trim();
    node.textContent = text || fallback;
}

async function copyTextToClipboard(text) {
    const content = String(text ?? '');
    if (!content.trim()) {
        return false;
    }

    if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
        try {
            await navigator.clipboard.writeText(content);
            return true;
        } catch (error) {
            console.warn('Clipboard API 写入失败，尝试降级复制:', error);
        }
    }

    const textarea = document.createElement('textarea');
    textarea.value = content;
    textarea.setAttribute('readonly', 'readonly');
    textarea.style.cssText = 'position: fixed; top: -9999px; left: -9999px; opacity: 0;';
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    textarea.setSelectionRange(0, textarea.value.length);

    let copied = false;
    try {
        copied = document.execCommand('copy');
    } catch (error) {
        console.warn('execCommand(copy) 失败:', error);
    }

    document.body.removeChild(textarea);
    return copied;
}

function getAdminDiscoveryNodeId(summary = APP_STATE.adminSystemSummary) {
    const value = String(summary?.discovery?.nodeId || summary?.nodeId || '').trim();
    return value && value !== '-' ? value : '';
}

function getAdminDiscoveryLocalEndpoint(summary = APP_STATE.adminSystemSummary) {
    const value = String(summary?.discovery?.localEndpoint || '').trim();
    return value && value !== '-' ? value : '';
}

function getAdminDiscoveryRegisterTemplate(summary = APP_STATE.adminSystemSummary) {
    const template = String(summary?.discovery?.registerDeviceCommand || '').trim();
    if (template) {
        return template;
    }

    const nodeId = getAdminDiscoveryNodeId(summary);
    const endpoint = getAdminDiscoveryLocalEndpoint(summary);
    if (!nodeId || !endpoint) {
        return '';
    }

    const lastColon = endpoint.lastIndexOf(':');
    if (lastColon <= 0 || lastColon >= endpoint.length - 1) {
        return '';
    }

    const host = endpoint.slice(0, lastColon).trim();
    const port = Number(endpoint.slice(lastColon + 1).trim());
    if (!host || !Number.isFinite(port) || port <= 0) {
        return '';
    }

    return `soonlnk register-device --id ${nodeId} --ip ${host} --port ${port} --connector soonlink-http --scheme http`;
}

function renderAdminDiscoveryActions(summary = APP_STATE.adminSystemSummary) {
    const templateNode = document.getElementById('admin-status-register-template');
    const noteNode = document.getElementById('admin-status-register-note');
    const template = getAdminDiscoveryRegisterTemplate(summary);

    if (templateNode) {
        templateNode.value = template || '等待状态加载后生成手动登记命令...';
    }

    if (noteNode) {
        noteNode.textContent = template
            ? '在另一台设备执行这条命令即可手动登记当前节点。'
            : '当前端点信息不足，暂无法生成手动登记命令。';
    }
}

async function handleAdminDiscoveryCopy(target) {
    let value = '';
    let successMessage = '';
    let emptyMessage = '';

    if (target === 'endpoint') {
        value = getAdminDiscoveryLocalEndpoint();
        successMessage = '本机端点已复制';
        emptyMessage = '当前没有可复制的本机端点';
    } else if (target === 'node') {
        value = getAdminDiscoveryNodeId();
        successMessage = '节点ID已复制';
        emptyMessage = '当前没有可复制的节点ID';
    } else if (target === 'register') {
        value = getAdminDiscoveryRegisterTemplate();
        successMessage = '手动登记命令已复制';
        emptyMessage = '当前还无法生成手动登记命令';
    }

    if (!value) {
        showAlert(emptyMessage, 'warning');
        return;
    }

    const copied = await copyTextToClipboard(value);
    if (copied) {
        showAlert(successMessage, 'success');
        return;
    }

    showAlert('复制失败，请手动选择文本复制', 'warning');
}

function renderAdminSystemSummary(data) {
    const discovery = data?.discovery || {};
    const supportsActiveDiscovery = !!discovery.supportsActiveDiscovery;
    const broadcastEnabled = supportsActiveDiscovery && !!discovery.udpBroadcastEnabled;
    const mdnsEnabled = supportsActiveDiscovery && !!discovery.mdnsEnabled;
    const noActiveChannels = supportsActiveDiscovery && !broadcastEnabled && !mdnsEnabled;
    const channelLabels = [];
    if (broadcastEnabled) {
        channelLabels.push('UDP广播');
    }
    if (mdnsEnabled) {
        channelLabels.push('mDNS');
    }
    const configuredAdvertiseIp = String(discovery.configuredAdvertiseIp || '').trim();
    const effectiveAdvertiseIp = String(discovery.effectiveAdvertiseIp || data?.primaryIp || '').trim();
    const localEndpoint = String(discovery.localEndpoint || '').trim();
    const heartbeatSeconds = Number(discovery.heartbeatSeconds || 0);
    const udpPort = Number(discovery.udpPort || 19090);

    setAdminStatusText('admin-status-node-id', discovery.nodeId || data?.nodeId || '-');
    setAdminStatusText('admin-status-advertise-ip', effectiveAdvertiseIp || '-');
    setAdminStatusText('admin-status-primary-ip', discovery.primaryIp || data?.primaryIp || '-');
    setAdminStatusText('admin-status-local-endpoint', localEndpoint || '-');
    setAdminStatusText('admin-status-configured-advertise-ip', configuredAdvertiseIp || '自动', '自动');
    setAdminStatusText(
        'admin-status-heartbeat',
        heartbeatSeconds > 0 ? `${heartbeatSeconds}s · UDP ${udpPort}` : `UDP ${udpPort}`,
    );

    setAdminStatusText('admin-discovery-mode-chip', supportsActiveDiscovery ? '简易互发现' : '被动发现');
    setAdminStatusText('admin-discovery-broadcast-chip', broadcastEnabled ? 'UDP广播开启' : 'UDP广播关闭');
    setAdminStatusText('admin-discovery-mdns-chip', mdnsEnabled ? 'mDNS开启' : 'mDNS关闭');

    ['admin-discovery-mode-chip', 'admin-discovery-broadcast-chip', 'admin-discovery-mdns-chip'].forEach((id) => {
        const node = document.getElementById(id);
        if (node) {
            node.classList.toggle('is-warning', noActiveChannels);
        }
    });

    renderAdminDiscoveryActions(data);

    const note = document.getElementById('admin-status-discovery-note');
    if (!note) {
        return;
    }
    note.classList.toggle('text-danger', noActiveChannels);
    if (!supportsActiveDiscovery) {
        note.textContent = '当前运行于被动发现模式，仅支持收到其他节点的发现信息和手动登记。';
        return;
    }
    if (channelLabels.length === 0) {
        note.textContent = `当前未开启主动发现通道，其他节点需要通过手动登记连接 ${localEndpoint || '本机端点'}；发现到的设备不会自动记住。`;
        return;
    }
    const advertiseModeText = configuredAdvertiseIp
        ? `按手动通告IP ${configuredAdvertiseIp} 对外公布`
        : '按自动选择的局域网地址对外公布';
    note.textContent = `当前通过 ${channelLabels.join(' + ')} 对外可发现，${advertiseModeText} ${effectiveAdvertiseIp || '本机地址'}；发现结果需手动记住后才会登记。`;
}

async function loadAdminSystemSummary() {
    if (!APP_STATE.accessContext.isLocalAdmin) {
        return;
    }

    try {
        const response = await fetch('/admin/api/system');
        const data = await response.json();
        if (!data.success) {
            throw new Error('admin system payload invalid');
        }
        APP_STATE.adminSystemSummary = data;
        renderAdminSystemSummary(data);
    } catch (error) {
        console.error('加载发现状态失败:', error);
        APP_STATE.adminSystemSummary = null;
        setAdminStatusText('admin-status-node-id', '-', '-');
        setAdminStatusText('admin-status-advertise-ip', '-', '-');
        setAdminStatusText('admin-status-primary-ip', '-', '-');
        setAdminStatusText('admin-status-local-endpoint', '-', '-');
        setAdminStatusText('admin-status-configured-advertise-ip', '自动', '自动');
        setAdminStatusText('admin-status-heartbeat', '-', '-');
        setAdminStatusText('admin-discovery-mode-chip', '状态未知');
        setAdminStatusText('admin-discovery-broadcast-chip', '状态未知');
        setAdminStatusText('admin-discovery-mdns-chip', '状态未知');
        ['admin-discovery-mode-chip', 'admin-discovery-broadcast-chip', 'admin-discovery-mdns-chip'].forEach((id) => {
            document.getElementById(id)?.classList.remove('is-warning');
        });
        renderAdminDiscoveryActions(null);
        const note = document.getElementById('admin-status-discovery-note');
        if (note) {
            note.classList.remove('text-danger');
            note.textContent = '发现状态加载失败，请稍后重试。';
        }
    }
}

async function loadAdminConfig() {
    if (!APP_STATE.accessContext.isLocalAdmin) {
        return;
    }

    try {
        const response = await fetch('/admin/config');
        const data = await response.json();

        if (!data.success || !data.config) {
            showAlert('加载管理配置失败', 'danger');
            return;
        }

        const cfg = data.config;

        setInputValue('admin-temp-dir', cfg.tempDir || '/tmp/soonlink');
        setInputValue('admin-log-dir', cfg.logDir || './logs');
        setInputValue('admin-local-root-dir', cfg.localRootDir || '');
        setInputValue('admin-max-connections', cfg.maxConnections || 100);
        setInputValue('admin-node-id', cfg.nodeId || '');
        if (hasCapability('peerTransfer')) {
            setInputValue('admin-security-mode', cfg.securityMode || 'plain');
        }
        if (hasCapability('activeDiscovery')) {
            setInputValue('admin-discovery-udp-port', cfg.discoveryUdpPort || 19090);
            setInputValue('admin-discovery-advertise-ip', cfg.discoveryAdvertiseIp || '');
            setChecked('admin-enable-mdns', !!cfg.enableMdns);
            setChecked('admin-discovery-broadcast-enabled', !!cfg.discoveryBroadcastEnabled);
            const mdnsCheckbox = document.getElementById('admin-enable-mdns');
            if (mdnsCheckbox) {
                mdnsCheckbox.disabled = !hasCapability('mdnsDiscovery');
            }
        }
        if (hasCapability('relay')) {
            setInputValue('admin-relay-retention-hours', cfg.relayRetentionHours || 24);
            setInputValue('admin-relay-limit-mode', cfg.relayLimitMode || 'fixed');
            setInputValue('admin-relay-cache-dir', cfg.relayCacheDir || './cache/relay');
            setInputValue('admin-relay-limit-bytes', cfg.relayLimitBytes || 21474836480);
            setInputValue('admin-relay-limit-percent', cfg.relayLimitPercent || 10);
            setChecked('admin-relay-enabled', !!cfg.relayEnabled);
        }
        if (hasCapability('favorites')) {
            setInputValue('admin-favorites-store-mode', cfg.favoritesStoreMode || 'cache');
            setInputValue('admin-favorites-toml-file', cfg.favoritesTomlFile || './config/favorites.toml');
        }
        if (hasCapability('whitelist')) {
            setInputValue('admin-whitelist-toml-file', cfg.whitelistTomlFile || './config/whitelist.toml');
        }
        setChecked('admin-local-auth-trust-proxy-headers', !!cfg.localAuthTrustProxyHeaders);

        setInputValue('temp-dir', cfg.tempDir || '/tmp/soonlink');
        setInputValue('max-connections', cfg.maxConnections || 100);
        setChecked('enable-encryption', hasCapability('peerTransfer') && (cfg.securityMode || 'plain') === 'encrypted');
        refreshAdminDiscoveryHint();
    } catch (error) {
        console.error('加载管理配置失败:', error);
        showAlert('加载管理配置失败', 'danger');
    }
}

async function saveAdminConfig(event) {
    event.preventDefault();

    if (!APP_STATE.accessContext.isLocalAdmin) {
        showAlert('仅本机管理员可修改配置', 'warning');
        return;
    }

    const payload = {
        tempDir: getInputValue('admin-temp-dir'),
        logDir: getInputValue('admin-log-dir'),
        localRootDir: getInputValue('admin-local-root-dir'),
        maxConnections: Number(getInputValue('admin-max-connections') || '100'),
        localAuthTrustProxyHeaders: isChecked('admin-local-auth-trust-proxy-headers'),
    };
    if (hasCapability('peerTransfer')) {
        payload.securityMode = getInputValue('admin-security-mode') || 'plain';
    }
    if (hasCapability('activeDiscovery')) {
        payload.discoveryUdpPort = Number(getInputValue('admin-discovery-udp-port') || '19090');
        payload.discoveryAdvertiseIp = getInputValue('admin-discovery-advertise-ip').trim();
        payload.enableMdns = hasCapability('mdnsDiscovery') && isChecked('admin-enable-mdns');
        payload.discoveryBroadcastEnabled = isChecked('admin-discovery-broadcast-enabled');
    }
    if (hasCapability('relay')) {
        payload.relayEnabled = isChecked('admin-relay-enabled');
        payload.relayCacheDir = getInputValue('admin-relay-cache-dir');
        payload.relayRetentionHours = Number(getInputValue('admin-relay-retention-hours') || '24');
        payload.relayLimitMode = getInputValue('admin-relay-limit-mode') || 'fixed';
        payload.relayLimitBytes = Number(getInputValue('admin-relay-limit-bytes') || '21474836480');
        payload.relayLimitPercent = Number(getInputValue('admin-relay-limit-percent') || '10');
    }
    if (hasCapability('favorites')) {
        payload.favoritesStoreMode = getInputValue('admin-favorites-store-mode') || 'cache';
        payload.favoritesTomlFile = getInputValue('admin-favorites-toml-file');
    }
    if (hasCapability('whitelist')) {
        payload.whitelistTomlFile = getInputValue('admin-whitelist-toml-file');
    }

    try {
        const response = await fetch('/admin/config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(payload),
        });

        const result = await response.json();
        if (result.success) {
            showAlert('管理配置已保存（重启后生效）', 'success');
            loadAdminConfig();
            loadAdminSystemSummary();
        } else {
            showAlert(result.error || '保存失败', 'danger');
        }
    } catch (error) {
        console.error('保存管理配置失败:', error);
        showAlert('保存管理配置失败', 'danger');
    }
}

async function loadAdminLogs() {
    const logBox = document.getElementById('admin-logs-list');
    if (!logBox || !APP_STATE.accessContext.isLocalAdmin) {
        return;
    }

    logBox.textContent = '日志加载中...';

    try {
        const response = await fetch('/admin/api/logs');
        const data = await response.json();

        if (!data.logs || data.logs.length === 0) {
            logBox.textContent = '暂无日志';
            return;
        }

        logBox.textContent = data.logs.map((entry) => {
            if (typeof entry === 'string') {
                return entry;
            }
            const stamp = formatDate((entry.timestamp || 0) * 1000);
            const level = String(entry.level || 'info').toUpperCase();
            const category = entry.category || '-';
            const message = entry.message || '';
            const details = entry.details ? ` | ${entry.details}` : '';
            return `${stamp} [${level}] [${category}] ${message}${details}`;
        }).join('\n');
    } catch (error) {
        console.error('加载日志失败:', error);
        logBox.textContent = '加载日志失败';
    }
}

function setInputValue(id, value) {
    const el = document.getElementById(id);
    if (el) {
        el.value = value;
    }
}

function getInputValue(id) {
    const el = document.getElementById(id);
    return el ? el.value : '';
}

function setChecked(id, value) {
    const el = document.getElementById(id);
    if (el) {
        el.checked = !!value;
    }
}

function isChecked(id) {
    const el = document.getElementById(id);
    return !!(el && el.checked);
}

function formatDate(timestamp) {
    if (!timestamp) {
        return '未知';
    }
    const date = new Date(timestamp);
    return date.toLocaleString();
}

function formatSize(bytes) {
    if (bytes === 0) {
        return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return (bytes / Math.pow(1024, i)).toFixed(2) + ' ' + units[i];
}

function getStatusText(status) {
    switch (status) {
        case 'pending': return '等待中';
        case 'running': return '传输中';
        case 'completed': return '已完成';
        case 'failed': return '失败';
        case 'cancelled': return '已取消';
        default: return status;
    }
}

function showAlert(message, type = 'info', duration = 4000) {
    let host = document.getElementById('soonlink-toast-host');
    if (!host) {
        host = document.createElement('div');
        host.id = 'soonlink-toast-host';
        host.className = 'soonlink-toast-host';
        document.body.appendChild(host);
    }

    const toast = document.createElement('div');
    toast.className = `soonlink-toast soonlink-toast-${type}`;
    toast.innerHTML = `
        <div class="soonlink-toast-body">${escapeHtml(message)}</div>
        <button type="button" class="soonlink-toast-close" aria-label="Close">&times;</button>
    `;

    host.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));

    const removeToast = () => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 220);
    };

    toast.querySelector('.soonlink-toast-close')?.addEventListener('click', removeToast);
    if (duration > 0) {
        setTimeout(removeToast, duration);
    }
}

function escapeHtml(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function escapeAttr(value) {
    return escapeHtml(value).replace(/`/g, '&#96;');
}

// ==================== 粘贴图片上传功能 ====================

let pasteImageData = null;

function initPasteUpload() {
    const pasteBtn = document.getElementById('paste-btn');
    if (pasteBtn) {
        pasteBtn.addEventListener('click', async () => {
            await handlePasteAction();
        });
    }

    // 全局粘贴事件监听
    document.addEventListener('paste', (event) => {
        // 只在文件页面激活时处理
        if (APP_STATE.activePageId !== 'files-page') {
            return;
        }

        handlePasteEvent(event);
    });

    // 粘贴预览模态框按钮事件
    const pasteDownloadBtn = document.getElementById('paste-download-btn');
    if (pasteDownloadBtn) {
        pasteDownloadBtn.addEventListener('click', downloadPastedImage);
    }

    const pasteUploadBtn = document.getElementById('paste-upload-btn');
    if (pasteUploadBtn) {
        pasteUploadBtn.addEventListener('click', uploadPastedImage);
    }
}

// 处理粘贴按钮点击
async function handlePasteAction() {
    try {
        // 方法1: 使用 Clipboard API (现代浏览器)
        if (navigator.clipboard && navigator.clipboard.read) {
            const imageData = await tryClipboardAPI();
            if (imageData) {
                showPastePreview(imageData);
                return;
            }
        }

        // 方法2: 创建临时输入框捕获粘贴内容
        const imageData = await tryTempInputMethod();
        if (imageData) {
            showPastePreview(imageData);
            return;
        }

        showAlert('剪贴板中没有图片内容，请先截图或复制图片\n\n提示: Windows 用户可按 Ctrl+V 粘贴', 'warning');
    } catch (error) {
        console.error('读取剪贴板失败:', error);
        if (error.name === 'NotAllowedError') {
            showAlert('无法访问剪贴板，请允许剪贴板权限后刷新页面重试\n\n或直接按 Ctrl+V 粘贴', 'warning');
        } else {
            showAlert('读取剪贴板失败，请直接按 Ctrl+V 粘贴图片', 'warning');
        }
    }
}

// 处理粘贴事件 (Ctrl+V)
function handlePasteEvent(event) {
    const items = event.clipboardData?.items;
    if (!items) return;

    let imageData = null;

    for (let i = 0; i < items.length; i++) {
        const item = items[i];

        // 检查是否是图片类型
        if (item.type.startsWith('image/')) {
            event.preventDefault();
            const blob = item.getAsFile();
            if (blob) {
                imageData = {
                    blob: blob,
                    type: item.type,
                    url: URL.createObjectURL(blob)
                };
            }
            break;
        }

        // Windows 截图工具有时会以文件形式存储
        if (item.kind === 'file' && item.type === 'Files') {
            const file = item.getAsFile();
            if (file && file.type.startsWith('image/')) {
                event.preventDefault();
                imageData = {
                    blob: file,
                    type: file.type,
                    url: URL.createObjectURL(file)
                };
                break;
            }
        }
    }

    if (imageData) {
        showPastePreview(imageData);
    }
}

// 尝试使用 Clipboard API
async function tryClipboardAPI() {
    try {
        const clipboardItems = await navigator.clipboard.read();

        for (const item of clipboardItems) {
            // 检查所有可用的类型
            const types = item.types;
            console.log('Clipboard types:', types);

            for (const type of types) {
                if (type.startsWith('image/')) {
                    const blob = await item.getType(type);
                    return {
                        blob: blob,
                        type: type,
                        url: URL.createObjectURL(blob)
                    };
                }

                // Windows 截图工具可能使用 text/html 包含 base64 图片
                if (type === 'text/html') {
                    const blob = await item.getType(type);
                    const html = await blob.text();
                    const base64Match = html.match(/src=["'](data:image\/[^"']+)["']/i);
                    if (base64Match) {
                        const dataUrl = base64Match[1];
                        const imageBlob = await dataURLtoBlob(dataUrl);
                        if (imageBlob) {
                            return {
                                blob: imageBlob,
                                type: imageBlob.type || 'image/png',
                                url: URL.createObjectURL(imageBlob)
                            };
                        }
                    }
                }
            }
        }
    } catch (error) {
        console.log('Clipboard API 尝试失败:', error.message);
    }
    return null;
}

// 尝试临时输入框方法 (兼容性方案)
async function tryTempInputMethod() {
    return new Promise((resolve) => {
        const tempInput = document.createElement('input');
        tempInput.type = 'text';
        tempInput.style.cssText = 'position: fixed; top: -9999px; left: -9999px; opacity: 0;';
        document.body.appendChild(tempInput);
        tempInput.focus();

        const handlePaste = async (e) => {
            const items = e.clipboardData?.items;
            if (!items) {
                cleanup();
                resolve(null);
                return;
            }

            for (let i = 0; i < items.length; i++) {
                const item = items[i];
                if (item.type.startsWith('image/')) {
                    const blob = item.getAsFile();
                    if (blob) {
                        cleanup();
                        resolve({
                            blob: blob,
                            type: item.type,
                            url: URL.createObjectURL(blob)
                        });
                        return;
                    }
                }
            }
            cleanup();
            resolve(null);
        };

        const cleanup = () => {
            tempInput.removeEventListener('paste', handlePaste);
            document.body.removeChild(tempInput);
        };

        tempInput.addEventListener('paste', handlePaste, { once: true });

        // 5秒超时
        setTimeout(() => {
            cleanup();
            resolve(null);
        }, 5000);

        // 提示用户粘贴
        showAlert('请按 Ctrl+V 粘贴图片...', 'info', 3000);
    });
}

// DataURL 转 Blob
async function dataURLtoBlob(dataURL) {
    try {
        const response = await fetch(dataURL);
        return await response.blob();
    } catch (error) {
        console.error('DataURL 转 Blob 失败:', error);
        return null;
    }
}

function showPastePreview(imageData) {
    pasteImageData = imageData;

    const previewImg = document.getElementById('paste-preview-image');
    const targetPathEl = document.getElementById('paste-target-path');
    const filenameInput = document.getElementById('paste-filename');
    const formatSelect = document.getElementById('paste-format');

    if (previewImg) {
        previewImg.src = imageData.url;
    }

    if (targetPathEl) {
        const currentPath = document.getElementById('current-path')?.value || '/';
        targetPathEl.textContent = currentPath;
    }

    // 生成默认文件名
    if (filenameInput) {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-').substring(0, 19);
        filenameInput.value = `screenshot-${timestamp}`;
    }

    // 根据图片类型选择默认格式
    if (formatSelect) {
        if (imageData.type === 'image/jpeg') {
            formatSelect.value = 'jpeg';
        } else if (imageData.type === 'image/webp') {
            formatSelect.value = 'webp';
        } else {
            formatSelect.value = 'png';
        }
    }

    // 显示模态框
    const modal = document.getElementById('paste-preview-modal');
    if (modal) {
        new bootstrap.Modal(modal).show();
    }
}

async function downloadPastedImage() {
    if (!pasteImageData) {
        showAlert('没有可下载的图片', 'warning');
        return;
    }

    const filenameInput = document.getElementById('paste-filename');
    const formatSelect = document.getElementById('paste-format');

    const filename = (filenameInput?.value || 'screenshot').replace(/\.(png|jpg|jpeg|webp)$/i, '');
    const format = formatSelect?.value || 'png';
    const extension = format === 'jpeg' ? 'jpg' : format;

    try {
        // 如果需要转换格式，使用 canvas
        let blob = pasteImageData.blob;

        if (pasteImageData.type !== `image/${format}` && format !== 'png') {
            blob = await convertImageFormat(pasteImageData.blob, format);
        }

        // 创建下载链接
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${filename}.${extension}`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);

        showAlert('图片已下载', 'success');
    } catch (error) {
        console.error('下载图片失败:', error);
        showAlert('下载图片失败', 'danger');
    }
}

async function uploadPastedImage() {
    if (!pasteImageData) {
        showAlert('没有可上传的图片', 'warning');
        return;
    }

    const deviceId = document.getElementById('device-selector')?.value;
    if (!deviceId) {
        showAlert('请先选择目标设备', 'warning');
        return;
    }

    const filenameInput = document.getElementById('paste-filename');
    const formatSelect = document.getElementById('paste-format');
    const currentPath = document.getElementById('current-path')?.value || '/';

    const filename = (filenameInput?.value || 'screenshot').replace(/\.(png|jpg|jpeg|webp)$/i, '');
    const format = formatSelect?.value || 'png';
    const extension = format === 'jpeg' ? 'jpg' : format;
    const fullFilename = `${filename}.${extension}`;

    try {
        // 转换格式（如果需要）
        let blob = pasteImageData.blob;
        if (pasteImageData.type !== `image/${format}`) {
            blob = await convertImageFormat(pasteImageData.blob, format);
        }

        // 创建 FormData 上传
        const formData = new FormData();
        formData.append('file', blob, fullFilename);

        showAlert('正在上传...', 'info');

        const response = await fetch(`/api/fs/upload?device=${encodeURIComponent(deviceId)}&path=${encodeURIComponent(currentPath)}`, {
            method: 'POST',
            body: formData
        });

        const result = await response.json();

        if (result.error) {
            throw new Error(result.error);
        }

        showAlert(`图片已上传: ${fullFilename}`, 'success');

        // 关闭模态框
        const modal = document.getElementById('paste-preview-modal');
        if (modal) {
            bootstrap.Modal.getInstance(modal)?.hide();
        }

        // 刷新文件列表
        loadFiles();

    } catch (error) {
        console.error('上传图片失败:', error);
        showAlert(`上传失败: ${error.message}`, 'danger');
    }
}

async function convertImageFormat(blob, targetFormat) {
    return new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => {
            const canvas = document.createElement('canvas');
            canvas.width = img.width;
            canvas.height = img.height;
            const ctx = canvas.getContext('2d');

            // JPEG 需要白色背景
            if (targetFormat === 'jpeg') {
                ctx.fillStyle = '#ffffff';
                ctx.fillRect(0, 0, canvas.width, canvas.height);
            }

            ctx.drawImage(img, 0, 0);

            const mimeType = targetFormat === 'jpeg' ? 'image/jpeg' : `image/${targetFormat}`;
            const quality = targetFormat === 'jpeg' ? 0.92 : undefined;

            canvas.toBlob((newBlob) => {
                if (newBlob) {
                    resolve(newBlob);
                } else {
                    reject(new Error('格式转换失败'));
                }
            }, mimeType, quality);
        };
        img.onerror = () => reject(new Error('图片加载失败'));
        img.src = URL.createObjectURL(blob);
    });
}
