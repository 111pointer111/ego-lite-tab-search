import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execute } from './runtime.mjs';

function fixture() {
  const spaces = [
    { id: 0, name: '工作', profileId: 'p', profileName: '个人', ownership: 'user', recentTabTitles: ['相同标题'] },
    { id: 1, name: '工作', profileId: 'q', profileName: '公司', ownership: 'user', recentTabTitles: ['相同标题'] },
    { id: 99, name: '标签搜索工具 · test', profileId: 'p', profileName: '个人', ownership: 'agent' },
  ];
  const targets = [
    { targetId: 'own', type: 'page', browserContextId: 'a', title: '新标签页', url: 'chrome://newtab/' },
    { targetId: 'first', type: 'page', browserContextId: 'a', title: '相同标题', url: 'https://example.test/one' },
    { targetId: 'second', type: 'page', browserContextId: 'b', title: '相同标题', url: 'https://example.test/two' },
  ];
  const windows = { own: 999, first: 100, second: 200 };
  const actions = [];
  const task = {
    spaceId: 99,
    tabs: async () => [{ targetId: 'own' }],
    cdp: async (method, params) => {
      actions.push({ method, params });
      if (method === 'Target.getTargets') return { targetInfos: targets };
      if (method === 'Browser.getWindowForTarget') return { windowId: windows[params.targetId] };
      return {};
    },
    finish: async () => ({ closedSpace: true }),
  };
  const api = { listTaskSpaces: async () => spaces, taskSpace: async () => task };
  return { api, actions, targets, windows, spaces };
}

async function run(api, request) {
  let result;
  await execute(api, { helperKey: 'test', ...request }, line => {
    result = JSON.parse(line.slice('__EGO_TAB_SEARCH__'.length));
  });
  return result;
}

test('live bridge inventory shape preserves duplicate names across profiles', async () => {
  const { api } = fixture();
  const result = await run(api, { action: 'list' });
  assert.equal(result.ok, true);
  assert.equal(result.tabs.length, 2);
  assert.deepEqual(result.tabs.map(tab => tab.spaceId), [0, 1]);
  assert.deepEqual(result.tabs.map(tab => tab.profileName), ['个人', '公司']);
  assert.equal(result.ambiguousWindows, 0);
});

test('activation checks target, window and profile context before switching', async () => {
  const { api, actions } = fixture();
  assert.equal((await run(api, { action: 'activate', targetId: 'second', windowId: 200, contextId: 'b' })).ok, true);
  assert.equal(actions.at(-1).method, 'Target.activateTarget');
});

test('closed or moved tabs return a recoverable error', async () => {
  const { api, actions } = fixture();
  assert.equal((await run(api, { action: 'activate', targetId: 'missing' })).ok, false);
  assert.equal((await run(api, { action: 'activate', targetId: 'second', windowId: 100, contextId: 'b' })).ok, false);
  assert.equal((await run(api, { action: 'activate', targetId: 'second', windowId: 200, contextId: 'old' })).ok, false);
  assert(!actions.some(action => action.method === 'Target.activateTarget'));
});

test('quitting before the first search does not create a helper space', async () => {
  const api = { listTaskSpaces: async () => [], taskSpace: async () => assert.fail('must not create') };
  assert.equal((await run(api, { action: 'finish' })).ok, true);
});

test('user takeover stops the bridge without creating or claiming another space', async () => {
  const { api, spaces } = fixture();
  spaces.find(space => space.id === 99).ownership = 'user';
  api.taskSpace = async () => assert.fail('must respect user control');
  assert.equal((await run(api, { action: 'list' })).ok, false);
  assert.equal((await run(api, { action: 'finish' })).ok, true);
});
