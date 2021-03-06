module WlMember
	include WlProjectWindowLogic

	def self.all_for_project(project)
		display_role_ids_list = WlProjectWindowLogic.retrieve_display_role_ids_list(project)
		member_role_ids = MemberRole.where(role_id: display_role_ids_list).pluck(:id)

		return Member.includes(:member_roles, :project, :user).where(users: {status: 1}, project_id: project.id, member_roles: {id: member_role_ids}).to_a.uniq
	end
	
	def get_check_ratio(from_date, to_date)
		leave_project_id = RedmineLeavesHolidays::Setting.defaults_settings(:default_project_id)
		wl_user = self.user
		wl_project = self.project
		start_week = from_date
		end_week = to_date # the trigger should be done by the end of the week

		date_list = []
		current_date = start_week
		daily_ratio_total = 0
		ratio = 0

		overtime_table =  WlUserOvertime.where(user_id: self.user_id, wl_project_window_id: wl_project.wl_project_window.id)
		logged_hours_table = wl_user.get_logged_time(wl_project, start_week, end_week)
		leave_table = wl_user.get_logged_time(Project.find(leave_project_id), start_week, end_week)
	
		while current_date <= end_week
			
			logged_hours = logged_hours_table[current_date]
			logged_hours = 0 if logged_hours.nil?
			daily_alloc_hours = 0
			extra_hours_per_day = 0
			alloc_hours_total = 0
			daily_basis_hours = (wl_user.actual_weekly_working_hours/5).round(2)

			#bank_holiday?
			unless wl_user.holiday_date_for_user(current_date) 
				if current_date.cwday != 6 && current_date.cwday != 7
					daily_alloc_percent = self.wl_project_allocation_between(current_date, current_date)
					daily_alloc_hours  = (wl_user.actual_weekly_working_hours*daily_alloc_percent)/(100*5)
				end
			end

			unless leave_table[current_date].nil?
				if leave_table[current_date].round(2) == daily_basis_hours
					#full day off - put the alloc to 0
					daily_alloc_hours = 0

				elsif leave_table[current_date].round(2) == (daily_basis_hours/2).round(2)
					#half day off - cut the alloc to half
					daily_alloc_hours = daily_alloc_hours/2

				else
					#NO change
				end
					
			end


			#overtime?
			unless overtime_table.empty?
		      overtime = overtime_table.overlaps(current_date, current_date).first
		    else
		      overtime = nil
		    end

		    unless overtime.nil?
		      extra_hours_per_day = (overtime.overtime_hours.to_f / overtime.overtime_days_count).round(1)
		  	end

		    unless extra_hours_per_day==0 && daily_alloc_hours==0
		    	alloc_hours_total= extra_hours_per_day + daily_alloc_hours
		    	date_list << current_date
		    end

		    daily_ratio_total += logged_hours/alloc_hours_total unless alloc_hours_total == 0
				    
			current_date = current_date+1
		end

		unless date_list.empty?
			ratio = (daily_ratio_total/date_list.size).round(2)
		else
			ratio = nil
		end

 		return ratio

	end


	def self.members_for_project_role(project, role_id)
    	member_role_ids = MemberRole.where(role_id: role_id).pluck(:id)
		members_list = Member.includes(:member_roles, :project, :user).where(users: {status: 1}, project_id: project.id, member_roles: {id: member_role_ids}).to_a.uniq
		return members_list
	end	




end
