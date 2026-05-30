# frozen_string_literal: true

RSpec::Matchers.define :be_success do
  match { |result| result.success? }
end

RSpec::Matchers.define :be_failure do
  match { |result| result.failure? }
end
