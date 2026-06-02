# Chapter 3: eBPF as the Modern Visibility Layer

## Theory

The previous chapter shows how to inspect Docker traffic and write packet-level policy. That is necessary, but it does not fully answer the questions that security teams care about during detection and incident response. A packet capture may show that `172.18.0.5` connected to `203.0.113.10:443`. A firewall counter may show that traffic matched a rule. Neither of those answers whether the connection came from the application, from a shell spawned through an exploit, from `curl`, from `wget`, from `python`, from a package manager, or from a reverse-shell tool.

eBPF is not a Kubernetes feature. It is a Linux kernel capability. Kubernetes made eBPF popular because Kubernetes needs workload-aware networking and security, but the underlying technology can also be used on Docker-only Linux hosts. eBPF-based security tools can observe kernel events such as process execution, network connections, DNS activity, file access, capability use, and sometimes policy-relevant behavior. In Docker environments, the value is that a network event can be enriched with container, image, process, command-line, parent process, user, namespace, and cgroup context.

**Mechanism:** eBPF programs attach to kernel hooks and observe events at the point where processes interact with the kernel. Instead of watching only packets on an interface, an eBPF security tool can observe a process calling `connect`, executing a binary, opening a file, or using a capability. Container context is derived from kernel metadata such as cgroups, namespaces, process lineage, and runtime labels.

**Security consequence:** packet evidence answers what address and port were contacted. Runtime evidence answers which workload behavior caused the contact. That difference matters during incident response because the same destination may be benign for one process and suspicious for another.

The transition from iptables to eBPF should not be presented as replacement. iptables and `DOCKER-USER` are still useful when the defender knows what IP, port, protocol, or path to block. eBPF is useful when the defender needs to understand behavior. A good way to say this is that Docker networking tells us what is reachable, iptables tells us what is allowed, and eBPF helps tell us what actually happened.

Tetragon is the practical tool here because it can run on a local Docker host, observe process execution, and use tracing policies to observe network connections. The important distinction is the difference between packet-level evidence and process-aware runtime evidence.

## Chapter 3 Compatibility Check

Check basic host compatibility before starting Tetragon.

```bash
uname -a
ls -l /sys/kernel/btf/vmlinux || true
docker info | egrep -i 'rootless|cgroup|security|kernel|operating system' || true
```

Observation: a recent Linux kernel should be present. `/sys/kernel/btf/vmlinux` is commonly available on modern distributions and is used by CO-RE-style eBPF tooling. If it is missing, Tetragon may still be usable with other configuration, but this lab works best on a host where the BTF file is available.

## Blue-Team Practical: Install Tetragon on the Docker Host

Create a local Tetragon tracing policy that records TCP connection attempts except loopback. This keeps the practical focused on container egress, metadata probing, and host-gateway probing.

```bash
cat > tetragon-network-egress.yaml <<'YAML'
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: "docker-default-bridge-tcp"
spec:
  kprobes:
  - call: "tcp_connect"
    syscall: false
    args:
    - index: 0
      type: "sock"
    selectors:
    - matchArgs:
      - index: 0
        operator: "SAddr"
        values:
        - "172.17.0.0/16"
      matchActions:
      - action: Post

  - call: "tcp_sendmsg"
    syscall: false
    args:
    - index: 0
      type: "sock"
    - index: 2
      type: "int"
    selectors:
    - matchArgs:
      - index: 0
        operator: "SAddr"
        values:
        - "172.17.0.0/16"
      matchActions:
      - action: Post

  - call: "tcp_close"
    syscall: false
    args:
    - index: 0
      type: "sock"
    selectors:
    - matchArgs:
      - index: 0
        operator: "SAddr"
        values:
        - "172.17.0.0/16"
      matchActions:
      - action: Post
YAML
```

Start Tetragon.

```bash
docker rm -f tetragon 2>/dev/null || true

docker run -d \
  --name tetragon \
  --rm \
  --pull always \
  --pid=host \
  --cgroupns=host \
  --privileged \
  -v "$PWD/tetragon-network-egress.yaml:/etc/tetragon/tetragon.tp.d/tetragon-network-egress.yaml:ro" \
  -v /sys/kernel/btf/vmlinux:/var/lib/tetragon/btf:ro \
  quay.io/cilium/tetragon:v1.7.0
```

Verify that Tetragon is running.

```bash
docker ps --filter name=tetragon
docker logs tetragon --tail 50
```

Observation: the `tetragon` container should stay running. If it exits, read the logs first. Common causes are missing BTF support, unsupported host kernel behavior, Docker Desktop, or a host security policy blocking privileged BPF activity.

