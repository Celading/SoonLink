// Dashboard页面JavaScript功能
class DashboardController {
    constructor() {
        this.mediaStatus = null;
        this.systemInfo = null;
        this.isMonitoring = false;
        this.monitoringInterval = null;
        this.refreshInterval = 5000; // 5秒刷新间隔
        this.roleVariant = 'remote';

        this.init();
    }

    init() {
        this.applyAutoTimeTheme();
        setInterval(() => this.applyAutoTimeTheme(), 60000);
        document.addEventListener('visibilitychange', () => {
            if (!document.hidden) {
                this.applyAutoTimeTheme();
            }
        });

        this.bindEvents();
        this.loadInitialData();
        this.startAutoRefresh();
    }

    bindEvents() {
        const themeToggleBtn = document.getElementById('theme-toggle-btn');
        if (themeToggleBtn) {
            themeToggleBtn.addEventListener('click', () => this.cycleThemePreference());
        }

        // 媒体控制按钮事件
        document.getElementById('play-pause-btn').addEventListener('click', () => this.togglePlayPause());
        document.getElementById('stop-btn').addEventListener('click', () => this.stopMedia());
        document.getElementById('prev-btn').addEventListener('click', () => this.previousTrack());
        document.getElementById('next-btn').addEventListener('click', () => this.nextTrack());

        // 音量控制事件
        document.getElementById('volume-slider').addEventListener('input', (e) => this.setVolume(e.target.value));
        document.getElementById('mute-btn').addEventListener('click', () => this.toggleMute());

        // 系统操作按钮事件
        document.getElementById('refresh-all-btn').addEventListener('click', () => this.refreshAll());
        document.getElementById('refresh-system-btn').addEventListener('click', () => this.refreshSystemInfo());
        document.getElementById('monitor-toggle-btn').addEventListener('click', () => this.toggleMonitoring());
    }

    async loadInitialData() {
        await Promise.all([
            this.loadSessionContext(),
            this.loadMediaStatus(),
            this.loadSystemInfo()
        ]);
    }

    async loadSessionContext() {
        try {
            const response = await fetch('/api/session/context');
            if (!response.ok) {
                return;
            }
            const data = await response.json();
            this.roleVariant = data.themeVariant === 'admin' ? 'admin' : 'remote';
            this.applyAutoTimeTheme();
            document.querySelectorAll('.admin-dashboard-link').forEach((node) => {
                node.style.display = data.isLocalAdmin ? '' : 'none';
            });
        } catch (_error) {
            // ignore
        }
    }

    findIconNode(target) {
        if (!target) {
            return null;
        }
        if (target.matches && (target.matches('svg.sl-icon') || target.matches('i.bi'))) {
            return target;
        }
        return target.querySelector('svg.sl-icon, i.bi');
    }

    setIcon(target, classNames) {
        if (!target) {
            return null;
        }
        if (window.SoonLinkIcons && typeof window.SoonLinkIcons.setIcon === 'function') {
            return window.SoonLinkIcons.setIcon(target, classNames);
        }

        const icon = this.findIconNode(target);
        if (icon && icon.classList && icon.classList.contains('bi')) {
            icon.className = `bi ${classNames}`;
            return icon;
        }
        return icon;
    }

    // 媒体控制相关方法
    async loadMediaStatus() {
        try {
            const response = await fetch('/api/media/status');
            this.mediaStatus = await response.json();
            this.updateMediaUI();
        } catch (error) {
            console.error('获取媒体状态失败:', error);
            this.showError('获取媒体状态失败');
        }
    }

