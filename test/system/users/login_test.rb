require 'application_system_test_case'

module Users
  class LoginTest < ::ApplicationSystemTestCase
    def log_in(user)
      user.update!(password: 'password')
      visit root_url
      click_on 'Sign in'
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'password'
      click_on 'Log in'
    end

    test 'can log in' do
      user = users(:one)
      log_in(user)
      assert_link "Timmy O'Toole"
    end

    test "can't log in when banned" do
      user = users(:one)
      user.update!(banned_at: Time.zone.now)
      log_in(user)
      assert_content 'Your account has been banned.'
    end

    test 'can see banned reason' do
      user = users(:one)
      user.update!(banned_at: Time.zone.now)
      ModeratorAction.create!(user:, reason: 'You suck', action: 'ban', moderator: users(:admin))
      log_in(user)
      assert_content 'Your account has been banned. A moderator gave the following reason: "You suck".'
    end

    test 'can see banning report' do
      user = users(:one)
      user.update!(banned_at: Time.zone.now)
      report = Report.create!(reporter: users(:admin), item: user, reason: Report::REASON_ABUSE)
      ModeratorAction.create!(user:, reason: 'You suck', action: 'ban', moderator: users(:admin), report:)
      log_in(user)
      assert_content 'Your account has been banned in response to this report.'
    end

    test 'can delete account when banned' do
      user = users(:one)
      user.update!(banned_at: Time.zone.now)
      log_in(user)
      assert_content 'Your account has been banned.'
      click_on 'delete your account'
      fill_in 'Email', with: user.email
      fill_in 'Password', with: 'password'
      assert_changes -> { User.find_by(id: user.id) }, to: nil do
        click_on 'Log in'
        assert_content 'Your account has been deleted.'
      end
    end

    test 'login with a really long URL' do
      visit code_search_scripts_path(q: '1' * 4000)
      assert_content 'You need to sign in or sign up before continuing.'
    end

    test 'login shows secure message when the user has scripts' do
      user = users(:one)
      assert user.scripts.any?
      log_in(user)
      assert_content 'As a script author, we suggest you use a more secure sign-in method.'
    end

    test 'login does not show secure message when the user has no scripts' do
      user = users(:one)
      user.scripts.delete_all
      log_in(user)
      assert_no_content 'As a script author, we suggest you use a more secure sign-in method.'
    end

    test 'login does not show secure message when the user already uses secure login' do
      user = users(:one)
      User.any_instance.expects(:uses_secure_login?).returns(true)
      log_in(user)
      assert_no_content 'As a script author, we suggest you use a more secure sign-in method.'
    end
  end
end