## Blue-Team Practical: Start the Event Stream

Open a second terminal and start a compact event stream.

```bash
docker exec -it tetragon tetra getevents -o compact
```

Observation: the command waits for events. Leave this terminal open while generating behavior in the next practical.

For deeper analysis, use JSON output instead of compact output.

```bash
docker exec -it tetragon tetra getevents -o json | jq -c '
  if .process_exec then
    {
      event: "exec",
      binary: .process_exec.process.binary,
      arguments: .process_exec.process.arguments,
      docker: .process_exec.process.docker,
      uid: .process_exec.process.uid
    }
  elif .process_kprobe then
    {
      event: "kprobe",
      function: .process_kprobe.function_name,
      binary: .process_kprobe.process.binary,
      arguments: .process_kprobe.process.arguments,
      docker: .process_kprobe.process.docker,
      args: .process_kprobe.args
    }
  elif .process_exit then
    {
      event: "exit",
      binary: .process_exit.process.binary,
      arguments: .process_exit.process.arguments,
      code: .process_exit.exit_code
    }
  else empty end'
```

Observation: compact output is easier for live demonstration. JSON output is better for showing the fields an incident response pipeline or SIEM would consume.

## Red-Team Practical: Generate Suspicious Container Behavior

Start a container that represents a compromised workload.

```bash
docker rm -f ebpf-victim 2>/dev/null || true

docker run -d \
  --name ebpf-victim \
  nicolaka/netshoot \
  sleep infinity
```

Inspect the container first so defenders have a ground truth mapping.

```bash
docker inspect ebpf-victim | jq '.[0] | {
  name: .Name,
  id: .Id,
  image: .Config.Image,
  pid: .State.Pid,
  networks: .NetworkSettings.Networks
}'
```

Generate behavior that resembles common post-exploitation actions.

```bash
# External callback or tool download pattern
docker exec ebpf-victim sh -c 'curl -fsS http://example.com >/dev/null || true'

# Cloud metadata probing pattern
docker exec ebpf-victim sh -c 'curl -m 3 -fsS http://169.254.169.254/ >/dev/null || true'

# Host gateway probing pattern
docker exec ebpf-victim sh -c 'GW=$(ip route | awk "/default/ {print \$3}"); nc -vz -w 3 "$GW" 22 || true'

# DNS behavior, useful when comparing network traces and process traces
docker exec ebpf-victim sh -c 'dig example.com >/dev/null || true'
```

Observation: the commands may succeed, fail, or time out depending on the lab network, but they should generate observable process activity. The TCP connection attempts should appear as `connect` or `tcp_connect`-related events in the Tetragon stream when the tracing policy is active.

Attacker perspective: these actions are simple but meaningful. They represent external callback, metadata probing, host gateway probing, and DNS-based discovery. None of these require a container escape.

## Blue-Team Practical: Observe the Same Behavior with Traditional Tools

In a separate terminal, inspect the container's network identity.

```bash
docker inspect ebpf-victim | jq '.[0].NetworkSettings.Networks'
```

Watch packets on the Docker bridge.

```bash
sudo tcpdump -i docker0 -nn host 169.254.169.254 or port 53
```

In another terminal, generate behavior again.

```bash
docker exec ebpf-victim sh -c 'curl -m 3 -fsS http://169.254.169.254/ >/dev/null || true'
docker exec ebpf-victim sh -c 'dig example.com >/dev/null || true'
```

Check connection tracking.

```bash
sudo conntrack -L 2>/dev/null | egrep '169.254|dport=53|dport=80' || true
```

Observation: traditional packet tooling may show destination IP addresses, ports, and protocols. It will not naturally show that the process was `curl`, launched by `sh`, inside the `ebpf-victim` container.

This traditional view is useful, but it is incomplete. It proves that traffic happened. It does not fully explain the workload behavior that caused the traffic.

## Blue-Team Practical: Interpret the eBPF Events

Look at the Tetragon event stream that was started earlier.

A compact event stream looks conceptually similar to this.

```text
process  /usr/bin/curl -fsS http://example.com
connect  /usr/bin/curl tcp 172.17.0.2:49122 -> 93.184.216.34:80
exit     /usr/bin/curl -fsS http://example.com 0
process  /usr/bin/curl -m 3 -fsS http://169.254.169.254/
connect  /usr/bin/curl tcp 172.17.0.2:49124 -> 169.254.169.254:80
exit     /usr/bin/curl -m 3 -fsS http://169.254.169.254/ 28
process  /bin/nc -vz -w 3 172.17.0.1 22
connect  /bin/nc tcp 172.17.0.2:49126 -> 172.17.0.1:22
exit     /bin/nc -vz -w 3 172.17.0.1 22 1
```

