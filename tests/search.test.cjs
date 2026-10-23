const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../Search.js'), 'utf8'), context);
const rows = [
  { name: 'other', path: '/home/me/dotfiles/other', primary: true },
  { name: 'dotfiles', path: '/home/me/Projects/dotfiles', primary: true },
  { name: 'SqlLinqer', path: '/home/me/work/SqlLinqer', primary: false },
  { name: 'same', path: '/home/me/a/same', primary: false },
  { name: 'same', path: '/home/me/b/same', primary: true },
];
assert.equal(context.rank(rows, 'dotfiles')[0].name, 'dotfiles');
assert.equal(context.rank(rows, 'SQLL')[0].name, 'SqlLinqer');
assert.equal(context.rank(rows, 'work sql')[0].name, 'SqlLinqer');
assert.equal(context.rank(rows, 'same')[0].primary, true);
assert.equal(context.rank(rows, 'no-such-project').length, 0);
assert.equal(context.rank(rows, '')[0].name, 'other');
assert.equal(context.rank(rows, 'other')[0].path, rows[0].path);
assert.equal(context.plainLabel('a\tb\nc'), 'a b c');
assert.equal(context.fuzzyScore('a', 'aa'), -Infinity);
assert(context.fuzzyScore('project-picker', 'pp') > context.fuzzyScore('pepper', 'pp'));
console.log('Search ranking tests passed.');
