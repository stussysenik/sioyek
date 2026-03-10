# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_10_011845) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "bookmarks", force: :cascade do |t|
    t.datetime "client_updated_at", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "device_id", null: false
    t.string "external_id", null: false
    t.string "label"
    t.bigint "library_entry_id", null: false
    t.text "note"
    t.integer "page_index", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_bookmarks_on_device_id"
    t.index ["library_entry_id", "external_id"], name: "index_bookmarks_on_library_entry_id_and_external_id", unique: true
    t.index ["library_entry_id"], name: "index_bookmarks_on_library_entry_id"
  end

  create_table "devices", force: :cascade do |t|
    t.string "access_token", null: false
    t.string "app_version"
    t.datetime "created_at", null: false
    t.datetime "last_seen_at"
    t.string "name", null: false
    t.string "platform", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["access_token"], name: "index_devices_on_access_token", unique: true
    t.index ["user_id", "name", "platform"], name: "index_devices_on_user_id_and_name_and_platform", unique: true
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "fingerprint", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "page_count"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["fingerprint"], name: "index_documents_on_fingerprint", unique: true
  end

  create_table "highlights", force: :cascade do |t|
    t.text "anchor"
    t.text "annotation_text"
    t.datetime "client_updated_at", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "device_id", null: false
    t.string "external_id", null: false
    t.bigint "library_entry_id", null: false
    t.integer "page_index", null: false
    t.text "quote"
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_highlights_on_device_id"
    t.index ["library_entry_id", "external_id"], name: "index_highlights_on_library_entry_id_and_external_id", unique: true
    t.index ["library_entry_id"], name: "index_highlights_on_library_entry_id"
  end

  create_table "library_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "custom_title"
    t.bigint "document_id", null: false
    t.datetime "last_opened_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["document_id"], name: "index_library_entries_on_document_id"
    t.index ["user_id", "document_id"], name: "index_library_entries_on_user_id_and_document_id", unique: true
    t.index ["user_id"], name: "index_library_entries_on_user_id"
  end

  create_table "notes", force: :cascade do |t|
    t.text "body"
    t.datetime "client_updated_at", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "device_id", null: false
    t.string "external_id", null: false
    t.bigint "highlight_id"
    t.bigint "library_entry_id", null: false
    t.integer "page_index", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_notes_on_device_id"
    t.index ["highlight_id"], name: "index_notes_on_highlight_id"
    t.index ["library_entry_id", "external_id"], name: "index_notes_on_library_entry_id_and_external_id", unique: true
    t.index ["library_entry_id"], name: "index_notes_on_library_entry_id"
  end

  create_table "reader_sessions", force: :cascade do |t|
    t.datetime "client_updated_at"
    t.datetime "created_at", null: false
    t.integer "current_page", default: 0, null: false
    t.bigint "device_id", null: false
    t.boolean "fit_to_window", default: true, null: false
    t.datetime "last_opened_at"
    t.bigint "library_entry_id", null: false
    t.datetime "updated_at", null: false
    t.float "zoom", default: 1.0, null: false
    t.index ["device_id"], name: "index_reader_sessions_on_device_id"
    t.index ["library_entry_id", "device_id"], name: "index_reader_sessions_on_library_entry_id_and_device_id", unique: true
    t.index ["library_entry_id"], name: "index_reader_sessions_on_library_entry_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "bookmarks", "devices"
  add_foreign_key "bookmarks", "library_entries"
  add_foreign_key "devices", "users"
  add_foreign_key "highlights", "devices"
  add_foreign_key "highlights", "library_entries"
  add_foreign_key "library_entries", "documents"
  add_foreign_key "library_entries", "users"
  add_foreign_key "notes", "devices"
  add_foreign_key "notes", "highlights"
  add_foreign_key "notes", "library_entries"
  add_foreign_key "reader_sessions", "devices"
  add_foreign_key "reader_sessions", "library_entries"
end
