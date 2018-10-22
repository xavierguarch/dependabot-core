# frozen_string_literal: true

require "toml-rb"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/utils/go/version"

module Dependabot
  module UpdateCheckers
    module Go
      class Modules < Dependabot::UpdateCheckers::Base
        def latest_resolvable_version
          # TODO
          #  - for psuedo versions, if the commit referenced has been tagged
          #    in a non-modules-compliant way, still update to the next release
          #    as recognised by the dep logic
          @latest_resolvable_version ||= find_latest_resolvable_version
        end

        # This is currently used to short-circuit latest_resolvable_version,
        # with the assumption that it'll be quicker than checking
        # resolvability. As this is quite quick in Go anyway, we just alias.
        def latest_version
          latest_resolvable_version
        end

        def latest_resolvable_version_with_no_unlock
          # Irrelevant, since Go modules uses a single dependency file
          nil
        end

        def updated_requirements
          # TODO
          dependency.requirements
          # dependency.requirements.map do |req|
          #   updated_source = req.fetch(:source).dup
          #   updated_source[:digest] = updated_digest if req[:source][:digest]
          #   updated_source[:tag] = latest_version if req[:source][:tag]

          #   req.merge(source: updated_source)
          # end
        end

        private

        def find_latest_resolvable_version
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              File.write("go.mod", go_mod.content)

              SharedHelpers.run_helper_subprocess(
                command: "GO111MODULE=on #{go_helper_path}",
                function: "getUpdatedVersion",
                args: {
                  dependency: {
                    name: dependency.name,
                    version: dependency.version,
                    indirect: dependency.requirements.empty?
                  }
                }
              )
            end
          end
        end

        def go_helper_path
          File.join(
            project_root,
            "helpers/go/go-helpers.#{platform}64",
          )
        end

        def project_root
          File.join(File.dirname(__FILE__), "../../../..")
        end

        def platform
          case RbConfig::CONFIG["arch"]
          when /linux/ then "linux"
          when /darwin/ then "darwin"
          else raise "Invalid platform #{RbConfig::CONFIG['arch']}"
          end
        end

        def module_update_info
          @module_update_info ||=
            SharedHelpers.in_a_temporary_directory do
              SharedHelpers.with_git_configured(credentials: credentials) do
                File.write("go.mod", go_mod.content)

                output = `GO111MODULE=on go list -m -u -json #{dependency.name}`
                unless $CHILD_STATUS.success?
                  raise Dependabot::DependencyFileNotParseable, go_mod.path
                end

                JSON.parse(output)
              end
            end
        end

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Go (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        # Override the base class's check for whether this is a git dependency,
        # since not all dep git dependencies have a SHA version (sometimes their
        # version is the tag)
        def existing_version_is_sha?
          git_dependency?
        end

        def library?
          dependency_files.none? { |f| f.type == "package_main" }
        end

        def version_from_tag(tag)
          # To compare with the current version we either use the commit SHA
          # (if that's what the parser picked up) of the tag name.
          if dependency.version&.match?(/^[0-9a-f]{40}$/)
            return tag&.fetch(:commit_sha)
          end

          tag&.fetch(:tag)
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def default_source
          { type: "default", source: dependency.name }
        end

        def go_mod
          @go_mod ||= dependency_files.find { |f| f.name == "go.mod" }
        end

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              credentials: credentials,
              ignored_versions: ignored_versions
            )
        end
      end
    end
  end
end
