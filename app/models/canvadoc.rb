#
# Copyright (C) 2014 Instructure, Inc.
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
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

class Canvadoc < ActiveRecord::Base
  attr_accessible :document_id, :process_state

  belongs_to :attachment

  has_and_belongs_to_many :submissions, -> { readonly(true) }, join_table: :canvadocs_submissions

  def upload(opts = {})
    return if document_id.present?

    url = attachment.authenticated_s3_url(:expires => 1.day)

    opts.delete(:annotatable) unless Canvadocs.annotations_supported?

    response = Canvas.timeout_protection("canvadocs") {
      canvadocs_api.upload(url, opts)
    }

    if response && response['id']
      self.document_id = response['id']
      self.process_state = response['status']
      self.has_annotations = opts[:annotatable]
      self.save!
    elsif response.nil?
      raise "no response received (request timed out?)"
    else
      raise response.inspect
    end
  end

  def session_url(opts = {})
    user = opts.delete(:user)
    opts.merge! annotation_opts(user)

    # The 'session' API call may fail if the document is not yet ready for viewing. This process usually
    # completes a few seconds after the initial upload, so we check a few times before giving up.
    attempts = 3
    backoff = 1 # initial wait time is 1 second
    begin
      return Canvas.timeout_protection("canvadocs", raise_on_timeout: true) do
        session = canvadocs_api.session(document_id, opts)
        canvadocs_api.view(session["id"])
      end
    rescue JSON::ParserError => e
      logger.warn "unable to retrieve session_url for document_id #{document_id}"
      Kernel.sleep(backoff)
      attempts -= 1
      backoff *= 2
      retry unless attempts.zero?
    end
    nil
  end

  def annotation_opts(user)
    return {} if !user || !has_annotations?

    opts = {
      annotation_context: "default",
      permissions: "readwrite",
      user_id: user.global_id,
      user_name: user.short_name.gsub(",", ""),
      user_role: "",
      user_filter: user.global_id,
    }

    submissions = self.submissions.preload(:assignment)

    return opts if submissions.empty?

    if submissions.any? { |s| s.grants_right? user, :read_grade }
      opts.delete :user_filter
    end

    # no commenting when anonymous peer reviews are enabled
    if submissions.map(&:assignment).any? { |a| a.peer_reviews? && a.anonymous_peer_reviews? }
      opts = {}
    end

    opts
  end
  private :annotation_opts

  def available?
    !!(document_id && process_state != 'error' && Canvadocs.enabled?)
  end

  def self.mime_types
    JSON.parse Setting.get('canvadoc_mime_types', %w[
      application/excel
      application/msword
      application/pdf
      application/vnd.ms-excel
      application/vnd.ms-powerpoint
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      application/vnd.openxmlformats-officedocument.presentationml.presentation
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
    ].to_json)
  end

  def canvadocs_api
    raise "Canvadocs isn't enabled" unless Canvadocs.enabled?
    Canvadocs::API.new(token: Canvadocs.config['api_key'],
                       base_url: Canvadocs.config['base_url'])
  end
  private :canvadocs_api
end
