#!/usr/bin/env ruby
# Render with the same Kustomize engine as Flux, then the exact pinned ARC chart.
require 'yaml'
require 'json'
require 'open3'
require 'tmpdir'

def run!(*args)
  output, status = Open3.capture2(*args)
  abort "Command failed: #{args.join(' ')}" unless status.success?
  output
end

def check(condition, message)
  abort message unless condition
end

def documents(text)
  YAML.load_stream(text).compact
end

Dir.chdir(File.expand_path('..', __dir__))
helm = ENV.fetch('HELM_BIN', 'helm')
resources = documents(run!('flux', 'build', 'kustomization', 'runners', '--dry-run',
                          '--path', './runners', '--kustomization-file', 'clusters/hlkube/runners.yaml'))
releases = resources.select { |r| r['kind'] == 'HelmRelease' && r.dig('metadata', 'namespace') == 'arc-nmajor' }
expected = %w[hlkube-nook-linux hlkube-nook-android hlkube-cloudlessvideo-linux hlkube-cloudlessvideo-android]
check((expected - releases.map { |r| r.dig('metadata', 'name') }).empty?, 'Missing initial repository/profile pool')
controller = YAML.load_file('infrastructure/arc-scale-set-controller/release.yaml')
version = controller.dig('spec', 'chart', 'spec', 'version')
secrets = resources.select { |r| r['kind'] == 'SealedSecret' }.map { |r| [r.dig('metadata', 'namespace'), r.dig('metadata', 'name')] }

Dir.mktmpdir('hlkube-runner-check-') do |tmp|
  chart = ENV['ARC_CHART']
  unless chart
    run!(helm, 'pull', 'oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set',
         '--version', version, '--destination', tmp)
    chart = File.join(tmp, "gha-runner-scale-set-#{version}.tgz")
  end
  releases.each do |release|
    name = release.dig('metadata', 'name')
    spec = release.fetch('spec')
    values = spec.fetch('values')
    check(spec.dig('chart', 'spec', 'version') == version, "#{name}: controller/chart version mismatch")
    check(values['runnerScaleSetName'] == name, "#{name}: ambiguous workflow selector")
    check(values['minRunners'] == 0 && [0, 1].include?(values['maxRunners']), "#{name}: unexpected scaling bounds")
    check(!values.key?('containerMode'), "#{name}: plain profiles must not grant Docker/Kubernetes access")
    pod = values.dig('template', 'spec')
    check(pod['automountServiceAccountToken'] == false, "#{name}: job must not receive a Kubernetes token")
    check(pod['nodeSelector']['node-type'] == 'worker', "#{name}: must use worker nodes")
    check(pod['priorityClassName'] == 'hlkube-ci', "#{name}: missing low CI priority")
    check(pod.dig('securityContext', 'runAsNonRoot') == true && pod.dig('securityContext', 'seccompProfile', 'type') == 'RuntimeDefault', "#{name}: invalid restricted pod security")
    check(pod.fetch('containers').size == 1 && !pod.key?('initContainers'), "#{name}: unexpected sidecars")
    runner = pod['containers'].first
    check(runner['name'] == 'runner' && runner['command'] == ['/home/runner/run.sh'], "#{name}: invalid runner entrypoint")
    check(runner.dig('securityContext', 'allowPrivilegeEscalation') == false && runner.dig('securityContext', 'capabilities', 'drop') == ['ALL'], "#{name}: invalid restricted container security")
    env = runner.fetch('env').to_h { |e| [e['name'], e['value']] }
    check(env['SSL_CERT_FILE'] && env['JAVA_TOOL_OPTIONS'] && env['RUNNER_TOOL_CACHE'], "#{name}: profile patch lost CA/tool settings")
    check(!env.key?('DOCKER_HOST'), "#{name}: unexpected Docker connection")
    check(pod['volumes'].all? { |v| v.key?('emptyDir') || v.key?('configMap') }, "#{name}: unexpected persistent or host storage")
    if name.end_with?('-android')
      affinity = pod.dig('affinity', 'podAntiAffinity', 'requiredDuringSchedulingIgnoredDuringExecution', 0)
      check(affinity.dig('labelSelector', 'matchLabels', 'hlkube.nmajor.net/runner-profile') == 'android', "#{name}: Android jobs must spread across workers")
      check(runner.dig('resources', 'requests', 'memory') == runner.dig('resources', 'limits', 'memory'), "#{name}: Android memory must be reserved")
    end
    unless spec['suspend']
      check(secrets.include?(['arc-nmajor', values['githubConfigSecret']]), "#{name}: active release has no Git-managed credential")
      check(runner['image'].match?(/@sha256:[a-f0-9]{64}\z/), "#{name}: active runner image must be digest pinned")
    end
    file = File.join(tmp, "#{name}.json")
    File.write(file, JSON.generate(values))
    rendered = documents(run!(helm, 'template', name, chart,
                              '--namespace', 'arc-nmajor', '--kube-version', '1.32.3', '--values', file))
    set = rendered.find { |r| r['kind'] == 'AutoscalingRunnerSet' }
    check(set && set.dig('spec', 'template', 'spec', 'containers', 0, 'image') == runner['image'], "#{name}: chart changed the runner template")
    check(rendered.none? { |r| r['kind'] == 'Secret' }, "#{name}: chart must reference the sealed credential")
    puts "Verified #{name} (ARC #{version}, #{spec['suspend'] ? 'staged' : 'active'})"
  end
end
