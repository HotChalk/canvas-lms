#encoding: utf-8

class UpdateConcordiaAccountEmailTemplates < ActiveRecord::Migration
  tag :postdeploy

  def self.up
    return unless Shard.current == Shard.default

    # Concordia University - Portland
    cup_account = Account.active.find_by_name('Concordia')
    if cup_account && cup_account.settings
      cup_account.settings[:message_template_overrides] ||= {}
      cup_account.settings[:message_template_overrides].merge!({
        # ================================================================
        # enrollment_notification.email.erb
        'enrollment_notification.email.erb' => '''
<% define_content :subject do %>
  <%= t :subject, "Course Enrollment" %>
<% end %>

<%= t :body, "Dear %{name},", :name => asset.user.name %>

<%=
    case asset.type
    when \'TeacherEnrollment\'
      t :body_teacher, "You have been enrolled in %{course} as an instructor.", :course => asset.course.name
    when \'TaEnrollment\'
      t :body_ta, "You have been enrolled in %{course} as a TA.", :course => asset.course.name
    when \'ObserverEnrollment\'
      t :body_observer, "You have been enrolled in %{course} as an observer.", :course => asset.course.name
    when \'DesignerEnrollment\'
      t :body_designer, "You have been enrolled in %{course} as a designer.", :course => asset.course.name
    else
      t :body_student, "You have been enrolled in %{course} as a student.", :course => asset.course.name
    end
%>

To access the course:

   • Login to http://login.cu-portland.edu/canvas with your network username and password. Please bookmark this page, if you have not done so already, as it is the only access point for your HotChalk Ember courses.

   • <%= t :body_course_name, "To view your newly added course, hover over the Courses tab at the top of the page. You will see all of your courses listed.  Choose %{course}.", :course => asset.course.name %>

   • If you are unable to access HotChalk Ember or your course, please submit a help ticket at https://support.hotchalkember.com and our support team will get back to you promptly.

Warm regards,
HotChalk Ember Support
''',

        # ================================================================
        # enrollment_notification.email.html.erb
        'enrollment_notification.email.html.erb' => '''
<% define_content :subject do %>
  <%= t :subject, "Course Enrollment" %>
<% end %>

<%= t :body, "Dear %{name},", :name => asset.user.name %>
<p>
<%=
    case asset.type
    when \'TeacherEnrollment\'
      t :body_teacher, "You have been enrolled in %{course} as an instructor.", :course => asset.course.name
    when \'TaEnrollment\'
      t :body_ta, "You have been enrolled in %{course} as a TA.", :course => asset.course.name
    when \'ObserverEnrollment\'
      t :body_observer, "You have been enrolled in %{course} as an observer.", :course => asset.course.name
    when \'DesignerEnrollment\'
      t :body_designer, "You have been enrolled in %{course} as a designer.", :course => asset.course.name
    else
      t :body_student, "You have been enrolled in %{course} as a student.", :course => asset.course.name
    end
%>
</p>

<p>To access the course:</p>

<ul>
    <li>Login to <a href="http://login.cu-portland.edu/canvas">http://login.cu-portland.edu/canvas</a> with your network username and password. Please bookmark this page, if you have not done so already, as it is the only access point for your HotChalk Ember courses.</li>
    <li><%= t :body_course_name, "To view your newly added course, hover over the Courses tab at the top of the page. You will see all of your courses listed.  Choose %{course}.", :course => asset.course.name %></li>
    <li>If you are unable to access HotChalk Ember or your course, please submit a help ticket at <a href="https://support.hotchalkember.com">https://support.hotchalkember.com</a> and our support team will get back to you promptly.</li>
</ul>

<p>Warm regards,</p>
<p>HotChalk Ember Support</p>
''',

        # ================================================================
        # new_user_registration.email.erb
        'new_user_registration.email.erb' => '''
<% p = asset.is_a?(Pseudonym) ? asset : asset.pseudonym %>

<% define_content :subject do %>
  <%= t :subject, "HotChalk Ember Account Created" %>
<% end %>

<%= t :body, "Dear %{name},", :name => p.user.name %>

Welcome to the HotChalk Ember Learning Management System (LMS) platform at Concordia University - Portland.

To access HotChalk Ember:

   • Login to http://login.cu-portland.edu/canvas with your network username and password. Please bookmark this page, if you have not done so already, as it is the only access point for your HotChalk Ember courses.

   • To view your courses, hover over the Courses tab at the top of the page. You will see all courses you are enrolled in that have been published.

   • If you are unable to access HotChalk Ember or your course, please submit a help ticket at https://support.hotchalkember.com and our support team will get back to you promptly.

Warm regards,
HotChalk Ember Support
''',

        # ================================================================
        # new_user_registration.email.html.erb
        'new_user_registration.email.html.erb' => '''
<% p = asset.is_a?(Pseudonym) ? asset : asset.pseudonym %>

<% define_content :subject do %>
  <%= t :subject, "HotChalk Ember Account Created" %>
<% end %>

<p><%= t :body, "Dear %{name},", :name => p.user.name %></p>

<p>Welcome to the HotChalk Ember Learning Management System (LMS) platform at Concordia University - Portland.</p>

<p>To access HotChalk Ember:</p>

<ul>
    <li>Login to <a href="http://login.cu-portland.edu/canvas">http://login.cu-portland.edu/canvas</a> with your network username and password. Please bookmark this page, if you have not done so already, as it is the only access point for your HotChalk Ember courses.</li>
    <li>To view your courses, hover over the Courses tab at the top of the page. You will see all courses you are enrolled in that have been published.</li>
    <li>If you are unable to access HotChalk Ember or your course, please submit a help ticket at <a href="https://support.hotchalkember.com">https://support.hotchalkember.com</a> and our support team will get back to you promptly.</li>
</ul>

<p>Warm regards,</p>
<p>HotChalk Ember Support</p>
'''
      })
      cup_account.save!
    end
  end

  def self.down
    return unless Shard.current == Shard.default

    # Concordia University - Portland
    cup_account = Account.active.find_by_name('Concordia')
    if cup_account && cup_account.settings
      cup_account.settings.delete(:message_template_overrides)
      cup_account.save!
    end
  end
end
