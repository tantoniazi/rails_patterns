# frozen_string_literal: true

module UseCases
  class AuthenticateUser
    def initialize(user_repo: Infrastructure::Repositories::UserRepository.new)
      @user_repo = user_repo
    end

    def call(email:, password:)
      user = @user_repo.find_by_email(email)

      unless user&.active && user.authenticate(password)
        return Domain::Result.fail(["Invalid email or password"])
      end

      tokens = Infrastructure::Auth::JwtService.issue_tokens(user_id: user.id)
      Domain::Result.ok(user: user, tokens: tokens)
    end
  end
end
