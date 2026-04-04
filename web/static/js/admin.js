// SoonLink 管理员面板脚本

const ADMIN_THEME_PREF_KEY = 'soonlink_theme_preference';

// 页面加载完成后执行
document.addEventListener('DOMContentLoaded', function() {
    applyAutoTimeTheme();
    setInterval(applyAutoTimeTheme, 60000);
    document.addEventListener('visibilitychange', function() {
        if (!document.hidden) {
            applyAutoTimeTheme();
        }
    });

    // 初始化导航
    initNavigation();

    // 初始化事件监听器
    initEventListeners();

    // 加载仪表板数据
    loadDashboard();

    // 定时更新仪表板
    setInterval(loadDashboard, 30000);
});

// 应用自动时间主题
function applyAutoTimeTheme() {
    const pref = (window.localStorage && localStorage.getItem(ADMIN_THEME_PREF_KEY)) || 'auto';
    let mode = pref;
    if (mode !== 'light' && mode !== 'dark') {
        const hour = new Date().getHours();
        mode = hour >= 7 && hour < 19 ? 'light' : 'dark';
    }
    document.body.dataset.timeMode = mode;
    document.body.dataset.themePreference = pref;

    const themeLabel = document.getElementById('theme-toggle-label');
    const themeToggleBtn = document.getElementById('theme-toggle-btn');
    const themeMeta = pref === 'light'
        ? { icon: 'bi-sun', label: '' }
        : (pref === 'dark'
            ? { icon: 'bi-moon-stars', label: '' }
            : { icon: 'bi-circle-half', label: `` });
    if (themeLabel) {
        themeLabel.textContent = themeMeta.label;
    }
    if (themeToggleBtn && window.SoonLinkIcons && typeof window.SoonLinkIcons.setIcon === 'function') {
        window.SoonLinkIcons.setIcon(themeToggleBtn, themeMeta.icon);
        themeToggleBtn.title = `切换主题（当前${themeMeta.label}）`;
    }
}

function getAdminThemePreferenceLabel(pref) {
    switch (pref) {
        case 'light':
            return '浅色';
        case 'dark':
            return '深色';
        default:
            return '自动';
    }
}

function cycleAdminThemePreference() {
    const order = ['auto', 'light', 'dark'];
    const current = (window.localStorage && localStorage.getItem(ADMIN_THEME_PREF_KEY)) || 'auto';
    const currentIndex = order.includes(current) ? order.indexOf(current) : 0;
    const nextPref = order[(currentIndex + 1) % order.length];
    if (window.localStorage) {
        localStorage.setItem(ADMIN_THEME_PREF_KEY, nextPref);
    }
    applyAutoTimeTheme();
}

// 初始化导航
function initNavigation() {
    const navTabs = document.querySelectorAll('.admin-nav-tab');

    navTabs.forEach(tab => {
        tab.addEventListener('click', function() {
            const pageId = this.dataset.page;
            if (!pageId) return;

            // 更新标签状态
            navTabs.forEach(t => t.classList.remove('active'));
            this.classList.add('active');

            // 隐藏所有页面
            document.querySelectorAll('.admin-content').forEach(page => {
                page.style.display = 'none';
            });

            // 显示目标页面
            const targetPage = document.getElementById(`${pageId}-page`);
            if (targetPage) {
                targetPage.style.display = 'block';
            }

            // 加载页面数据
            loadPageData(pageId);
        });
    });
}