    updateMediaUI() {
        if (!this.mediaStatus) return;

        // 更新播放信息
        document.getElementById('current-track').textContent = this.mediaStatus.currentTrack || '无播放内容';
        document.getElementById('current-artist').textContent = this.mediaStatus.artist || '';
        document.getElementById('current-album').textContent = this.mediaStatus.album || '';
        const providerLabel = document.getElementById('media-provider');
        if (providerLabel) {
            const provider = this.mediaStatus.provider || 'unknown';
            providerLabel.textContent = this.mediaStatus.supportsSystemMedia
                ? `已接入系统媒体 · ${provider}`
                : `后端会话媒体状态 · ${provider}`;
        }

        // 更新播放按钮状态
        const playPauseBtn = document.getElementById('play-pause-btn');
        if (this.mediaStatus.isPlaying) {
            this.setIcon(playPauseBtn, 'bi-pause-fill');
            playPauseBtn.classList.add('active');
            playPauseBtn.title = '暂停';
        } else {
            this.setIcon(playPauseBtn, 'bi-play-fill');
            playPauseBtn.classList.remove('active');
            playPauseBtn.title = '播放';
        }

        // 更新音量
        const volumeSlider = document.getElementById('volume-slider');
        const volumeText = document.getElementById('volume-text');
        const muteBtn = document.getElementById('mute-btn');

        volumeSlider.value = this.mediaStatus.volume;
        volumeText.textContent = this.mediaStatus.volume + '%';

        // 更新静音按钮
        if (this.mediaStatus.isMuted) {
            this.setIcon(muteBtn, 'bi-volume-mute-fill');
        } else if (this.mediaStatus.volume > 50) {
            this.setIcon(muteBtn, 'bi-volume-up-fill');
        } else if (this.mediaStatus.volume > 0) {
            this.setIcon(muteBtn, 'bi-volume-down-fill');
        } else {
            this.setIcon(muteBtn, 'bi-volume-off-fill');
        }
    }

    async togglePlayPause() {
        try {
            const endpoint = this.mediaStatus?.isPlaying ? '/api/media/pause' : '/api/media/play';
            const response = await fetch(endpoint, { method: 'POST' });
            const result = await response.json();

            if (result.success) {
                this.showSuccess(result.message);
                await this.loadMediaStatus();
            } else {
                this.showError(result.message || '操作失败');
            }
        } catch (error) {
            console.error('播放控制失败:', error);
            this.showError('播放控制失败');
        }
    }

    async stopMedia() {
        try {
            const response = await fetch('/api/media/stop', { method: 'POST' });
            const result = await response.json();

            if (result.success) {
                this.showSuccess(result.message);
                await this.loadMediaStatus();
            } else {
                this.showError(result.message || '停止失败');
            }
        } catch (error) {
            console.error('停止播放失败:', error);
            this.showError('停止播放失败');
        }
    }

    async previousTrack() {
        try {
            const response = await fetch('/api/media/previous', { method: 'POST' });
            const result = await response.json();

            if (result.success) {
                this.showSuccess(result.message);
                await this.loadMediaStatus();
            } else {
                this.showError(result.message || '上一曲失败');
            }
        } catch (error) {
            console.error('上一曲失败:', error);
            this.showError('上一曲失败');
        }
    }

    async nextTrack() {
        try {
            const response = await fetch('/api/media/next', { method: 'POST' });
            const result = await response.json();

            if (result.success) {
                this.showSuccess(result.message);
                await this.loadMediaStatus();
            } else {
                this.showError(result.message || '下一曲失败');
            }
        } catch (error) {
            console.error('下一曲失败:', error);
            this.showError('下一曲失败');
        }
    }

