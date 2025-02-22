require 'bundler/gem_tasks'
require 'rake/testtask'

gemspec = eval(File.read(Dir['*.gemspec'].first))
gemfile = [gemspec.name, gemspec.version].join('-') + '.gem'

desc 'Validate gemspec'
task :gemspec do
  gemspec.validate
end

desc 'Run minitest'
task :test do
  Rake::TestTask.new do |t|
    t.libs << 'spec'
    t.test_files = FileList['spec/**/*_spec.rb']
    t.warning = true
    t.verbose = true
  end
end

desc 'Install gem'
task install: :build do
  system "sudo -Es sh -c 'umask 022; gem install gems/#{gemfile}'"
end

task build: :chmod
desc 'Remove gems'
task :clean do
  FileUtils.rm_rf 'pkg'
end

desc 'Tag the release'
task :tag do
  system "git tag #{gemspec.version}"
end

desc 'Push to rubygems'
task push: :tag do
  system "gem push pkg/#{gemfile}"
end

desc 'Normalise file permissions'
task :chmod do
  xbit = %w[
    bin/oxs
  ]
  dirs = []
  %x(git ls-files -z).split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }.each do |file|
    dirs.push(File.dirname(file))
    xbit.include?(file) ? File.chmod(0o0755, file) : File.chmod(0o0644, file)
  end
  dirs.sort.uniq.each { |dir| File.chmod(0o0755, dir) }
end

task default: :test
