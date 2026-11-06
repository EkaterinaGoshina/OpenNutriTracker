// Exercises the family RPCs and RLS as different users. Run with `npm test`
// in this folder.
import { createHarness, ids } from './harness.mjs';

const { ok, as, one, fails, done } = await createHarness();

// Profiles
const profiles = (await as('admin', 'select user_id, display_name from public.profiles order by user_id')).rows;
ok(profiles.map((p) => p.display_name).join(',') === 'Анна,boris,Clara,dima', 'profiles created on sign-up');

// Creating a family
await fails('A', "select public.create_family('   ')", 'invalid_name', 'blank family name rejected');
const fam = (await one('A', "select public.create_family('Титовы') as id")).id;
ok(!!fam, 'A creates a family');
await fails('A', "select public.create_family('Ещё')", 'already_in_family', 'second family rejected');

// Invites
await fails('B', 'select * from public.create_invite()', 'not_in_family', 'outsider cannot invite');
const inv = await one('A', 'select * from public.create_invite()');
ok(/^[A-Z2-9]{8}$/.test(inv.code) && !/[IO01]/.test(inv.code), `invite code looks right (${inv.code})`);
const hours = (new Date(inv.expires_at) - Date.now()) / 3.6e6;
ok(hours > 47.9 && hours <= 48, 'invite lives 48 hours');

// Joining
const messy = ` ${inv.code.slice(0, 4).toLowerCase()}-${inv.code.slice(4)} `;
ok((await one('B', 'select public.join_family($1) as id', [messy])).id === fam, 'B joins with a lowercase dashed code');
ok((await one('B', 'select public.join_family($1) as id', [inv.code])).id === fam, 'reopening the link is idempotent');
await fails('C', 'select public.join_family($1)', 'invite_used', 'used code rejected', [inv.code]);
await fails('C', "select public.join_family('ZZZZZZZZ')", 'invite_not_found', 'unknown code rejected');
await fails('B', 'select * from public.create_invite()', 'not_owner', 'member cannot invite');

const old = await one('A', 'select * from public.create_invite()');
await as('admin', "update public.family_invites set expires_at = now() - interval '1 minute' where code = $1", [old.code]);
await fails('C', 'select public.join_family($1)', 'invite_expired', 'expired code rejected', [old.code]);

// A member of another family cannot join
const famD = (await one('D', "select public.create_family('Другие') as id")).id;
const forD = await one('A', 'select * from public.create_invite()');
await fails('D', 'select public.join_family($1)', 'already_in_family', 'member of another family cannot join', [forD.code]);

// RLS reads
ok((await as('B', 'select id from public.families')).rows.length === 1, 'B sees their family');
ok((await as('B', 'select user_id from public.family_members')).rows.length === 2, 'B sees both members');
ok((await as('B', 'select user_id from public.profiles')).rows.length === 2, 'B sees family profiles only');
ok((await as('C', 'select id from public.families')).rows.length === 0, 'C sees no family');
ok((await as('C', 'select user_id from public.family_members')).rows.length === 0, 'C sees no members');
ok((await as('C', 'select user_id from public.profiles')).rows.length === 1, 'C sees only own profile');
ok((await as('D', 'select id from public.families')).rows.map((r) => r.id).join() === famD, 'D sees only their own family');
ok((await as('B', 'select code from public.family_invites')).rows.length === 0, 'member sees no invites');
ok((await as('A', 'select code from public.family_invites')).rows.length === 3, 'owner sees invites');
ok((await one('B', 'select public.is_family_member($1) as v', [fam])).v === true, 'is_family_member true for member');
ok((await one('C', 'select public.is_family_member($1) as v', [fam])).v === false, 'is_family_member false for outsider');
ok((await one('B', 'select public.my_family_id() as v')).v === fam, 'my_family_id');

