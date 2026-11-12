import { resolveSpaces, displaySpace } from './mapping.mjs';

const marker = '__EGO_TAB_SEARCH__';

export async function execute(api, request = {}, emit = value => console.log(value)) {
  try {
    const helperName = request.helperKey ? `标签搜索工具 · ${request.helperKey}` : '标签搜索工具';
    let spaces = await api.listTaskSpaces();
    const existing = spaces.find(space => space.name === helperName && space.ownership === 'agent');
    if (request.action === 'finish' && !existing) {
      emit(marker + JSON.stringify({ ok: true }));
      return;
    }
    if (!existing && spaces.some(space => space.name === helperName)) {
      throw new Error('标签搜索工具空间当前由用户控制，连接已停止。');
    }
    const task = await api.taskSpace(existing ? existing.id : helperName);
    if (request.action === 'finish') {
      emit(marker + JSON.stringify({ ok: true, cleanup: await task.finish({ keep: [] }) }));
      return;
    }
    const allTargets = (await task.cdp('Target.getTargets')).targetInfos || [];
    if (request.action === 'activate') {
      const target = allTargets.find(target => target.targetId === request.targetId);
      if (!target) throw new Error('这个标签页已关闭，请刷新搜索结果。');
      // Verify the identity again before activating a result from an older snapshot.
      const location = await task.cdp('Browser.getWindowForTarget', { targetId: target.targetId });
      if (location.windowId !== request.windowId || target.browserContextId !== request.contextId) {
        throw new Error('这个标签页已移动，请刷新后重试。');
      }
      await task.cdp('Target.activateTarget', { targetId: target.targetId });
      emit(marker + JSON.stringify({ ok: true }));
      return;
    }

    const ownTabs = await task.tabs();
    const ownTarget = allTargets.find(target => ownTabs.some(tab => tab.targetId === target.targetId));
    if (!ownTarget) throw new Error('搜索连接尚未就绪，请重试。');
    const ownWindow = (await task.cdp('Browser.getWindowForTarget', { targetId: ownTarget.targetId })).windowId;
    spaces = await api.listTaskSpaces();
    const ownSpace = spaces.find(space => space.id === task.spaceId);
    const userSpaces = spaces.filter(space => space.id !== task.spaceId);
    const groups = new Map();
    for (const target of allTargets.filter(target => target.type === 'page' || target.type === 'browser_ui')) {
      if (target.url.startsWith('chrome://omnibox-popup')) continue;
      let windowId;
      try {
        windowId = (await task.cdp('Browser.getWindowForTarget', { targetId: target.targetId })).windowId;
      } catch {
        // A target can close during enumeration. Browser UI targets may have no window.
        continue;
      }
      if (windowId === ownWindow) continue;
      if (!groups.has(windowId)) groups.set(windowId, { windowId, contextId: target.browserContextId, tabs: [] });
      groups.get(windowId).tabs.push({ id: target.targetId, title: target.title || target.url || '新标签页', url: target.url });
    }
    const windows = [...groups.values()];
    const contextProfiles = { [ownTarget.browserContextId]: ownSpace.profileId };
    const otherProfiles = [...new Set(userSpaces.map(space => space.profileId))].filter(id => id !== ownSpace.profileId);
    const otherContexts = [...new Set(windows.map(window => window.contextId))].filter(id => id !== ownTarget.browserContextId);
    if (otherProfiles.length === 1 && otherContexts.length === 1) contextProfiles[otherContexts[0]] = otherProfiles[0];
    // Additional profiles can be identified when all observed space titles point to one context.
    for (const context of otherContexts.filter(id => !contextProfiles[id])) {
      const titles = new Set(windows.filter(window => window.contextId === context).flatMap(window => window.tabs.map(tab => tab.title)));
      const profileIds = [...new Set(userSpaces.filter(space => space.recentTabTitles?.length && space.recentTabTitles.every(title => titles.has(title))).map(space => space.profileId))];
      if (profileIds.length === 1) contextProfiles[context] = profileIds[0];
    }
    const mapped = resolveSpaces(windows, userSpaces, contextProfiles, request.bindings || []);
    const tabs = mapped.flatMap(window => window.tabs.map(tab => ({
      ...tab,
      windowId: window.windowId,
      contextId: window.contextId,
      profileName: userSpaces.find(space => space.profileId === contextProfiles[window.contextId])?.profileName || 'Profile 待确认',
      spaceId: window.space?.id ?? null,
      spaceName: window.space ? displaySpace(window.space) : '选择所属空间',
      candidates: window.candidates.map(space => ({ id: space.id, name: displaySpace(space), profileName: space.profileName })),
    })));
    emit(marker + JSON.stringify({ ok: true, tabs, ambiguousWindows: mapped.filter(window => !window.space).length }));
  } catch (error) {
    emit(marker + JSON.stringify({ ok: false, error: error.message || '无法连接 ego lite。' }));
  }
}
