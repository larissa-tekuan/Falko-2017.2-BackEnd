require "rest-client"

class IssuesController < ApplicationController
  include IssueGraphicHelper

  before_action :set_authorization, except: [:update_assignees]
  before_action :set_path, except: [:update_assignees]

  def index
    client = Adapter::GitHubIssue.new(request)

    @issues = client.list_issues(@path)

    convert_form_params(@issues)

    all_stories = Story.all

    all_stories_number = []

    all_stories.each do |story|
      all_stories_number.push(story.issue_number.to_i)
    end

    @filter_form = { issues_infos: [] }

    @filter_form[:issues_infos] = @form_params[:issues_infos]
    render json: @filter_form
  end

  def create
    client = Adapter::GitHubIssue.new(request)

    @issue = client.create_issue(@project.github_slug, issue_params)

    convert_form_params(@issue)

    render json: @form_params, status: :created
  end

  def update
    client = Adapter::GitHubIssue.new(request)

    @issue = client.update_issue(@project.github_slug, issue_params)

    convert_form_params(@issue)

    render json: @form_params
  end

  def close
    client = Adapter::GitHubIssue.new(request)

    client.close_issue(@path, issue_params)

    render status: :ok
  end

  def issue_graphic_data
    client = Adapter::GitHubIssue.new(request)

    page = 0
    issues_page = {}
    issues_hash = {}
    count = 0

    loop do
      issues_page = client.list_all_issues(@path, page)
      page = page + 1
      if(issues_page.count != 0)
        issues_page.each do |issue|
          issues_hash[count] = issue
          count = count + 1
        end
      end
      break if (issues_page.count == 0)
    end

    @issues = issues_hash

    actual_date = params[:actual_date].to_date
    option = params[:option]

    data_of_issues = {}

    data_of_issues = get_issues_graphic(actual_date, option, @issues, count)

    render json: data_of_issues
  end

  def update_assignees
    begin
      set_project

      @current_user = AuthorizeApiRequest.call(request.headers).result

      response = RestClient.patch("https://api.github.com/repos/#{@project.github_slug}/issues/#{params[:issue_number]}",
        { assignees: params[:assignees] }.to_json,
        Authorization: "token #{@current_user.access_token}"
      )

      render status: :ok
    rescue RestClient::UnprocessableEntity
      render json: { errors: "Cannot update assignees" }, status: :unprocessable_entity
    rescue RestClient::NotFound
      render json: { errors: "Content not found" }, status: :not_found
    rescue ActiveRecord::RecordNotFound
      render json: { errors: "Project not found" }, status: :not_found
    end
  end

  private

    def set_authorization
      client = Adapter::GitHubIssue.new(request)
    end

    def set_project
      @project = Project.find(params[:id])
    end

    def set_path
      set_project

      if @project.name.include? "/"
        @path = @project.name
      else
        client = Adapter::GitHubIssue.new(request)
        @name = client.get_github_user
        @repo = @project.name
        @path = @name.to_s + "/" + @repo
      end

      @path
    end

    def convert_form_params(issue)
      @form_params = { issues_infos: [] }
      if issue.kind_of?(Array)
        @issues.each do |issue|
          @form_params[:issues_infos].push(name: issue.title, number: issue.number, body: issue.body)
        end
      else
        @form_params[:issues_infos].push(name: issue.title, number: issue.number, body: issue.body)
      end
      @form_params
    end

    def issue_params
      params.require(:issue).permit(:name, :body, :number)
    end
end
