# frozen_string_literal: true

module UseCases
  class CreateComment
    def call(user:, post:, body:)
      comment = post.comments.build(user: user, body: body)

      if comment.save
        Domain::Result.ok(comment)
      else
        Domain::Result.fail(comment.errors.full_messages)
      end
    end
  end
end
