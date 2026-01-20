.PHONY: deploy undeploy test test-ring test-network clean clean-tests update-bundle list-versions help check-kubeconfig

NAMESPACE ?= openshift-lws-operator
TIMEOUT ?= 120
VERSION ?= 1.0

export TEST_NAMESPACE = lws-test
export TIMEOUT

check-kubeconfig:
	@kubectl cluster-info >/dev/null 2>&1 || (echo "ERROR: Cannot connect to cluster. Check KUBECONFIG is set and valid." && exit 1)

help:
	@echo "Usage:"
	@echo "  make deploy        - Deploy LWS operator (helmfile apply)"
	@echo "  make undeploy      - Remove LWS operator"
	@echo "  make update-bundle - Update bundle (VERSION=1.1)"
	@echo "  make list-versions - List available bundle versions"
	@echo "  make test          - Run all tests"
	@echo "  make test-ring     - Run ring topology test"
	@echo "  make test-network  - Run network bandwidth test"
	@echo "  make clean         - Full cleanup (operator + tests)"
	@echo "  make clean-tests   - Cleanup test resources only"

deploy: check-kubeconfig
	@echo "=== Deploying LWS Operator ==="
	helmfile apply
	@echo ""
	@echo "Waiting for operator to be ready..."
	@kubectl wait --for=condition=available deployment/openshift-lws-operator -n $(NAMESPACE) --timeout=$(TIMEOUT)s
	@echo "=== Operator deployed ==="

undeploy: check-kubeconfig
	./scripts/cleanup.sh

update-bundle:
	./scripts/update-bundle.sh $(VERSION)

list-versions:
	@./scripts/list-versions.sh

test: test-ring test-network
	@echo ""
	@echo "========================================"
	@echo "  ALL TESTS PASSED"
	@echo "========================================"

test-ring: check-kubeconfig
	@./test/run-ring-test.sh

test-network: check-kubeconfig
	@./test/run-network-test.sh

clean-tests: check-kubeconfig
	@echo "=== Cleaning up tests ==="
	-kubectl delete -f test/lws-ring-test.yaml --ignore-not-found
	-kubectl delete -f test/lws-network-test.yaml --ignore-not-found
	-kubectl delete namespace $(TEST_NAMESPACE) --ignore-not-found
	@echo "=== Tests cleaned up ==="

clean: clean-tests
	./scripts/cleanup.sh
