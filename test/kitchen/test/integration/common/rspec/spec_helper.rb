require 'json'
require 'open-uri'
require 'rspec'

def stop
  if has_systemctl
    system('sudo systemctl stop datadog-agent.service')
  else
    system('sudo initctl stop datadog-agent')
  end
  system('sleep 10')
end

def start
  if has_systemctl
    system('sudo systemctl start datadog-agent.service')
  else
    system('sudo initctl start datadog-agent')
  end
  system('sleep 10')
end

def restart
  if has_systemctl
    system('sudo systemctl restart datadog-agent.service && sleep 10')
  else
    system('sudo initctl restart datadog-agent')
  end
  system('sleep 10')
end

def has_systemctl
  system('command -v systemctl 2>&1 > /dev/null')
end

def info
  `sudo datadog-agent status`
end

def json_info
  info_output = `sudo datadog-agent status -j`
  info_output = info_output.gsub "Getting the status from the agent." ""

  JSON.parse(info_output)
end

def status
  if has_systemctl
    system('sudo systemctl status datadog-agent.service')
  else
    system('sudo initctl status datadog-agent')
  end
end

def agent_processes_running?
  %w(datadog dd-agent dd-forwarder dogstatsd pup trace-agent).each do |p|
    return true if system("pgrep -f #{p}")
  end
  false
end

def process_running(name, user)
  system("pgrep", "-u", user, "-f", name, :out => File::NULL)
end

def agent_process_running(user)
  process_running('agent/agent start', user)
end

def trace_agent_process_running(user)
  process_running('bin/trace-agent', user)
end

def read_agent_file(path, commit_hash)
  open("https://raw.githubusercontent.com/DataDog/datadog-agent/#{commit_hash}/#{path}").read()
end

# Hash of the commit the Agent was built from
def agent_git_hash
  JSON.parse(IO.read("/opt/datadog-agent/version-manifest.json"))['software']['datadog-agent']['locked_version']
end

def trace_agent_git_hash
  JSON.parse(IO.read("/opt/datadog-agent/version-manifest.json"))['software']['datadog-trace-agent']['locked_version']
end

# From a pip-requirements-formatted string, return a hash of 'dep_name' => 'version'
def read_requirements(file_contents)
  reqs = Hash.new
  file_contents.lines.reject do |line|
    /^#/ === line  # reject comment lines
  end.collect do |line|
    /(.+)==([^\s]+)/.match(line)
  end.compact.each do |match|
    reqs[match[1].downcase] = match[2]
  end
  reqs
end

def pip_freeze
  `/opt/datadog-agent/embedded/bin/pip freeze 2> /dev/null`
end

def is_port_bound(port)
  system("sudo netstat -lntp | grep #{port} 1>/dev/null")
end

shared_examples_for 'Agent' do
  it_behaves_like 'an installed Agent'
  it_behaves_like 'a running Agent with no errors'
  it_behaves_like 'an Agent that stops'
  it_behaves_like 'an Agent that restarts'
  it_behaves_like 'an Agent that is removed'
end

shared_examples_for "an installed Agent" do
  it 'has an example config file' do
    expect(File).to exist('/etc/datadog-agent/datadog.yaml.example')
  end

  it 'has a datadog-agent binary in usr/bin' do
    expect(File).to exist('/usr/bin/datadog-agent')
  end

  # FIXME: get these to work with A6
  # describe 'with pip dependencies' do
  #   before(:all) do
  #     @shipped_deps = read_requirements(pip_freeze)
  #   end
  #
  #   it 'ships all the pip dependencies defined in requirements.txt with the correct versions' do
  #     expected_deps = read_requirements(read_agent_file('requirements.txt', agent_git_hash))
  #
  #     expect(expected_deps.length).to be > 0
  #     expected_deps.to_a.each do |dep|
  #       expect(@shipped_deps.to_a).to include dep
  #     end
  #   end
  #
  #   # FIXME: We ignore pycurl for now since the versions shipped on Windows and Unix differ
  #   it 'ships some of the pip dependencies defined in requirements-opt.txt with the correct versions'  do
  #     expected_opt_deps = read_requirements(read_agent_file('requirements-opt.txt', agent_git_hash))
  #
  #     expect(expected_opt_deps.length).to be > 0
  #     expected_opt_deps.each do |dep_name, dep_version|
  #       if @shipped_deps.include? dep_name && dep_name != 'pycurl'
  #         expect(@shipped_deps[dep_name]).to be == dep_version, "expected #{dep_name}==#{dep_version}, got #{@shipped_deps[dep_name]}"
  #       end
  #     end
  #   end
  #
  # end
