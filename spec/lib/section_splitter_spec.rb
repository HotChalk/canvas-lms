require File.expand_path(File.dirname(__FILE__) + '/../spec_helper.rb')

describe SectionSplitter do
  before :once do
    @admin_user = account_admin_user

    @source_course = course({:course_name => "Course 1"})
    @sections = (1..3).collect do |n|
      {:index => n, :name => "Section #{n}"}
    end

    # Permissions
    @source_course.account.role_overrides.create!(permission: :post_to_forum, role: student_role, enabled: true)
    @source_course.account.role_overrides.create!(permission: :read_forum, role: student_role, enabled: true)

    # Student and teacher enrollments
    @all_sections_teacher = user({:name => "All Sections Teacher"})
    @sections.each do |section|
      add_section section[:name]
      section[:self] = @source_course.course_sections.find {|s| s.name == section[:name]}
      section[:teachers] = [teacher_in_section(@course_section, {:user => @all_sections_teacher})]
      teacher = teacher_in_section(@course_section)
      teacher.name = "#{section[:name]} Teacher"
      teacher.save!
      section[:teachers] << teacher
      5.times do |i|
        section[:students] ||= []
        student = student_in_section(@course_section)
        student.name = "#{section[:name]} Student#{i}"
        student.save!
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

    # User-generated data
    create_submissions

    # Invoke procedure
    @result = SectionSplitter.run({:course_id => @source_course.id, :user_id => @admin_user.id})
  end

  def create_announcements
    @context = @source_course
    @all_sections_announcement = announcement_model({:title => "All Sections Announcement"})
    @section1_announcement = announcement_model({:title => "Section 1 Announcement"})
    create_section_override_for_assignment(@a, {:course_section => @sections[0][:self]})
  end

  def create_assignments
    @all_sections_assignment = assignment_model({:course => @source_course, :title => "All Sections Assignment"})
    @section2_assignment = assignment_model({:course => @source_course, :title => "Section 2 Assignment"})
    create_section_override_for_assignment(@section2_assignment, {:course_section => @sections[1][:self]})
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
    @all_sections_topic = @source_course.discussion_topics.create!(:title => "all sections topic", :message => "message", :user => @admin_user, :discussion_type => 'threaded')
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

    @section1_topic = @source_course.discussion_topics.create!(:title => "section 1 topi", :message => "message", :user => @admin_user, :discussion_type => 'threaded')
    create_section_override_for_assignment(@section1_topic, {:course_section => @sections[0][:self]})
    @s1_root_1 = DiscussionEntry.new(:user => @sections[0][:students][2], :message => "section 1", :discussion_topic => @section1_topic)
    @s1_root_1.save!
    @s1_root_2 = DiscussionEntry.new(:user => @sections[0][:teachers][1], :message => "section 1", :discussion_topic => @section1_topic)
    @s1_root_2.save!

    @section3_topic = @source_course.discussion_topics.create!(:title => "section 3 topic", :message => "message", :user => @admin_user, :discussion_type => 'threaded')
    create_section_override_for_assignment(@section3_topic, {:course_section => @sections[2][:self]})
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
    @all_sections_quiz = quiz_model({:course => @source_course, :title => "All Sections Quiz"})
    @section3_quiz = quiz_model({:course => @source_course, :title => "Section 3 Quiz"})
    create_section_override_for_assignment(@section3_quiz, {:course_section => @sections[2][:self]})
  end

  def create_wiki_pages
    @wiki_page1 = wiki_page_model({:course => @source_course, :title => "Page 1", :html => <<-HTML})
      <p>
        <a href="/courses/#{@source_course.id}/announcements">Announcements</a>
        <br />
        <a href="/courses/#{@source_course.id}/discussion_topics/#{@all_sections_topic.id}">All Sections Topic</a>
      </p>
    HTML
    @wiki_page2 = wiki_page_model({:course => @source_course, :title => "Page 2", :html => <<-HTML})
      <p><a href="/courses/#{@source_course.id}/pages/page-1">This links to Page 1.</a></p>
    HTML
  end

  def create_submissions
    submission_model({:course => @source_course, :section => @sections[0][:self], :assignment => @all_sections_assignment, :user => @sections[0][:students][0]})
    submission_model({:course => @source_course, :section => @sections[1][:self], :assignment => @all_sections_assignment, :user => @sections[1][:students][0]})
    submission_model({:course => @source_course, :section => @sections[1][:self], :assignment => @all_sections_assignment, :user => @sections[1][:students][1]})
    submission_model({:course => @source_course, :section => @sections[1][:self], :assignment => @section2_assignment, :user => @sections[1][:students][0]})
  end

  it "should create a new course shell per section" do
    expect(@result.length).to eq 3
    expect(@result.map(&:name)).to contain_exactly("Section 1", "Section 2", "Section 3")
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
      expect(section1_announcement).to be
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
      expect(@result[0].discussion_topics.length).to eq 2
      expect(@result[1].discussion_topics.length).to eq 1
      section3_topic = @result[2].discussion_topics.find {|d| d.title == @section3_topic.title }
      expect(section3_topic).not_to be
      expect(@result[2].discussion_topics.length).to eq 2
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
  end
end