// 初始化事件监听器
function initEventListeners() {
    // 刷新按钮
    const refreshBtn = document.getElementById('refresh-btn');
    if (refreshBtn) {
        refreshBtn.addEventListener('click', function() {
            const activeTab = document.querySelector('.admin-nav-tab.active');
            if (activeTab) {
                loadPageData(activeTab.dataset.page);
            }
        });
    }

    // 快速操作按钮
    const quickCleanup = document.getElementById('quick-cleanup');
    if (quickCleanup) {
        quickCleanup.addEventListener('click', performCleanup);
    }

    const quickRefresh = document.getElementById('quick-refresh');
    if (quickRefresh) {
        quickRefresh.addEventListener('click', () => loadPageData('devices'));
    }

    const quickLogs = document.getElementById('quick-logs');
    if (quickLogs) {
        quickLogs.addEventListener('click', () => {
            const logsTab = document.querySelector('.admin-nav-tab[data-page="logs"]');
            if (logsTab) logsTab.click();
        });
    }

    // 系统控制按钮
    const restartBtn = document.getElementById('restart-system');
    if (restartBtn) {
        restartBtn.addEventListener('click', restartSystem);
    }

    const shutdownBtn = document.getElementById('shutdown-system');
    if (shutdownBtn) {
        shutdownBtn.addEventListener('click', shutdownSystem);
    }

    // 清理按钮
    const startCleanup = document.getElementById('start-cleanup');
    if (startCleanup) {
        startCleanup.addEventListener('click', performCleanup);
    }

    const clearLogsBtn = document.getElementById('clear-logs');
    if (clearLogsBtn) {
        clearLogsBtn.addEventListener('click', clearLogs);
    }

    // 主题切换
    const themeToggle = document.getElementById('theme-toggle-btn');
    if (themeToggle) {
        themeToggle.addEventListener('click', cycleAdminThemePreference);
    }
}

// 加载仪表板数据
async function loadDashboard() {
    try {
        const response = await fetch('/admin/api/system');
        const data = await response.json();
        if (!data.success) {
            throw new Error(data.error || 'invalid system payload');
        }

        // 更新指标卡片
        const cpuUsage = document.getElementById('cpu-usage');
        if (cpuUsage) cpuUsage.textContent = data.cpu || '0%';

        const memoryUsage = document.getElementById('memory-usage');
        if (memoryUsage) memoryUsage.textContent = data.memory || '0%';

        const activeTasks = document.getElementById('active-tasks');
        if (activeTasks) activeTasks.textContent = data.tasks || '0';

        const onlineDevices = document.getElementById('online-devices');
        if (onlineDevices) onlineDevices.textContent = data.onlineDevices || data.devices || '0';

        // 更新系统信息
        const hostname = document.getElementById('hostname');
        if (hostname) hostname.textContent = data.hostname || '-';

        const uptime = document.getElementById('uptime');
        if (uptime) uptime.textContent = data.uptime || '-';

        const diskUsage = document.getElementById('disk-usage');
        if (diskUsage) diskUsage.textContent = data.disk || '-';

    } catch (error) {
        console.error('加载仪表板数据失败:', error);
        showAlert('加载仪表板数据失败', 'danger');
    }
}

// 根据页面类型加载数据
function loadPageData(pageId) {
    switch(pageId) {
        case 'dashboard':
            loadDashboard();
            break;
        case 'system':
            loadSystemInfo();
            break;
        case 'drives':
            loadDrives();
            break;
        case 'visibility':
            loadVisibilitySettings();
            break;
        case 'logs':
            loadLogs();
            break;
        case 'tasks':
            loadTasks();
            break;
        case 'devices':
            loadDevices();
            break;
        case 'cleanup':
            loadCleanupPreview();
            break;
    }
}

// 加载系统信息
async function loadSystemInfo() {
    try {
        const response = await fetch('/admin/api/system');
        const data = await response.json();
        if (!data.success) {
            throw new Error(data.error || 'invalid system payload');
        }

        const systemInfo = document.getElementById('system-info');
        if (!systemInfo) return;

        systemInfo.innerHTML = `
            <div class="info-grid">
                <div class="info-item">
                    <span class="info-label">主机名</span>
                    <span class="info-value">${data.hostname || '-'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">操作系统</span>
                    <span class="info-value">${data.os || '-'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">运行时间</span>
                    <span class="info-value">${data.uptime || '-'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">主IP</span>
                    <span class="info-value">${data.primaryIp || '-'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">CPU使用率</span>
                    <span class="info-value">${data.cpu || '0%'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">内存使用</span>
                    <span class="info-value">${data.memory || '0%'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">磁盘使用</span>
                    <span class="info-value">${data.disk || '-'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">活动任务</span>
                    <span class="info-value">${data.tasks || '0'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">在线设备</span>
                    <span class="info-value">${data.onlineDevices || data.devices || '0'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">日志总数</span>
                    <span class="info-value">${data.logTotal || '0'}</span>
                </div>
            </div>
        `;
    } catch (error) {
        console.error('加载系统信息失败:', error);
        const systemInfo = document.getElementById('system-info');
        if (systemInfo) {
            systemInfo.innerHTML = '<p class="text-danger">加载系统信息失败</p>';
        }
    }
}

