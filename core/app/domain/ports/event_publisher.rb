# frozen_string_literal: true

module Ports
  module EventPublisher
    def publish(**event_data) = raise NotImplementedError
  end
end
