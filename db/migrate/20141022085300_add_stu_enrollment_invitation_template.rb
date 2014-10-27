#encoding: utf-8

class AddStuEnrollmentInvitationTemplate < ActiveRecord::Migration
  tag :postdeploy

  def self.up
    return unless Shard.current == Shard.default

    # St. Thomas
    stu_account = Account.active.find_by_name('St. Thomas')
    if stu_account && stu_account.settings
      stu_account.settings[:message_template_overrides] ||= {}
      stu_account.settings[:message_template_overrides].merge!({
        # ================================================================
        # enrollment_invitation.email.erb
        'enrollment_invitation.email.erb' => '''
<% define_content :link do %>
  <%= HostUrl.protocol %>://<%= HostUrl.context_host(asset.course) %>/login?account_id=<%= asset.root_account_id %>&course_id=<%= asset.course_id %>
<% end %>

<% define_content :subject do %>
  <%= t :subject, "Course Invitation" %>
<% end %>

<%=
    case asset.type
    when \'TeacherEnrollment\'
      t :body_teacher, "You\'ve been invited to participate in the course, %{course}, as a teacher.", :course => asset.course.name
    when \'TaEnrollment\'
      t :body_ta, "You\'ve been invited to participate in the course, %{course}, as a TA.", :course => asset.course.name
    when \'ObserverEnrollment\'
      t :body_observer, "You\'ve been invited to participate in the course, %{course}, as an observer.", :course => asset.course.name
    when \'DesignerEnrollment\'
      t :body_designer, "You\'ve been invited to participate in the course, %{course}, as a designer.", :course => asset.course.name
    else
      t :body_student, "You\'ve been invited to participate in the course, %{course}, as a student.", :course => asset.course.name
    end
%>
<% email = asset.user.email; login = (asset.user.pseudonym.unique_id rescue "none") %>
<%= before_label :name, "Name" %> <%= asset.user.name %>
<%= before_label :email, "Email" %> <%= asset.user.email %>
<% if email != login %><%= before_label :username, "Username" %> <%= asset.user.pseudonym.unique_id rescue t(:none, "none") %><% end %>

<%= t :details, "Visit the course page here:" %>
<%= content :link %>        
''',
				# ================================================================
        # enrollment_invitation.email.html.erb
        'enrollment_invitation.email.html.erb' => '''
<% define_content :link do %>
  <%= HostUrl.protocol %>://<%= HostUrl.context_host(asset.course) %>/login?account_id=<%= asset.root_account_id %>&course_id=<%= asset.course_id %>
<% end %>
<% define_content :subject do %>
  <%= t :subject, "Course Invitation" %>
<% end %>
<% email = asset.user.email; login = (asset.user.pseudonym.unique_id rescue "none") %>

<p>
    <%=
        case asset.type
          when \'TeacherEnrollment\'
            t :body_teacher, "You\'ve been invited to participate in the course, %{course}, as a teacher.", :course => asset.course.name
          when \'TaEnrollment\'
            t :body_ta, "You\'ve been invited to participate in the course, %{course}, as a TA.", :course => asset.course.name
          when \'ObserverEnrollment\'
            t :body_observer, "You\'ve been invited to participate in the course, %{course}, as an observer.", :course => asset.course.name
          when \'DesignerEnrollment\'
            t :body_designer, "You\'ve been invited to participate in the course, %{course}, as a designer.", :course => asset.course.name
          else
            t :body_student, "You\'ve been invited to participate in the course, %{course}, as a student.", :course => asset.course.name
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
    <% if email != login %>
      <tr>
          <td style="padding-right: 10px;"><%= t(:username, \'Username\') %>:</td>
          <td style="font-weight: bold;"><%= asset.user.pseudonym.unique_id rescue t(:none, "none") %></td>
      </tr>
    <% end %>
</table>

<p><a href="<%= content(:link) %>"><%= t(:link, "Click here to view the course page") %></a></p>
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
      stu_account.settings[:message_template_overrides].delete('enrollment_invitation.email.erb')
      stu_account.settings[:message_template_overrides].delete('enrollment_invitation.email.html.erb')
      stu_account.save!
    end
  end
end
