class ReadingLogProcessor
  attr_reader :username

  def initialize(username:)
    @username = username
  end

  def user_prepared?
    ReadingLogExtractor::Processor
      .new(username: username, gh_facade: gh_facade)
      .repo_exist?
  end

  def pull_commits
    commits = []

    ReadingLogExtractor::Processor
      .new(username: username, gh_facade: gh_facade)
      .latest_commits(last_sha)  # in ASC order
      .reverse # DESC order
      .each do |log_commit|
        commits << Commit.new
          .tap {|c| c.sha         = log_commit.sha }
          .tap {|c| c.author      = log_commit.author }
          .tap {|c| c.avatar      = log_commit.avatar }
          .tap {|c| c.message     = log_commit.message }
          .tap {|c| c.commited_at = timeparser(log_commit.date) }
      end

    Commit.transaction do
      commits.each { |c| c.save! }
    end
  end

  def process_commits
    shas_groups_for_processing.each do |sha1, sha2|
      Commit
        .find_by!(sha: sha2 )
        .tap do |c|
          c.links = Parser
            .new(content(sha1, sha2))
            .tap { |r| r.call }
            .additions
        end
        .tap { |c| c.set_processed }
        .save!
    end
  end

  private
    def gh_facade
      ReadingLogExtractor::GithubFacade.new(gh_connection: gh_connection)
    end

    def gh_connection
      @gh_connection ||= begin
        oauth_token = Rails.application.secrets.fetch(:github_api_token)
        if oauth_token
          Github.new(oauth_token: oauth_token)
        else
          Github
        end
      end
    end

    def timeparser(js_time)
      Time.parse(js_time)
    end

    def content(sha1, sha2)
      raw_content(sha1, sha2)
    end

      def raw_content(sha1, sha2)
        ReadingLogExtractor::Processor
          .new(username: username, gh_facade: gh_facade)
          .content(sha1, sha2)
      end

    def last_sha
      Commit.latest_commit(username).try(:sha)
    end

    def shas_groups_for_processing
      (unprocessed_shas.concat([last_proccessed_sha]))
        .each_cons(2)
        .map { |a| a }
    end

      def unprocessed_shas
        Commit.unprocessed_shas(username)
      end

      def last_proccessed_sha
        Commit.latest_processed_sha(username)
      end
end
