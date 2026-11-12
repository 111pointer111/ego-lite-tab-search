// Browser window IDs and space IDs are different namespaces.
// Resolve the complete inventory together so duplicate titles do not force a guess.
export function resolveSpaces(windows, spaces, contextProfiles, bindings = []) {
  const candidates = windows.map(window => spaces.filter(space => {
    if (contextProfiles[window.contextId] !== space.profileId) return false;
    const available = new Map();
    for (const tab of window.tabs) available.set(tab.title, (available.get(tab.title) || 0) + 1);
    for (const title of space.recentTabTitles || []) {
      const count = available.get(title) || 0;
      if (!count) return false;
      available.set(title, count - 1);
    }
    return true;
  }).map(space => space.id));

  const validBindings = bindings.filter(binding => {
    const index = windows.findIndex(window => window.windowId === binding.windowId && window.contextId === binding.contextId);
    return index >= 0 && candidates[index].includes(binding.spaceId);
  });
  const pinnedSpaces = new Map();
  const pinnedWindows = new Map();
  for (const binding of validBindings) {
    if (pinnedSpaces.has(binding.spaceId)) continue;
    const index = windows.findIndex(window => window.windowId === binding.windowId && window.contextId === binding.contextId);
    pinnedSpaces.set(binding.spaceId, index);
    pinnedWindows.set(index, binding.spaceId);
  }
  const edges = candidates.map((ids, index) => pinnedWindows.has(index)
    ? [pinnedWindows.get(index)]
    : ids.filter(id => !pinnedSpaces.has(id)));

  function match(removedWindow = -1, removedSpace = -1) {
    const owners = new Map();
    function visit(index, seen) {
      for (const id of edges[index]) {
        if ((index === removedWindow && id === removedSpace) || seen.has(id)) continue;
        seen.add(id);
        if (!owners.has(id) || visit(owners.get(id), seen)) {
          owners.set(id, index);
          return true;
        }
      }
      return false;
    }
    for (let index = 0; index < windows.length; index++) visit(index, new Set());
    return owners;
  }
  const assignment = match();
  const complete = assignment.size === windows.length && windows.length === spaces.length;
  return windows.map((window, index) => {
    const assigned = [...assignment].find(([, owner]) => owner === index)?.[0];
    const forced = assigned !== undefined && (pinnedWindows.has(index) ||
      (complete && match(index, assigned).size < assignment.size));
    return {
      ...window,
      space: forced ? spaces.find(space => space.id === assigned) : null,
      candidates: spaces.filter(space => candidates[index].includes(space.id)),
    };
  });
}

export function displaySpace(space) {
  return space.name?.trim() || `未命名空间 · #${space.id}`;
}
