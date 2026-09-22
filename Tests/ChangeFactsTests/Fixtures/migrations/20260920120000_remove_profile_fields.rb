class RemoveProfileFields < ActiveRecord::Migration[7.1]
  def up
    remove_column :users, :bio
    change_column :users, :age, :string
    drop_table :legacy_profiles
    # remove_column :users, :email   -- commented out, never runs
    execute "DELETE FROM sessions"
  end
end