// 加载磁盘驱动器信息
async function loadDrives() {
    try {
        const response = await fetch('/admin/api/drives');
        const data = await response.json();
        if (!data.success) {
            throw new Error(data.error || 'invalid drives payload');
        }

        const drivesList = document.getElementById('drives-list');
        if (!drivesList) return;

        drivesList.innerHTML = '';

        if (data.drives && data.drives.length > 0) {
            data.drives.forEach(drive => {
                const driveItem = document.createElement('div');
                driveItem.className = 'app-card mb-2';
                driveItem.innerHTML = `
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h6 class="mb-1"><i class="bi bi-hdd me-2"></i>${drive.name}</h6>
                            <small class="text-muted">${drive.path}</small>
                        </div>
                        <div class="text-end">
                            <div class="mb-1">
                                <span class="stat-chip">${drive.used} / ${drive.size}</span>
                                <span class="stat-chip ms-1">${Math.round(Number(drive.usedPercent || 0))}%</span>
                            </div>
                            <div class="progress" style="width: 150px; height: 6px;">
                                <div class="progress-bar" style="width: ${drive.usedPercent || 0}%"></div>
                            </div>
                        </div>
                    </div>
                `;
                drivesList.appendChild(driveItem);
            });
        } else {
            drivesList.innerHTML = '<p class="text-muted">没有找到磁盘驱动器</p>';
        }
    } catch (error) {
        console.error('加载磁盘信息失败:', error);
        const drivesList = document.getElementById('drives-list');
        if (drivesList) {
            drivesList.innerHTML = '<p class="text-danger">加载磁盘信息失败</p>';
        }
    }
}

// 加载可见性设置
async function loadVisibilitySettings() {
    try {
        const response = await fetch('/admin/api/visibility');
        const data = await response.json();
        if (!data.success) {
            throw new Error(data.error || 'invalid visibility payload');
        }

        const visibilityControls = document.getElementById('visibility-controls');
        const visibilityFilters = document.getElementById('visibility-filters');
        if (!visibilityControls) return;

        visibilityControls.innerHTML = '';
        if (visibilityFilters) {
            const filters = data.filters || {};
            visibilityFilters.innerHTML = `
                <div class="visibility-filter-card">
                    <div class="visibility-filter-card-head">
                        <div>
                            <div class="visibility-filter-title">隐藏点文件 / 点目录</div>
                            <div class="visibility-filter-copy">例如 .git、.cache、.ssh 这类以 . 开头的条目。</div>
                        </div>
                        <div class="form-check form-switch mb-0">
                            <input class="form-check-input visibility-filter-input" type="checkbox" id="visibility-hide-dot" ${filters.hideDotEntries ? 'checked' : ''}>
                        </div>
                    </div>
                </div>
                <div class="visibility-filter-card">
                    <div class="visibility-filter-card-head">
                        <div>
                            <div class="visibility-filter-title">隐藏缓存噪音文件</div>
                            <div class="visibility-filter-copy">例如 .DS_Store、desktop.ini、Thumbs.db 这类系统缓存痕迹。</div>
                        </div>
                        <div class="form-check form-switch mb-0">
                            <input class="form-check-input visibility-filter-input" type="checkbox" id="visibility-hide-cache" ${filters.hideCacheEntries ? 'checked' : ''}>
                        </div>
                    </div>
                </div>
            `;

            document.querySelectorAll('.visibility-filter-input').forEach((input) => {
                input.addEventListener('change', updateVisibilityFilters);
            });
        }

        const folders = Array.isArray(data.folders) ? data.folders : [];
        if (folders.length === 0) {
            visibilityControls.innerHTML = '<p class="text-muted">当前根目录下暂无可管理目录</p>';
            return;
        }

        folders.forEach(folder => {
            const isVisible = folder.visible !== false && (!data.settings || data.settings[folder.path] !== false);
            const indent = Math.max(Number(folder.depth || 1) - 1, 0) * 12;
            const folderItem = document.createElement('details');
            folderItem.className = 'visibility-folder-item';
            folderItem.innerHTML = `
                <summary>
                    <div class="visibility-folder-summary" style="padding-left: ${indent}px;">
                        <i class="bi bi-folder"></i>
                        <div class="visibility-folder-meta">
                            <div class="visibility-folder-name">${folder.name}</div>
                            <div class="visibility-folder-path">${folder.path}</div>
                        </div>
                    </div>
                    <span class="stat-chip">${isVisible ? '可见' : '隐藏'}</span>
                </summary>
                <div class="visibility-folder-body">
                    <div class="visibility-folder-body-note">关闭后，该目录将不会出现在文件浏览器列表中。</div>
                    <div class="d-flex justify-content-between align-items-center">
                        <span>目录显示开关</span>
                        <div class="form-check form-switch mb-0">
                            <input class="form-check-input folder-visibility" type="checkbox"
                                data-path="${folder.path}" ${isVisible ? 'checked' : ''}>
                        </div>
                    </div>
                </div>
            `;
            visibilityControls.appendChild(folderItem);
        });

        // 添加可见性切换事件
        document.querySelectorAll('.folder-visibility').forEach(checkbox => {
            checkbox.addEventListener('change', function() {
                updateFolderVisibility(this.dataset.path, this.checked);
            });
        });

    } catch (error) {
        console.error('加载可见性设置失败:', error);
        const visibilityControls = document.getElementById('visibility-controls');
        if (visibilityControls) {
            visibilityControls.innerHTML = '<p class="text-danger">加载可见性设置失败</p>';
        }
    }
}

