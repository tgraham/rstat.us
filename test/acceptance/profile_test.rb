require 'require_relative' if RUBY_VERSION[0,3] == '1.8'
require_relative 'acceptance_helper'

describe "profile" do
  include AcceptanceHelper

  it "redirects to the username's profile with the right case" do
    u = Fabricate(:user)
    visit "/users/#{u.username.upcase}"
    current_url.must_match(/\/users\/#{u.username}$/)
  end

  it "allows viewing of profiles when username contains a dot" do
    u = Fabricate(:user, :username => "foo.bar")
    visit "/users/#{u.username}"

    page.within('div.nickname') do
      assert_match /@foo\.bar/, text
    end
  end

  it "has the user's updates on the page in reverse chronological order" do
    skip "Passing locally but failing on Travis and we don't know why"

    u = Fabricate(:user)
    update1 = Fabricate(:update,
                      :text       => "This is a message posted yesterday",
                      :author     => u.author,
                      :created_at => 1.day.ago)
    update2 = Fabricate(:update,
                      :text       => "This is a message posted last week",
                      :author     => u.author,
                      :created_at => 1.week.ago)
    u.feed.updates << update1
    u.feed.updates << update2

    visit "/users/#{u.username}"
    assert_match /#{update1.text}.*#{update2.text}/m, page.body
  end

  it "responds with HTML by default if Accept header is */*" do
    u = Fabricate(:user)

    header "Accept", "*/*"
    get "/users/#{u.username}"

    html = Nokogiri::HTML::Document.parse(last_response.body)
    user_text = html.css("span.user-text")

    user_text.first.text.must_match(u.username)
  end

  it "404s if the user doesnt exist" do
    visit "/users/nonexistent"
    assert_match "The page you were looking for doesn't exist.", page.body
  end

  it "has a link to edit your own profile" do
    log_in_as_some_user
    visit "/users/#{@u.username}"

    assert has_link? "Edit"
  end

  describe "updating" do
    before do
      Pony.deliveries.clear
      log_in_as_some_user
    end

    attributes_without_confirmation = {"name"    => "Mark Zuckerberg",
                                       "website" => "http://test.com",
                                       "bio"     => "To be or not to be"}

    attributes_without_confirmation.each do |key, value|
      it "updates your #{key}" do
        visit "/users/#{@u.username}/edit"
        fill_in key, :with => value

        VCR.use_cassette("update_profile_#{key}") do
          click_button "Save"
        end

        within profile(key) do
          assert has_content?(value), "Cannot find #{key} with text #{value}"
        end
      end
    end

    it "updates your password successfully" do
      visit "/users/#{@u.username}/edit"
      fill_in "password", :with => "new_password"
      fill_in "password_confirm", :with => "new_password"

      VCR.use_cassette("update_profile_password") do
        click_button "Save"
      end

      within profile "name" do
        assert has_content?(@u.author.name), "Password update failed"
      end
    end

    it "does not update your password if the confirmation doesn't match" do
      visit "/users/#{@u.username}/edit"
      fill_in "password", :with => "new_password"
      fill_in "password_confirm", :with => "bunk"

      VCR.use_cassette("update_profile_password_mismatch") do
        click_button "Save"
      end

      within flash do
        assert has_content?("Profile could not be saved: Passwords must match")
      end

      assert has_field?("password")
    end

    it "verifies your email if you change it" do
      visit "/users/#{@u.username}/edit"
      email = "new_email@new_email.com"
      fill_in "email", :with => email

      VCR.use_cassette('update_profile_email') do
        click_button "Save"
      end

      within profile "name" do
        assert has_content? @u.author.name
      end

      if ENV["CONFIRMATION_DISABLED"]
        assert_equal 0, Pony.deliveries.size
      else
        assert_equal 1, Pony.deliveries.size
      end
    end

    it "does not verify your email if you havent specified one" do
      user_without_email = Fabricate(:user, :email => nil, :username => "no_email")
      a = Fabricate(:authorization, :user => user_without_email)

      log_in(user_without_email, a.uid)
      visit "/users/#{user_without_email.username}/edit"
      name = "Mark Zuckerberg"
      fill_in "name", :with => name

      VCR.use_cassette('update_profile_no_email') do
        click_button "Save"
      end

      within profile "name" do
        assert has_content? name
      end

      assert Pony.deliveries.empty?
    end

    it "does not verify your email if you havent changed it" do
      visit "/users/#{@u.username}/edit"
      name = "Steve Jobs"
      fill_in "name", :with => name

      VCR.use_cassette('update_profile_no_email') do
        click_button "Save"
      end

      within profile "name" do
        assert has_content? name
      end

      assert Pony.deliveries.empty?
    end
  end

  it "doesn't let a logged out user update someone's profile" do
    u = Fabricate(:user)
    visit "/users/#{u.username}/edit"
    page.current_url.wont_match(/\/users\/#{u.username}\/edit/)
  end

  it "doesn't let you update someone else's profile" do
    log_in_as_some_user
    u = Fabricate(:user)
    visit "/users/#{u.username}/edit"
    assert_match /\/users\/#{u.username}$/, page.current_url
  end

  it "does let you update your profile even if you use a different case in the url" do
    u = Fabricate(:user, :username => "LADY_GAGA")
    a = Fabricate(:authorization, :user => u)
    log_in(u, a.uid)
    visit "/users/lady_gaga/edit"
    bio_text = "To be or not to be"
    fill_in "bio", :with => bio_text

    VCR.use_cassette('update_profile_different_case') do
      click_button "Save"
    end

    within profile "bio" do
      assert has_content? bio_text
    end
  end
end
