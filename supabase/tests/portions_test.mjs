// Exercises the cook's portions: who can serve to whom, the recipient's
// mailbox, idempotent retries and what happens when people leave. Run with
// `npm test` in this folder.
import { createHarness, ids } from './harness.mjs';

const { ok, as, one, fails, done } = await createHarness();

const P1 = '11111111-1111-4111-8111-111111111111';
const P2 = '22222222-2222-4222-8222-222222222222';
const P3 = '33333333-3333-4333-8333-333333333333';
const payload = { unit: 'g', amount: 320, type: 'dinner', dateTime: '2026-11-11T19:00:00Z', meal: { name: 'Борщ' } };
const item = (id, to, p = payload) => ({ id, recipient_id: ids[to], payload: p });
const serve = 'select public.serve_portions($1::jsonb) as n';
const receive = 'select public.receive_portions($1::uuid[]) as n';
const pending = "select id from public.family_portions where recipient_id = auth.uid() and received_at is null order by created_at";

// A, B, D are one family, C is another, E (added here) is in none.
ids.E = '00000000-0000-4000-8000-00000000000e';
await as('admin', `insert into auth.users (id, email, raw_user_meta_data) values ('${ids.E}', 'eva@example.com', '{}')`);
await as('A', "select public.create_family('Титовы')");
for (const who of ['B', 'D']) {
  const inv = await one('A', 'select * from public.create_invite()');
  await as(who, 'select public.join_family($1)', [inv.code]);
}
await as('C', "select public.create_family('Другие')");

// Who can serve
await fails('E', serve, 'not_in_family', 'outside a family nothing is served', [JSON.stringify([item(P1, 'B')])]);
await fails('anon', serve, 'permission denied', 'anon cannot serve', [JSON.stringify([item(P1, 'B')])]);
await fails('A', serve, 'invalid_portion', 'the cook cannot serve themselves', [JSON.stringify([item(P1, 'A')])]);
await fails('A', serve, 'not_a_member', 'cannot serve another family', [JSON.stringify([item(P1, 'C')])]);
await fails('A', serve, 'not_a_member', 'cannot serve a stranger', [JSON.stringify([item(P1, 'E')])]);

// Validation
await fails('A', serve, 'invalid_portion', 'empty batch rejected', ['[]']);
await fails('A', serve, 'invalid_portion', 'non-array batch rejected', ['{}']);
await fails('A', serve, 'invalid_portion', 'payload must be an object', [JSON.stringify([{ id: P1, recipient_id: ids.B, payload: [] }])]);
await fails('A', serve, 'invalid_portion', 'id must be a uuid', [JSON.stringify([{ id: 'x', recipient_id: ids.B, payload }])]);
const many = Array.from({ length: 21 }, (_, i) => item(`aaaaaaaa-aaaa-4aaa-8aaa-${String(i).padStart(12, '0')}`, 'B'));
await fails('A', serve, 'invalid_portion', 'more than 20 items rejected', [JSON.stringify(many)]);
const huge = { ...payload, blob: 'x'.repeat(40000) };
await fails('A', serve, 'invalid_portion', 'oversized payload rejected', [JSON.stringify([item(P1, 'B', huge)])]);
ok((await as('B', pending)).rows.length === 0, 'a rejected batch leaves nothing behind');

// All or nothing: a bad second item takes the first one back
await fails('A', serve, 'not_a_member', 'a bad item fails the whole batch', [JSON.stringify([item(P1, 'B'), item(P2, 'C')])]);
ok((await as('B', pending)).rows.length === 0, 'the good item was not kept');

// Serving to two people at once
ok((await one('A', serve, [JSON.stringify([item(P1, 'B'), item(P2, 'D')])])).n === 2, 'A serves B and D in one call');
ok((await as('B', pending)).rows.map((r) => r.id).join() === P1, 'B sees only their own portion');
ok((await as('D', pending)).rows.map((r) => r.id).join() === P2, 'D sees only their own portion');
const mine = await one('B', 'select * from public.family_portions where id = $1', [P1]);
ok(mine.payload.meal.name === 'Борщ' && mine.payload.amount === 320, 'the payload arrives intact');
ok(mine.cook_id === ids.A, 'the portion names its cook');

// Who can read
ok((await as('D', 'select id from public.family_portions where id = $1', [P1])).rows.length === 0, 'D cannot read the portion meant for B');
ok((await as('A', 'select id from public.family_portions')).rows.length === 2, 'the cook reads what they served');
ok((await as('C', 'select id from public.family_portions')).rows.length === 0, 'another family sees nothing');
await fails('anon', 'select * from public.family_portions', 'permission denied', 'anon cannot read');

// Retry is safe, a clash is not
ok((await one('A', serve, [JSON.stringify([item(P1, 'B')])])).n === 0, 'serving the same id again adds nothing');
ok((await as('B', pending)).rows.length === 1, 'and does not duplicate it');
await fails('A', serve, 'invalid_portion', 'the same id aimed at someone else is refused', [JSON.stringify([item(P1, 'D')])]);
await fails('B', serve, 'invalid_portion', 'someone else\'s id cannot be reused', [JSON.stringify([item(P1, 'D')])]);

// The recipient's mailbox
await fails('A', 'update public.family_portions set payload = \'{}\'', 'permission denied', 'no direct update');
await fails('B', 'delete from public.family_portions', 'permission denied', 'no direct delete');
ok((await one('D', receive, [[P1]])).n === 0, 'D cannot mark B\'s portion');
ok((await as('B', pending)).rows.length === 1, 'it stays pending for B');
ok((await one('B', receive, [[P1, P3]])).n === 1, 'B marks theirs; unknown ids are ignored');
ok((await as('B', pending)).rows.length === 0, 'a received portion is no longer pending');
ok((await one('B', receive, [[P1]])).n === 0, 'marking twice changes nothing');
ok((await one('A', 'select received_at from public.family_portions where id = $1', [P1])).received_at !== null, 'the cook can see it was received');

// Membership changes
await as('A', serve, [JSON.stringify([item(P3, 'B')])]);
await as('A', `select public.remove_member('${ids.B}')`);
ok((await as('B', 'select id from public.family_portions')).rows.length === 0, 'a removed member loses access to their mailbox');
await fails('A', serve, 'not_a_member', 'a removed member cannot be served', [JSON.stringify([item('44444444-4444-4444-8444-444444444444', 'B')])]);
await as('admin', `delete from auth.users where id = '${ids.A}'`);
ok((await one('admin', 'select cook_id from public.family_portions where id = $1', [P2])).cook_id === null, 'a deleted cook leaves the portion authorless');
ok((await as('D', pending)).rows.length === 1, 'and it still reaches D');
await as('D', 'select public.leave_family()');
ok((await as('D', 'select id from public.family_portions')).rows.length === 0, 'a member who left sees nothing');

done();