// Direct writes
await fails('B', `insert into public.family_members values ('${famD}', '${ids.B}', 'owner')`, 'permission denied', 'no direct insert into members');
await fails('C', `insert into public.families (name) values ('x')`, 'permission denied', 'no direct insert into families');
await fails('B', `update public.family_members set role = 'owner'`, 'permission denied', 'no direct role change');
await fails('A', `delete from public.family_members where user_id = '${ids.B}'`, 'permission denied', 'no direct member delete');
ok((await as('B', "update public.families set name = 'Хак'")).affectedRows === 0, 'member cannot rename family');
ok((await as('A', "update public.families set name = 'Семья'")).affectedRows === 1, 'owner renames family');
await fails('A', "update public.families set created_by = null", 'permission denied', 'owner cannot touch other family columns');
ok((await as('B', `update public.profiles set display_name = 'x' where user_id = '${ids.A}'`)).affectedRows === 0, 'cannot rename someone else');
ok((await as('B', "update public.profiles set display_name = 'Боря'")).affectedRows === 1, 'renames own profile');
ok((await as('B', `delete from public.family_invites where code = '${forD.code}'`)).affectedRows === 0, 'member cannot revoke invites');
ok((await as('A', `delete from public.family_invites where code = '${forD.code}'`)).affectedRows === 1, 'owner revokes a pending invite');
ok((await as('A', `delete from public.family_invites where code = '${inv.code}'`)).affectedRows === 0, 'used invite is kept');

// Anonymous callers get nothing
await fails('anon', 'select * from public.families', 'permission denied', 'anon cannot read families');
await fails('anon', "select public.create_family('x')", 'permission denied', 'anon cannot call RPCs');
await fails('anon', `select public.is_family_member('${fam}')`, 'permission denied', 'anon cannot call helpers');

// Invite cap
for (let i = 0; i < 8; i++) await as('D', 'select * from public.create_invite()');
await as('D', 'select * from public.create_invite()');
await as('D', 'select * from public.create_invite()');
await fails('D', 'select * from public.create_invite()', 'too_many_invites', 'eleventh pending invite rejected');

// Removing members
const forC = await one('A', 'select * from public.create_invite()');
await as('C', 'select public.join_family($1)', [forC.code]);
await fails('B', `select public.remove_member('${ids.C}')`, 'not_owner', 'member cannot remove');
await fails('A', `select public.remove_member('${ids.A}')`, 'owner_must_transfer', 'owner cannot remove self');
await fails('A', `select public.remove_member('${ids.D}')`, 'not_a_member', 'cannot remove outsider');
await as('A', `select public.remove_member('${ids.C}')`);
ok((await as('C', 'select id from public.families')).rows.length === 0, 'removed member loses access');

// Leaving and ownership
await fails('A', 'select public.leave_family()', 'owner_must_transfer', 'owner cannot leave with members');
await fails('A', `select public.transfer_ownership('${ids.C}')`, 'not_a_member', 'cannot hand over to outsider');
await as('A', `select public.transfer_ownership('${ids.B}')`);
ok((await one('B', 'select role from public.family_members where user_id = auth.uid()')).role === 'owner', 'B is owner after transfer');
await as('A', 'select public.leave_family()');
ok((await as('A', 'select id from public.families')).rows.length === 0, 'A left');
await as('B', 'select public.leave_family()');
ok((await as('admin', 'select id from public.families where id = $1', [fam])).rows.length === 0, 'last member leaving deletes the family');
ok((await as('admin', 'select code from public.family_invites where family_id = $1', [fam])).rows.length === 0, 'its invites are gone');
await fails('B', 'select public.leave_family()', 'not_in_family', 'leaving twice');

// Deleted auth user: the family keeps an owner
const forA = await one('D', 'select code from public.family_invites limit 1');
await as('A', 'select public.join_family($1)', [forA.code]);
await as('admin', `delete from auth.users where id = '${ids.D}'`);
ok((await one('A', 'select role from public.family_members where user_id = auth.uid()')).role === 'owner', 'oldest member promoted when owner account is deleted');
await as('admin', `delete from auth.users where id = '${ids.A}'`);
ok((await as('admin', 'select id from public.families where id = $1', [famD])).rows.length === 0, 'family deleted with its last account');

done();
