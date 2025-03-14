# frozen_string_literal: true

#
# Copyright (C) 2013 - present Instructure, Inc.
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

# @API CommMessages
#
# API for accessing the messages (emails, sms, etc) that have
# been sent to a user.
#
# @model CommMessage
#     {
#       "id": "CommMessage",
#       "description": "",
#       "properties": {
#         "id": {
#           "description": "The ID of the CommMessage.",
#           "example": 42,
#           "type": "integer"
#         },
#         "created_at": {
#           "description": "The date and time this message was created",
#           "example": "2013-03-19T21:00:00Z",
#           "type": "datetime"
#         },
#         "sent_at": {
#           "description": "The date and time this message was sent",
#           "example": "2013-03-20T22:42:00Z",
#           "type": "datetime"
#         },
#         "workflow_state": {
#           "description": "The workflow state of the message. Possible values: 'created' : The message has been created, but not yet processed. 'staged' : The message is queued for sending. 'sending' : The message is being sent currently. 'sent' : The message has been successfully sent. 'bounced' : An error occurred during the sending of the message.'dashboard' : The message has been sent to the dashboard. 'closed' :  The message has been sent and closed, typically for dashboard messages or messages sent to deleted users. 'cancelled' : The message was cancelled before it could be sent.",
#           "example": "sent",
#           "type": "string",
#           "allowableValues": {
#             "values": [
#               "created",
#               "staged",
#               "sending",
#               "sent",
#               "bounced",
#               "dashboard",
#               "cancelled",
#               "closed"
#             ]
#           }
#         },
#         "from": {
#           "description": "The address that was put in the 'from' field of the message",
#           "example": "notifications@example.com",
#           "type": "string"
#         },
#         "from_name": {
#           "description": "The display name for the from address",
#           "example": "Instructure Canvas",
#           "type": "string"
#         },
#         "to": {
#           "description": "The address the message was sent to:",
#           "example": "someone@example.com",
#           "type": "string"
#         },
#         "reply_to": {
#           "description": "The reply_to header of the message",
#           "example": "notifications+specialdata@example.com",
#           "type": "string"
#         },
#         "subject": {
#           "description": "The message subject",
#           "example": "example subject line",
#           "type": "string"
#         },
#         "body": {
#           "description": "The plain text body of the message",
#           "example": "This is the body of the message",
#           "type": "string"
#         },
#         "html_body": {
#           "description": "The HTML body of the message.",
#           "example": "<html><body>This is the body of the message</body></html>",
#           "type": "string"
#         }
#       }
#     }
#
class CommMessagesApiController < ApplicationController
  include Api::V1::CommMessage

  before_action :require_user

  # @API List of CommMessages for a user
  #
  # Retrieve a paginated list of messages sent to a user.
  #
  # @argument user_id [Required, String]
  #   The user id for whom you want to retrieve CommMessages
  #
  # @argument start_time [DateTime]
  #   The beginning of the time range you want to retrieve message from.
  #   Up to a year prior to the current date is available.
  #
  # @argument end_time [DateTime]
  #   The end of the time range you want to retrieve messages for.
  #   Up to a year prior to the current date is available.
  #
  # @returns [CommMessage]
  def index
    user = api_find(User, params[:user_id])
    start_time = CanvasTime.try_parse(params[:start_time])
    end_time = CanvasTime.try_parse(params[:end_time])

    query = user.messages.order("created_at DESC")

    # site admins see all, but if not a site admin...
    unless Account.site_admin.grants_right?(@current_user, :read_messages) && @domain_root_account.grants_right?(@current_user, :read)
      # ensure they can see the domain root account
      unless @domain_root_account.settings[:admins_can_view_notifications] &&
             @domain_root_account.grants_right?(@current_user, :view_notifications)
        return render_unauthorized_action
      end

      # and then scope to just the messages from that root account
      query = query.where(root_account_id: @domain_root_account)
    end

    query = query.where(created_at: start_time..) if start_time
    query = query.where(created_at: ..end_time) if end_time
    messages = Api.paginate(query, self, api_v1_comm_messages_url)

    messages_json = messages.map { |m| comm_message_json(m) }
    render json: messages_json
  end
end