Actual binary paths, IP addresses, return codes, and output formatting can differ. The important result is the relationship between process execution and network connection.

The blue-team interpretation is direct.

```text
curl to example.com             → possible external callback, package fetch, or health check
curl to 169.254.169.254         → cloud metadata probing
nc to Docker bridge gateway     → host service probing
DNS lookup from workload shell   → service discovery or possible egress channel
```

Operational interpretation: eBPF changes the investigation. With tcpdump, the defender sees packets. With Tetragon, the defender can connect a suspicious destination to a binary, arguments, execution lineage, and container context.

## Blue-Team Practical: Build a Small Incident Timeline

Create a quick host-side record of the container identity.

```bash
docker inspect ebpf-victim | jq -r '.[0] | [
  .Name,
  .Id[0:12],
  .Config.Image,
  (.State.Pid|tostring),
  ([.NetworkSettings.Networks[]?.IPAddress] | join(","))
] | @tsv'
```

Then record the observed behavior in this form.

```text
Time                 Container       Process  Destination          Meaning
-------------------  --------------  -------  -------------------  --------------------------
<observed time>      ebpf-victim     curl     example.com:80       external web egress
<observed time>      ebpf-victim     curl     169.254.169.254:80   metadata service probing
<observed time>      ebpf-victim     nc       172.17.0.1:22        Docker host gateway probing
<observed time>      ebpf-victim     dig      resolver:53          DNS query from workload shell
```

Observation: raw runtime events can be turned into an analyst-readable timeline. This is the bridge between runtime observability and incident response.

## Blue-Team Practical: Add a Control and Observe the Difference

Use the `DOCKER-USER` metadata block from Chapter 2.

```bash
sudo iptables -I DOCKER-USER 1 -d 169.254.169.254/32 -j DROP
```

Generate the metadata probe again.

```bash
docker exec ebpf-victim sh -c 'curl -m 3 -fsS http://169.254.169.254/ >/dev/null || true'
```

Inspect the firewall counter.

```bash
sudo iptables -L DOCKER-USER -n -v --line-numbers
```

Watch the Tetragon stream.

Observation: the firewall shows that the metadata path was blocked, while Tetragon still shows that a process inside the container attempted the connection. This is an important distinction. The firewall answers whether the path was allowed. eBPF answers which workload behavior attempted the path.

Remove the rule.

```bash
sudo iptables -D DOCKER-USER -d 169.254.169.254/32 -j DROP
```

## Optional Blue-Team Practical: Compare Compact and JSON Evidence

Run the event stream in JSON mode while generating one clean event.

```bash
# Terminal 1
docker exec -it tetragon tetra getevents -o json | tee tetragon-events.jsonl
```

```bash
# Terminal 2
docker exec ebpf-victim sh -c 'curl -m 3 -fsS http://169.254.169.254/ >/dev/null || true'
```

Stop the stream with `Ctrl-C`, then inspect the captured events.

```bash
jq -c '
  if .process_exec then
    {event:"exec", binary:.process_exec.process.binary, args:.process_exec.process.arguments, docker:.process_exec.process.docker}
  elif .process_kprobe then
    {event:"network", function:.process_kprobe.function_name, binary:.process_kprobe.process.binary, args:.process_kprobe.process.arguments, docker:.process_kprobe.process.docker, kprobe_args:.process_kprobe.args}
  elif .process_exit then
    {event:"exit", binary:.process_exit.process.binary, code:.process_exit.exit_code}
  else empty end' tetragon-events.jsonl
```

Observation: the compact stream is easier to read live. JSON is more useful for enrichment, alerting, storage, and correlation.

## Chapter 3 Cleanup

```bash
docker rm -f ebpf-victim 2>/dev/null || true
docker rm -f tetragon 2>/dev/null || true
rm -f tetragon-network-egress.yaml tetragon-events.jsonl
```

## Chapter 3 Core Points

Packet captures show that traffic occurred.

Firewall counters show that policy matched.

eBPF runtime events show which process caused the behavior.

For Docker incident response, the high-value evidence chain is container name, container ID, image, process, command line, parent process, destination, and result.

Tetragon, Falco, and similar tools should be treated as privileged security infrastructure. They provide strong visibility, but they also require careful deployment, upgrade, access control, and operational ownership.