async function updateVisibilityFilters() {
    const hideDotEntries = !!document.getElementById('visibility-hide-dot')?.checked;
    const hideCacheEntries = !!document.getElementById('visibility-hide-cache')?.checked;

    try {
        const response = await fetch('/admin/api/visibility', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                hideDotEntries,
                hideCacheEntries,
            })
        });

        if (!response.ok) {
            throw new Error('更新过滤规则失败');
        }
        showAlert('文件浏览过滤规则已更新', 'success');
        loadVisibilitySettings();
    } catch (error) {
        console.error('更新过滤规则失败:', error);
        showAlert('更新过滤规则失败', 'danger');
    }
}

// 加载系统日志
async function loadLogs() {
    try {
        const response = await fetch('/admin/api/logs?limit=200');
        const data = await response.json();
        if (!data.success) {
            throw new Error(data.error || 'invalid logs payload');
        }

        const logsContainer = document.getElementById('logs-container');
        if (!logsContainer) return;

        logsContainer.innerHTML = '';

        if (data.logs && data.logs.length > 0) {
            data.logs.forEach(log => {
                const logEntry = document.createElement('div');
                const timestamp = formatDate(log.timestamp);
                const level = (log.level || 'info').toUpperCase();
                const levelClass = getLogLevelClass(level);
                logEntry.className = `log-entry ${levelClass}`;
                logEntry.innerHTML = `
                    <span class="text-muted">${timestamp}</span>
                    <span class="badge bg-${levelClass === 'text-danger' ? 'danger' : levelClass === 'text-warning' ? 'warning' : 'secondary'} me-1">${level}</span>
                    <span>${log.message || ''}</span>
                `;
                logsContainer.appendChild(logEntry);
            });

            // 自动滚动到底部
            logsContainer.scrollTop = logsContainer.scrollHeight;
        } else {
            logsContainer.innerHTML = '<p class="text-muted">没有日志记录</p>';
        }
    } catch (error) {
        console.error('加载日志失败:', error);
        const logsContainer = document.getElementById('logs-container');
        if (logsContainer) {
            logsContainer.innerHTML = '<p class="text-danger">加载日志失败</p>';
        }
    }
}

