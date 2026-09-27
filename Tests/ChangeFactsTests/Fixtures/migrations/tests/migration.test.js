// A test that checks the generated SQL: the words are here, nothing runs against data.
test('drops the legacy table', () => {
  expect(sql).toBe('DROP TABLE legacy_profiles');
});
