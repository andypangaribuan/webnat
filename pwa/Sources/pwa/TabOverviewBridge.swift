import Foundation
import WebKit

class TabOverviewBridge: NSObject, WKScriptMessageHandler {
    weak var appDelegate: AppDelegate?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        DispatchQueue.main.async { [weak self] in
            guard let app = self?.appDelegate else { return }
            switch action {
            case "selectTab":
                if let id = body["id"] as? String {
                    app.selectTab(byId: id)
                    app.hideTabOverview()
                }
            case "closeTab":
                if let id = body["id"] as? String {
                    app.closeTab(byId: id)
                }
            case "newTab":
                app.hideTabOverview()
                app.createNewTabAndLoadHome()
            case "openBookmark":
                if let url = body["url"] as? String, !url.isEmpty {
                    app.hideTabOverview()
                    app.createNewTab(with: nil, initialUrl: url, switchTo: true)
                }
            case "deleteBookmark":
                if let id = body["id"] as? String {
                    app.deleteBookmark(byId: id)
                }
            case "reorderBookmarks":
                if let ids = body["ids"] as? [String] {
                    app.reorderBookmarks(orderedIds: ids)
                }
            case "dismiss":
                app.hideTabOverview()
            default:
                break
            }
        }
    }

    static let overviewHTML: String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
        * { box-sizing: border-box; user-select: none; -webkit-user-select: none; scrollbar-width: none; }
        *::-webkit-scrollbar { display: none; width: 0; height: 0; }
        html, body {
            margin: 0; padding: 0; width: 100%; height: 100%;
            background: #363638;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            color: #f2f2f7;
            overflow-y: auto;
        }
        .top-bar {
            position: sticky;
            top: 0;
            z-index: 30;
            display: flex;
            align-items: center;
            justify-content: flex-end;
            padding: 12px 20px;
            background: rgba(54, 54, 56, 0.88);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
        }
        .top-controls {
            position: relative;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .search-wrapper {
            position: relative;
            width: 220px;
        }
        .search-icon {
            position: absolute;
            left: 9px;
            top: 50%;
            transform: translateY(-50%);
            width: 13px;
            height: 13px;
            opacity: 0.65;
            pointer-events: none;
        }
        .search-input {
            width: 100%;
            height: 28px;
            background: rgba(0, 0, 0, 0.32);
            border: 1px solid rgba(255, 255, 255, 0.14);
            border-radius: 7px;
            padding: 5px 10px 5px 28px;
            color: #fff;
            font-size: 12.5px;
            outline: none;
            transition: border-color 0.15s, background 0.15s;
        }
        .search-input::placeholder {
            color: rgba(255, 255, 255, 0.45);
        }
        .search-input:focus {
            background: rgba(0, 0, 0, 0.48);
            border-color: rgba(255, 255, 255, 0.35);
        }
        .bookmark-btn {
            height: 28px;
            padding: 0 10px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 5px;
            background: rgba(0, 0, 0, 0.32);
            border: 1px solid rgba(255, 255, 255, 0.14);
            border-radius: 7px;
            color: rgba(255, 255, 255, 0.85);
            font-size: 12px;
            font-weight: 500;
            cursor: pointer;
            outline: none;
            transition: background 0.15s, border-color 0.15s, color 0.15s;
        }
        .bookmark-btn:hover,
        .bookmark-btn.active {
            background: rgba(0, 0, 0, 0.52);
            border-color: rgba(255, 255, 255, 0.35);
            color: #fff;
        }
        .bookmark-btn svg {
            width: 13px;
            height: 13px;
            stroke: currentColor;
            flex-shrink: 0;
        }
        .bookmark-dropdown {
            position: absolute;
            top: calc(100% + 6px);
            left: 0;
            right: 0;
            min-width: 280px;
            max-height: 360px;
            overflow-y: auto;
            background: rgba(32, 32, 35, 0.96);
            backdrop-filter: blur(24px);
            -webkit-backdrop-filter: blur(24px);
            border: 1px solid rgba(255, 255, 255, 0.16);
            border-radius: 9px;
            box-shadow: 0 14px 36px rgba(0, 0, 0, 0.55);
            padding: 6px;
            display: none;
            z-index: 50;
        }
        .bookmark-dropdown.open {
            display: block;
        }
        .bookmark-empty {
            padding: 14px 12px;
            text-align: center;
            font-size: 12px;
            color: rgba(255, 255, 255, 0.45);
            line-height: 1.4;
        }
        .bookmark-item {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 7px 9px;
            border-radius: 6px;
            cursor: pointer;
            position: relative;
            transition: background 0.12s, opacity 0.12s;
        }
        .bookmark-item:hover {
            background: rgba(255, 255, 255, 0.12);
        }
        .bookmark-item.drag-source {
            opacity: 0.35;
        }
        .bookmark-drag-ghost {
            position: fixed;
            left: 0;
            top: 0;
            pointer-events: none;
            z-index: 9999;
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 7px 9px;
            border-radius: 7px;
            background: rgba(48, 48, 52, 0.96);
            border: 1px solid rgba(255, 255, 255, 0.22);
            box-shadow: 0 12px 28px rgba(0, 0, 0, 0.6);
            opacity: 0.95;
        }
        .bookmark-drop-indicator {
            position: fixed;
            height: 2px;
            background: #4da3ff;
            border-radius: 2px;
            pointer-events: none;
            z-index: 9998;
            box-shadow: 0 0 6px rgba(77, 163, 255, 0.85);
            display: none;
        }
        .bookmark-drop-indicator::before {
            content: '';
            position: absolute;
            left: -4px;
            top: -3px;
            width: 8px;
            height: 8px;
            border-radius: 50%;
            background: #4da3ff;
            box-shadow: 0 0 6px rgba(77, 163, 255, 0.85);
        }
        .bookmark-info {
            flex: 1;
            min-width: 0;
            display: flex;
            flex-direction: column;
            gap: 2px;
        }
        .bookmark-title {
            font-size: 12.5px;
            font-weight: 500;
            color: #f2f2f7;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .bookmark-url {
            font-size: 11px;
            color: rgba(255, 255, 255, 0.45);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .bookmark-del-btn {
            width: 20px;
            height: 20px;
            border-radius: 4px;
            border: none;
            background: transparent;
            color: rgba(255, 255, 255, 0.4);
            font-size: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            padding: 0;
            flex-shrink: 0;
            transition: background 0.12s, color 0.12s;
        }
        .bookmark-del-btn:hover {
            background: rgba(255, 255, 255, 0.16);
            color: #fff;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
            gap: 28px;
            width: 100%;
            padding: 24px 48px 64px 48px;
        }
        .card {
            aspect-ratio: 16 / 10;
            border-radius: 12px;
            overflow: hidden;
            background: #1e1e20;
            box-shadow: 0 12px 30px rgba(0, 0, 0, 0.42);
            display: flex;
            flex-direction: column;
            cursor: pointer;
            transition: transform 0.16s cubic-bezier(0.2, 0.8, 0.2, 1), box-shadow 0.16s ease;
            position: relative;
        }
        .card:hover {
            transform: scale(1.02);
            box-shadow: 0 16px 38px rgba(0, 0, 0, 0.55);
        }
        .card.active {
            box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.45), 0 14px 34px rgba(0, 0, 0, 0.5);
        }
        .card-header {
            height: 30px;
            background: #232326;
            display: flex;
            align-items: center;
            padding: 0 10px;
            position: relative;
            border-bottom: 1px solid rgba(255, 255, 255, 0.06);
            flex-shrink: 0;
        }
        .close-btn {
            width: 18px;
            height: 18px;
            border-radius: 4px;
            border: none;
            background: transparent;
            color: rgba(255, 255, 255, 0.55);
            font-size: 14px;
            line-height: 1;
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            padding: 0;
            z-index: 2;
            transition: background 0.12s, color 0.12s;
        }
        .close-btn:hover {
            background: rgba(255, 255, 255, 0.15);
            color: #fff;
        }
        .title-wrap {
            position: absolute;
            left: 34px;
            right: 34px;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 6px;
            overflow: hidden;
            pointer-events: none;
        }
        .favicon {
            width: 14px;
            height: 14px;
            border-radius: 3px;
            flex-shrink: 0;
        }
        .title-text {
            font-size: 12px;
            font-weight: 500;
            color: #e5e5ea;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .card-body {
            flex: 1;
            width: 100%;
            background: #161618;
            overflow: hidden;
            position: relative;
        }
        .card-body img {
            width: 100%;
            height: 100%;
            object-fit: cover;
            object-position: top center;
            display: block;
        }
        .new-tab-card {
            aspect-ratio: 16 / 10;
            border-radius: 12px;
            background: rgba(255, 255, 255, 0.16);
            display: flex;
            align-items: center;
            justify-content: center;
            cursor: pointer;
            transition: background 0.15s ease, transform 0.16s cubic-bezier(0.2, 0.8, 0.2, 1);
        }
        .new-tab-card:hover {
            background: rgba(255, 255, 255, 0.22);
            transform: scale(1.02);
        }
        .plus-icon {
            width: 52px;
            height: 52px;
            stroke: rgba(255, 255, 255, 0.65);
            stroke-width: 2.2;
        }
    </style>
    </head>
    <body>
        <div class="top-bar">
            <div class="top-controls" id="topControls">
                <div class="search-wrapper">
                    <svg class="search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
                        <circle cx="11" cy="11" r="8"></circle>
                        <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
                    </svg>
                    <input id="searchInput" class="search-input" type="text" placeholder="Search Tabs" autocomplete="off" spellcheck="false" />
                </div>
                <button id="bookmarkBtn" class="bookmark-btn" title="Bookmarks">
                    <svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"></path>
                    </svg>
                </button>
                <div id="bookmarkDropdown" class="bookmark-dropdown"></div>
            </div>
        </div>
        <div id="tabGrid" class="grid"></div>

        <script>
            let allTabs = [];
            let allBookmarks = [];
            let currentActiveId = null;

            const searchInput = document.getElementById('searchInput');
            const tabGrid = document.getElementById('tabGrid');
            const bookmarkBtn = document.getElementById('bookmarkBtn');
            const bookmarkDropdown = document.getElementById('bookmarkDropdown');
            const topControls = document.getElementById('topControls');

            searchInput.addEventListener('input', () => {
                const q = searchInput.value.trim().toLowerCase();
                renderGrid(q);
                renderBookmarks(q);
            });

            bookmarkBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                const isOpen = bookmarkDropdown.classList.toggle('open');
                bookmarkBtn.classList.toggle('active', isOpen);
                if (isOpen) {
                    renderBookmarks(searchInput.value.trim().toLowerCase());
                }
            });

            document.addEventListener('click', (e) => {
                if (!topControls.contains(e.target)) {
                    bookmarkDropdown.classList.remove('open');
                    bookmarkBtn.classList.remove('active');
                }
            });

            window.addEventListener('keydown', (e) => {
                if (e.key === 'Escape') {
                    if (bookmarkDropdown.classList.contains('open')) {
                        bookmarkDropdown.classList.remove('open');
                        bookmarkBtn.classList.remove('active');
                        return;
                    }
                    window.webkit.messageHandlers.tabOverview.postMessage({ action: 'dismiss' });
                }
            });

            window.updateTabs = (tabs, activeId, bookmarks) => {
                allTabs = tabs || [];
                currentActiveId = activeId;
                if (bookmarks !== undefined) {
                    allBookmarks = bookmarks || [];
                }
                const q = searchInput.value.trim().toLowerCase();
                renderGrid(q);
                renderBookmarks(q);
            };

            function getFaviconUrl(urlStr) {
                try {
                    const u = new URL(urlStr);
                    return `https://www.google.com/s2/favicons?sz=64&domain_url=${encodeURIComponent(u.origin)}`;
                } catch {
                    return '';
                }
            }

            function renderBookmarks(query) {
                bookmarkDropdown.innerHTML = '';
                const filtered = allBookmarks.filter(b => {
                    if (!query) return true;
                    return (b.title || '').toLowerCase().includes(query) || (b.url || '').toLowerCase().includes(query);
                });

                if (filtered.length === 0) {
                    const empty = document.createElement('div');
                    empty.className = 'bookmark-empty';
                    empty.textContent = allBookmarks.length === 0
                        ? 'No bookmarks yet. Press Cmd + Ctrl + B on any page to save.'
                        : 'No matching bookmarks.';
                    bookmarkDropdown.appendChild(empty);
                    return;
                }

                let suppressClickState = { active: false };
                let dropIndicator = document.getElementById('bookmarkDropIndicator');
                if (!dropIndicator) {
                    dropIndicator = document.createElement('div');
                    dropIndicator.id = 'bookmarkDropIndicator';
                    dropIndicator.className = 'bookmark-drop-indicator';
                    document.body.appendChild(dropIndicator);
                }
                dropIndicator.style.display = 'none';

                filtered.forEach(b => {
                    const item = document.createElement('div');
                    item.className = 'bookmark-item';
                    item.dataset.id = b.id;

                    item.addEventListener('pointerdown', (e) => {
                        if (e.button !== 0 || e.target.closest('.bookmark-del-btn')) return;
                        e.preventDefault();

                        const startX = e.clientX;
                        const startY = e.clientY;
                        const itemRect = item.getBoundingClientRect();
                        const offsetX = startX - itemRect.left;
                        const offsetY = startY - itemRect.top;

                        let hasDragged = false;
                        let ghostEl = null;
                        let targetRefEl = null;
                        let insertAfterTarget = false;

                        const onPointerMove = (moveEvent) => {
                            const dx = moveEvent.clientX - startX;
                            const dy = moveEvent.clientY - startY;

                            if (!hasDragged && Math.hypot(dx, dy) > 3) {
                                hasDragged = true;
                                item.classList.add('drag-source');

                                ghostEl = item.cloneNode(true);
                                const delInGhost = ghostEl.querySelector('.bookmark-del-btn');
                                if (delInGhost) delInGhost.remove();
                                ghostEl.className = 'bookmark-drag-ghost';
                                ghostEl.style.width = `${itemRect.width}px`;
                                document.body.appendChild(ghostEl);
                            }

                            if (!hasDragged) return;

                            if (ghostEl) {
                                ghostEl.style.transform = `translate3d(${moveEvent.clientX - offsetX}px, ${moveEvent.clientY - offsetY}px, 0)`;
                            }

                            const allRows = Array.from(bookmarkDropdown.querySelectorAll('.bookmark-item'));
                            if (allRows.length === 0) return;

                            let bestRow = allRows[allRows.length - 1];
                            let after = true;
                            for (const row of allRows) {
                                const r = row.getBoundingClientRect();
                                const midY = r.top + r.height / 2;
                                if (moveEvent.clientY < midY) {
                                    bestRow = row;
                                    after = false;
                                    break;
                                }
                            }

                            targetRefEl = bestRow;
                            insertAfterTarget = after;

                            const refRect = bestRow.getBoundingClientRect();
                            const lineY = after ? refRect.bottom : refRect.top;
                            dropIndicator.style.display = 'block';
                            dropIndicator.style.left = `${refRect.left + 6}px`;
                            dropIndicator.style.width = `${refRect.width - 12}px`;
                            dropIndicator.style.top = `${lineY - 1}px`;
                        };

                        const onPointerUp = () => {
                            window.removeEventListener('pointermove', onPointerMove);
                            window.removeEventListener('pointerup', onPointerUp);
                            window.removeEventListener('pointercancel', onPointerUp);

                            if (ghostEl) {
                                ghostEl.remove();
                                ghostEl = null;
                            }
                            dropIndicator.style.display = 'none';
                            item.classList.remove('drag-source');

                            if (hasDragged) {
                                suppressClickState.active = true;
                                setTimeout(() => { suppressClickState.active = false; }, 80);

                                if (targetRefEl && targetRefEl !== item) {
                                    if (insertAfterTarget) {
                                        bookmarkDropdown.insertBefore(item, targetRefEl.nextSibling);
                                    } else {
                                        bookmarkDropdown.insertBefore(item, targetRefEl);
                                    }
                                }

                                const orderedIds = Array.from(bookmarkDropdown.querySelectorAll('.bookmark-item'))
                                    .map(el => el.dataset.id)
                                    .filter(Boolean);

                                const byId = new Map(allBookmarks.map(bm => [bm.id, bm]));
                                const reordered = [];
                                orderedIds.forEach(id => {
                                    if (byId.has(id)) {
                                        reordered.push(byId.get(id));
                                        byId.delete(id);
                                    }
                                });
                                byId.forEach(bm => reordered.push(bm));
                                allBookmarks = reordered;

                                window.webkit.messageHandlers.tabOverview.postMessage({
                                    action: 'reorderBookmarks',
                                    ids: orderedIds
                                });
                            }
                        };

                        window.addEventListener('pointermove', onPointerMove);
                        window.addEventListener('pointerup', onPointerUp);
                        window.addEventListener('pointercancel', onPointerUp);
                    });

                    item.addEventListener('click', () => {
                        if (suppressClickState.active) return;
                        bookmarkDropdown.classList.remove('open');
                        bookmarkBtn.classList.remove('active');
                        window.webkit.messageHandlers.tabOverview.postMessage({ action: 'openBookmark', url: b.url });
                    });

                    const favUrl = getFaviconUrl(b.url);
                    if (favUrl) {
                        const fav = document.createElement('img');
                        fav.className = 'favicon';
                        fav.draggable = false;
                        fav.src = favUrl;
                        fav.onerror = () => { fav.style.display = 'none'; };
                        item.appendChild(fav);
                    }

                    const info = document.createElement('div');
                    info.className = 'bookmark-info';

                    const titleEl = document.createElement('div');
                    titleEl.className = 'bookmark-title';
                    titleEl.textContent = b.title || b.url;

                    const urlEl = document.createElement('div');
                    urlEl.className = 'bookmark-url';
                    urlEl.textContent = b.url;

                    info.appendChild(titleEl);
                    info.appendChild(urlEl);

                    const delBtn = document.createElement('button');
                    delBtn.className = 'bookmark-del-btn';
                    delBtn.innerHTML = '&#10005;';
                    delBtn.title = 'Remove Bookmark';
                    delBtn.addEventListener('click', (e) => {
                        e.stopPropagation();
                        window.webkit.messageHandlers.tabOverview.postMessage({ action: 'deleteBookmark', id: b.id });
                    });

                    item.appendChild(info);
                    item.appendChild(delBtn);
                    bookmarkDropdown.appendChild(item);
                });
            }

            function renderGrid(query) {
                tabGrid.innerHTML = '';
                const filtered = allTabs.filter(t => {
                    if (!query) return true;
                    return (t.title || '').toLowerCase().includes(query) || (t.url || '').toLowerCase().includes(query);
                });

                filtered.forEach(tab => {
                    const card = document.createElement('div');
                    card.className = 'card' + (tab.id === currentActiveId ? ' active' : '');
                    card.addEventListener('click', () => {
                        window.webkit.messageHandlers.tabOverview.postMessage({ action: 'selectTab', id: tab.id });
                    });

                    const header = document.createElement('div');
                    header.className = 'card-header';

                    const closeBtn = document.createElement('button');
                    closeBtn.className = 'close-btn';
                    closeBtn.innerHTML = '&#10005;';
                    closeBtn.title = 'Close Tab';
                    closeBtn.addEventListener('click', (e) => {
                        e.stopPropagation();
                        window.webkit.messageHandlers.tabOverview.postMessage({ action: 'closeTab', id: tab.id });
                    });

                    const titleWrap = document.createElement('div');
                    titleWrap.className = 'title-wrap';

                    const favUrl = getFaviconUrl(tab.url);
                    if (favUrl) {
                        const fav = document.createElement('img');
                        fav.className = 'favicon';
                        fav.src = favUrl;
                        fav.onerror = () => { fav.style.display = 'none'; };
                        titleWrap.appendChild(fav);
                    }

                    const titleText = document.createElement('span');
                    titleText.className = 'title-text';
                    titleText.textContent = tab.title || tab.url || 'Tab';
                    titleWrap.appendChild(titleText);

                    header.appendChild(closeBtn);
                    header.appendChild(titleWrap);

                    const body = document.createElement('div');
                    body.className = 'card-body';
                    if (tab.snapshot) {
                        const img = document.createElement('img');
                        img.src = tab.snapshot;
                        body.appendChild(img);
                    }

                    card.appendChild(header);
                    card.appendChild(body);
                    tabGrid.appendChild(card);
                });

                const plusCard = document.createElement('div');
                plusCard.className = 'new-tab-card';
                plusCard.title = 'New Tab';
                plusCard.innerHTML = `
                    <svg class="plus-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round">
                        <line x1="12" y1="5" x2="12" y2="19"></line>
                        <line x1="5" y1="12" x2="19" y2="12"></line>
                    </svg>
                `;
                plusCard.addEventListener('click', () => {
                    window.webkit.messageHandlers.tabOverview.postMessage({ action: 'newTab' });
                });
                tabGrid.appendChild(plusCard);
            }
        </script>
    </body>
    </html>
    """
}
