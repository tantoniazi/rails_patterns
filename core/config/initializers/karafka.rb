# frozen_string_literal: true

return if Rails.env.test?

require "karafka"
require Rails.root.join("karafka")
