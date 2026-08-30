require "test_helper"

class FireMilestoneTest < ActiveSupport::TestCase
  setup do
    @kids = fire_milestones(:kids)
    @windfall = fire_milestones(:windfall)
  end

  test "valid fixtures save" do
    assert @kids.valid?
    assert @windfall.valid?
  end

  test "name is required" do
    @kids.name = ""
    assert_not @kids.valid?
  end

  test "affects must be one of the allowed values" do
    @kids.affects = "vibes"
    assert_not @kids.valid?
    assert_includes @kids.errors[:affects], "is not included in the list"
  end

  test "end_age cannot be before start_age" do
    @kids.end_age = @kids.start_age - 1
    assert_not @kids.valid?
    assert_includes @kids.errors[:end_age], "must be greater than or equal to start age"
  end

  test "covers? is true within the annual window" do
    assert @kids.covers?(32)
    assert @kids.covers?(41)
    assert @kids.covers?(50)
  end

  test "covers? is false outside the annual window" do
    assert_not @kids.covers?(31)
    assert_not @kids.covers?(51)
  end

  test "covers? treats a nil end_age as a single-year window" do
    assert @windfall.covers?(40)
    assert_not @windfall.covers?(41)
  end

  test "covers? is false when inactive" do
    @kids.active = false
    assert_not @kids.covers?(35)
  end

  test "active scope excludes inactive milestones" do
    @kids.update!(active: false)
    assert_includes FireMilestone.active, @windfall
    assert_not_includes FireMilestone.active, @kids
  end

  test "family association exposes its milestones" do
    family = families(:dylan_family)
    assert_includes family.fire_milestones, @kids
    assert_includes family.fire_milestones, @windfall
  end

  test "destroying the family destroys its milestones" do
    family = Family.create!(name: "Milestone Test Family")
    family.fire_milestones.create!(name: "Test", start_age: 30, affects: "expenses")

    assert_difference -> { FireMilestone.count }, -1 do
      family.destroy
    end
  end
end