    async setVolume(volume) {
        try {
            const response = await fetch('/api/media/volume', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ volume: parseInt(volume) }),
            });

            const result = await response.json();
            if (result.success) {
                document.getElementById('volume-text').textContent = volume + '%';
                if (this.mediaStatus) {
                    this.mediaStatus.volume = parseInt(volume);
                    this.updateVolumeIcon();
                }
            } else {
                this.showError(result.error || '设置音量失败');
            }
        } catch (error) {
            console.error('设置音量失败:', error);
            this.showError('设置音量失败');
        }
    }

    async toggleMute() {
        try {
            const endpoint = this.mediaStatus?.isMuted ? '/api/media/unmute' : '/api/media/mute';
            const response = await fetch(endpoint, { method: 'POST' });
            const result = await response.json();

            if (result.success) {
                this.showSuccess(result.message);
                await this.loadMediaStatus();
            } else {
                this.showError(result.message || '静音操作失败');
            }
        } catch (error) {
            console.error('静音操作失败:', error);
            this.showError('静音操作失败');
        }
    }

    updateVolumeIcon() {
        const muteBtn = document.getElementById('mute-btn');

        if (this.mediaStatus.isMuted) {
            this.setIcon(muteBtn, 'bi-volume-mute-fill');
        } else if (this.mediaStatus.volume > 50) {
            this.setIcon(muteBtn, 'bi-volume-up-fill');
        } else if (this.mediaStatus.volume > 0) {
            this.setIcon(muteBtn, 'bi-volume-down-fill');
        } else {
            this.setIcon(muteBtn, 'bi-volume-off-fill');
        }
    }

    // 系统监控相关方法
    async loadSystemInfo() {
        try {
            const response = await fetch('/api/monitor/system');
            this.systemInfo = await response.json();
            this.updateSystemUI();
        } catch (error) {
            console.error('获取系统信息失败:', error);
            this.showError('获取系统信息失败');
        }
    }

    updateSystemUI() {
        if (!this.systemInfo) return;

        // 更新系统状态圆圈
        this.updateStatCircle('cpu-circle', 'cpu-percent', this.systemInfo.cpuUsage);
        this.updateStatCircle('memory-circle', 'memory-percent', this.systemInfo.memoryUsage);
        this.updateStatCircle('disk-circle', 'disk-percent', this.systemInfo.diskUsage);

        // 更新温度
        const tempValue = document.getElementById('temp-value');
        if (this.systemInfo.temperature > 0) {
            tempValue.textContent = Math.round(this.systemInfo.temperature) + '°C';
        } else {
            tempValue.textContent = '--°C';
        }

        // 更新设备信息
        document.getElementById('hostname').textContent = this.systemInfo.hostname || '未知';
        document.getElementById('os-info').textContent = `${this.systemInfo.os} ${this.systemInfo.platform}` || '未知';
        document.getElementById('uptime').textContent = this.formatUptime(this.systemInfo.uptime);
        document.getElementById('primary-ip').textContent = this.systemInfo.primaryIp || '-';
        document.getElementById('network-gateway').textContent = this.systemInfo.gateway || '-';

        // 更新网络信息
        document.getElementById('network-rx').textContent = this.formatBytes(this.systemInfo.networkRx);
        document.getElementById('network-tx').textContent = this.formatBytes(this.systemInfo.networkTx);

        // 如果启用了详细监控，更新详细信息
        if (this.isMonitoring) {
            this.updateDetailedMonitoring();
        }
    }

    updateStatCircle(circleId, textId, percentage) {
        const circle = document.getElementById(circleId);
        const text = document.getElementById(textId);

        text.textContent = Math.round(percentage) + '%';

        // 根据使用率设置颜色
        let color = 'rgba(255,255,255,0.2)';
        if (percentage > 80) {
            color = 'rgba(255, 99, 99, 0.8)'; // 红色
        } else if (percentage > 60) {
            color = 'rgba(255, 193, 7, 0.8)'; // 黄色
        } else {
            color = 'rgba(40, 167, 69, 0.8)'; // 绿色
        }

        circle.style.background = color;
    }

    async updateDetailedMonitoring() {
        try {
            const [cpuData, memoryData, diskData, networkData] = await Promise.all([
                fetch('/api/monitor/cpu').then(r => r.json()),
                fetch('/api/monitor/memory').then(r => r.json()),
                fetch('/api/monitor/disk').then(r => r.json()),
                fetch('/api/monitor/network').then(r => r.json())
            ]);

            // 更新CPU详情
            document.getElementById('cpu-details').innerHTML = `
                <p class="mb-1">使用率: ${Math.round(cpuData.usage)}%</p>
            `;

            // 更新内存详情
            document.getElementById('memory-details').innerHTML = `
                <p class="mb-1">总计: ${this.formatBytes(memoryData.total)}</p>
                <p class="mb-1">已用: ${this.formatBytes(memoryData.used)}</p>
                <p class="mb-1">可用: ${this.formatBytes(memoryData.free)}</p>
            `;

            // 更新磁盘详情
            document.getElementById('disk-details').innerHTML = `
                <p class="mb-1">总计: ${this.formatBytes(diskData.total)}</p>
                <p class="mb-1">已用: ${this.formatBytes(diskData.used)}</p>
                <p class="mb-1">可用: ${this.formatBytes(diskData.free)}</p>
            `;

            // 更新网络详情
            document.getElementById('network-details').innerHTML = `
                <p class="mb-1">主IP: ${networkData.primaryIp || '-'}</p>
                <p class="mb-1">网关: ${networkData.gateway || '-'}</p>
                <p class="mb-1">地址: ${(Array.isArray(networkData.ips) && networkData.ips.length > 0) ? networkData.ips.join(', ') : '-'}</p>
                <p class="mb-1">DNS: ${(Array.isArray(networkData.dns) && networkData.dns.length > 0) ? networkData.dns.join(', ') : '-'}</p>
                <p class="mb-1">收包: ${networkData.packetsRecv.toLocaleString()}</p>
                <p class="mb-1">发包: ${networkData.packetsSent.toLocaleString()}</p>
                <p class="mb-1">收流量: ${this.formatBytes(networkData.bytesRecv)}</p>
                <p class="mb-1">发流量: ${this.formatBytes(networkData.bytesSent)}</p>
            `;

        } catch (error) {
            console.error('更新详细监控信息失败:', error);
        }
    }

    // 控制相关方法
    async refreshAll() {
        const btn = document.getElementById('refresh-all-btn');
        const icon = this.findIconNode(btn);

        // 添加旋转动画
        if (icon) {
            icon.style.animation = 'spin 1s linear infinite';
        }

        try {
            await Promise.all([
                this.loadMediaStatus(),
                this.loadSystemInfo()
            ]);
            this.showSuccess('已刷新所有信息');
        } catch (error) {
            this.showError('刷新失败');
        } finally {
            // 移除旋转动画
            setTimeout(() => {
                if (icon) {
                    icon.style.animation = '';
                }
            }, 1000);
        }
    }

    async refreshSystemInfo() {
        const btn = document.getElementById('refresh-system-btn');
        const icon = this.findIconNode(btn);

        // 添加旋转动画
        if (icon) {
            icon.style.animation = 'spin 1s linear infinite';
        }

        try {
            await this.loadSystemInfo();
            this.showSuccess('系统信息已刷新');
        } catch (error) {
            this.showError('刷新系统信息失败');
        } finally {
            // 移除旋转动画
            setTimeout(() => {
                if (icon) {
                    icon.style.animation = '';
                }
            }, 1000);
        }
    }

    toggleMonitoring() {
        const btn = document.getElementById('monitor-toggle-btn');
        const label = document.getElementById('monitor-toggle-label');
        const detailedMonitoring = document.getElementById('detailed-monitoring');

        this.isMonitoring = !this.isMonitoring;

        if (this.isMonitoring) {
            // 开启监控
            this.setIcon(btn, 'bi-eye-slash me-1');
            if (label) {
                label.textContent = '关闭实时监控';
            }
            detailedMonitoring.style.display = 'block';

            // 开始定时刷新
            this.monitoringInterval = setInterval(() => {
                this.loadSystemInfo();
            }, 2000); // 2秒刷新一次

            this.showSuccess('已开启实时监控');
        } else {
            // 关闭监控
            this.setIcon(btn, 'bi-eye me-1');
            if (label) {
                label.textContent = '开启实时监控';
            }
            detailedMonitoring.style.display = 'none';

            // 停止定时刷新
            if (this.monitoringInterval) {
                clearInterval(this.monitoringInterval);
                this.monitoringInterval = null;
            }

            this.showSuccess('已关闭实时监控');
        }
    }

    startAutoRefresh() {
        // 每5秒自动刷新媒体状态
        setInterval(() => {
            this.loadMediaStatus();
        }, this.refreshInterval);

        // 每30秒自动刷新系统信息（如果没有开启实时监控）
        setInterval(() => {
            if (!this.isMonitoring) {
                this.loadSystemInfo();
            }
        }, 30000);
    }

    // 工具方法
    applyAutoTimeTheme() {
        const pref = (window.localStorage && localStorage.getItem('soonlink_theme_preference')) || 'auto';
        let mode = pref;
        if (mode !== 'light' && mode !== 'dark') {
            const hour = new Date().getHours();
            mode = hour >= 7 && hour < 19 ? 'light' : 'dark';
        }
        document.body.dataset.roleVariant = this.roleVariant;
        document.body.dataset.timeMode = mode;
        document.body.dataset.themePreference = pref;

        const themeToggleLabel = document.getElementById('theme-toggle-label');
        const themeToggleBtn = document.getElementById('theme-toggle-btn');
        const themeMeta = pref === 'light'
            ? { icon: 'bi-sun', label: '浅色' }
            : (pref === 'dark'
                ? { icon: 'bi-moon-stars', label: '深色' }
                : { icon: 'bi-circle-half', label: `自动 · ${mode === 'light' ? '浅色' : '深色'}` });
        if (themeToggleLabel) {
            themeToggleLabel.textContent = themeMeta.label;
        }
        if (themeToggleBtn) {
            this.setIcon(themeToggleBtn, themeMeta.icon);
            themeToggleBtn.title = `切换主题（当前${themeMeta.label}）`;
        }
    }

    cycleThemePreference() {
        const order = ['auto', 'light', 'dark'];
        const current = (window.localStorage && localStorage.getItem('soonlink_theme_preference')) || 'auto';
        const currentIndex = order.includes(current) ? order.indexOf(current) : 0;
        const next = order[(currentIndex + 1) % order.length];
        if (window.localStorage) {
            localStorage.setItem('soonlink_theme_preference', next);
        }
        this.applyAutoTimeTheme();
    }

    formatBytes(bytes) {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    formatUptime(seconds) {
        if (!seconds) return '未知';

        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);

        if (days > 0) {
            return `${days}天 ${hours}小时 ${minutes}分钟`;
        } else if (hours > 0) {
            return `${hours}小时 ${minutes}分钟`;
        } else {
            return `${minutes}分钟`;
        }
    }

    showSuccess(message) {
        this.showToast(message, 'success');
    }

    showError(message) {
        this.showToast(message, 'danger');
    }

    showToast(message, type = 'info') {
        // 创建toast元素
        const toastContainer = document.querySelector('.toast-container') || this.createToastContainer();

        const toastId = 'toast-' + Date.now();
        const toast = document.createElement('div');
        toast.id = toastId;
        toast.className = 'toast align-items-center text-white bg-' + type + ' border-0';
        toast.setAttribute('role', 'alert');
        toast.innerHTML = `
            <div class="d-flex">
                <div class="toast-body">${message}</div>
                <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
            </div>
        `;

        toastContainer.appendChild(toast);

        // 显示toast
        const bsToast = new bootstrap.Toast(toast, {
            autohide: true,
            delay: 3000
        });
        bsToast.show();

        // 移除已隐藏的toast
        toast.addEventListener('hidden.bs.toast', () => {
            toast.remove();
        });
    }

    createToastContainer() {
        const container = document.createElement('div');
        container.className = 'toast-container position-fixed bottom-0 end-0 p-3';
        container.style.zIndex = '9999';
        document.body.appendChild(container);
        return container;
    }
}

// 添加旋转动画CSS
const style = document.createElement('style');
style.textContent = `
    @keyframes spin {
        from { transform: rotate(0deg); }
        to { transform: rotate(360deg); }
    }
`;
document.head.appendChild(style);

// 页面加载完成后初始化Dashboard控制器
document.addEventListener('DOMContentLoaded', () => {
    window.dashboardController = new DashboardController();
});
