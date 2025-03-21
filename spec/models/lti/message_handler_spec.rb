# frozen_string_literal: true

#
# Copyright (C) 2014 - present Instructure, Inc.
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

require_relative "../../lti2_spec_helper"

module Lti
  describe MessageHandler do
    let(:account) { Account.create }
    let(:product_family) { ProductFamily.create(vendor_code: "123", product_code: "abc", vendor_name: "acme", root_account: account) }

    describe "validations" do
      before do
        subject.message_type = "message_type"
        subject.launch_path = "launch_path"
        subject.resource_handler = ResourceHandler.new
      end

      it "requires the message type" do
        subject.message_type = nil
        subject.save
        expect(subject.errors[:message_type].first).to eq "can't be blank"
      end

      it "requires the launch path" do
        subject.launch_path = nil
        subject.save
        expect(subject.errors[:launch_path].first).to eq "can't be blank"
      end

      it "requires a resource_handler" do
        subject.resource_handler = nil
        subject.save
        expect(subject.errors[:resource_handler].first).to eq "can't be blank"
      end
    end

    describe "scope #message_type" do
      it "returns all message_handlers for a message_type" do
        create_message_handler
        create_message_handler
        create_message_handler(create_resource_handler, message_type: "content_item")

        message_handlers = described_class.by_message_types("basic-lti-launch-request")
        expect(message_handlers.count).to eq 2
      end

      it "returns all message_handlers for mutlipe message types" do
        rh = create_resource_handler
        create_message_handler(rh)
        create_message_handler(rh, message_type: "other_type")
        create_message_handler(rh, message_type: "content_item")

        message_handlers = described_class.by_message_types("basic-lti-launch-request", "other_type")
        expect(message_handlers.count).to eq 2
      end
    end

    describe "scope #for_context" do
      it "returns all message_handlers for a tool proxy" do
        tp = create_tool_proxy
        tp.bindings.create(context: account)
        message_handlers = (1..3).map do |code|
          rh = create_resource_handler(tp, resource_type_code: code)
          create_message_handler(rh)
        end
        expect(Set.new(described_class.for_context(account))).to eq Set.new(message_handlers)
      end

      it "returns all message_handlers for multiple tool_proxy" do
        tool_proxies = (1..3).map { |_| create_tool_proxy }
        message_handlers = tool_proxies.map do |tp|
          tp.bindings.create(context: account)
          rh = create_resource_handler(tp)
          create_message_handler(rh)
        end
        expect(Set.new(described_class.for_context(account))).to eq Set.new(message_handlers)
      end
    end

    describe "scope #has_placements" do
      before :once do
        tp = create_tool_proxy
        rh1 = create_resource_handler(tp, resource_type_code: 1)
        rh2 = create_resource_handler(tp, resource_type_code: 2)
        rh3 = create_resource_handler(tp, resource_type_code: 3)
        @mh1 = create_message_handler(rh1)
        @mh2 = create_message_handler(rh2)
        @mh3 = create_message_handler(rh3)
        @mh1.placements.create!(placement: ResourcePlacement::ACCOUNT_NAVIGATION)
        @mh1.placements.create!(placement: ResourcePlacement::COURSE_NAVIGATION)
        @mh2.placements.create!(placement: ResourcePlacement::ACCOUNT_NAVIGATION)
        @mh3.placements.create!(placement: ResourcePlacement::COURSE_NAVIGATION)
      end

      it "filters on one placement type" do
        handlers = described_class.has_placements(ResourcePlacement::ACCOUNT_NAVIGATION)
        expect(handlers.count).to eq 2
        expect(handlers).to include(@mh1)
        expect(handlers).to include(@mh2)
      end

      it "filters on multiple placement types" do
        handlers = described_class.has_placements(ResourcePlacement::ACCOUNT_NAVIGATION, ResourcePlacement::COURSE_NAVIGATION)
        expect(handlers.count).to eq 3
        expect(handlers).to include(@mh1)
        expect(handlers).to include(@mh2)
        expect(handlers).to include(@mh3)
      end
    end

    describe "#lti_apps_tabs" do
      before :once do
        @tp = create_tool_proxy
        rh1 = create_resource_handler(@tp, resource_type_code: 1)
        rh2 = create_resource_handler(@tp, resource_type_code: 2)
        rh3 = create_resource_handler(@tp, resource_type_code: 3)
        @mh1 = create_message_handler(rh1)
        @mh2 = create_message_handler(rh2)
        @mh3 = create_message_handler(rh3)
        @mh1.placements.create!(placement: ResourcePlacement::ACCOUNT_NAVIGATION)
        @mh1.placements.create!(placement: ResourcePlacement::COURSE_NAVIGATION)
        @mh2.placements.create!(placement: ResourcePlacement::ACCOUNT_NAVIGATION)
        @mh3.placements.create!(placement: ResourcePlacement::COURSE_NAVIGATION)
      end

      it "converts a message handler into json tab" do
        @tp.bindings.create!(context: account)

        tabs = described_class.lti_apps_tabs(account, [ResourcePlacement::ACCOUNT_NAVIGATION], {})
        expect(tabs.count).to eq 2
        tab = tabs.find { |t| t[:id] == "lti/message_handler_#{@mh1.id}" }
        expect(tab).to eq({
                            id: "lti/message_handler_#{@mh1.id}",
                            label: "resource name",
                            css_class: "lti/message_handler_#{@mh1.id}",
                            href: :account_basic_lti_launch_request_path,
                            visibility: nil,
                            external: true,
                            hidden: false,
                            args: { message_handler_id: @mh1.id, resource_link_fragment: "nav", account_id: account.id }
                          })
      end

      it "returns message handlers tabs for account with account_navigation placement" do
        @tp.bindings.create(context: account)

        tabs = described_class.lti_apps_tabs(account, [ResourcePlacement::ACCOUNT_NAVIGATION], {})
        expect(tabs.count).to eq 2
        tab1 = tabs.find { |t| t[:id] == "lti/message_handler_#{@mh1.id}" }
        tab2 = tabs.find { |t| t[:id] == "lti/message_handler_#{@mh2.id}" }
        expect(tab1).to_not be_nil
        expect(tab2).to_not be_nil
      end

      it "returns message handlers tabs for course with course_navigation placement" do
        course_with_teacher(account:)
        @tp.bindings.create(context: @course)

        tabs = described_class.lti_apps_tabs(@course, [ResourcePlacement::COURSE_NAVIGATION], {})
        expect(tabs.count).to eq 2
        tab1 = tabs.find { |t| t[:id] == "lti/message_handler_#{@mh1.id}" }
        tab2 = tabs.find { |t| t[:id] == "lti/message_handler_#{@mh3.id}" }
        expect(tab1).to_not be_nil
        expect(tab2).to_not be_nil
      end
    end

    describe "#self.by_resource_codes" do
      include_context "lti2_spec_helper"

      let(:jwt_body) do
        {
          vendor_code: product_family.vendor_code,
          product_code: product_family.product_code,
          resource_type_code: resource_handler.resource_type_code
        }
      end

      before do
        message_handler.update(message_type: MessageHandler::BASIC_LTI_LAUNCH_REQUEST)
      end

      it "finds message handlers when tool is installed in current account" do
        tool_proxy.update(context: account)
        mh = MessageHandler.by_resource_codes(vendor_code: jwt_body[:vendor_code],
                                              product_code: jwt_body[:product_code],
                                              resource_type_code: jwt_body[:resource_type_code],
                                              context: tool_proxy.context)
        expect(mh).to eq message_handler
      end

      it "finds message handlers when tool is installed in current course" do
        tool_proxy.update(context: course)
        mh = MessageHandler.by_resource_codes(vendor_code: jwt_body[:vendor_code],
                                              product_code: jwt_body[:product_code],
                                              resource_type_code: jwt_body[:resource_type_code],
                                              context: tool_proxy.context)
        expect(mh).to eq message_handler
      end

      it "does not return message handlers with a different message_type" do
        message_handler.update(message_type: "banana")
        mh = MessageHandler.by_resource_codes(vendor_code: jwt_body[:vendor_code],
                                              product_code: jwt_body[:product_code],
                                              resource_type_code: jwt_body[:resource_type_code],
                                              context: tool_proxy.context)
        expect(mh).to be_nil
      end

      context "account chain search" do
        it "finds message handlers when tool is installed in course root account" do
          course.update(root_account: account)
          tool_proxy.update(context: account)
          mh = MessageHandler.by_resource_codes(vendor_code: jwt_body[:vendor_code],
                                                product_code: jwt_body[:product_code],
                                                resource_type_code: jwt_body[:resource_type_code],
                                                context: course)
          expect(mh).to eq message_handler
        end

        it "finds message handlers when tool is installed in account root account" do
          sub = account.sub_accounts.create!
          mh = MessageHandler.by_resource_codes(vendor_code: jwt_body[:vendor_code],
                                                product_code: jwt_body[:product_code],
                                                resource_type_code: jwt_body[:resource_type_code],
                                                context: sub)
          expect(mh).to eq message_handler
        end
      end
    end

    describe "#valid_resource_url?" do
      include_context "lti2_spec_helper"

      it "returns false if the domain does not match the launch path domain" do
        invalid_url = "http://www.banana.com/launch"
        expect(message_handler.valid_resource_url?(invalid_url)).to be false
      end

      it "returns true if the domain matches the launch path domain" do
        valid_url = "#{message_handler.launch_path}/my-launch"
        expect(message_handler.valid_resource_url?(valid_url)).to be true
      end
    end

    describe "#resource_codes" do
      include_context "lti2_spec_helper"

      let(:expected_hash) do
        {
          product_code: product_family.product_code,
          vendor_code: product_family.vendor_code,
          resource_type_code: resource_handler.resource_type_code
        }
      end

      it "returns three identifying lti codes" do
        expect(message_handler.resource_codes).to eq expected_hash
      end
    end

    def create_tool_proxy(opts = {})
      default_opts = {
        context: account,
        shared_secret: "shared_secret",
        guid: SecureRandom.uuid,
        product_version: "1.0beta",
        lti_version: "LTI-2p0",
        product_family:,
        workflow_state: "active",
        raw_data: "some raw data"
      }
      ToolProxy.create(default_opts.merge(opts))
    end

    def create_resource_handler(tool_proxy = create_tool_proxy, opts = {})
      default_opts = { resource_type_code: "code", name: "resource name", tool_proxy: }
      ResourceHandler.create(default_opts.merge(opts))
    end

    def create_message_handler(resource_handler = create_resource_handler, opts = {})
      default_ops = { message_type: "basic-lti-launch-request", launch_path: "https://samplelaunch/blti", resource_handler: }
      MessageHandler.create!(default_ops.merge(opts))
    end
  end
end
