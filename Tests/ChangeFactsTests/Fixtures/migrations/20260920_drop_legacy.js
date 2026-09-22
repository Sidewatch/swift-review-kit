/** Knex migration written by the agent. There is no down step. */
exports.up = async function (knex) {
  await knex.schema.dropTableIfExists('legacy_profiles');
  await knex.schema.alterTable('users', (table) => {
    table.dropColumn('bio');
  });
  // await knex('sessions').del();  // commented out
  await knex.raw('DELETE FROM sessions');
};
