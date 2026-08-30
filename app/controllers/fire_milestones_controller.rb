class FireMilestonesController < ApplicationController
  before_action :require_preview_features!

  def create
    @milestone = Current.family.fire_milestones.build(fire_milestone_params)

    if @milestone.save
      redirect_back fallback_location: fire_plan_path
    else
      flash[:alert] = @milestone.errors.full_messages.to_sentence
      redirect_back fallback_location: fire_plan_path
    end
  end

  def destroy
    Current.family.fire_milestones.find(params[:id]).destroy
    redirect_back fallback_location: fire_plan_path
  end

  private
    def fire_milestone_params
      params.require(:fire_milestone).permit(:name, :affects, :start_age, :end_age, :one_time_amount, :annual_amount)
    end
end
