class WlUserOvertime < ActiveRecord::Base
  unloadable
  include WlScopeExtension::Dates
  include WlScopeExtension::Users
  include WlCommonValidation

  belongs_to :wl_project_window
  belongs_to :user

  validates :start_date, date: true, presence: true
  validates :end_date, date: true, presence: true
  validates :wl_project_window_id, presence: true
  validates :user_id, presence: true
  validates :overtime_hours, presence: true, numericality: { :greater_than => 0 }


  validate :end_date_not_before_start_date
  validate :dates_not_beyond_project_window
  validate :custom_alloc_per_user_uniq_within_period

  attr_accessible :start_date, :end_date, :overtime_hours, :wl_project_window_id, :user_id

private
  
end