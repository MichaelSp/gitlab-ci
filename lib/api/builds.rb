require "#{Rails.root}/lib/report_parser/report_file_parser"

module API
  # Builds API
  class Builds < Grape::API
    resource :builds do
      # Runs oldest pending build by runner - Runners only
      #
      # Parameters:
      #   token (required) - The uniq token of runner
      #
      # Example Request:
      #   POST /builds/register
      post "register" do
        authenticate_runner!
        required_attributes! [:token]

        ActiveRecord::Base.transaction do
          builds = Build.scoped
          builds = builds.where(project_id: current_runner.projects) unless current_runner.shared?
          build =  builds.first_pending

          not_found! and return unless build

          build.runner_id = current_runner.id
          build.save!
          build.run!
          present build, with: Entities::Build
        end
      end

      # Update an existing build - Runners only
      #
      # Parameters:
      #   id (required) - The ID of a project
      #   state (optional) - The state of a build
      #   trace (optional) - The trace of a build
      #   reports(optional)- The requested report files as an json array
      # Example Request:
      #   PUT /builds/:id
      put ":id" do
        authenticate_runner!
        build = Build.where(runner_id: current_runner.id).running.find(params[:id])
        build.update_attributes(trace: params[:trace])
        state = params[:state].to_s
        params[:reports].each do |report|
          state = ReportParser.parse(report, build) unless report.content.blank?
        end if params[:reports]
        state = params[:state] unless state == 'failed'
        case state
        when 'success'
          build.success!
        when 'failed'
          build.drop!
        end
      end

      # Create a build
      #
      # Parameters:
      #   project_id (required) - The ID of a project
      #   project_token (requires) - Project token
      #   data (required) - GitLab push data
      #
      #   Sample GitLab push data:
      #   {
      #     "before": "95790bf891e76fee5e1747ab589903a6a1f80f22",
      #     "after": "da1560886d4f094c3e6c9ef40349f7d38b5d27d7",
      #     "ref": "refs/heads/master",
      #     "commits": [
      #       {
      #         "id": "b6568db1bc1dcd7f8b4d5a946b0b91f9dacd7327",
      #         "message": "Update Catalan translation to e38cb41.",
      #         "timestamp": "2011-12-12T14:27:31+02:00",
      #         "url": "http://localhost/diaspora/commits/b6568db1bc1dcd7f8b4d5a946b0b91f9dacd7327",
      #         "author": {
      #           "name": "Jordi Mallach",
      #           "email": "jordi@softcatala.org",
      #         }
      #       }, .... more commits
      #     ]
      #   }
      #
      # Example Request:
      #   POST /builds
      post do
        required_attributes! [:project_id, :data, :project_token]
        project = Project.find(params[:project_id])
        authenticate_project_token!(project)
        build = project.register_build(params[:data])

        if build.persisted?
          present build, with: Entities::Build
        else
          errors = build.errors.full_messages.join(", ")
          render_api_error!(errors, 400)
        end
      end
    end
  end
end
