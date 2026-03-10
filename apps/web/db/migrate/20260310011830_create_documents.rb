class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string :fingerprint, null: false
      t.string :title
      t.string :filename, null: false
      t.integer :page_count
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :documents, :fingerprint, unique: true
  end
end
