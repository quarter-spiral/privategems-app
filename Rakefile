#encoding: utf-8

require "rubygems"
require "rubygems/package_task"

Gem::PackageTask.new(eval(File.read("geminabox.gemspec"))) do |pkg|
end

desc 'Clear out generated packages'
task :clean => [:clobber_package]

require 'rake/testtask'

Rake::TestTask.new("test:integration") do |t|
  t.libs << "test" << "lib"
  t.pattern = "test/integration/**/*_test.rb"
end

Rake::TestTask.new("test:smoke:paranoid") do |t|
  t.libs << "test" << "lib"
  t.pattern = "test/smoke_test.rb"
end

desc "Run the smoke tests, faster."
task "test:smoke" do
  $:.unshift("lib").unshift("test")
  require "smoke_test"
end

Rake::TestTask.new("test:requests") do |t|
  t.libs << "test" << "lib"
  t.pattern = "test/requests/**/*_test.rb"
end

Rake::TestTask.new("test:units") do |t|
  t.libs << "test" << "lib"
  t.pattern = "test/units/**/*_test.rb"
end

task :st => "test:smoke"
task :test => ["test:units", "test:requests", "test:integration"]
task :default => :test


def github_http
  return @github_http if @github_http

  github_api_uri = URI.parse('https://api.github.com/')

  @github_http = Net::HTTP.new(github_api_uri.host, github_api_uri.port)
  @github_http.use_ssl = true
  @github_http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  @github_http
end

def github_request(url, clazz, options = {})
  if options[:oauth]
    suffix = (url =~ /\?/) ? '&' : '?'
    url += "#{suffix}access_token=#{options[:oauth]}"
  end

  request = clazz.new(url)

  if options[:basic_auth]
    request.basic_auth(options[:basic_auth][:user], options[:basic_auth][:pass])
  end

  request.body = JSON.dump(options[:body] || {})
  response = github_http.request(request)
  data = JSON.parse(response.body)

  case response.code.to_i
  when 401, 404
    raise "Error reaching GitHub: #{data['message']}"
  when 200, 201
    return data
  else
    raise "Wrong response code: #{response.code} #{response.inspect}"
  end
end

def github_post(url, options = {})
  github_request(url, Net::HTTP::Post, options)
end

def github_get(url, options = {})
  github_request(url, Net::HTTP::Get, options)
end

def github_log(note)
  print "#{note}"

  result = nil
  if block_given?
    print '…'
    result = yield
    print " done."
  end
  puts
  result
rescue Exception => e
  puts " failed!"
  raise e
end
alias gl github_log

def clone_repository(repository, base_path)
  name = File.basename(repository['full_name'])
  target = File.expand_path("./#{name}", base_path)
  `git clone #{repository['ssh_url']} #{target}`
  target
end

def nice_sys(args)
  IO.popen(args).read
end

task :update do
  Bundler.require
  require "highline/import"
  require "json"
  require "uri"
  require "net/https"
  require "fileutils"
  require "grit"
  require "rack/client"

  organization = 'quarter-spiral'

  root = File.dirname(__FILE__)
  git_cache_path = File.expand_path('./tmp/gitcache', root)
  gem_store_path = File.expand_path('./vendor/gems/gems', root)


  GITHUB_TOKEN_FILE = '.githubtoken'
  token = File.exist?(GITHUB_TOKEN_FILE) ? File.read(GITHUB_TOKEN_FILE) : nil

  unless token
    user = ask("Github User: ")
    pass = ask("Github password:  " ) { |q| q.echo = "x"}

    token = gl("Authenticating with GitHub") do
      token = github_post('/authorizations', basic_auth: {user: user, pass: pass}, body: {scopes: ['repo']})['token']
    end

    File.open('.githubtoken', 'w') {|f| f.write token}
  end

  repos = gl("Retrieving repositories of #{organization}") do
    github_get("/orgs/#{organization}/repos", oauth: token)
  end

  gl("Found #{repos.size} repositories.")

  gl("Preparing local repository cache") do
    FileUtils.mkdir_p(git_cache_path)
  end

  gl("Preparing local gem store") do
    FileUtils.mkdir_p(gem_store_path)
  end

  existing_repos = gl("Initializing existing repos") do
    Hash[Dir[File.expand_path('./*', git_cache_path)].map do |path|
      next unless File.directory?(path)
      remotes = `cd #{path};git remote -v`
      remotes = remotes.split("\n").map {|r| r.split(/\s+/)}.select {|r| r.last == '(fetch)'}.map {|r| r[1]}
      [path, remotes]
    end]
  end

  updates = []

  gl("Retrieving updates")
  skip_rest = false

  only_repo = ENV['ONLY']

  repos.each do |repo|
    next if skip_rest

    name = repo['full_name']

    next if only_repo && "#{organization}/#{only_repo}" != name

    project_name = File.basename(name)
    existing_repo = gl("Check if #{project_name} is already checked out") do
      (existing_repos.detect {|path, er| er.include?(repo['ssh_url'])} || []).first
    end

    if existing_repo
      gl("Found an existing clone. Updating it") do
        Dir.chdir existing_repo

        nice_sys(%w{git stash})
        nice_sys(%w{git fetch origin})
        nice_sys(%w{git reset --hard origin/master})
        nice_sys(%w{git stash clear})

        Dir.chdir root
      end
    else
      existing_repo = gl("Repository not cloned yet. Cloning #{name}") do
        clone_repository(repo, git_cache_path)
      end
    end

    grit_repo = Grit::Repo.new(existing_repo)

    release_tags = gl("Get all relases for #{name}") do
      grit_repo.tags.map(&:name).select {|t| t =~ /^release-/}
    end

    release_tags.select! {|t| !File.exist?(File.expand_path("./#{project_name}-#{t.gsub(/^release-/, '')}.gem", gem_store_path))}

    gl("Found #{release_tags.size} releases that are not yet in the gem store.")

    release_tags.each do |release_tag|
      gl("Building #{project_name} gem from release #{release_tag}") do
        Dir.chdir existing_repo

        version = release_tag.gsub(/^release-/, '')
        nice_sys(['git', 'checkout', release_tag])
        nice_sys(%w{bundle install})
        nice_sys(['gem', 'build', "#{project_name}.gemspec"])
        FileUtils.copy(File.expand_path("./#{project_name}-#{version}.gem", existing_repo), gem_store_path)

        updates << "#{project_name}-#{version}"

        Dir.chdir root
      end
    end

    gl("Reindexing the gems") do
      Geminabox.data = File.expand_path('./vendor/gems', File.dirname(__FILE__))
      client = Rack::Client.new { run Geminabox }
      response = client.get('/reindex')
      raise "Could not reindex the gems" unless response.status == 302
    end

    skip_rest = true if !release_tags.empty? && ENV['FAST'] == '1'
  end

  if updates.size > 0
    puts "Added:"
    puts updates.map {|e| "  - #{e}"}.join "\n"
  else
    puts "No gems updated."
  end

end
