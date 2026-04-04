(function() {
    const ICON_MAP = {
        'bi-circle-half': 'theme',
        'bi-sun': 'sun',
        'bi-moon-stars': 'moon',
        'bi-layout-sidebar-inset': 'panel',
        'bi-arrow-clockwise': 'refresh',
        'bi-arrow-repeat': 'refresh',
        'bi-person-circle': 'user',
        'bi-broadcast': 'radar',
        'bi-star': 'star',
        'bi-star-fill': 'star',
        'bi-cloud-upload': 'upload',
        'bi-cloud-arrow-up': 'upload',
        'bi-clipboard2': 'clipboard',
        'bi-clipboard2-image': 'clipboard',
        'bi-arrow-return-left': 'turn',
        'bi-arrow-up': 'arrow-up',
        'bi-plus-circle': 'plus',
        'bi-check2-square': 'check-square',
        'bi-check-circle': 'check',
        'bi-check-lg': 'check',
        'bi-x-octagon': 'close-octagon',
        'bi-x-circle': 'close-circle',
        'bi-x': 'close',
        'bi-trash': 'trash',
        'bi-trash3': 'trash',
        'bi-grid': 'grid',
        'bi-devices': 'devices',
        'bi-pc-display': 'devices',
        'bi-folder2-open': 'folder',
        'bi-folder-fill': 'folder',
        'bi-folder': 'folder',
        'bi-chevron-down': 'chevron-down',
        'bi-arrow-left-right': 'transfer',
        'bi-arrow-right': 'arrow-right',
        'bi-sort-up': 'sort-asc',
        'bi-sort-down': 'sort-desc',
        'bi-sliders': 'sliders',
        'bi-gear': 'sliders',
        'bi-shield-lock': 'shield',
        'bi-shield-check': 'shield',
        'bi-file-earmark': 'file',
        'bi-file-text': 'file',
        'bi-download': 'download',
        'bi-hourglass-split': 'hourglass',
        'bi-hdd': 'drive',
        'bi-cpu': 'cpu',
        'bi-memory': 'memory',
        'bi-eye': 'eye',
        'bi-eye-slash': 'eye-off',
        'bi-list-task': 'list',
        'bi-exclamation-triangle': 'warning',
        'bi-house': 'home',
        'bi-speedometer2': 'dashboard',
        'bi-graph-up': 'chart',
        'bi-lightning': 'bolt',
        'bi-music-note-beamed': 'music',
        'bi-play-fill': 'play',
        'bi-pause-fill': 'pause',
        'bi-stop-fill': 'stop',
        'bi-skip-start-fill': 'skip-prev',
        'bi-skip-end-fill': 'skip-next',
        'bi-volume-up-fill': 'volume',
        'bi-volume-down-fill': 'volume',
        'bi-volume-off-fill': 'volume',
        'bi-volume-mute-fill': 'volume',
        'bi-info-circle': 'info',
    };

    const SPRITE_PATH = '/static/icons/sprite.svg';

    function normalizeClassList(input) {
        if (Array.isArray(input)) {
            return input.filter(Boolean);
        }
        if (typeof input === 'string') {
            return input.split(/\s+/).filter(Boolean);
        }
        return Array.from(input || []).filter(Boolean);
    }

    function resolveIconNameFromClasses(classes) {
        const biClass = classes.find((cls) => cls.startsWith('bi-'));
        return biClass ? (ICON_MAP[biClass] || 'spark') : 'spark';
    }

    function resolveIconName(node) {
        return resolveIconNameFromClasses(normalizeClassList(node.classList || []));
    }

    function buildSvgFromClasses(classes, iconName) {
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('viewBox', '0 0 24 24');
        svg.setAttribute('aria-hidden', 'true');
        svg.classList.add('sl-icon');
        normalizeClassList(classes).forEach((cls) => {
            if (cls !== 'bi' && !cls.startsWith('bi-')) {
                svg.classList.add(cls);
            }
        });

        const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
        const href = `${SPRITE_PATH}#${iconName}`;
        use.setAttribute('href', href);
        use.setAttributeNS('http://www.w3.org/1999/xlink', 'xlink:href', href);
        svg.appendChild(use);
        return svg;
    }

    function buildSvg(node, iconName) {
        return buildSvgFromClasses(node.classList || [], iconName);
    }

    function replaceIcon(node) {
        if (!node || !node.classList || !node.classList.contains('bi')) {
            return;
        }
        const svg = buildSvg(node, resolveIconName(node));
        node.replaceWith(svg);
    }

    function setIcon(target, classNames) {
        if (!target) {
            return null;
        }
        const host = (target.matches && (target.matches('svg.sl-icon') || target.matches('i.bi')))
            ? target
            : target.querySelector?.('svg.sl-icon, i.bi');
        if (!host) {
            return null;
        }

        const classes = normalizeClassList(classNames);
        const iconName = resolveIconNameFromClasses(classes);
        const svg = buildSvgFromClasses(classes, iconName);
        host.replaceWith(svg);
        return svg;
    }

    function upgrade(root = document) {
        if (!root) {
            return;
        }
        if (root.nodeType === 1 && root.matches && root.matches('i.bi')) {
            replaceIcon(root);
            return;
        }
        const scope = root.querySelectorAll ? root : document;
        scope.querySelectorAll('i.bi').forEach(replaceIcon);
    }

    function observe() {
        if (!window.MutationObserver || !document.body) {
            return;
        }
        const observer = new MutationObserver((mutations) => {
            mutations.forEach((mutation) => {
                mutation.addedNodes.forEach((node) => {
                    if (node.nodeType !== 1) {
                        return;
                    }
                    upgrade(node);
                });
            });
        });
        observer.observe(document.body, {
            childList: true,
            subtree: true,
        });
    }

    window.SoonLinkIcons = {
        upgrade,
        setIcon,
    };

    document.addEventListener('DOMContentLoaded', () => {
        upgrade(document);
        observe();
    });
})();
