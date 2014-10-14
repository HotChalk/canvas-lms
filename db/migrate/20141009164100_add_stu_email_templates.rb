#encoding: utf-8

class AddStuEmailTemplates < ActiveRecord::Migration
  tag :postdeploy

  def self.up
    return unless Shard.current == Shard.default

    # St. Thomas
    stu_account = Account.active.find_by_name('St. Thomas')
    if stu_account && stu_account.settings
      stu_account.settings[:message_template_overrides] ||= {}
      stu_account.settings[:message_template_overrides].merge!({
        # ================================================================
        # enrollment_notification.email.erb
        'enrollment_notification.email.erb' => '''
<% define_content :link do %>
  <%= HostUrl.protocol %>://<%= HostUrl.context_host(asset.course) %>/login?account_id=<%= asset.root_account_id %>&course_id=<%= asset.course_id %>
<% end %>

<% define_content :subject do %>
  <%= t :subject, "Course Enrollment" %>
<% end %>

<%=
    case asset.type
    when \'TeacherEnrollment\'
      t :body_teacher, "You\'ve been enrolled in the course, %{course}, as a teacher.", :course => asset.course.name
    when \'TaEnrollment\'
      t :body_ta, "You\'ve been enrolled in the course, %{course}, as a TA.", :course => asset.course.name
    when \'ObserverEnrollment\'
      t :body_observer, "You\'ve been enrolled in the course, %{course}, as an observer.", :course => asset.course.name
    when \'DesignerEnrollment\'
      t :body_designer, "You\'ve been enrolled in the course, %{course}, as a designer.", :course => asset.course.name
    else
      t :body_student, "You\'ve been enrolled in the course, %{course}, as a student.", :course => asset.course.name
    end
%>
<% email = asset.user.email; login = (asset.user.pseudonym.unique_id rescue "none") %>
<%= before_label :name, "Name" %> <%= asset.user.name %>
<%= before_label :email, "Email" %> <%= asset.user.email %>

<% if !asset.user.registered? && asset.user.communication_channel %>
<%= t :register, "Visit %{link} to complete registration", :link => registration_confirmation_url(asset.user.communication_channel.confirmation_code, :host => HostUrl.context_host(asset.course)) %>
<% end %>

<%= t :details, "Visit the course page here:" %>
<%= content :link %>
''',

        # ================================================================
        # enrollment_notification.email.html.erb
        'enrollment_notification.email.html.erb' => '''
<% define_content :link do %>
  <%= HostUrl.protocol %>://<%= HostUrl.context_host(asset.course) %>/login?account_id=<%= asset.root_account_id %>&course_id=<%= asset.course_id %>
<% end %>

<% define_content :subject do %>
  <%= t :subject, "Course Enrollment" %>
<% end %>

<% define_content :footer_link do %>
  <% if !asset.user.registered? && asset.user.communication_channel %>
    <a href="<%= registration_confirmation_url(asset.user.communication_channel.confirmation_code, :host => HostUrl.context_host(asset.course)) %>">
      <%= t :complete_registration_link, "Click here to complete registration" %>
    </a>
  <% end %>
<% end %>

<% email = asset.user.email; login = (asset.user.pseudonym.unique_id rescue "none") %>
<% course = "<a href=\"#{content :link}\">#{h asset.course.name}</a>".html_safe %>
<p>
<%=
    case asset.type
    when \'TeacherEnrollment\'
      t :body_teacher, "You\'ve been enrolled in the course, %{course}, as a teacher.", :course => course
    when \'TaEnrollment\'
      t :body_ta, "You\'ve been enrolled in the course, %{course}, as a TA.", :course => course
    when \'ObserverEnrollment\'
      t :body_observer, "You\'ve been enrolled in the course, %{course}, as an observer.", :course => course
    when \'DesignerEnrollment\'
      t :body_designer, "You\'ve been enrolled in the course, %{course}, as a designer.", :course => course
    else
      t :body_student, "You\'ve been enrolled in the course, %{course}, as a student.", :course => course
    end
%>
</p>

<table border="0" style="font-size: 14px; color: #444444;
    font-family: \'Open Sans\', \'Lucida Grande\', \'Segoe UI\', Arial, Verdana, \'Lucida Sans Unicode\', Tahoma, \'Sans Serif\';
    border-collapse: collapse;">
    <tr>
        <td style="padding-right: 10px;"><%= t(:name, \'Name\') %>:</td>
        <td style="font-weight: bold;"><%= asset.user.name %></td>
    </tr>
    <tr>
        <td style="padding-right: 10px"><%= t(:email, \'Email\') %>:</td>
        <td style="font-weight: bold;"><%= email %></td>
    </tr>
</table>
'''
      })
      stu_account.save!
    end
  end

  def self.down
    return unless Shard.current == Shard.default

    # St. Thomas
    stu_account = Account.active.find_by_name('St. Thomas')
    if stu_account && stu_account.settings
      stu_account.settings.delete(:message_template_overrides)
      stu_account.save!
    end
  end
end
