# frozen_string_literal: true

module Api
  module V1
    class CommentsController < BaseController
      before_action :set_post

      def index
        @comments = @post.comments.includes(:user).order(created_at: :desc)
      end

      def create
        authorize @post, :comment?
        result = Domain::UseCases::CreateComment.new.call(
          user: current_user,
          post: @post,
          body: comment_params[:body]
        )

        if result.success?
          @comment = result.value
          render :show, status: :created
        else
          render_errors(result.errors)
        end
      end

      private

      def set_post
        @post = Post.find(params[:post_id])
      end

      def comment_params
        params.require(:comment).permit(:body)
      end
    end
  end
end
