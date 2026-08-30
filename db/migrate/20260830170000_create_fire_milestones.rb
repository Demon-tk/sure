# frozen_string_literal: true

class CreateFireMilestones < ActiveRecord::Migration[7.2]
  def change
    create_table :fire_milestones, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid

      t.string :name, null: false
      t.integer :start_age, null: false
      t.integer :end_age
      t.decimal :one_time_amount, precision: 19, scale: 4, null: false, default: 0
      t.decimal :annual_amount, precision: 19, scale: 4, null: false, default: 0
      t.string :affects, null: false, default: "expenses"
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_check_constraint :fire_milestones,
                         "affects IN ('income', 'expenses', 'portfolio')",
                         name: "chk_fire_milestones_affects"
  end
end
