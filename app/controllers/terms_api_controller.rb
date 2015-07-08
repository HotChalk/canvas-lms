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
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

# @API Enrollment Terms
#
# API for viewing enrollment terms.  For all actions, the specified account
# must be a root account and the caller must have permission to manage the
# account (when called on non-root accounts, the errorwill be indicate the
# appropriate root account).
#
# @model EnrollmentTerm
#     {
#       "id": "EnrollmentTerm",
#       "description": "",
#       "properties": {
#         "id": {
#           "description": "The unique identifier for the enrollment term.",
#           "example": "1",
#           "type": "integer"
#         },
#         "sis_term_id": {
#           "description": "The SIS id of the term. Only included if the user has permission to view SIS information.",
#           "example": "Sp2014",
#           "type": "string"
#         },
#         "name": {
#           "description": "The name of the term.",
#           "example": "Spring 2014",
#           "type": "string"
#         },
#         "start_at": {
#           "description": "The datetime of the start of the term.",
#           "example": "2014-01-06T08:00:00-05:00",
#           "type": "datetime"
#         },
#         "end_at": {
#           "description": "The datetime of the end of the term.",
#           "example": "2014-05-16T05:00:00-04:00",
#           "type": "datetime"
#         },
#           "workflow_state": {
#           "description": "The state of the term. Can be 'active' or 'deleted'.",
#           "example": "active",
#           "type": "string"
#         }
#       }
#     }
#
class TermsApiController < ApplicationController
  before_filter :require_context, :require_root_account_management

  include Api::V1::EnrollmentTerm

  # @API List enrollment terms
  #
  # Return all of the terms in the account.
  #
  # @argument workflow_state[] [String, 'active'| 'deleted'| 'all']
  #   If set, only returns terms that are in the given state.
  #   Defaults to 'active'.
  # @argument sis_term_id [Optional, String]
  #   If set, returns the specified term.
  #   Defaults to nil.
  #
  # @returns [EnrollmentTerm]
  #
  def index
    terms = @context.enrollment_terms.order('start_at ASC, end_at ASC, id ASC')

    state = params[:workflow_state] || 'active'
    state = nil if Array(state).include?('all')
    terms = terms.where(workflow_state: state) if state.present?

    sis_term_id = params[:sis_term_id] || nil
    if sis_term_id.present?
      terms = terms.where(sis_source_id: sis_term_id)

      render json: {enrollment_term: enrollment_term_json(terms.first, @current_user, session)} if terms.size == 1
      render json: {errors: [{message: 'The requested term was not found.'}]}, status: 400 if terms.size != 1      
    else
      terms = Api.paginate(terms, self, api_v1_enrollment_terms_url)
      render json: { enrollment_terms: enrollment_terms_json(terms, @current_user, session) }
    end
  end

  def create
    overrides = params[:enrollment_term].delete(:overrides) rescue nil
    @term = @context.enrollment_terms.active.build(params[:enrollment_term])
    @term.sis_source_id = params[:enrollment_term].delete(:sis_term_id)
    if @term.save
      @term.set_overrides(@context, overrides)
      render :json => enrollment_term_json(@term, @current_user, session, [], [:enrollment_dates_overrides])
    else
      render :json => @term.errors, :status => :bad_request
    end
  end

  def update
    overrides = params[:enrollment_term].delete(:overrides) rescue nil
    @term = @context.enrollment_terms.active.find(params[:id])
    root_account = @context.root_account
    if sis_id = params[:enrollment_term].delete(:sis_term_id)
      if sis_id != @account.sis_source_id && root_account.grants_right?(@current_user, session, :manage_sis)
        if sis_id == ''
          @term.sis_source_id = nil
        else
          @term.sis_source_id = sis_id
        end
      end
    end
    if @term.update_attributes(params[:enrollment_term])
      @term.set_overrides(@context, overrides)
      render :json => enrollment_term_json(@term, @current_user, session, [], [:enrollment_dates_overrides])
    else
      render :json => @term.errors, :status => :bad_request
    end
  end

  def destroy
    @term = @context.enrollment_terms.find(params[:id])
    @term.destroy
    render :json => enrollment_term_json(@term, @current_user, session)
  end
end
