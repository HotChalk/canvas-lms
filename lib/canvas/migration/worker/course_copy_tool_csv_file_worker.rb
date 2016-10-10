#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require 'csv'

class Canvas::Migration::Worker::CourseCopyToolCsvFileWorker < Canvas::Migration::Worker::Base
  def perform(cm=nil)
    cm ||= ContentMigration.find migration_id

    filename = Rails.root.join('public', 'uploads', cm.migration_settings[:filename])

    cm.workflow_state = :pre_processing
    cm.reset_job_progress
    cm.migration_settings[:skip_import_notification] = true
    cm.migration_settings[:import_immediately] = true
    cm.save
    cm.job_progress.start    
    puts "USER ID : #{cm.user_id.inspect}"
    
    cm.shard.activate do
      begin
        # runs validation about courses ids
        result = read_csv_file filename
        # puts "RESULTADO DE LA VALIDACION DEL CSV FILE... #{result.inspect}"
        
        if (result.count{|x| x[:state] == "Queued"} > 0)
          cm.workflow_state = :csv_validated
          cm.migration_settings[:results] = result
          cm.update_import_progress(15)
          cm.save
        else
          cm.workflow_state = :failed
          cm.migration_settings[:results] = result
          cm.migration_settings[:last_error] = result.join(" / ")
          cm.save
          break;
        end

        #SE PROCESA LOS DATOS
        i = 0
        CSV.foreach(Rails.root.join('public', 'uploads', filename), :headers => true, :header_converters => :symbol, :converters => :all) do |row|
          unless result[i][:status]
            i += 1
            next
          end

          data = {
            :target_id => 1234,
            :target_name => "Target Course Name",
            :target_code_id => 9876,
            :target_section_name => "section 1",
            :start_at => nil,
            :master_id => 1234,
            :master_name => "Master Course Name",
            :master_code_id => 9876,
            :master_section_name => "section 1",
            :created_at => nil,
            :updated_at => nil,
            :workflow_state => "queued",
            :completion => 0,
            :message => "",
            :error => nil,
            :status => true
          }

          # find master course data
          course = Course.find(row[0])
          data[:master_id] = course.id
          data[:master_name] = course.name
          data[:master_code_id] = course.course_code
          data[:master_section_name] = course.default_section.section_code
          data[:master_start_at] = course.start_at        
          data[:master_conclude_at] = course.conclude_at
            
          # find target course data
          course = Course.find(row[1])
          data[:target_id] = course.id
          data[:target_name] = course.name
          data[:target_code_id] = course.course_code
          data[:target_section_name] = course.default_section.section_code
          
          # other data
          data[:due_dates] = cm.migration_settings[:due_dates]
          if cm.migration_settings[:due_dates] == 1
            data[:new_start_date] = cm.migration_settings[:new_start_date]
          end
          
          # run cource copy tool script with master course and target course.
          puts "Se procesa el copy tool con master: #{row[0].inspect} and target: #{row[1].inspect}, index: #{i.inspect}  "
          script_result = execPythonFile data
          # get result
          data[:workflow_state] = "Completed"        
          data[:completion] = 100
          data[:script_result] = script_result
          # data_result = { :status => true, :error => nil, :state =>"Completed", completion => 100, :message => "" }
          result[i] = data

          i += 1
        end

        cm.migration_settings[:results] = result
        cm.workflow_state = :imported
        cm.save
        cm.update_import_progress(100)
        
      rescue => e
        cm.fail_with_error!(e)
        raise e
      end
    end
  end

  def self.enqueue(content_migration)
    Delayed::Job.enqueue(new(content_migration.id),
                         :priority => Delayed::LOW_PRIORITY,
                         :max_attempts => 1,
                         :strand => content_migration.strand)
  end

  def read_csv_file filename
    result = Array.new()
    data = { :status => true, :message => "" }
    
    CSV.foreach(Rails.root.join('public', 'uploads', filename), :headers => true, :header_converters => :symbol, :converters => :all) do |row|
      if row.count == 2        
        # verify ids on master and target
        if row[0] == row[1]
          data = { :status => false, :workflow_state => "Error", :master_id => row[0], :target_id => row[1], :error => 404, :state =>"Error", :message => "Master Course Id and Target Course Id are equals; Id: #{row[0]}" }
          # add the check to result array
          result.push(data)    
          next
        end
        # find master
        data = { :status => true, :error => nil, :state =>"Queued", :message => "" }
        unless Course.exists?(row[0])
          data = { :status => false, :workflow_state => "Error", :master_id => row[0], :target_id => row[1], :error => 404, :state =>"Error", :message => "Master Course Id: #{row[0]} Not Found" }
          # add the check to result array
          result.push(data)    
          next
        end            

        # find target        
        unless Course.exists?(row[1])
          data = { :status => false, :workflow_state => "Error", :master_id => row[0], :target_id => row[1], :error => 404, :state =>"Error", :message => "Target Course Id: #{row[1]} Not Found" }
          # add the check to result array
          result.push(data)    
          next
        end

        # add the check to result array
        result.push(data)    
      else
        data = { :status => false, :workflow_state => "Error",  :error => 405, :state =>"Error", :message => "Wrong row configuration - Number of columns on row is different than two(2)" }
        # add the check to result array
        result.push(data)    
      end
    end
    result
  end

  def execPythonFile(data) 
    filename = 'CourseCopy.py'    
    file_path = Rails.root.join('vendor', 'CourseCopyTool', filename).to_s rescue nil
    unless File.exist?(file_path)
      result = { :status => :bad_request, :message => t('must_script_file', "Python script file is required"), :state => false }
      return result
    end

    # obj = {
    #   master_id: 1,
    #   target_id: 3,
    #   modify_dates: 'Y',
    #   master_start_at: DateTime.now,
    #   master_conclude_at: DateTime.now, 
    #   start_date: DateTime.now
    # }

    python_std_out = `python #{file_path} #{data.to_json}`
    puts "SE EJECUTA EL PYTHON SCRIPT... #{python_std_out.inspect}"

    python_std_out
  end

end