// 加载任务列表
async function loadTasks() {
    try {
        const response = await fetch('/api/tasks/');
        const data = await response.json();

        const tasksList = document.getElementById('tasks-list');
        if (!tasksList) return;

        tasksList.innerHTML = '';

        if (data && data.length > 0) {
            const table = document.createElement('table');
            table.className = 'table table-hover align-middle mb-0';
            table.innerHTML = `
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>传输方向</th>
                        <th>文件路径</th>
                        <th>状态</th>
                        <th>进度</th>
                        <th>操作</th>
                    </tr>
                </thead>
                <tbody>
                    ${data.map(task => `
                        <tr>
                            <td><span class="task-id">${(task.id || '').substring(0, 8)}</span></td>
                            <td>
                                <div class="transfer-direction">
                                    <span class="transfer-device source">${task.sourceDevice || '-'}</span>
                                    <i class="bi bi-arrow-right transfer-arrow"></i>
                                    <span class="transfer-device target">${task.targetDevice || '-'}</span>
                                </div>
                            </td>
                            <td><span class="task-file-path">${task.filePath || '-'}</span></td>
                            <td><span class="badge status-${task.status}">${getStatusText(task.status)}</span></td>
                            <td>
                                <div class="progress" style="width: 80px; height: 6px;">
                                    <div class="progress-bar" style="width: ${task.progress || 0}%">${Math.round(task.progress || 0)}%</div>
                                </div>
                            </td>
                            <td>
                                ${task.status === 'pending' || task.status === 'running'
                                    ? `<button class="btn btn-sm btn-danger cancel-task" data-task-id="${task.id}">取消</button>`
                                    : '<button class="btn btn-sm btn-secondary" disabled>已完成</button>'
                                }
                            </td>
                        </tr>
                    `).join('')}
                </tbody>
            `;
            tasksList.appendChild(table);

            // 添加取消任务事件
            document.querySelectorAll('.cancel-task').forEach(btn => {
                btn.addEventListener('click', function() {
                    cancelTask(this.dataset.taskId);
                });
            });
        } else {
            tasksList.innerHTML = '<p class="text-muted">没有活动任务</p>';
        }
    } catch (error) {
        console.error('加载任务列表失败:', error);
        const tasksList = document.getElementById('tasks-list');
        if (tasksList) {
            tasksList.innerHTML = '<p class="text-danger">加载任务列表失败</p>';
        }
    }
}

// 加载设备列表
async function loadDevices() {
    try {
        const response = await fetch('/api/devices/');
        const data = await response.json();

        const devicesList = document.getElementById('devices-list');
        if (!devicesList) return;

        devicesList.innerHTML = '';

        if (data && data.length > 0) {
            data.forEach(device => {
                const deviceCard = document.createElement('div');
                deviceCard.className = 'app-card mb-2';
                deviceCard.innerHTML = `
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h6 class="mb-1">
                                <span class="device-status status-${device.online ? 'online' : 'offline'}"></span>
                                ${device.name || device.id}
                            </h6>
                            <small class="text-muted">${device.type || '-'}</small>
                        </div>
                        <div class="text-end">
                            <div class="mb-1">
                                <span class="stat-chip">${device.ip || '-'}:${device.port || '-'}</span>
                            </div>
                            <small class="text-muted">${formatDate(device.lastSeen)}</small>
                        </div>
                    </div>
                `;
                devicesList.appendChild(deviceCard);
            });
        } else {
            devicesList.innerHTML = '<p class="text-muted">没有设备连接</p>';
        }
    } catch (error) {
        console.error('加载设备列表失败:', error);
        const devicesList = document.getElementById('devices-list');
        if (devicesList) {
            devicesList.innerHTML = '<p class="text-danger">加载设备列表失败</p>';
        }
    }
}

// 加载清理预览
async function loadCleanupPreview() {
    try {
        const response = await fetch('/admin/api/cleanup/preview');
        const data = await response.json();

        // 可以在这里显示预览信息
        console.log('Cleanup preview:', data);
    } catch (error) {
        console.error('加载清理预览失败:', error);
    }
}

// 更新文件夹可见性
async function updateFolderVisibility(path, visible) {
    try {
        const response = await fetch('/admin/api/visibility', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                path: path,
                visible: visible
            })
        });

        if (response.ok) {
            showAlert(`文件夹可见性已更新`, 'success');
            loadVisibilitySettings();
        } else {
            showAlert('更新文件夹可见性失败', 'danger');
        }
    } catch (error) {
        console.error('更新文件夹可见性失败:', error);
        showAlert('更新文件夹可见性失败', 'danger');
    }
}

// 执行系统清理
async function performCleanup() {
    if (!confirm('确定要执行系统清理吗？这将删除所有过期的临时文件。')) {
        return;
    }

    try {
        const response = await fetch('/admin/cleanup', {
            method: 'POST'
        });

        const data = await response.json();

        if (data.success) {
            showAlert(data.message, 'success');
            const resultDiv = document.getElementById('cleanup-result');
            if (resultDiv) {
                resultDiv.style.display = 'block';
                resultDiv.innerHTML = `
                    <div class="alert alert-success mt-3">
                        <i class="bi bi-check-circle me-2"></i>
                        ${data.message}
                    </div>
                `;
            }
        } else {
            showAlert(data.error || '清理失败', 'danger');
        }
    } catch (error) {
        console.error('执行清理失败:', error);
        showAlert('执行清理失败', 'danger');
    }
}

