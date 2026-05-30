# frozen_string_literal: true

class Result
  attr_reader :value, :errors

  def initialize(success:, value: nil, errors: [])
    @success = success
    @value = value
    @errors = Array(errors)
  end

  def success?
    @success
  end

  def failure?
    !success?
  end

  def self.ok(value = nil)
    new(success: true, value: value)
  end

  def self.fail(errors)
    new(success: false, errors: errors)
  end
end
