#
# Copyright (C) 2011 Instructure, Inc.
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

class EnrollmentDatesOverride < ActiveRecord::Base
  belongs_to :context, :polymorphic => true
  validates_inclusion_of :context_type, :allow_nil => true, :in => ['Account']
  belongs_to :enrollment_term

  attr_accessible :context, :enrollment_type, :enrollment_term, :start_at, :end_at

  EXPORTABLE_ATTRIBUTES = [:id, :enrollment_term_id, :enrollment_type, :context_id, :context_type, :start_at, :end_at, :created_at, :updated_at]
  EXPORTABLE_ASSOCIATIONS = [:context, :enrollment_term]

  before_save :touch_all_courses
  validate :end_at_date_cannot_be_before_start_at_date

  def touch_all_courses
    self.enrollment_term.update_courses_later if self.changed?
  end

  def end_at_date_cannot_be_before_start_at_date
    if self.end_at && self.start_at && (self.end_at < self.start_at)
      errors.add(:start_at, "To date can't be before the from date")
    end
  end
end
