class CreatePackages < ActiveRecord::Migration[5.2]
  def change
    create_table :packages do |t|
      t.string  :name
      t.string  :version
      t.date    :publication_date
      t.string  :title
      t.string  :description
      t.string  :author
      t.string  :maintainer
      t.timestamps
    end
  end
end
