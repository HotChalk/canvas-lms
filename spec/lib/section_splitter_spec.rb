require File.expand_path(File.dirname(__FILE__) + '/../spec_helper.rb')

describe SectionSplitter do
  before :once do
    @admin_user = account_admin_user

    @source_course = course({:course_name => "Course 1", :active_course => true})
    @source_course.start_at = Time.zone.now - 1.month
    @source_course.conclude_at = Time.zone.now + 1.month
    @source_course.time_zone = ActiveSupport::TimeZone.new('Pacific Time (US & Canada)')
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
    create_groups

    # User-generated data
    create_submissions
    create_messages
    create_page_views

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
    @section2_assignment = assignment_model({:course => @source_course, :title => "Section 2 Assignment"})
    assignment_override_model({:assignment => @section2_assignment, :set => @sections[1][:self]})
  end

  # Discussion topics structure is as follows:
  #
  # +-- @all_sections_topic: All sections topic
  # |   +--- @as_root_as_1: Reply by all-sections teacher
  # |   |    +--- @as_root_as_1_reply1: Reply by section 1 student
  # |   |    +--- @as_root_as_1_reply2: Reply by section 2 student
  # |   +--- @as_root_s1_1: Reply by section 1 student
  # |   |    +--- @as_root_s1_1_reply1: Reply by section 1 student (with attachment reference in HTML)
  # |   +--- @as_root_s2_1: Reply by section 2 student
  # |        +--- @as_root_s1_1_reply1: Reply by section 2 student (with direct attachment)
  # +-- @section1_topic: Section 1 topic
  # |   +--- @s1_root_1: Reply by section 1 student
  # |   +--- @s1_root_2: Reply by section 1 teacher
  # +-- @section3_topic: Section 3 topic
  # |   +--- @s3_root_1: Reply by section 3 student
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
    @as_root_as_1_reply2 = DiscussionEntry.new(:user => @sections[1][:students][0], :message => "section 2 reply", :discussion_topic => @all_sections_topic, :parent_entry => @as_root_as_1)
    @as_root_as_1_reply2.save!
    @as_root_s1_1_reply1_attachment = attachment_model(:context => @source_course)
    @as_root_s1_1_reply1 = DiscussionEntry.new(:user => @sections[0][:students][1], :message => <<-HTML, :discussion_topic => @all_sections_topic, :parent_entry => @as_root_s1_1)
    <p><a href="/courses/#{@source_course.id}/files/#{@as_root_s1_1_reply1_attachment.id}/download">This is a file link</a></p>
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

    @section3_topic = @source_course.discussion_topics.create!(:title => "Section 3 Topic", :message => "message", :user => @admin_user, :discussion_type => 'threaded')
    assignment_override_model({:assignment => @section3_topic, :set => @sections[2][:self]})
    @s3_root_1 = DiscussionEntry.new(:user => @sections[2][:students][0], :message => "section 3", :discussion_topic => @section3_topic)
    @s3_root_1.save!
    @s3_root_2 = DiscussionEntry.new(:user => @all_sections_teacher, :message => "section 3", :discussion_topic => @section3_topic)
    @s3_root_2.save!

    @all_entries = [@as_root_as_1, @as_root_s1_1, @as_root_s2_1, @as_root_as_1_reply1, @as_root_as_1_reply2, @as_root_s1_1_reply1, @as_root_s2_1_reply1, @s1_root_1, @s1_root_2, @s3_root_1, @s3_root_2]
    @all_entries.each &:reload
    @all_sections_topic.reload
    @section1_topic.reload
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
    @all_sections_quiz.published_at = Time.zone.now
    @all_sections_quiz.workflow_state = "available"
    @all_sections_quiz.save!
    @section3_quiz = Quizzes::Quiz.where(assignment_id: @section3_quiz_assignment).first
    @section3_quiz.published_at = Time.zone.now
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

  def create_groups
    @section3_group = group_model({:context => @source_course, :name => "Section 3 Group", :course_section_id => @sections[2][:self].id})
    @sections[2][:self].users.each {|u| @section3_group.add_user(u)}
  end

  def create_submissions
    submission_model({:course => @source_course, :section => @sections[0][:self], :assignment => @all_sections_assignment, :user => @sections[0][:students][0]})
    submission_model({:course => @source_course, :section => @sections[1][:self], :assignment => @all_sections_assignment, :user => @sections[1][:students][0]})
    submission_model({:course => @source_course, :section => @sections[1][:self], :assignment => @all_sections_assignment, :user => @sections[1][:students][1]})
    @section2_assignment1_submission = submission_model({:course => @source_course, :section => @sections[1][:self], :assignment => @section2_assignment, :user => @sections[1][:students][0]})
    submission_comment_model({:submission => @section2_assignment1_submission, :author => @sections[1][:teachers][1]})

    @asset = factory_with_protected_attributes(AssetUserAccess, :user => @sections[0][:students][0], :context => @source_course, :asset_code => @all_sections_assignment.asset_string, :display_name => @all_sections_assignment.asset_string)
    @asset.save!
    @asset = factory_with_protected_attributes(AssetUserAccess, :user => @sections[1][:students][0], :context => @source_course, :asset_code => @all_sections_assignment.asset_string, :display_name => @all_sections_assignment.asset_string)
    @asset.save!
    @asset = factory_with_protected_attributes(AssetUserAccess, :user => @sections[1][:students][1], :context => @source_course, :asset_code => @all_sections_assignment.asset_string, :display_name => @all_sections_assignment.asset_string)
    @asset.save!
    @asset = factory_with_protected_attributes(AssetUserAccess, :user => @sections[1][:students][0], :context => @source_course, :asset_code => @section2_assignment.asset_string, :display_name => @section2_assignment.asset_string)
    @asset.save!
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
    (0..4).each do |i|
      page_view_model({:context => @source_course, :user => @sections[2][:students][i]})
    end
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
    end
  end

  context "discussion topics" do
    it "should transfer discussion topics assigned to all sections" do
      @result.each do |course|
        all_sections_topic = course.discussion_topics.find {|d| d.title == @all_sections_topic.title }
        expect(all_sections_topic).to be
      end
    end

    it "should transfer section-specific discussion topics" do
      section1_topic = @result[0].discussion_topics.find {|d| d.title == @section1_topic.title }
      expect(section1_topic).to be
      expect(@result[0].discussion_topics.length).to eq 4
      expect(@result[1].discussion_topics.length).to eq 2
      section3_topic = @result[2].discussion_topics.find {|d| d.title == @section3_topic.title }
      expect(section3_topic).to be
      expect(@result[2].discussion_topics.length).to eq 3
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
      expect(@result[0].submissions.length).to eq 1
      expect(@result[1].submissions.length).to eq 3
    end

    it "should transfer submission comments" do
      comment = SubmissionComment.where(:author => @sections[1][:teachers][1]).first
      expect(comment).to be
      expect(comment.context).to eq(@result[1])
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
      expect(@result[2].page_views.length).to eq 5
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
    it "should transfer section-specific groups" do
      expect(@result[0].groups.length).to eq 0
      expect(@result[2].groups.length).to eq 1
      group = @result[2].groups.where(:name => "Section 3 Group").first
      expect(group).to be
      expect(group.group_memberships.length).to eq 7
    end
  end
end
