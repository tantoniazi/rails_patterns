# frozen_string_literal: true

module UseCases
  class TransferFunds
    class InsufficientFundsError < StandardError; end

    def initialize(account_repo: Infrastructure::Repositories::AccountRepository.new)
      @account_repo = account_repo
    end

    def call(from_user:, to_user_id:, amount:)
      amount = BigDecimal(amount.to_s)
      return Domain::Result.fail(["Amount must be positive"]) unless amount.positive?

      to_user = User.active.find_by(id: to_user_id)
      return Domain::Result.fail(["Recipient not found"]) unless to_user

      transfer = nil

      Account.transaction do
        from_account = @account_repo.lock_for_user!(from_user.id)
        to_account = @account_repo.lock_for_user!(to_user.id)

        raise InsufficientFundsError if from_account.balance < amount

        from_account.balance -= amount
        to_account.balance += amount

        @account_repo.save!(from_account)
        @account_repo.save!(to_account)

        transfer = {
          from_account_id: from_account.id,
          to_account_id: to_account.id,
          amount: amount,
          from_balance: from_account.balance,
          to_balance: to_account.balance
        }
      end

      Domain::Result.ok(transfer)
    rescue InsufficientFundsError
      Domain::Result.fail(["Insufficient funds"])
    rescue ActiveRecord::StaleObjectError
      Domain::Result.fail(["Transfer conflict, please retry"])
    end
  end
end
