module WlSeries

	def self.attribut_options 
		#return [ project_allocation: 0, total_allocation: 1, remaining_allocation: 2, logged_time: 3, check_ratio: 4]
		return { project_allocation: 0, total_allocation: 1, remaining_allocation: 2, logged_time: 3, check_ratio: 4}
		
	end

	def self.get_tooltip_valueSuffix(attribut)
		unity = ""
		case attribut 
		when 4
			unity = ""
		else
			unity = " hours"
		end
 		return unity
	end

	def self.average_for_period(total_alloc, current_day, end_recc_date, attribut)
		output = 0
		nb_increment = 0
		while current_day <= end_recc_date
			total_alloc.each_with_index do |ta, i|
				if current_day.between?(ta[:start_date], ta[:end_date])
					case attribut #integer
	# project_allocation: 0, total_allocation: 1, remaining_allocation: 2, logged_time: 3, check_ratio: 4#
					when 0 #project_allocation
						output += (ta[:percent_alloc])
					when 1 #total_allocation
						output += (ta[:percent_alloc])
					when 2 #remaining_allocation
						total = (ta[:percent_alloc])
						total = 100 if total > 100
						output += 100 - total
					else
						#other attribut
					end

					nb_increment = nb_increment+1
				end
			end

			current_day = current_day+1
		end #current_day = end_recc_date => end of the week
		unless nb_increment == 0
			return (output/nb_increment).round(2)	
		else
			return output
		end	
	end


	def self.operation_options
		#return { sum: 0, average: 1, min: 2, max: 3}
		return { sum: 0, average: 1, min: 2, max: 3}
	end

	def self.gr_operation(array_data, operation_type)
		calculated_data = []
		#{ sum: 0, average: 1, min: 2, max: 3}
		case operation_type 
		when 0
			calculated_data = array_data.transpose.map{|a| a.reduce(:+)}
		when 2
			calculated_data = array_data.transpose.map(&:min)
		when 3
			calculated_data = array_data.transpose.map(&:max)
		else # do average by default : when 1
			calculated_data = array_data.transpose.map{|a| a.reduce(:+) / a.size}
		end	

		return calculated_data 
	end


	def self.get_array_data(project, gr_cat)
		series_data = []

		unless gr_cat.nil?
			#initialisation
			
			start_period = gr_cat.properties[:start_date].to_date
			end_period = gr_cat.properties[:end_date].to_date
			granularity = gr_cat.properties[:granularity].to_i
			graph_id = gr_cat.gr_graph_id
			
			#calcul series
			gr_ser_list = GrSeries.where(gr_graph_id: graph_id)

			unless gr_ser_list.blank?
				category_hash = WlCategories.hash_date_period(start_period, end_period, granularity)

				gr_ser_list.each do |series|

					#single series initialisation
					final_entry_data = []
					series_color = series.properties[:color]
					attribut_type = series.properties[:attribut].to_i
					operation_type = series.properties[:operation]

					if operation_type.nil?
						# no operation = only one entry and this entry is an user
						gr_entry = GrEntry.find_by(gr_series_id: series.id)
						gr_member = project.wl_members.select{|wl_m| wl_m.user_id == gr_entry.entry_id }.first
						final_entry_data = gr_member.gr_entry_data(start_period, end_period, category_hash, granularity, attribut_type)
					else
						#if there are an operation then = either one or multiple role(s), or multiple users
						gr_entries = GrEntry.where(gr_series_id: series.id)
						gr_members = []
						if gr_entries.first.entry_type == "Role"
							gr_entries.each do |gr_entry|
							 gr_members += WlMember.members_for_project_role(project,gr_entry.entry_id)
							end
						else
							gr_entries.each do |gr_entry|
								gr_members << project.wl_members.select{|wl_m| wl_m.user_id == gr_entry.entry_id }.first
							end
						end
						data_array = []
						gr_members.each do |gr_member|
							entry_data = []
							entry_data = gr_member.gr_entry_data(start_period, end_period, category_hash, granularity, attribut_type)
							unless entry_data.blank?
								data_array << entry_data
							end
						end
						final_entry_data = self.gr_operation(data_array, operation_type.to_i)
					end

					series_unity = self.get_tooltip_valueSuffix(attribut_type)

					series_data << {name: series.name, type: series.chart_type, color: "##{series_color}", tooltip: {valueSuffix: series_unity}, data: final_entry_data}

				end
				
			end
			
		end
		return series_data
	end

end