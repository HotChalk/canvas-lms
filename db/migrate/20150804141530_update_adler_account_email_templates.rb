#encoding: utf-8

class UpdateAdlerAccountEmailTemplates < ActiveRecord::Migration
  tag :postdeploy

  def self.up
    return unless Shard.current == Shard.default

    # Adler University
    adler_account = Account.active.find_by_name('Adler')
    if adler_account && adler_account.settings
      adler_account.settings[:message_template_overrides] ||= {}
      adler_account.settings[:message_template_overrides].merge!({
        # ================================================================
        # new_user_registration.email.erb
        'new_user_registration.email.erb' => '''
<% p = asset.is_a?(Pseudonym) ? asset : asset.pseudonym %>

<% define_content :subject do %>
  <%= t :subject, "HotChalk Ember Account Created" %>
<% end %>

<%= t :body, "Hello %{name},", :name => p.user.name %>

Welcome to the HotChalk Ember Learning Management System for Adler University.

To access HotChalk Ember:

   • Login to https://hotchalkember.com with your username and password.
      • <%= t :body_login, "Username: %{login}", :login => p.unique_id %>
      • Your Password is the same as your Adler Connect password - a combination of the letters AU* and your six-digit birthdate AU*MMDDYY, where MM = your birth month, DD = your date of birth, and YY = your year of birth. For example, if your birthday was August 3, 1977, your password will be AU*080377.
   • Please bookmark https://hotchalkember.com, if you have not done so already, as it is the only access point for your HotChalk Ember courses.
   • To view your courses, hover over the Courses tab at the top of the page. You will see all active courses you are enrolled in.
   • If you are unable to access HotChalk Ember or your course, please submit a help ticket at https://support.hotchalkember.com and our support team will get back to you promptly.

Sincerely,

The Ember Support Team
''',

        # ================================================================
        # new_user_registration.email.html.erb
        'new_user_registration.email.html.erb' => '''
<% p = asset.is_a?(Pseudonym) ? asset : asset.pseudonym %>

<% define_content :subject do %>
  <%= t :subject, "HotChalk Ember Account Created" %>
<% end %>

<p><%= t :body, "Hello %{name},", :name => p.user.name %></p>

<p>Welcome to the HotChalk Ember Learning Management System for Adler University.</p>

<p>To access HotChalk Ember:</p>

<ul>
    <li>Login to <a href="https://hotchalkember.com">https://hotchalkember.com</a> with your username and password.</li>
    <ul>
      <li><%= t :body_login, "Username: %{login}", :login => p.unique_id %></li>
      <li>Your Password is the same as your Adler Connect password - a combination of the letters AU* and your six-digit birthdate AU*MMDDYY, where MM = your birth month, DD = your date of birth, and YY = your year of birth. For example, if your birthday was August 3, 1977, your password will be AU*080377.</li>
    </ul>
    <li>Please bookmark <a href="https://hotchalkember.com">https://hotchalkember.com</a>, if you have not done so already, as it is the only access point for your HotChalk Ember courses.</li>
    <li>To view your courses, hover over the Courses tab at the top of the page. You will see all active courses you are enrolled in.</li>
    <li>If you are unable to access HotChalk Ember or your course, please submit a help ticket at <a href="https://support.hotchalkember.com">https://support.hotchalkember.com</a> and our support team will get back to you promptly.</li>
</ul>

<p>Sincerely,</p>
<p>The Ember Support Team</p>
'''
      })
      adler_account.save!
    end
  end

  def self.down
    return unless Shard.current == Shard.default

    # Adler University
    adler_account = Account.active.find_by_name('Adler')
    if adler_account && adler_account.settings
      adler_account.settings.delete(:message_template_overrides)
      adler_account.save!
    end
  end
end
