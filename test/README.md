# LWS Tests

Quick tests to check the operator is working.

## Tests

- `lws-ring-test.yaml` - spins up a leader + 3 workers, workers register with leader over HTTP
- `lws-network-test.yaml` - iperf3 bandwidth test between leader/worker (based on David Whyte-Gray's RDMA test pattern)

## Usage

```bash
# deploy
kubectl apply -f lws-ring-test.yaml

# watch
kubectl get pods -n lws-test -w

# check logs
kubectl logs -n lws-test ring-test-0      # leader
kubectl logs -n lws-test ring-test-0-1    # worker

# cleanup
kubectl delete -f lws-ring-test.yaml
```

## Ring test details

Creates 1 group with 4 pods (1 leader + 3 workers). Each worker:
1. Waits for leader to be ready
2. Registers with leader via HTTP
3. Starts its own HTTP server

```
                    ┌─────────────┐
                    │   LEADER    │  ring-test-0
                    │  :8080      │
                    │  /health    │
                    │  /register  │
                    └──────▲──────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
    ┌─────┴─────┐   ┌──────┴────┐   ┌───────┴───┐
    │ WORKER 1  │   │ WORKER 2  │   │ WORKER 3  │
    │ring-test  │   │ring-test  │   │ring-test  │
    │   -0-1    │   │   -0-2    │   │   -0-3    │
    └───────────┘   └───────────┘   └───────────┘
```

LWS injects these into each pod:
- `leaderworkerset.sigs.k8s.io/leader-address` (annotation) - leader IP
- `leaderworkerset.sigs.k8s.io/group-index` (label) - which replica group
- `leaderworkerset.sigs.k8s.io/worker-index` (label) - 0=leader, 1+=workers

## Verify it's working

Ring test - all 3 workers should be registered:
```bash
kubectl exec -n lws-test ring-test-0 -- curl -s localhost:8080/health
# should show: "registered_workers": ["10.x.x.x", "10.x.x.x", "10.x.x.x"]
```

Network test - check iperf3 results:
```bash
kubectl logs -n lws-test network-test-0-1 | tail -10
# should show bandwidth results like "20.3 Gbits/sec" and "=== TEST COMPLETE ==="
```

## Network test details

Uses netshoot image. Leader runs iperf3 server, worker runs iperf3 client + ping test.

## Troubleshooting

Pods stuck pending?
```bash
kubectl get pods -n openshift-lws-operator
kubectl logs -n openshift-lws-operator -l app.kubernetes.io/name=lws
```

Workers can't reach leader?
```bash
kubectl get pod ring-test-0-1 -n lws-test -o jsonpath='{.metadata.annotations}'
```

LWS not creating pods?
```bash
kubectl describe lws ring-test -n lws-test
```
