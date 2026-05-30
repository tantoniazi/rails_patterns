# frozen_string_literal: true

module Api
  module V1
    module Reports
      class PostsController < BaseController
        def summary
          authorize :report, :posts_summary?
          @summaries = PostsSummary.order(:status)
        end
      end
    end
  end
end
