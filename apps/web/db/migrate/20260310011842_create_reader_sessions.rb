class CreateReaderSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :reader_sessions do |t|
      t.references :library_entry, null: false, foreign_key: true
      t.references :device, null: false, foreign_key: true
      t.integer :current_page, null: false, default: 0
      t.float :zoom, null: false, default: 1.0
      t.boolean :fit_to_window, null: false, default: true
      t.datetime :last_opened_at
      t.datetime :client_updated_at

      t.timestamps
    end

    add_index :reader_sessions, %i[library_entry_id device_id], unique: true
  end
end
