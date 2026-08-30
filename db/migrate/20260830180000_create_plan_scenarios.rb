# frozen_string_literal: true

class CreatePlanScenarios < ActiveRecord::Migration[7.2]
  def change
    create_table :plan_scenarios, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid

      t.string :name, null: false
      t.string :path, null: false

      t.timestamps
    end
  end
end
