# This file is auto-generated from the current state of the database.
ActiveRecord::Schema[7.1].define(version: 2026_09_20_120000) do
  enable_extension "plpgsql"

  create_table "users", force: :cascade do |t|
    t.string "email", limit: 120, null: false
    t.string "name"
    t.integer "legacy_id"
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "profiles", force: :cascade do |t|
    t.text "bio", null: false
    t.references "user", null: false, foreign_key: true
    t.timestamps
  end

  create_table "posts", id: :bigint, force: :cascade do |t|
    t.string "title", limit: 200, null: false
    t.text "body"
    t.boolean "published", default: false
    t.bigint "author_id", null: false
    t.decimal "price", precision: 10, scale: 2
    t.timestamps
    t.index ["author_id", "title"], name: "index_posts_on_author_id_and_title", unique: true
  end

  # create_table "drafts" do |t| end   -- commented out

  add_foreign_key "posts", "users", column: "author_id"
  add_index "posts", ["published"], name: "index_posts_on_published"
end
