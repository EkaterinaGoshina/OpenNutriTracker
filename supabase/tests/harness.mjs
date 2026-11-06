// Shared test harness: applies every migration to an in-memory Postgres
// (PGlite) with a minimal stand-in for Supabase's auth schema and roles, and
// runs queries as one of four signed-in users, anonymously, or as admin.
import { PGlite } from '@electric-sql/pglite';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

export const ids = {
  A: '00000000-0000-4000-8000-00000000000a',
  B: '00000000-0000-4000-8000-00000000000b',
  C: '00000000-0000-4000-8000-00000000000c',
  D: '00000000-0000-4000-8000-00000000000d',
};

export async function createHarness() {
  const migrationsDir = join(import.meta.dirname, '..', 'migrations');
  const migrations = readdirSync(migrationsDir)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => readFileSync(join(migrationsDir, f), 'utf8'));
  const db = new PGlite();

  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create schema auth;
    create table auth.users (
      id uuid primary key,
      email text,
      raw_user_meta_data jsonb default '{}'::jsonb
    );
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    grant usage on schema auth, public to anon, authenticated;
    grant execute on function auth.uid() to anon, authenticated;
    -- Mimic Supabase's default privileges so the migrations' revokes matter.
    alter default privileges in schema public grant all on tables to anon, authenticated;
    alter default privileges in schema public grant all on functions to anon, authenticated;
  `);
  for (const sql of migrations) await db.exec(sql);

  await db.exec(`
    insert into auth.users (id, email, raw_user_meta_data) values
      ('${ids.A}', 'anna@example.com', '{"full_name":"Анна"}'),
      ('${ids.B}', 'boris@example.com', '{}'),
      ('${ids.C}', 'clara@example.com', '{"name":"Clara"}'),
      ('${ids.D}', 'dima@example.com', '{}');
  `);

  let failures = 0;
  const ok = (cond, label) => {
    console.log(`${cond ? 'ok  ' : 'FAIL'} ${label}`);
    if (!cond) failures++;
  };

  async function as(who, sql, params = []) {
    await db.exec('reset role');
    if (who === 'admin') {
      await db.query("select set_config('request.jwt.claim.sub', '', false)");
    } else if (who === 'anon') {
      await db.query("select set_config('request.jwt.claim.sub', '', false)");
      await db.exec('set role anon');
    } else {
      await db.query("select set_config('request.jwt.claim.sub', $1, false)", [ids[who]]);
      await db.exec('set role authenticated');
    }
    try {
      return await db.query(sql, params);
    } finally {
      await db.exec('reset role');
    }
  }
  const one = async (who, sql, params) => (await as(who, sql, params)).rows[0];
  async function fails(who, sql, expected, label, params) {
    try {
      await as(who, sql, params);
      ok(false, `${label} (no error, expected ${expected})`);
    } catch (e) {
      ok(e.message.includes(expected), `${label} -> ${e.message}`);
    }
  }
  function done() {
    console.log(failures ? `\n${failures} failed` : '\nall passed');
    process.exit(failures ? 1 : 0);
  }

  return { db, ok, as, one, fails, done };
}
