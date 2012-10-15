class StaticController < ApplicationController
  def homepage
    @list_class = ""
    render :layout => false
  end

  def open_source
    @title = "open source"
  end

  def about
    @title = "about us"
    
    github = Github.new
    results = github.repos.contributors 'hotsh', 'rstat.us'
    @contributors = results.sort {|x,y| (x.login.downcase <=> y.login.downcase)}
  end

  def contact
    @title = "contact us"
  end
end
