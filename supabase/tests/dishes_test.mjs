// Exercises the shared dishes: who sees and edits them, version conflicts,
// tombstones and the sync cursor. Run with `npm test` in this folder.
import { randomBytes } from 'node:crypto';
import { createHarness, ids } from './harness.mjs';

const { ok, as, one, fails, done } = await createHarness();

const X = '11111111-1111-4111-8111-111111111111';
const Y = '22222222-2222-4222-8222-222222222222';
const borscht = JSON.stringify({ name: 'Борщ', totalWeightG: 3200, ingredients: [] });
const save = 'select public.save_family_dish($1, $2::jsonb, $3, $4) as v';
const del = 'select public.delete_family_dish($1, $2) as v';

// A and B are one family, C another, D in none.
const fam = (await one('A', "select public.create_family('Титовы') as id")).id;
const invite = await one('A', 'select * from public.create_invite()');
await as('B', 'select public.join_family($1)', [invite.code]);
const otherFam = (await one('C', "select public.create_family('Другие') as id")).id;

// Who can write
await fails('D', save, 'not_in_family', 'outside a family nothing is saved', [X, borscht, null, null]);
await fails('anon', save, 'permission denied', 'anon cannot save', [X, borscht, null, null]);
ok((await one('A', save, [X, borscht, null, null])).v === 1, 'A creates a dish at version 1');
await fails('A', save, 'dish_conflict', 'creating an existing id is a conflict', [X, borscht, null, null]);

// Who can read
const row = await one('B', 'select * from public.family_dishes where id = $1', [X]);
ok(row?.payload?.name === 'Борщ', 'B reads the dish');
ok(row?.created_by === ids.A, 'created_by is the author');
ok((await as('C', 'select id from public.family_dishes')).rows.length === 0, 'another family sees nothing');
ok((await as('D', 'select id from public.family_dishes')).rows.length === 0, 'outsider sees nothing');
await fails('anon', 'select * from public.family_dishes', 'permission denied', 'anon cannot read');

// Editing and conflicts
const cursor = (await one('admin', 'select max(updated_at) as t from public.family_dishes')).t;
const edited = JSON.stringify({ name: 'Борщ зелёный', totalWeightG: 3000, ingredients: [] });
ok((await one('B', save, [X, edited, null, 1])).v === 2, 'B edits on top of version 1');
await fails('A', save, 'dish_conflict', 'A editing stale version 1 is refused', [X, borscht, null, 1]);
await fails('A', save, 'dish_conflict', 'A editing a future version is refused', [X, borscht, null, 9]);
ok((await one('A', 'select payload->>$2 as n from public.family_dishes where id = $1', [X, 'name'])).n === 'Борщ зелёный', 'B\'s edit stands');

// Validation
await fails('A', save, 'invalid_dish', 'array payload rejected', [Y, '[]', null, null]);
const huge = JSON.stringify({ name: 'x', blob: randomBytes(300000).toString('hex') });
await fails('A', save, 'invalid_dish', 'oversized payload rejected', [Y, huge, null, null]);
const foreignKey = `families/${otherFam}/33333333-3333-4333-8333-333333333333.webp`;
await fails('A', save, 'invalid_dish', 'photo key of another family rejected', [Y, borscht, foreignKey, null]);
await fails('A', save, 'invalid_dish', 'photo key outside the families prefix rejected', [Y, borscht, 'secret/x.webp', null]);
const ownKey = `families/${fam}/33333333-3333-4333-8333-333333333333.webp`;
ok((await one('A', save, [Y, borscht, ownKey, null])).v === 1, 'photo key under own family accepted');

// Sync cursor: everything changed after it, nothing before
const changed = (await as('B', 'select id from public.family_dishes where updated_at > $1 order by updated_at', [cursor])).rows.map((r) => r.id);
ok(changed.join() === `${X},${Y}`, 'cursor returns the edited and the new dish');

// Deleting
await fails('B', del, 'dish_conflict', 'deleting a stale version is refused', [Y, 7]);
ok((await one('B', del, [Y, 1])).v === 2, 'B deletes Y at its version');
const tomb = await one('A', 'select * from public.family_dishes where id = $1', [Y]);
ok(tomb.deleted_at !== null && JSON.stringify(tomb.payload) === '{}' && tomb.photo_key === null, 'tombstone keeps no content or photo');
ok((await one('A', del, [Y, null])).v === 2, 'deleting again is a no-op');
await fails('A', save, 'dish_deleted', 'saving a deleted dish is refused', [Y, borscht, null, 2]);
ok((await one('A', del, [X, null])).v === 3, 'null version deletes whatever is there');
await fails('A', del, 'dish_conflict', 'deleting an unknown dish', ['44444444-4444-4444-8444-444444444444', null]);
const deletedAfter = (await as('B', 'select id from public.family_dishes where updated_at > $1 and deleted_at is not null', [cursor])).rows.length;
ok(deletedAfter === 2, 'cursor also returns tombstones');

// No direct writes
await fails('A', `insert into public.family_dishes (family_id, id, payload) values ('${fam}', gen_random_uuid(), '{}')`, 'permission denied', 'no direct insert');
await fails('A', "update public.family_dishes set payload = '{}'", 'permission denied', 'no direct update');
await fails('A', 'delete from public.family_dishes', 'permission denied', 'no direct delete');

// The same dish id lives on independently in another family
ok((await one('C', save, [X, borscht, null, null])).v === 1, 'same id can exist in another family');
ok((await as('C', 'select id from public.family_dishes')).rows.length === 1, 'C sees only their own copy');

// Membership changes
const fresh = '55555555-5555-4555-8555-555555555555';
await as('B', save, [fresh, borscht, null, null]);
await as('A', `select public.remove_member('${ids.B}')`);
ok((await as('B', 'select id from public.family_dishes')).rows.length === 0, 'removed member loses the dishes');
await fails('B', save, 'not_in_family', 'removed member cannot save', [fresh, borscht, null, 1]);
ok((await as('A', 'select id from public.family_dishes where id = $1', [fresh])).rows.length === 1, 'their dishes stay with the family');
await as('admin', `delete from auth.users where id = '${ids.B}'`);
ok((await one('A', 'select created_by from public.family_dishes where id = $1', [fresh])).created_by === null, 'deleted account leaves the dish authorless');
await as('C', 'select public.leave_family()');
ok((await one('admin', 'select count(*)::int as n from public.family_dishes where family_id = $1', [otherFam])).n === 0, 'a deleted family takes its dishes');

done();
