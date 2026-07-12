const test = require('node:test');
const assert = require('node:assert/strict');
const { publicAccount, publicCapture, publicDictionary } = require('../lib/public-dto');

test('public DTOs never expose credentials', () => {
  const account = publicAccount({ user_id: 'u1', nickname: 'N', token: 'secret', cookie: 'c' });
  const capture = publicCapture({ user_id: 'u1', token: 'secret', user_info: { private: true } }, 'cap');
  const dictionary = publicDictionary({ words: [{ term: 'alpha', auto: true, internal: 'x' }] });
  assert.equal(JSON.stringify({ account, capture, dictionary }).includes('secret'), false);
  assert.equal(JSON.stringify({ account, capture, dictionary }).includes('private'), false);
  assert.deepEqual(dictionary.words, [{ term: 'alpha', auto: true }]);
});
