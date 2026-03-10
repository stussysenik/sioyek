class CreateBookmarks < ActiveRecord::Migration[8.1]
  def change
    create_table :bookmarks do |t|
      t.references :library_entry, null: false, foreign_key: true
      t.references :device, null: false, foreign_key: true
      t.string :external_id, null: false
      t.integer :page_index, null: false
      t.string :label
      t.text :note
      t.datetime :client_updated_at, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :bookmarks, %i[library_entry_id external_id], unique: true
  end
end
