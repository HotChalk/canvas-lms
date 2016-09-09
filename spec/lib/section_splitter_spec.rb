require File.expand_path(File.dirname(__FILE__) + '/../spec_helper.rb')
require File.expand_path(File.dirname(__FILE__) + '/../cassandra_spec_helper.rb')

describe SectionSplitter do
  before :once do
    Setting.set('enable_page_views', 'cassandra')
    @admin_user = account_admin_user

    @now = Time.now

    @source_course = course({:course_name => "Course 1", :active_course => true})
    @source_course.start_at = @now - 1.month
    @source_course.conclude_at = @now + 1.month
    @source_course.time_zone = ActiveSupport::TimeZone.new('Pacific Time (US & Canada)')
    @source_course.public_syllabus = true
    @source_course.organize_epub_by_content_type = true
    @source_course.dynamic_tab_configuration = [{:context_type => "external_url", :label => "Label", :url => "http://example.com"}]
    @source_course.save
    @sections = (1..3).collect do |n|
      {:index => n, :name => "Section #{n}"}
    end

    # Permissions
    @source_course.account.role_overrides.create!(permission: :post_to_forum, role: student_role, enabled: true)
    @source_course.account.role_overrides.create!(permission: :read_forum, role: student_role, enabled: true)

    # Student and teacher enrollments
    @all_sections_teacher = user({:name => "All Sections Teacher"})
    communication_channel(@all_sections_teacher)
    @sections.each do |section|
      add_section section[:name]
      section[:self] = @source_course.course_sections.find {|s| s.name == section[:name]}
      enrollment = @source_course.enroll_user(@all_sections_teacher, 'TeacherEnrollment', :section => section[:self], :allow_multiple_enrollments => true)
      @all_sections_teacher.save!
      enrollment.workflow_state = 'active'
      enrollment.save!
      section[:teachers] = [
        @all_sections_teacher,
        teacher_in_section(@course_section, {:user => user({:name => "#{section[:name]} Teacher"})}),
      ]
      communication_channel(section[:teachers][1])
      5.times do |i|
        section[:students] ||= []
        student = student_in_section(@course_section)
        student.name = "#{section[:name]} Student#{i}"
        student.save!
        communication_channel(student)
        section[:students] << student
      end
    end
    @source_course.reload

    # Course content
    create_announcements
    create_assignments
    create_discussion_topics
    create_quizzes
    create_wiki_pages
    create_calendar_events
    create_group_categories
    create_groups
    create_custom_gradebook_columns

    # User-generated data
    create_submissions
    create_messages
    create_page_views
    create_page_views_rollups

    # Track generated jobs
    @previous_jobs = Delayed::Job.all

    # Invoke procedure
    @result = SectionSplitter.run({:course_id => @source_course.id, :user_id => @admin_user.id, :delete => true})
    @result.sort_by! {|c| c.course_code}
    @source_course.reload
  end

  def create_announcements
    @context = @source_course
    @all_sections_announcement = announcement_model({:title => "All Sections Announcement"})
    @section1_announcement = announcement_model({:title => "Section 1 Announcement"})
    assignment_override_model({:assignment => @a, :set => @sections[0][:self]})
  end

  def create_assignments
    @all_sections_assignment = assignment_model({:course => @source_course, :title => "All Sections Assignment"})
    @section2_assignment = assignment_model({:course => @source_course, :title => "Section 2 Assignment", :only_visible_to_overrides => true})
    assignment_override_model({:assignment => @section2_assignment, :set => @sections[1][:self], :due_at => @now + 1.weeks, :lock_at => @now + 2.weeks, :unlock_at => @now + 1.days})
    @all_sections_assignment2 = assignment_model({:course => @source_course, :title => "All Sections Assignment 2", :submission_types => "online_upload"})
    assignment_override_model({:assignment => @all_sections_assignment2, :set => @sections[0][:self], :due_at => @now + 1.weeks})
    assignment_override_model({:assignment => @all_sections_assignment2, :set => @sections[1][:self], :due_at => @now + 2.weeks})
    assignment_override_model({:assignment => @all_sections_assignment2, :set => @sections[2][:self], :due_at => @now + 3.weeks})
    @section3_assignment = assignment_model({:course => @source_course, :title => "Section 3 Assignment", :only_visible_to_overrides => true})
    ao = assignment_override_model({:assignment => @section3_assignment, :set_type => 'ADHOC'})
    ao.assignment_override_students.build({:user => @sections[2][:students][0]})
    ao.save
  end

  # Discussion topics structure is as follows:
  #
  # +-- @all_sections_topic: All sections topic
  # |   +--- @as_root_as_1: Reply by all-sections teacher
  # |   |    +--- @as_root_as_1_reply1: Reply by section 1 student
  # |   +--- @as_root_s1_1: Reply by section 1 student
  # |   |    +--- @as_root_s1_1_reply1: Reply by section 1 student (with attachment reference in HTML)
  # |   +--- @as_root_s2_1: Reply by section 2 student
  # |        +--- @as_root_s2_1_reply1: Reply by section 2 student (with direct attachment)
  # +-- @section1_topic: Section 1 topic
  # |   +--- @s1_root_1: Reply by section 1 student
  # |   +--- @s1_root_2: Reply by section 1 teacher
  # +-- @section2_topic: Section 2 topic
  # +-- @section3_topic: Section 3 topic
  # |   +--- @s3_root_1: Reply by section 3 student
  # |   |    +--- @s3_root_1_reply1: Reply by section 1 student
  # |   |    +--- @s3_root_1_reply2: Reply by section 1 student
  # |   |    +--- @s3_root_1_reply3: Reply by section 1 student
  # |   +--- @s3_root_2: Reply by all-sections teacher
  def create_discussion_topics
    @all_sections_topic = @source_course.discussion_topics.create!(:title => "All Sections Topic", :message => "message", :user => @admin_user, :discussion_type => 'threaded')
    @all_sections_topic.reload
    @as_root_as_1 = DiscussionEntry.new(:user => @all_sections_teacher, :message => "all sections", :discussion_topic => @all_sections_topic)
    @as_root_as_1.save!
    @as_root_s1_1 = DiscussionEntry.new(:user => @sections[0][:students][0], :message => "section 1", :discussion_topic => @all_sections_topic)
    @as_root_s1_1.save!
    @as_root_s2_1 = DiscussionEntry.new(:user => @sections[1][:students][0], :message => "section 2", :discussion_topic => @all_sections_topic)
    @as_root_s2_1.save!
    @as_root_as_1_reply1 = DiscussionEntry.new(:user => @sections[0][:students][0], :message => "section 1 reply", :discussion_topic => @all_sections_topic, :parent_entry => @as_root_as_1)
    @as_root_as_1_reply1.save!
    @as_root_s1_1_reply1_attachment = attachment_model(:context => @source_course)
    @as_root_s1_1_reply1 = DiscussionEntry.new(:user => @sections[0][:students][1], :message => <<-HTML, :discussion_topic => @all_sections_topic, :parent_entry => @as_root_s1_1)
    <p><a href="/courses/#{@source_course.id}/files/#{@as_root_s1_1_reply1_attachment.id}/download">This is a file link</a></p>
    <p><a href="/courses/#{@source_course.id}/announcements">This is an Announcements link</a></p>
    HTML
    @as_root_s1_1_reply1.save!
    @as_root_s2_1_reply1 = DiscussionEntry.new(:user => @sections[1][:students][1], :message => "section 2 reply reply", :discussion_topic => @all_sections_topic, :parent_entry => @as_root_s2_1)
    @as_root_s2_1_reply1.update_attribute(:attachment, attachment_model)
    @as_root_s2_1_reply1.save!

    @section1_topic = @source_course.discussion_topics.create!(:title => "Section 1 Topic", :message => "message", :user => @admin_user, :discussion_type => 'threaded')
    assignment_override_model({:assignment => @section1_topic, :set => @sections[0][:self]})
    @s1_root_1 = DiscussionEntry.new(:user => @sections[0][:students][2], :message => "section 1", :discussion_topic => @section1_topic)
    @s1_root_1.save!
    @s1_root_2 = DiscussionEntry.new(:user => @sections[0][:teachers][1], :message => "section 1", :discussion_topic => @section1_topic)
    @s1_root_2.save!

    @section2_topic = assignment_model({:course => @source_course, :title => "Section 2 Topic"})
    @section2_topic.workflow_state = "published"
    @section2_topic.submission_types = "discussion_topic"
    @section2_topic.save
    assignment_override_model({:assignment => @section2_topic, :set => @sections[1][:self]})

    @section3_topic = @source_course.discussion_topics.create!(:title => "Section 3 Topic", :message => "message", :user => @admin_user, :discussion_type => 'threaded')
    assignment_override_model({:assignment => @section3_topic, :set => @sections[2][:self]})
    @s3_root_1 = DiscussionEntry.new(:user => @sections[2][:students][0], :message => "section 3", :discussion_topic => @section3_topic)
    @s3_root_1.save!
    @s3_root_2 = DiscussionEntry.new(:user => @all_sections_teacher, :message => "section 3", :discussion_topic => @section3_topic)
    @s3_root_2.save!
    @s3_root_1_reply1 = DiscussionEntry.new(:user => @sections[2][:students][1], :message => "section 3 reply reply", :discussion_topic => @section3_topic, :parent_entry => @s3_root_1)
    @s3_root_1_reply1.save!
    @s3_root_1_reply2 = DiscussionEntry.new(:user => @sections[2][:students][2], :message => "section 3 reply reply", :discussion_topic => @section3_topic, :parent_entry => @s3_root_1)
    @s3_root_1_reply2.save!
    @s3_root_1_reply3 = DiscussionEntry.new(:user => @sections[2][:students][3], :message => "section 3 reply reply", :discussion_topic => @section3_topic, :parent_entry => @s3_root_1)
    @s3_root_1_reply3.save!

    @all_entries = [@as_root_as_1, @as_root_s1_1, @as_root_s2_1, @as_root_as_1_reply1, @as_root_s1_1_reply1, @as_root_s2_1_reply1, @s1_root_1, @s1_root_2, @s3_root_1, @s3_root_2, @s3_root_1_reply1, @s3_root_1_reply2, @s3_root_1_reply3]
    @all_entries.each &:reload
    @all_sections_topic.reload
    @section1_topic.reload
    @section2_topic.reload
    @section3_topic.reload
  end

  def create_quizzes
    @all_sections_quiz_assignment = assignment_model({:course => @source_course, :title => "All Sections Quiz"})
    @all_sections_quiz_assignment.workflow_state = "published"
    @all_sections_quiz_assignment.submission_types = "online_quiz"
    @all_sections_quiz_assignment.save
    @section3_quiz_assignment = assignment_model({:course => @source_course, :title => "Section 3 Quiz"})
    @section3_quiz_assignment.workflow_state = "published"
    @section3_quiz_assignment.submission_types = "online_quiz"
    @section3_quiz_assignment.save
    @all_sections_quiz = Quizzes::Quiz.where(assignment_id: @all_sections_quiz_assignment).first
    @all_sections_quiz.published_at = @now
    @all_sections_quiz.workflow_state = "available"
    @all_sections_quiz.save!
    @section3_quiz = Quizzes::Quiz.where(assignment_id: @section3_quiz_assignment).first
    @section3_quiz.published_at = @now
    @section3_quiz.workflow_state = "available"
    @section3_quiz.save!
    assignment_override_model({:quiz => @section3_quiz, :set => @sections[2][:self]})
  end

  def create_wiki_pages
    @wiki_page1 = wiki_page_model({:course => @source_course, :title => "Page 1", :body => <<-HTML})
      <p>
        <a href="/courses/#{@source_course.id}/announcements">Announcements</a>
        <br />
        <a href="/courses/#{@source_course.id}/discussion_topics/#{@all_sections_topic.id}">All Sections Topic</a>
      </p>
    HTML
    @wiki_page2 = wiki_page_model({:course => @source_course, :title => "Page 2", :body => <<-HTML})
      <p><a href="/courses/#{@source_course.id}/pages/page-1">This links to Page 1.</a></p>
    HTML
  end

  def create_calendar_events
    @course = @source_course
    calendar_event_model({:title => "All Sections Event"})
    calendar_event_model({:title => "Section 2 Event", :course_section_id => @sections[1][:self].id})
    calendar_event_model({:title => "Section 3 Event", :course_section_id => @sections[2][:self].id})
  end

  def create_group_categories
    @group_category1 = group_category({:context => @source_course, :name => "Group Category 1"})
    @group_category2 = group_category({:context => @source_course, :name => "Group Category 2"})
  end

  def create_groups
    @section1_group = group_model({:context => @source_course, :name => "Section 1 Group", :group_category => @group_category1, :course_section_id => @sections[0][:self].id})
    @section2_group = group_model({:context => @source_course, :name => "Section 2 Group", :group_category => @group_category1, :course_section_id => @sections[1][:self].id})
    @section3_group = group_model({:context => @source_course, :name => "Section 3 Group", :group_category => @group_category1, :course_section_id => @sections[2][:self].id})
    @sections[0][:self].students.each {|u| @section1_group.add_user(u)}
    @sections[1][:self].students.each {|u| @section2_group.add_user(u)}
    @sections[2][:self].students.each {|u| @section3_group.add_user(u)}
  end

  def create_custom_gradebook_columns
    @notes_column = @source_course.custom_gradebook_columns.build(:teacher_notes => true, :title => "Notes")
    @notes_column.save!
    @notes_column.custom_gradebook_column_data.build.tap do |data|
      data.content = "Student1 Comment"
      data.user_id = @sections[0][:students][0].id
    end
    @notes_column.custom_gradebook_column_data.build.tap do |data|
      data.content = "Student3 Comment"
      data.user_id = @sections[1][:students][2].id
    end
    @notes_column.save!
    @other_column = @source_course.custom_gradebook_columns.build(:teacher_notes => false, :title => "Other Column")
    @other_column.save!
    @other_column.custom_gradebook_column_data.build.tap do |data|
      data.content = "Student0 Other"
      data.user_id = @sections[2][:students][0].id
    end
    @other_column.save!
  end

  def create_submissions
    submission_model({:course => @source_course, :section => @sections[0][:self], :assignment => @all_sections_assignment, :user => @sections[0][:students][0]})
    submission_model({:course => @source_course, :section => @sections[1][:self], :assignment => @all_sections_assignment, :user => @sections[1][:students][0]})
    submission_model({:course => @source_course, :section => @sections[1][:self], :assignment => @all_sections_assignment, :user => @sections[1][:students][1]})
    @section2_assignment.submissions.delete_all
    @section2_assignment1_submission = submission_model({:course => @source_course, :section => @sections[1][:self], :assignment => @section2_assignment, :user => @sections[1][:students][0]})
    submission_comment_model({:submission => @section2_assignment1_submission, :author => @sections[1][:teachers][1]})
    Auditors::GradeChange.record(@section2_assignment1_submission)
    @all_sections_assignment2_submission_attachment = attachment_model(:context => @all_sections_assignment2)
    @all_sections_assignment2_submission = submission_model({:course => @source_course, :section => @sections[0][:self], :assignment => @all_sections_assignment2, :user => @sections[0][:students][0], :submission_type => "online_upload", :attachments => [@all_sections_assignment2_submission_attachment]})

    @asset = factory_with_protected_attributes(AssetUserAccess, :user => @sections[0][:students][0], :context => @source_course, :asset_code => @all_sections_assignment.asset_string, :display_name => @all_sections_assignment.asset_string)
    @asset.save!
    page_view_model({:context => @source_course, :user => @sections[0][:students][0], :participated => true, :asset_user_access => @asset})
    @asset = factory_with_protected_attributes(AssetUserAccess, :user => @sections[1][:students][0], :context => @source_course, :asset_code => @all_sections_assignment.asset_string, :display_name => @all_sections_assignment.asset_string)
    @asset.save!
    page_view_model({:context => @source_course, :user => @sections[1][:students][0], :participated => true, :asset_user_access => @asset})
    @asset = factory_with_protected_attributes(AssetUserAccess, :user => @sections[1][:students][1], :context => @source_course, :asset_code => @all_sections_assignment.asset_string, :display_name => @all_sections_assignment.asset_string)
    @asset.save!
    page_view_model({:context => @source_course, :user => @sections[1][:students][1], :participated => true, :asset_user_access => @asset})
    @asset = factory_with_protected_attributes(AssetUserAccess, :user => @sections[1][:students][0], :context => @source_course, :asset_code => @section2_assignment.asset_string, :display_name => @section2_assignment.asset_string)
    @asset.save!
    page_view_model({:context => @source_course, :user => @sections[1][:students][0], :participated => true, :asset_user_access => @asset})
  end

  def create_messages
    from = @sections[0][:students][0].communication_channels.first
    to = @sections[0][:students][1].communication_channels.first
    message = to.messages.build(
      :subject => "Hi",
      :to => to.path,
      :from => from.path,
      :user => @sections[0][:students][0],
      :context => @source_course,
      :asset_context => @source_course
    )
    # message.parse!
    message.save
  end

  def create_page_views
    page_view_model({:context => @source_course, :user => @sections[0][:students][0], :created_at => @now - 1.days, :participated => false, :controller => :courses, :action => :get})
    page_view_model({:context => @source_course, :user => @sections[0][:students][1], :created_at => @now - 3.days, :participated => true, :controller => :submissions, :action => :post})
    page_view_model({:context => @source_course, :user => @sections[0][:students][2], :created_at => @now - 4.days, :participated => false, :controller => :users, :action => :get})
    page_view_model({:context => @source_course, :user => @sections[0][:students][3], :created_at => @now - 2.days, :participated => true, :controller => :"quizzes/quizzes", :action => :post})
    page_view_model({:context => @source_course, :user => @sections[0][:students][4], :created_at => @now - 1.days, :participated => false, :controller => :wiki_pages, :action => :get})
    page_view_model({:context => @source_course, :user => @sections[1][:students][0], :created_at => @now - 5.days, :participated => true, :controller => :discussion_topics, :action => :post})
    page_view_model({:context => @source_course, :user => @sections[1][:students][1], :created_at => @now - 4.days, :participated => false, :controller => :courses, :action => :get})
    page_view_model({:context => @source_course, :user => @sections[1][:students][2], :created_at => @now - 4.days, :participated => false, :controller => :gradebooks, :action => :get})
    page_view_model({:context => @source_course, :user => @sections[1][:students][3], :created_at => @now - 5.days, :participated => false, :controller => :files, :action => :get})
    page_view_model({:context => @source_course, :user => @sections[1][:students][4], :created_at => @now - 1.days, :participated => false, :controller => :discussion_topics, :action => :get})
    page_view_model({:context => @source_course, :user => @sections[2][:students][0], :created_at => @now - 2.days, :participated => false, :controller => :files, :action => :get})
    page_view_model({:context => @source_course, :user => @sections[2][:students][1], :created_at => @now - 3.days, :participated => false, :controller => :discussion_topics, :action => :get})
    page_view_model({:context => @source_course, :user => @sections[2][:students][2], :created_at => @now - 3.days, :participated => true, :controller => :discussion_topics, :action => :post})
    page_view_model({:context => @source_course, :user => @sections[2][:students][3], :created_at => @now - 3.days, :participated => true, :controller => :submissions, :action => :post})
    page_view_model({:context => @source_course, :user => @sections[2][:students][4], :created_at => @now - 5.days, :participated => false, :controller => :announcements, :action => :get})
  end

  def create_page_views_rollups
    PageViewsRollup.augment!(@source_course, (@now - 1.days).to_date, :general, 1, 0)
    PageViewsRollup.augment!(@source_course, (@now - 1.days).to_date, :pages, 1, 0)
    PageViewsRollup.augment!(@source_course, (@now - 1.days).to_date, :discussions, 1, 0)
    PageViewsRollup.augment!(@source_course, (@now - 2.days).to_date, :quizzes, 1, 1)
    PageViewsRollup.augment!(@source_course, (@now - 2.days).to_date, :files, 1, 0)
    PageViewsRollup.augment!(@source_course, (@now - 3.days).to_date, :assignments, 2, 2)
    PageViewsRollup.augment!(@source_course, (@now - 3.days).to_date, :discussions, 2, 1)
    PageViewsRollup.augment!(@source_course, (@now - 4.days).to_date, :other, 1, 0)
    PageViewsRollup.augment!(@source_course, (@now - 4.days).to_date, :general, 1, 0)
    PageViewsRollup.augment!(@source_course, (@now - 4.days).to_date, :grades, 1, 0)
    PageViewsRollup.augment!(@source_course, (@now - 5.days).to_date, :discussions, 1, 1)
    PageViewsRollup.augment!(@source_course, (@now - 5.days).to_date, :files, 1, 0)
    PageViewsRollup.augment!(@source_course, (@now - 5.days).to_date, :announcements, 1, 0)
  end

  it "should create a new course shell per section" do
    expect(@result.length).to eq 3
    expect(@result.map(&:name)).to contain_exactly("Course 1", "Course 1", "Course 1")
    expect(@result.map(&:course_code)).to contain_exactly("Section 1", "Section 2", "Section 3")
  end

  it "should delete the source course after splitting" do
    expect(@source_course.workflow_state).to eq "deleted"
  end

  it "should transfer start/end dates and timezone" do
    @result.each do |course|
      expect(course.start_at).to eq @source_course.start_at
      expect(course.conclude_at).to eq @source_course.conclude_at
      expect(course.time_zone).to eq @source_course.time_zone
    end
  end

  it "should transfer course settings" do
    @result.each do |course|
      expect(course.public_syllabus).to eq true
      expect(course.organize_epub_by_content_type).to eq true
    end
  end

  it "should transfer dynamic tab configurations" do
    @result.each do |course|
      expect(course.dynamic_tab_configuration).to eq @source_course.dynamic_tab_configuration
    end
  end

  context "announcements" do
    it "should transfer announcements assigned to all sections" do
      @result.each do |course|
        all_sections_announcement = course.announcements.find {|a| a.title == @all_sections_announcement.title }
        expect(all_sections_announcement).to be
      end
    end

    it "should transfer section-specific announcements" do
      section1_announcement = @result[0].announcements.find {|a| a.title == @section1_announcement.title }
      expect(section1_announcement).to be
      section1_announcement = @result[1].announcements.find {|a| a.title == @section1_announcement.title }
      expect(section1_announcement).not_to be
    end
  end

  context "assignments" do
    it "should transfer assignments assigned to all sections" do
      @result.each do |course|
        all_sections_assignment = course.assignments.find {|a| a.title == @all_sections_assignment.title }
        expect(all_sections_assignment).to be
      end
    end

    it "should transfer section-specific assignments" do
      section2_assignment = @result[0].assignments.find {|a| a.title == @section2_assignment.title }
      expect(section2_assignment).not_to be
      section2_assignment = @result[1].assignments.find {|a| a.title == @section2_assignment.title }
      expect(section2_assignment).to be
      expect(section2_assignment.only_visible_to_overrides).to eq true
    end

    it "should transfer assignment overrides" do
      all_sections_assignment2 = @result[0].assignments.find {|a| a.title == @all_sections_assignment2.title }
      expect(all_sections_assignment2).to be
      expect(all_sections_assignment2.assignment_overrides.length).to eq 1
      expect(all_sections_assignment2.assignment_overrides[0].set_type).to eq 'CourseSection'
      expect(all_sections_assignment2.assignment_overrides[0].set_id).to eq @result[0].course_sections.first.id
      expect(all_sections_assignment2.assignment_overrides[0].due_at).to eq (@now + 1.weeks)

      all_sections_assignment2 = @result[1].assignments.find {|a| a.title == @all_sections_assignment2.title }
      expect(all_sections_assignment2).to be
      expect(all_sections_assignment2.assignment_overrides.length).to eq 1
      expect(all_sections_assignment2.assignment_overrides[0].set_type).to eq 'CourseSection'
      expect(all_sections_assignment2.assignment_overrides[0].set_id).to eq @result[1].course_sections.first.id
      expect(all_sections_assignment2.assignment_overrides[0].due_at).to eq (@now + 2.weeks)

      all_sections_assignment2 = @result[2].assignments.find {|a| a.title == @all_sections_assignment2.title }
      expect(all_sections_assignment2).to be
      expect(all_sections_assignment2.assignment_overrides.length).to eq 1
      expect(all_sections_assignment2.assignment_overrides[0].set_type).to eq 'CourseSection'
      expect(all_sections_assignment2.assignment_overrides[0].set_id).to eq @result[2].course_sections.first.id
      expect(all_sections_assignment2.assignment_overrides[0].due_at).to eq (@now + 3.weeks)

      section2_assignment = @result[0].assignments.find {|a| a.title == @section2_assignment.title }
      expect(section2_assignment).not_to be
      section2_assignment = @result[1].assignments.find {|a| a.title == @section2_assignment.title }
      expect(section2_assignment).to be
      expect(section2_assignment.only_visible_to_overrides).to eq true
      expect(section2_assignment.assignment_overrides.length).to eq 1
      expect(section2_assignment.assignment_overrides[0].set_type).to eq 'CourseSection'
      expect(section2_assignment.assignment_overrides[0].set_id).to eq @result[1].default_section.id
      expect(section2_assignment.assignment_overrides[0].due_at).to eq (@now + 1.weeks)
      expect(section2_assignment.assignment_overrides[0].lock_at).to eq (@now + 2.weeks)
      expect(section2_assignment.assignment_overrides[0].unlock_at).to eq (@now + 1.days)
      expect(section2_assignment.assignment_overrides[0].assignment_override_students.length).to eq 0
      section2_assignment = @result[2].assignments.find {|a| a.title == @section2_assignment.title }
      expect(section2_assignment).not_to be

      section3_assignment = @result[0].assignments.find {|a| a.title == @section3_assignment.title }
      expect(section3_assignment).not_to be
      section3_assignment = @result[1].assignments.find {|a| a.title == @section3_assignment.title }
      expect(section3_assignment).not_to be
      section3_assignment = @result[2].assignments.find {|a| a.title == @section3_assignment.title }
      expect(section3_assignment).to be
      expect(section3_assignment.only_visible_to_overrides).to eq true
      expect(section3_assignment.assignment_overrides.length).to eq 1
      expect(section3_assignment.assignment_overrides[0].set_type).to eq 'ADHOC'
      expect(section3_assignment.assignment_overrides[0].assignment_override_students.length).to eq 1
      expect(section3_assignment.assignment_overrides[0].assignment_override_students[0].user).to eq @sections[2][:students][0]
    end
  end

  context "discussion topics" do
    it "should transfer discussion topics and entries assigned to all sections" do
      @result.each do |course|
        all_sections_topic = course.discussion_topics.find {|d| d.title == @all_sections_topic.title }
        expect(all_sections_topic).to be
        expect(all_sections_topic.user).to eq @all_sections_topic.user
        if course == @result[0]
          expect(all_sections_topic.root_discussion_entries.length).to eq 2
          expect(all_sections_topic.root_discussion_entries[0].discussion_subentries.length).to eq 1
          expect(all_sections_topic.root_discussion_entries[0].discussion_subentries[0].user_id).to eq(@sections[0][:students][0].id)
          expect(all_sections_topic.root_discussion_entries[1].discussion_subentries.length).to eq 1
          expect(all_sections_topic.root_discussion_entries[1].discussion_subentries[0].user_id).to eq(@sections[0][:students][1].id)
        elsif course == @result[1]
          expect(all_sections_topic.root_discussion_entries.length).to eq 1
          expect(all_sections_topic.root_discussion_entries[0].discussion_subentries.length).to eq 1
          expect(all_sections_topic.root_discussion_entries[0].discussion_subentries[0].user_id).to eq(@sections[1][:students][1].id)
          expect(all_sections_topic.root_discussion_entries[0].discussion_subentries[0].attachment).to be
        elsif course == @result[2]
          expect(all_sections_topic.root_discussion_entries.length).to eq 0
        end
      end
    end

    it "should transfer section-specific discussion topics and entries" do
      section1_topic = @result[0].discussion_topics.find {|d| d.title == @section1_topic.title }
      expect(section1_topic).to be
      expect(@result[0].discussion_topics.length).to eq 4
      expect(@result[1].discussion_topics.length).to eq 3
      section3_topic = @result[2].discussion_topics.find {|d| d.title == @section3_topic.title }
      expect(section3_topic).to be
      expect(section3_topic.user).to eq @section3_topic.user
      expect(@result[2].discussion_topics.length).to eq 3

      expect(section1_topic.root_discussion_entries.length).to eq 2
      expect(section1_topic.discussion_entries.map(&:user_id)).to contain_exactly(@sections[0][:students][2].id, @sections[0][:teachers][1].id)
      expect(section3_topic.root_discussion_entries.length).to eq 2
      expect(section3_topic.discussion_entries.map(&:user_id)).to contain_exactly(@sections[2][:students][0].id, @all_sections_teacher.id, @sections[2][:students][1].id, @sections[2][:students][2].id, @sections[2][:students][3].id)
      expect(section3_topic.child_discussion_entries.length).to eq 3
    end

    it "should transfer correct data for the materialized view" do
      [@result[0], @result[1]].each do |course|
        all_sections_topic = course.discussion_topics.find {|d| d.title == @all_sections_topic.title }
        entry_ids = all_sections_topic.discussion_entries.map(&:id)
        user_ids = all_sections_topic.discussion_entries.map(&:user_id)
        structure, participant_ids, mv_entry_ids, new_entries = all_sections_topic.materialized_view(:include_new_entries => true)
        entries = JSON.parse(structure)
        expect(entries.length).to be > 0
        found_entry_ids = entries.map {|e| [e["id"].to_i] + e["replies"].map {|r| r["id"].to_i}}.flatten
        found_user_ids = entries.map {|e| [e["user_id"].to_i] + e["replies"].map {|r| r["user_id"].to_i}}.flatten
        expect(found_entry_ids).to match_array(entry_ids)
        expect(found_user_ids).to match_array(user_ids)
      end
    end

    it "should translate links embedded in discussion entries" do
      all_sections_topic = @result[0].discussion_topics.find {|d| d.title == @all_sections_topic.title }
      expect(all_sections_topic).to be
      entry = all_sections_topic.discussion_entries.find {|e| e.user == @sections[0][:students][1]}
      expect(entry).to be
      expect(entry.message).to match(/courses\/#{@result[0].id}\/files/)
      expect(entry.message).to match(/courses\/#{@result[0].id}\/announcements/)
      expect(entry.message).not_to match(/courses\/#{@source_course.id}\/files/)
      expect(entry.message).not_to match(/courses\/#{@source_course.id}\/announcements/)
    end
  end

  context "quizzes" do
    it "should transfer quizzes assigned to all sections" do
      @result.each do |course|
        all_sections_quiz = course.quizzes.find {|q| q.title == @all_sections_quiz.title }
        expect(all_sections_quiz).to be
      end
    end

    it "should transfer section-specific quizzes" do
      section3_quiz = @result[0].quizzes.find {|q| q.title == @section3_quiz.title }
      expect(section3_quiz).not_to be
      section3_quiz = @result[2].quizzes.find {|q| q.title == @section3_quiz.title }
      expect(section3_quiz).to be
    end
  end

  context "wiki pages" do
    it "should replace links in page content" do
      expect(@result[1].wiki.wiki_pages.length).to eq 2
      dt1 = @result[1].discussion_topics.first
      page1 = @result[1].wiki.wiki_pages.find {|p| p.title == @wiki_page1.title }
      expect(page1).to be
      expect(page1.body).to match "courses/#{@result[1].id}/announcements"
      expect(page1.body).to match "courses/#{@result[1].id}/discussion_topics/#{dt1.id}"
    end
  end

  context "submissions" do
    it "should transfer submissions" do
      all_sections_assignment = @result[0].assignments.find {|a| a.title == @all_sections_assignment.title }
      expect(@result[0].submissions.where(:assignment_id => all_sections_assignment.id).length).to eq 1
      all_sections_assignment = @result[1].assignments.find {|a| a.title == @all_sections_assignment.title }
      expect(@result[1].submissions.where(:assignment_id => all_sections_assignment.id).length).to eq 2
      section2_assignment = @result[1].assignments.find {|a| a.title == @section2_assignment.title }
      expect(@result[1].submissions.where(:assignment_id => section2_assignment.id).length).to eq 1
    end

    it "should transfer submission comments" do
      comment = SubmissionComment.where(:author => @sections[1][:teachers][1]).first
      expect(comment).to be
      expect(comment.context).to eq(@result[1])
    end

    it "should transfer submission attachments" do
      all_sections_assignment2 = @result[0].assignments.find {|a| a.title == @all_sections_assignment2.title }
      expect(@result[0].submissions.having_submission.where(:assignment_id => all_sections_assignment2.id).length).to eq 1
      submission = @result[0].submissions.having_submission.where(:assignment_id => all_sections_assignment2.id).first
      expect(submission.attachment_ids).to eq "#{@all_sections_assignment2_submission_attachment.id}"
      @all_sections_assignment2_submission_attachment.reload
      expect(@all_sections_assignment2_submission_attachment.context).to eq all_sections_assignment2
    end

    context "cassandra" do
      include_examples "cassandra audit logs"

      it "should transfer grade change audit events" do
        expect(Auditors::GradeChange::Stream.database.execute("SELECT COUNT(*) FROM grade_changes WHERE context_id = ?", @source_course.global_id).fetch_row["count"]).to eq 0
        expect(Auditors::GradeChange::Stream.database.execute("SELECT COUNT(*) FROM grade_changes WHERE context_id = ?", @result[1].global_id).fetch_row["count"]).to eq 1
      end
    end
  end

  context "enrollments" do
    it "should transfer enrollments" do
      @result.each do |course|
        expect(course.enrollments.length).to eq 7
        expect(course.teacher_enrollments.length).to eq 2
        expect(course.student_enrollments.length).to eq 5
      end
    end
  end

  context "messages" do
    it "should transfer messages" do
      expect(@result[0].messages.length).to eq 1
    end
  end

  context "page views" do
    it "should transfer page views" do
      skip "requires database implementation for page views" unless Setting.get('enable_page_views', 'db') == 'db'
      expect(@result[0].page_views.length).to eq 6
      expect(@result[1].page_views.length).to eq 8
      expect(@result[2].page_views.length).to eq 5
    end

    it "should transfer page views rollups" do
      expect(@result[0].page_views_rollups.length).to eq 5
      expect(@result[1].page_views_rollups.length).to eq 5
      expect(@result[2].page_views_rollups.length).to eq 4

      expect(@source_course.page_views_rollups.length).to eq 13
      @source_course.page_views_rollups.each do |rollup|
        expect(rollup.views).to eq 0
        expect(rollup.participations).to eq 0
      end

      rollup = @result[0].page_views_rollups.find {|rollup| rollup[:date] == (@now - 1.days).to_date && rollup[:category] == 'pages'}
      expect(rollup.views).to eq 1
      expect(rollup.participations).to eq 0

      rollup = @result[2].page_views_rollups.find {|rollup| rollup[:date] == (@now - 3.days).to_date && rollup[:category] == 'discussions'}
      expect(rollup.views).to eq 2
      expect(rollup.participations).to eq 1
    end

    context "cassandra" do
      include_examples "cassandra page views"

      it "should transfer page_views" do
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views WHERE context_id = ?", @source_course.id).fetch_row["count"]).to eq 0
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views WHERE context_id = ?", @result[0].id).fetch_row["count"]).to eq 6
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views WHERE context_id = ?", @result[1].id).fetch_row["count"]).to eq 8
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views WHERE context_id = ?", @result[2].id).fetch_row["count"]).to eq 5
      end

      it "should transfer page_views_counters_by_context_and_hour" do
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views_counters_by_context_and_hour WHERE context = ?", "course_#{@source_course.id}").fetch_row["count"]).to eq 0
        contexts = @result[0].student_enrollments.map {|e| "course_#{e.course.id}/user_#{e.user.id}"}
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views_counters_by_context_and_hour WHERE context IN (?)", contexts).fetch_row["count"]).to eq 6
        contexts = @result[1].student_enrollments.map {|e| "course_#{e.course.id}/user_#{e.user.id}"}
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views_counters_by_context_and_hour WHERE context IN (?)", contexts).fetch_row["count"]).to eq 7
        contexts = @result[2].student_enrollments.map {|e| "course_#{e.course.id}/user_#{e.user.id}"}
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views_counters_by_context_and_hour WHERE context IN (?)", contexts).fetch_row["count"]).to eq 5
      end

      it "should transfer page_views_counters_by_context_and_user" do
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views_counters_by_context_and_user WHERE context = ?", "course_#{@source_course.id}").fetch_row["count"]).to eq 0
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views_counters_by_context_and_user WHERE context = ?", "course_#{@result[0].id}").fetch_row["count"]).to eq 5
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views_counters_by_context_and_user WHERE context = ?", "course_#{@result[1].id}").fetch_row["count"]).to eq 5
        expect(PageView::EventStream.database.execute("SELECT COUNT(*) FROM page_views_counters_by_context_and_user WHERE context = ?", "course_#{@result[2].id}").fetch_row["count"]).to eq 5
      end
    end
  end

  context "asset user accesses" do
    it "should transfer asset user accesses" do
      expect(@result[0].asset_user_accesses.length).to eq 1
      expect(@result[1].asset_user_accesses.length).to eq 3
    end
  end

  context "content participation counts" do
    it "should transfer content participation counts" do
      expect(@result[1].content_participation_counts.length).to eq 1
    end
  end

  context "calendar events" do
    it "should transfer non-section-specific calendar events" do
      @result.each do |c|
        event = c.calendar_events.where(:title => "All Sections Event").first
        expect(event).to be
      end
    end

    it "should transfer section-specific calendar events" do
      expect(@result[0].calendar_events.length).to eq 1
      expect(@result[1].calendar_events.where(:title => "Section 2 Event").first).to be
      expect(@result[2].calendar_events.where(:title => "Section 3 Event").first).to be
    end
  end

  context "groups" do
    it "should transfer group categories" do
      @result.each do |c|
        expect(c.group_categories.length).to eq 2
      end
    end

    it "should transfer section-specific groups" do
      @result.each_with_index do |course, i|
        expect(course.groups.length).to eq 1
        group = course.groups.where(:name => "Section #{i + 1} Group").first
        expect(group).to be
        expect(group.group_category.context).to eq group.context
        expect(group.group_memberships.length).to eq 5
      end
    end
  end

  context "delayed messages" do
    it "should not generate emails" do
      expect(@previous_jobs.pluck(:id)).to match_array Delayed::Job.all.pluck(:id)
    end
  end

  context "grades" do
    it "should transfer custom gradebook columns" do
      expect(@result[0].custom_gradebook_columns.length).to eq 2
      expect(@result[0].custom_gradebook_columns.find {|cc| cc.teacher_notes == true}.custom_gradebook_column_data.length).to eq 1
      expect(@result[0].custom_gradebook_columns.find {|cc| cc.teacher_notes == false}.custom_gradebook_column_data.length).to eq 0
      expect(@result[1].custom_gradebook_columns.length).to eq 2
      expect(@result[1].custom_gradebook_columns.find {|cc| cc.teacher_notes == true}.custom_gradebook_column_data.length).to eq 1
      expect(@result[1].custom_gradebook_columns.find {|cc| cc.teacher_notes == false}.custom_gradebook_column_data.length).to eq 0
      expect(@result[2].custom_gradebook_columns.length).to eq 2
      expect(@result[2].custom_gradebook_columns.find {|cc| cc.teacher_notes == true}.custom_gradebook_column_data.length).to eq 0
      expect(@result[2].custom_gradebook_columns.find {|cc| cc.teacher_notes == false}.custom_gradebook_column_data.length).to eq 1
    end
  end
end
