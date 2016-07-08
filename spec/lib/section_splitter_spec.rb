require File.expand_path(File.dirname(__FILE__) + '/../spec_helper.rb')

describe SectionSplitter do
  before :once do
    @admin_user = account_admin_user

    @source_course = course({:course_name => "Course 1"})
    @sections = (1..3).collect do |n|
      {:index => n, :name => "Section #{n}"}
    end

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

    # Course content
    create_announcements
    create_assignments
    create_discussion_topics
    create_quizzes
    create_wiki_pages

    # User-generated data
    create_submissions

    # Invoke procedure
    splitter = SectionSplitter.new
    splitter.run({:course => @source_course})
  end

  def create_announcements
    @context = @source_course
    @all_sections_announcement = announcement_model({:title => "All Sections Announcement"})
    @section1_announcement = announcement_model({:title => "Section 1 Announcement"})
    create_section_override_for_assignment(@a, {:course_section => @sections[0][:self]})
  end

  def create_assignments
    @all_sections_assignment = assignment_model({:title => "All Sections Assignment"})
    @section2_assignment = announcement_model({:title => "Section 2 Announcement"})
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
    @as_root_as_1 = @all_sections_topic.reply_from(:user => @all_sections_teacher, :html => "all sections")
    @as_root_s1_1 = @all_sections_topic.reply_from(:user => @sections[0][:students][0], :html => "section 1")
    @as_root_s2_1 = @all_sections_topic.reply_from(:user => @sections[1][:students][0], :html => "section 2")
    @as_root_as_1_reply1 = @as_root_as_1.reply_from(:user => @sections[0][:students][0], :html => "section 1 reply")
    @as_root_as_1_reply2 = @as_root_as_1.reply_from(:user => @sections[1][:students][0], :html => "section 2 reply")
    @as_root_s1_1_reply1_attachment = attachment_model(:context => @source_course)
    @as_root_s1_1_reply1 = @as_root_s1_1.reply_from(:user => @sections[0][:students][1], :html => <<-HTML)
    <p><a href="/courses/#{@source_course.id}/files/#{@as_root_s1_1_reply1_attachment.id}/download">This is a file link</a></p>
    HTML
    @as_root_s2_1_reply1 = @as_root_s2_1.reply_from(:user => @sections[1][:students][1], :html => "section 2 reply reply")
    @as_root_s2_1_reply1.update_attribute(:attachment, attachment_model)

    @section1_topic = @source_course.discussion_topics.create!(:title => "title", :message => "message", :user => @admin_user, :discussion_type => 'threaded')
    create_section_override_for_assignment(@section1_topic, {:course_section => @sections[0][:self]})
    @s1_root_1 = @section1_topic.reply_from(:user => @sections[0][:students][2], :html => "section 1")
    @s1_root_2 = @section1_topic.reply_from(:user => @sections[0][:teachers][1], :html => "section 1")

    @section3_topic = @source_course.discussion_topics.create!(:title => "title", :message => "message", :user => @admin_user, :discussion_type => 'threaded')
    create_section_override_for_assignment(@section3_topic, {:course_section => @sections[2][:self]})
    @s3_root_1 = @section3_topic.reply_from(:user => @sections[2][:students][0], :html => "section 3")
    @s3_root_2 = @section3_topic.reply_from(:user => @all_sections_teacher, :html => "section 3")

    @all_entries = [@as_root_as_1, @as_root_s1_1, @as_root_s2_1, @as_root_as_1_reply1, @as_root_as_1_reply2, @as_root_s1_1_reply1, @as_root_s2_1_reply1, @s1_root_1, @s1_root_2, @s3_root_1, @s3_root_2]
    @all_entries.each &:reload
    @all_sections_topic.reload
    @section1_topic.reload
    @section2_topic.reload
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
    submission_model({:course => @source_course, :assignment => @all_sections_assignment, :user => @sections[0][:students][0]})
    submission_model({:course => @source_course, :assignment => @all_sections_assignment, :user => @sections[1][:students][0]})
    submission_model({:course => @source_course, :assignment => @all_sections_assignment, :user => @sections[1][:students][1]})
    submission_model({:course => @source_course, :assignment => @section2_assignment, :user => @sections[1][:students][0]})
  end

  it "should create a new course shell per section" do
    expect(@result.length).to eq 3
    @result.each_with_index do |course, i|
      expect(course.name).to eq "Section #{i}"
    end
  end

  context "announcements" do
    it "should transfer announcements assigned to all sections" do
      @result.each do |course|
        expect(course.announcements).to include(@all_sections_announcement)
      end
    end

    it "should transfer section-specific announcements" do
      expect(@result[0].announcements).to include(@section1_announcement)
      expect(@result[1].announcements).not_to include(@section1_announcement)
    end
  end

  context "assignments" do
    it "should transfer assignments assigned to all sections" do
      @result.each do |course|
        expect(course.assignments).to include(@all_sections_assignment)
      end
    end

    it "should transfer section-specific assignments" do
      expect(@result[0].assignments).not_to include(@section2_assignment)
      expect(@result[1].assignments).to include(@section2_assignment)
    end
  end

  context "discussion topics" do
    it "should transfer discussion topics assigned to all sections" do
      @result.each do |course|
        expect(course.assignments).to include(@all_sections_topic)
      end
    end

    it "should transfer section-specific discussion topics" do
      expect(@result[0].discussion_topics).to include(@section1_topic)
      expect(@result[0].discussion_topics.length).to eq 2
      expect(@result[1].discussion_topics.length).to eq 1
      expect(@result[2].discussion_topics).not_to include(@section3_topic)
      expect(@result[2].discussion_topics.length).to eq 2
    end
  end

  context "quizzes" do
    it "should transfer quizzes assigned to all sections" do
      @result.each do |course|
        expect(course.quizzes).to include(@all_sections_quiz)
      end
    end

    it "should transfer section-specific quizzes" do
      expect(@result[0].quizzes).not_to include(@section3_quiz)
      expect(@result[2].quizzes).to include(@section3_quiz)
    end
  end

  context "wiki pages" do
    it "should replace links in page content" do
      expect(@result[1].wiki.wiki_pages.length).to eq 2
      dt1 = @result[1].discussion_topics.first
      page1 = @result[1].wiki.wiki_pages.find {|p| p.title == @wiki_page1.title }
      expect(page1).to exist
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