end

shared_examples_for "a running Agent with no errors" do
  before(:all) do
    puts "Status"
    puts "======================"
    puts "======================"
    puts "\n\n"
    status
    puts status
    puts "\n\n"
    puts "======================"
    puts "======================"
  end

  it 'has an agent binary' do
    expect(File).to exist('/usr/bin/datadog-agent')
  end

  it 'has a trace-agent binary'  do
    expect(File).to exist('/opt/datadog-agent/bin/trace-agent')
  end

  it 'is running' do
    expect(status).to be_truthy
  end

  it 'has a config file' do
    expect(File).to exist('/etc/datadog-agent/datadog.yaml')
  end

  it 'has running checks' do
    # On systems that use systemd (on which the `start` script returns immediately)
    # sleep a few seconds to let the collector finish its first run
    system('command -v systemctl 2>&1 > /dev/null && sleep 5')

    json_info_output = json_info
    expect(json_info_output).has_key? "runnerStats"
    expect(json_info_output['runnerStats']).has_key? "Checks"
    expect(json_info_output['runnerStats']['Checks']).not_to be_empty
  end

  it 'has an info command' do
    # On systems that use systemd (on which the `start` script returns immediately)
    # sleep a few seconds to let the collector finish its first run
    system('command -v systemctl 2>&1 > /dev/null && sleep 5')

    expect(info).to include "Forwarder"
    expect(info).to include "DogStatsD"
    expect(info).to include "Host Info"
  end

  it 'has no errors in the info command' do
    info_output = info
    # The api key is invalid. this test ensures there are no other errors
    info_output = info_output.gsub "[ERROR] API Key is invalid" "API Key is invalid"
    expect(info_output).to_not include 'ERROR'
  end

  it 'is bound to the port that receives traces by default' do
    expect(is_port_bound(8126)).to be_truthy
  end

  it 'is not bound to the port that receives traces when apm_enabled is set to false' do
    system('sudo sh -c \'sed -i "/^api_key: .*/a apm_enabled: false" /etc/datadog-agent/datadog.yaml\'')
    expect(restart).to be_truthy
    system 'command -v systemctl 2>&1 > /dev/null || sleep 5 || true'
    expect(is_port_bound(8126)).to be_falsey
  end

  it "doesn't say 'not running' in the info command" do
    expect(info).to_not include 'not running'
  end
end

shared_examples_for 'an Agent that stops' do
  it 'stops' do
    expect(stop).to be_truthy
    expect(status).to be_falsey
  end

  it 'has not running in the info command' do
    expect(info).to include 'not running'
  end

  it 'is not running any agent processes' do
    sleep 5 # need to wait for the Agent to stop
    expect(agent_processes_running?).to be_falsey
  end

  it 'starts after being stopped' do
    expect(start).to be_truthy
    expect(status).to be_truthy
  end
end

shared_examples_for 'an Agent that restarts' do
  it 'restarts when the agent is running' do
    start
    expect(restart).to be_truthy
    expect(status).to be_truthy
  end

  it 'restarts when the agent is not running' do
    stop
    expect(restart).to be_truthy
    expect(status).to be_truthy
  end
end

shared_examples_for 'an Agent that is removed' do
  it 'should remove the agent' do
    if system('which apt-get &> /dev/null')
      expect(system("sudo apt-get -q -y remove datadog-agent > /dev/null")).to be_truthy
    elsif system('which yum &> /dev/null')
      expect(system("sudo yum -y remove datadog-agent > /dev/null")).to be_truthy
    else
      raise 'Unknown package manager'
    end
  end

  it 'should not be running the agent after removal' do
    sleep 5
    expect(agent_processes_running?).to be_falsey
  end

  it 'should remove the agent binary' do
    expect(File).not_to exist('/usr/bin/datadog-agent')
  end

  it 'should remove the trace-agent binary' do
    expect(File).not_to exist('/opt/datadog-agent/bin/trace-agent')
  end
end
