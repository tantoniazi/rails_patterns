# frozen_string_literal: true

module Api
  module V1
    class PostsController < BaseController
      before_action :set_post, only: %i[show update destroy]

      def index
        result = Domain::UseCases::ListPosts.new.call(filters: index_filters)
        @posts = result.value
      end

      def show
        authorize @post
        @post.increment_views! if @post.published?
      end

      def create
        authorize Post
        result = Domain::UseCases::CreatePost.new.call(
          user: current_user,
          attributes: post_params
        )

        if result.success?
          @post = result.value
          render :show, status: :created
        else
          render_errors(result.errors)
        end
      end

      def update
        authorize @post
        result = Domain::UseCases::UpdatePost.new.call(post: @post, attributes: post_params)

        if result.success?
          @post = result.value
          render :show
        else
          render_errors(result.errors)
        end
      end

      def destroy
        authorize @post
        Domain::UseCases::DestroyPost.new.call(post: @post)
        head :no_content
      end

      private

      def set_post
        @post = Post.find(params[:id])
      end

      def index_filters
        params.permit(:status, :q).to_h.symbolize_keys
      end

      def post_params
        params.require(:post).permit(:title, :body, :status)
      end
    end
  end
end
