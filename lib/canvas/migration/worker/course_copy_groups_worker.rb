require_dependency 'importers'

class Canvas::Migration::Worker::CourseCopyGroupsWorker < Canvas::Migration::Worker::Base
  def perform(cm=nil)
    cm ||= ContentMigration.find migration_id

    cm.workflow_state = :pre_processing
    cm.reset_job_progress
    cm.migration_settings[:skip_import_notification] = true
    cm.migration_settings[:import_immediately] = true
    cm.save
    cm.job_progress.start

    cm.shard.activate do
      begin
        source = cm.source_course || Course.find(cm.migration_settings[:source_course_id])
        groups = source.groups.active        
        group_categories = source.group_categories.active
        data = {
          :groups => groups || [],
          :group_categories => group_categories || []
        }
        cm.workflow_state = :exporting
        cm.update_import_progress(10)
        Importers::GroupImporter.import_groups_extra(data, cm)
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
end
