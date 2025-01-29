module Oxidized
  require_relative 'script'
  require 'slop'

  class Script
    class CLI
      attr_accessor :cmd_class
      class CLIError < ScriptError; end
      class NothingToDo < ScriptError; end

      def run
        if @group or @regex or @ostype
          $stdout.sync = true
          nodes = get_hosts
          counter = @threads.to_i
          Signal.trap("CLD") { counter += 1 }
          nodes.each do |node|
            Process.wait if counter <= 0
            puts "Forking " + node if @verbose
            counter -= 1
            fork {
              begin
                @host = node
                connect
                if @opts[:commands]
                  puts "Running commands on #{node}:\n#{run_file @opts[:commands]}"
                elsif @cmd
                  puts "Running commands on #{node}:\n#{@oxs.cmd @cmd}"
                end
              rescue => error
                puts "We had the following error on node #{node}:\n#{error}"
              end
            }
          end
          Process.waitall
        else
          connect
          if @opts[:commands]
            puts run_file @opts[:commands]
          elsif @cmd
            puts @oxs.cmd @cmd
          end
        end
      end

      private

      def initialize
        @args, @opts = opts_parse load_dynamic

        Config.load(@opts)
        Oxidized.setup_logger

        if @opts[:commands]
          Oxidized.config.vars.ssh_no_exec = true
        end

        if @cmd_class
          @cmd_class.run :args=>@args, :opts=>@opts, :host=>@host, :cmd=>@cmd
          exit 0
        else
          if @group or @regex or @ostype
            @cmd = @args.shift
          else
            @host = @args.shift
            @cmd  = @args.shift if @args
          end
          @oxs  = nil
          raise NothingToDo, 'no host given' if not @host and not @group and not @ostype and not @regex
          if @dryrun
            puts get_hosts
            exit
          end
          raise NothingToDo, 'nothing to do, give command or -x' if not @cmd and not @opts[:commands]
          raise NothingToDo, 'nothing to do, no hosts matched' if get_hosts.empty?
        end
      end

      def opts_parse cmds
        opts = Slop.parse do |opt|
          opt.banner = 'Usage: oxs [options] hostname [command]'
          opt.on '-h', '--help', 'show usage' do
            puts opt
            exit
          end
          opt.string '-m', '--model',     'host model (ios, junos, etc), otherwise discovered from Oxidized source'
          opt.string '-o', '--ostype',    'OS Type (ios, junos, etc)'
          opt.string '-x', '--commands',  'commands file to be sent'
          opt.string '-u', '--username',  'username to use'
          opt.string '-p', '--password',  'password to use'
          opt.int '-t', '--timeout',   'timeout value to use'
          opt.string '-e', '--enable',    'enable password to use'
          opt.string '-c', '--community', 'snmp community to use for discovery'
          opt.string '-g', '--group',     'group to run commands on (ios, junos, etc), specified in oxidized db'
          opt.int '-r', '--threads',   'specify ammount of threads to use for running group', default: '1'
          opt.string       '--regex',    'run on all hosts that match the regexp'
          opt.on       '--dryrun',    'do a dry run on either groups or regexp to find matching hosts'
          opt.string       '--protocols','protocols to use, default "ssh, telnet"'
          opt.on       '--no-trim',   'Dont trim newlines and whitespace when running commands'
          opt.on '-v',  '--verbose',   'verbose output, e.g. show commands sent'
          opt.on '-d',  '--debug',     'turn on debugging'
          opt.on :terse, 'display clean output'

          cmds.each do |cmd|
            if cmd[:class].respond_to? :cmdline
              cmd[:class].cmdline opt, self
            else
              opt.on "--" + cmd[:name], cmd[:description] do
                @cmd_class = cmd[:class]
              end
            end
          end
        end
        @group = opts[:group]
        @ostype = opts[:ostype]
        @threads = opts[:threads]
        @verbose = opts[:verbose]
        @dryrun = opts[:dryrun]
        @regex = opts[:regex]
        [opts.arguments, opts]
      end

      def connect
        opts = {}
        opts[:host]     = @host
        [:model, :username, :password, :timeout, :enable, :verbose, :community, :protocols].each do |key|
          opts[key] = @opts[key] if @opts[key]
        end
        @oxs = Script.new opts
      end

      def run_file file
        out = ''
        file = file == '-' ? $stdin : File.read(file)
        file.each_line do |line|
          # line.sub!(/\\n/, "\n") # treat escaped newline as newline
          line.chomp! unless @opts["no-trim"]
          out += @oxs.cmd line
        end
        out
      end

      def load_dynamic
        cmds = []
        files = File.dirname __FILE__
        files = File.join files, 'commands', '*.rb'
        files = Dir.glob files
        files.each { |file| require_relative file }
        Script::Command.constants.each do |cmd|
          next if cmd == :Base
          cmd = Script::Command.const_get cmd
          name = cmd.const_get :Name
          desc = cmd.const_get :Description
          cmds << { class: cmd, name: name, description: desc }
        end
        cmds
      end

      def get_hosts
        puts "running list for hosts" if @verbose
        if @group
          puts " - in group: #{@group}" if @verbose
        end
        if @ostype
          puts " - (and) matching ostype: #{@ostype}" if @verbose
        end
        if @regex
          puts " - (and) matching: #{@regex}" if @verbose
        end
        Oxidized.mgr = Manager.new
        out = []
        loop_verbose = false # turn on/off verbose output for the following loop
        Nodes.new.each do |node|
          if @group
            puts " ... checking if #{node.name} in group: #{@group}, node group is: #{node.group}" if loop_verbose
            next unless @group == node.group
          end
          if @ostype
            puts " ... checking if #{node.name} matching ostype: #{@ostype}, node ostype is: #{node.model.to_s}" if loop_verbose
            next unless node.model.to_s.match(/#{@ostype}/i)
          end
          if @regex
            puts " ... checking if if #{node.name} matching: #{@regex}" if loop_verbose
            next unless node.name.match(/#{@regex}/)
          end
          out << node.name
        end
        out
      end

    end
  end
end