// 取消任务
async function cancelTask(taskId) {
    if (!confirm('确定要取消这个任务吗？')) {
        return;
    }

    try {
        const response = await fetch(`/api/tasks/${taskId}`, {
            method: 'DELETE'
        });
        const result = await response.json().catch(() => ({}));

        if (response.ok && result.success !== false) {
            showAlert(result.message || '任务已取消', 'success');
            loadTasks();
        } else {
            showAlert(result.error || '取消任务失败', 'danger');
        }
    } catch (error) {
        console.error('取消任务失败:', error);
        showAlert('取消任务失败', 'danger');
    }
}

// 重启系统
function restartSystem() {
    if (!confirm('确定要重启系统吗？')) {
        return;
    }
    showAlert('系统重启功能暂未实现', 'warning');
}

// 关闭系统
async function shutdownSystem() {
    if (!confirm('确定要关闭系统吗？这将停止所有服务。')) {
        return;
    }

    try {
        const response = await fetch('/admin/shutdown', {
            method: 'POST'
        });

        const data = await response.json();

        if (data.success) {
            showAlert(data.message, 'success');
        } else {
            showAlert('关闭系统失败', 'danger');
        }
    } catch (error) {
        console.error('关闭系统失败:', error);
        showAlert('关闭系统失败', 'danger');
    }
}

// 清空日志
function clearLogs() {
    if (!confirm('确定要清空所有日志吗？')) {
        return;
    }

    fetch('/api/logs/', { method: 'DELETE' })
        .then(async (response) => {
            const data = await response.json().catch(() => ({}));
            if (!response.ok || data.success === false) {
                throw new Error(data.error || '清空日志失败');
            }
            showAlert(data.message || '日志已清空', 'success');
            loadLogs();
            loadDashboard();
        })
        .catch((error) => {
            console.error('清空日志失败:', error);
            showAlert(error.message || '清空日志失败', 'danger');
        });
}

// 获取日志级别样式类
function getLogLevelClass(level) {
    const levelMap = {
        'ERROR': 'text-danger',
        'WARN': 'text-warning',
        'WARNING': 'text-warning',
        'INFO': 'text-info',
        'DEBUG': 'text-muted'
    };
    return levelMap[level] || 'text-muted';
}

// 获取状态徽章类
function getStatusBadgeClass(status) {
    const statusMap = {
        'pending': 'bg-secondary',
        'running': 'bg-primary',
        'completed': 'bg-success',
        'failed': 'bg-danger',
        'cancelled': 'bg-warning'
    };
    return statusMap[status] || 'bg-secondary';
}

// 获取状态文本
function getStatusText(status) {
    const statusMap = {
        'pending': '等待中',
        'running': '进行中',
        'completed': '已完成',
        'failed': '失败',
        'cancelled': '已取消'
    };
    return statusMap[status] || status;
}

// 格式化日期
function formatDate(timestamp) {
    if (!timestamp) return '-';

    const normalized = Number(timestamp) < 1000000000000 ? Number(timestamp) * 1000 : Number(timestamp);
    const date = new Date(normalized);
    return date.toLocaleString('zh-CN', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
    });
}

// 显示提示消息
function showAlert(message, type = 'info') {
    // 创建提示框
    const alertDiv = document.createElement('div');
    alertDiv.className = `soonlink-toast soonlink-toast-${type}`;
    alertDiv.innerHTML = `
        <span class="soonlink-toast-body">${message}</span>
        <button type="button" class="soonlink-toast-close" onclick="this.parentElement.remove()">×</button>
    `;

    // 查找或创建 toast 容器
    let toastHost = document.querySelector('.soonlink-toast-host');
    if (!toastHost) {
        toastHost = document.createElement('div');
        toastHost.className = 'soonlink-toast-host';
        document.body.appendChild(toastHost);
    }

    toastHost.appendChild(alertDiv);

    // 动画显示
    setTimeout(() => alertDiv.classList.add('show'), 10);

    // 自动移除
    setTimeout(() => {
        alertDiv.classList.remove('show');
        setTimeout(() => alertDiv.remove(), 300);
    }, 5000);
}
