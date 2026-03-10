class CreateHighlights < ActiveRecord::Migration[8.1]
  def change
    create_table :highlights do |t|
      t.references :library_entry, null: false, foreign_key: true
      t.references :device, null: false, foreign_key: true
      t.string :external_id, null: false
      t.integer :page_index, null: false
      t.text :quote
      t.string :color
      t.text :anchor
      t.text :annotation_text
      t.datetime :client_updated_at, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :highlights, %i[library_entry_id external_id], unique: true
  end
end
