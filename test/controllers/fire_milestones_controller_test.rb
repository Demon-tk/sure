require "test_helper"

class FireMilestonesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "redirects users without preview access" do
    disable_preview_features

    post fire_milestones_url, params: { fire_milestone: valid_milestone_params }

    assert_redirected_to root_path
    assert_equal 2, @user.family.fire_milestones.count
  end

  test "create with valid params saves a family milestone and redirects" do
    enable_preview_features

    assert_difference -> { @user.family.fire_milestones.count }, +1 do
      post fire_milestones_url, params: { fire_milestone: valid_milestone_params }
    end

    milestone = @user.family.fire_milestones.order(:created_at).last
    assert_equal "Social Security", milestone.name
    assert_equal "income", milestone.affects
    assert_equal 67, milestone.start_age
    assert_equal BigDecimal("24000"), milestone.annual_amount
    assert_redirected_to fire_plan_path
  end

  test "create with invalid params (blank name) redirects with an alert" do
    enable_preview_features

    assert_no_difference -> { @user.family.fire_milestones.count } do
      post fire_milestones_url, params: { fire_milestone: valid_milestone_params.merge(name: "") }
    end

    assert_redirected_to fire_plan_path
    assert flash[:alert].present?
  end

  test "destroy removes a milestone owned by the family" do
    enable_preview_features

    milestone = fire_milestones(:kids)

    assert_difference -> { @user.family.fire_milestones.count }, -1 do
      delete fire_milestone_url(milestone)
    end

    assert_redirected_to fire_plan_path
    assert_raises(ActiveRecord::RecordNotFound) { milestone.reload }
  end

  test "destroy of another family's milestone returns not found" do
    enable_preview_features

    other_family = Family.create!(name: "Other", currency: "USD", locale: "en", country: "US", timezone: "UTC")
    foreign_milestone = other_family.fire_milestones.create!(
      name: "Foreign pension",
      affects: "income",
      start_age: 67,
      annual_amount: 10_000,
      one_time_amount: 0
    )

    delete fire_milestone_url(foreign_milestone)

    assert_response :not_found
    assert foreign_milestone.reload.persisted?
  end

  private
    def valid_milestone_params
      {
        name: "Social Security",
        affects: "income",
        start_age: 67,
        annual_amount: 24_000,
        one_time_amount: 0
      }
    end

    def enable_preview_features
      @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    end

    def disable_preview_features
      @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => false))
    end
end
