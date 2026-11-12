import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolveSpaces, displaySpace } from './mapping.mjs';

const window = (id, titles, contextId = 'a') => ({ windowId: id, contextId, tabs: titles.map(title => ({ title })) });
const space = (id, titles, profileId = 'p', name = '同名空间') => ({ id, profileId, name, recentTabTitles: titles });

test('global assignment resolves a repeated title by eliminating the other window', () => {
  const result = resolveSpaces([window(10, ['共享标题', '唯一标题']), window(20, ['共享标题'])],
    [space(0, ['唯一标题']), space(1, ['共享标题'])], { a: 'p' });
  assert.deepEqual(result.map(window => window.space.id), [0, 1]);
});

test('fully identical windows remain ambiguous and allow duplicate space names', () => {
  const result = resolveSpaces([window(10, ['同名标签']), window(20, ['同名标签'])],
    [space(0, ['同名标签']), space(1, ['同名标签'])], { a: 'p' });
  assert(result.every(window => window.space === null));
  assert(result.every(window => window.candidates.length === 2));
});

test('manual binding resolves the remaining one-to-one assignment', () => {
  const result = resolveSpaces([window(10, ['同名标签']), window(20, ['同名标签'])],
    [space(0, ['同名标签']), space(1, ['同名标签'])], { a: 'p' }, [{ windowId: 10, contextId: 'a', spaceId: 1 }]);
  assert.deepEqual(result.map(window => window.space.id), [1, 0]);
});

test('profile IDs keep identical titles and names in separate accounts', () => {
  const result = resolveSpaces([window(10, ['同名'], 'a'), window(20, ['同名'], 'b')],
    [space(0, ['同名'], 'p'), space(1, ['同名'], 'q')], { a: 'p', b: 'q' });
  assert.deepEqual(result.map(window => window.space.profileId), ['p', 'q']);
});

test('a binding from an earlier browser context is discarded', () => {
  const result = resolveSpaces([window(10, ['同名'])], [space(0, ['同名']), space(1, ['同名'])],
    { a: 'p' }, [{ windowId: 10, contextId: 'old-context', spaceId: 1 }]);
  assert.equal(result[0].space, null);
});

test('an inconsistent inventory does not invent a space assignment', () => {
  const result = resolveSpaces([window(10, ['已变更标题'])], [space(0, ['旧标题'])], { a: 'p' });
  assert.equal(result[0].space, null);
  assert.deepEqual(result[0].candidates, []);
});

test('recent titles are a multiset and unnamed space zero remains valid', () => {
  const result = resolveSpaces([window(10, ['相同', '相同']), window(20, ['相同'])],
    [space(0, ['相同', '相同'], 'p', ''), space(1, ['相同'])], { a: 'p' });
  assert.equal(result[0].space.id, 0);
  assert.equal(displaySpace(result[0].space), '未命名空间 · #0');
});
