class CreateLibraryEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :library_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.string :custom_title
      t.datetime :last_opened_at

      t.timestamps
    end

    add_index :library_entries, %i[user_id document_id], unique: true
  end
end
