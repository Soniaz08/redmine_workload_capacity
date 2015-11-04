module RedmineWorkloadCapacity
  module Helpers

    class WlTimetable
      class MaxLinesLimitReached < Exception
      end

      include ERB::Util
      include Redmine::I18n
      include Redmine::Utils::DateCalculation
      include WlCheckLoggedtimeHelper

      attr_reader :year_from, :month_from, :date_from, :date_to, :zoom, :months, :truncated, :max_rows

      attr_accessor :view
      attr_accessor :project
      attr_accessor :wl_users
      attr_accessor :role_ids

      def initialize(options={})
        @leave_project_id = RedmineLeavesHolidays::Setting.defaults_settings(:default_project_id)
        @project = options[:project]
        @wl_pw_start_date = @project.wl_project_window.start_date if @project.wl_window?
        @wl_pw_end_date = @project.wl_project_window.end_date if @project.wl_window?

        options = options.dup
        if options[:year] && options[:year].to_i >0
          @year_from = options[:year].to_i
          if options[:month] && options[:month].to_i >=1 && options[:month].to_i <= 12
            @month_from = options[:month].to_i
          else
            @month_from = 1
          end
        else
         
          @month_from ||=Date.today.month #wl_pw_start_date.month  #
          @year_from ||=Date.today.year #wl_pw_start_date.year  #
        end
        zoom = (options[:zoom] || User.current.pref[:timeline_zoom]).to_i
        @zoom = (zoom > 0 && zoom < 6) ? zoom : 5

         #((wl_pw_end_date.to_time.to_f - wl_pw_start_date.to_time.to_f)/(1.month)).ceil 
        months =(options[:months] || User.current.pref[:timeline_months]).to_i

        @months = (months > 0 && months < 25) ? months : 1

        if (User.current.logged? && (@zoom != User.current.pref[:timeline_zoom] ||
              @months != User.current.pref[:timeline_months]))
          User.current.pref[:timeline_zoom], User.current.pref[:timeline_months] = @zoom, @months
          User.current.preference.save
        end
        @date_from = Date.civil(@year_from, @month_from, 1)
        @date_to = (@date_from >> @months) - 1
        @users = ''
        @lines = ''
        @number_of_rows = nil
        @truncated = false
        if options.has_key?(:max_rows)
          @max_rows = options[:max_rows]
        else
          @max_rows = 1000
        end
      end

      def common_params
        p = { :controller => 'wl_check_loggedtime', :action => 'show' }
        # if @project
        #  # p.merge({:project_id => @project.id})
        #  p[:action] = 'show_project'
        # end
        return p
      end

      def params
        common_params.merge({:zoom => zoom, :year => year_from,
                             :month => month_from, :months => months})
      end

      def params_previous
        common_params.merge({:year => (date_from << months).year,
                             :month => (date_from << months).month,
                             :zoom => zoom, :months => months})
      end

      def params_next
        common_params.merge({:year => (date_from >> months).year,
                             :month => (date_from >> months).month,
                             :zoom => zoom, :months => months})
      end

      def render(options={})
        options = {:top => 0, :top_increment => 20,
                   :indent_increment => 20, :render => :subject,
                   :format => :html}.merge(options)
        indent = options[:indent] || 4
        @users = '' unless options[:only] == :lines
        @lines = '' unless options[:only] == :users
        @number_of_rows = 0
        begin
          if @project
            options[:indent] = indent
            # render_project(@project, options)
            unless @wl_users.empty?
              @wl_users.each do |user|
                render_user(user, options)
              end
            end
          else

          end
        rescue MaxLinesLimitReached
          @truncated = true
        end
        @users_rendered = true unless options[:only] == :lines
        @lines_rendered = true unless options[:only] == :users
      end

      def number_of_rows
        return @number_of_rows if @number_of_rows
        return @wl_users.distinct.pluck(:user_id)
      end

      def users_list
        return @wl_users.uniq
      end

      # def projects_list_tree
      #   if @projects
      #     # return @user.leave_memberships.map {|m| m.project}
      #     #projects_user = @user.memberships.map {|m| m.project}
      #     plist = []
      #     Project.project_tree(projects) do |p, l|
      #       plist << [p, l]
      #     end
      #     return plist
      #   else
      #     return []
      #   end
      # end

      def members_list(project)
        return [] unless project
        #user_ids = users_list.map(&:id)
        #return project.members.where(user_id: user_ids).includes(:roles).to_a.uniq
        return @project.wl_members.to_a.uniq
      end

      # Returns [[Role 1,[User 1, User 2...]],...]
      # if role_ids
      def roles_users_list(project)
        return [] unless project
        roles_users = project.users_by_role.sort.map {|t| [t[0], t[1].sort{|a,b| a.login <=> b.login}] }
        if @role_ids && !@role_ids.empty?
          return roles_users.delete_if{|t| !t[0].id.in?(@role_ids)}
        else
          return roles_users
        end
      end

  

      def users(options={})
        render(options.merge(:only => :users)) unless @users_rendered
        @users
      end

      def lines(options={})
        render(options.merge(:only => :lines)) unless @lines_rendered
        @lines
      end

      # def render_project(project, options={})
      #   unless wl_users.empty?
      #     wl_users.each do |user|
      #       render_user(user, options)
      #     end
      #   end
      # end

      def render_role(role, options={})

      end

      def render_user(user, options={})
        render_object_row(user, options)
      end

      def render_object_row(object, options)
        class_name = object.class.name.downcase
        send("subject_for_#{class_name}", object, options) unless options[:only] == :lines
        send("line_for_#{class_name}", object, options) unless options[:only] == :subjects
        options[:top] += options[:top_increment]
        @number_of_rows += 1
        if @max_rows && @number_of_rows >= @max_rows
          raise MaxLinesLimitReached
        end
      end

      def subject_for_user(user, options)
        subject(user.name, options, user)
      end

      def line_for_user(user, options)

        member = Member.where(user_id: user.id, project_id: @project.id).first

        start_date = @date_from 
        end_date =  @date_to

        #total_weeks = (end_date.to_time.to_f - start_date.to_time.to_f)/(1.week)

        if member.wl_project_allocation?
          logged_time_table = get_logged_time_table(user.id, @project)

          table_alloc = member.wl_global_table_allocation

          table_alloc.each_with_index do |alloc,i|
            
            start_alloc = alloc[:start_date] 
            end_alloc = alloc[:end_date]

            current_date = start_alloc

            while current_date.between?(start_alloc, end_alloc)
              
              if current_date.between?(start_date, end_date)

                #alloc hours for a day
                alloc_day = ((user.weekly_working_hours*alloc[:percent_alloc])/(100*5)).round(1)

                unless alloc_day==0
                 
                  overtime = WlUserOvertime.where(user_id: user.id, wl_project_window_id: @project.wl_project_window.id).overlaps(current_date, current_date).first
                  unless overtime.nil?
                    extra_hours_per_day = (overtime.overtime_hours.to_f / overtime.overtime_days_count).round(1)
                  else 
                    extra_hours_per_day = 0
                  end
                  #bank holiday
                   is_holiday_date = holiday_date(current_date)

                  #logged_hours for current_date
                  logged_hours = logged_time_table[current_date]
                  logged_hours = 0.0 if logged_hours.nil?

                  #week end - overtime only
                  if current_date.cwday == 6 || current_date.cwday == 7
                    unless overtime.nil?
                      #dont forget bank holiday
                      if (overtime[:include_sat] && current_date.cwday == 6 ) || (overtime[:include_sun] && current_date.cwday == 7) || (overtime[:include_bank_holidays] && is_holiday_date)
                        compare_hours(user, options, current_date, logged_hours, 0, extra_hours_per_day) 
                      end
                    end

                  else
                  #other days
                    if !is_holiday_date #&& extra_hours_per_day!=0  &&
                      compare_hours(user, options, current_date, logged_hours, alloc_day, extra_hours_per_day)
                    elsif is_holiday_date && extra_hours_per_day!=0 && overtime[:include_bank_holidays]
                      #case the current date is a bank holiday and not on the week end and there is overtime for bank holiday
                      compare_hours(user, options, current_date, logged_hours, 0, extra_hours_per_day)
                    end
                      

                  end

                end

              end

              current_date = current_date+1

            end

          end

        end
 
      end

      def get_logged_time(user, project_id, current_date)
        TimeEntry.all.where(user_id: user.id, project_id: project_id, spent_on: current_date).sum(:hours)
        #TimeEntryQuery.new(project: Project.find(project_id)).results_scope.where(user_id: user.id, spent_on: current_date).sum(:hours)
        #TimeEntryQuery.new(project: Project.find(37)).results_scope.where(user_id: "159").group(:spent_on).sum(:hours)

      end

      def get_logged_time_table(user_id, project)
        #TimeEntry.all.where(user_id: user.id, project_id: project_id, spent_on: current_date).sum(:hours)
        #TimeEntryQuery.new(project: Project.find(project_id)).results_scope.where(user_id: user.id, spent_on: current_date).sum(:hours)
        TimeEntryQuery.new(project: project).results_scope.where(user_id: user_id).group(:spent_on).sum(:hours)

      end

      def compare_hours(user, options, current_date, logged_hours, allocated_hours, extra_hours = 0)
        output_tooltip = ""
        output_field = ""
        reference_hours = allocated_hours
        if extra_hours > 0
          output_field << " * "
          reference_hours = allocated_hours + extra_hours
        end
        #logged_hours = get_logged_time(user, @project.id, current_date)

        #leave
        leave_time = get_logged_time(user, @leave_project_id, current_date).round(1)

        base_hours = (user.weekly_working_hours/5).round(1)

        unless leave_time == base_hours
          unless reference_hours == 0.0 # there is at least some allocated hours and/or overtime extra hours
            output_tooltip << "Logged time (hours): #{logged_hours.round(1)}"
            output_tooltip << "<br />Allocation time (hours): #{allocated_hours}"
            if logged_hours==0.0
                line(current_date, current_date, options, 2, output_tooltip, output_field)
            else
              # output_tooltip << "Logged time (hours): #{logged_hours.round(1)}"
              # output_tooltip << "<br />Allocation time (hours): #{allocated_hours}"
              if extra_hours > 0
                output_tooltip << "<br />Overtime (hours): #{extra_hours}"
                output_tooltip << "<br />Reference time (hours): #{allocated_hours}+#{extra_hours} = #{reference_hours}"
              end
              ratio = (logged_hours/reference_hours).round(2)
              output_tooltip << "<br /><strong>Ratio</strong>: #{logged_hours.round(1)}/#{reference_hours} = <strong>#{ratio}</strong> "
              
              if logged_hours < reference_hours
                line(current_date, current_date, options, 1, output_tooltip, output_field)
              else 
                line(current_date, current_date, options, 0, output_tooltip, output_field)
              end
            end
          end
        else
          #leave for a whole day
          line(current_date, current_date, options, 4, "Leave Holiday: #{leave_time}hours - full day", "")
        end
      end

      # def subject_for_project(project, options)
      #   subject(project.name, options, project)
      # end

      # def line_for_project(project, options)
      # end

      # def subject_for_role(role, options)
      #   subject(role.name, options, role)
      # end

      # def line_for_role(role, options)
      # end

      def line(start_date, end_date, options, check_status=nil, text, ratio)
        options[:zoom] ||= 1
        options[:g_width] ||= (self.date_to - self.date_from + 1) * options[:zoom]
      
          coords = coordinates(start_date, end_date, options[:zoom])
 
        html_task(options, coords, check_status, text, ratio)

      end

      def subject(label, options, object=nil)
        html_subject(options, label, object)
      end

      def countries
         # @wl_users.distinct.pluck(:region)
         LeavePreference.where(user_id: @wl_users).distinct.pluck(:region)
      end

      # Optimise for date_from - date_to period
      def holiday_date(date)
         countries.map {|c| date.holiday?(c.to_sym, :observed)}.any?
      end

      def country_holiday_list(date)
        # TODO
        # countries.delete_if {|c| !date.holiday?(c.to_sym, :observed)}
      end

      def leave_date(date)
         countries.map {|c| date.holiday?(c.to_sym, :observed)}.any?
      end


      def increment_indent(options, factor=1)
        options[:indent] += options[:indent_increment] * factor
        if block_given?
          yield
          decrement_indent(options, factor)
        end
      end

      def decrement_indent(options, factor=1)
        increment_indent(options, -factor)
      end

    private

      def coordinates(start_date, end_date, zoom=nil)
        zoom ||= @zoom
        coords = {}
        if start_date && end_date && start_date <= self.date_to && end_date >= self.date_from
          if start_date >= self.date_from
            coords[:start] = start_date - self.date_from
            coords[:bar_start] = start_date - self.date_from
          else
            coords[:bar_start] = 0
          end
          if end_date <= self.date_to
            coords[:end] = end_date - self.date_from
            coords[:bar_end] = end_date - self.date_from + 1
          else
            coords[:bar_end] = self.date_to - self.date_from + 1
          end
        end
        # Transforms dates into pixels witdh
        coords.keys.each do |key|
          coords[key] = (coords[key] * zoom).floor
        end
        coords
      end

      def html_subject_content(object)
        user = object
        css_classes = ''
        css_classes << ' icon'

        s = "".html_safe

        s << view.avatar(user,
                        :size => 10,
                        :title => '').to_s.html_safe
        s << " ".html_safe
        s << view.link_to_user(user).html_safe
        view.content_tag(:span, s, :class => css_classes).html_safe
      end

      def html_subject(params, subject, object)
        style = "position: absolute;top:#{params[:top]}px;left:#{params[:indent]}px; "
        style << "width:#{params[:subject_width] - params[:indent]}px;" if params[:subject_width]
        content = html_subject_content(object) || subject
        tag_options = {:style => style}
        case object
        when User
        tag_options[:id] = "issue-#{object.id}"
        tag_options[:class] = "issue-subject"
        tag_options[:title] = object.name
        when Project
          tag_options[:class] = "project-name"
        when Role
          tag_options[:class] = "project-name"
        end 

        output = view.content_tag(:div, content, tag_options)
        @users << output
        output
      end

      def html_task(params, coords, check_status, text, ratio)
        output = ''
        css = "task parent"

        #Renders the tooltip
        if coords[:bar_start] && coords[:bar_end]
       
          s = view.content_tag(:span,
                               "#{text}".html_safe,
                               :class => "tip")
          style = ""
          style << "position: absolute;"
          style << "text-align: center;"
          style << "top:#{params[:top]}px;"
          style << "left:#{coords[:bar_start]}px;"
          style << "width:#{coords[:bar_end] - coords[:bar_start] - 1}px;"
          style << "height:16px;"
          if check_status == 0
            style << "background-color: #19A347;" # green
          elsif check_status == 1
            style << "background-color: #FF9933;" # orange
          elsif check_status == 4 #leave
            style << "background-color: #DADADA;" # grey
          else
            style << "background-color: #CC0000;" # red
          end
          s << "#{ratio}".html_safe
          output << view.content_tag(:div, s.html_safe,
                                     :style => style,
                                     :class => "tooltip")
        end
        @lines << output
        output
      end

    end
  end
end