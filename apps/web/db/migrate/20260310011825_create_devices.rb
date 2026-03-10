class CreateDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :platform, null: false
      t.string :app_version
      t.string :access_token, null: false
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :devices, :access_token, unique: true
    add_index :devices, %i[user_id name platform], unique: true
  end
end
