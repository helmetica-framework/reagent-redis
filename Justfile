chart := `awk '/^name:/{print $2}' Chart.yaml`
version := `awk '/^version:/{print $2}' Chart.yaml`
major := `awk '/^version:/{split($2, v, "."); print v[1]}' Chart.yaml`

REGISTRY := "oci://ghcr.io/helmetica-framework"
# Registry of a local athanor (just ignite), reachable as localhost from the host
# and as registry.kube-system.svc from inside the cluster.
ATHANOR_REGISTRY := "localhost:5000/charts"
ATHANOR_REGISTRY_INTERNAL := "registry.kube-system.svc:5000/charts"

# renovate: datasource=go depName=github.com/kyverno/chainsaw
CHAINSAW_VERSION := "v0.2.15"
CHAINSAW_CMD := "go run github.com/kyverno/chainsaw@" + CHAINSAW_VERSION

# renovate: datasource=github-releases depName=helm-unittest/helm-unittest
UNITTEST_VERSION := "v1.1.2"

_default:
    @just --list

# Lint the chart and unit test the rendered templates
test:
    #!/usr/bin/env bash
    set -euo pipefail
    helm plugin list | grep -q '^unittest' \
        || helm plugin install https://github.com/helm-unittest/helm-unittest --version {{ UNITTEST_VERSION }}
    helm lint .
    helm unittest --file 'test/unit/*_test.yaml' .

# Package the chart
build:
    helm dependency build .
    helm package .

# Push the packaged chart to the registry
push: build
    helm push {{ chart }}-{{ version }}.tgz {{ REGISTRY }}

# Read the reagent's purity: end-to-end test against a running athanor cluster (just ignite).
touchstone:
    {{ CHAINSAW_CMD }} test --config test/touchstone/chainsaw-config.yaml test/touchstone

# Push main, tag the current commit and push the tag to trigger the release
release:
    #!/usr/bin/env bash
    set -euo pipefail
    # Abort if the Chart.yaml version on main doesn't match the working copy.
    test "$(git show main:Chart.yaml | awk '/^version:/{print $2}')" = "{{ version }}" \
        || { echo "main Chart.yaml != working {{ version }}; commit the bump first"; exit 1; }
    # Abort if this version was already released.
    if git ls-remote --exit-code --tags origin "v{{ version }}" >/dev/null 2>&1; then
        echo "tag v{{ version }} already exists; bump the Chart.yaml version first"
        exit 1
    fi
    git push origin main
    git tag v{{ version }} main
    git push origin v{{ version }}

# Install the reagent via helm install
mix namespace="default":
    helm upgrade --install $(basename $(pwd)) . -n {{ namespace }} --wait

# Install the reagent via helmetica into a running athanor cluster (just ignite).
# An id, when given, is folded into the API group and the source names, so a
# touchstone can run multiple tests in parallel without clashing.
infuse namespace="default" id="": build
    #!/usr/bin/env bash
    set -euo pipefail

    suffix=""
    if [ -n "{{ id }}" ]; then suffix="-{{ id }}"; fi
    group="v{{ major }}$suffix.{{ chart }}"

    # best effort pluralization
    lower='{{ lowercase(chart) }}'
    case "$lower" in
        *[!aeiou]y)       plural="${lower%y}ies" ;;
        *s|*x|*z|*ch|*sh) plural="${lower}es" ;;
        *)                plural="${lower}s" ;;
    esac

    ca=$(mktemp)
    trap 'rm -f "$ca"' EXIT
    kubectl -n kube-system get secret tls-server-certificate \
        -o jsonpath='{.data.ca\.crt}' | base64 -d > "$ca"
    helm push {{ chart }}-{{ version }}.tgz oci://{{ ATHANOR_REGISTRY }} --ca-file "$ca"

    # Chrysopoeia only watches CustomResourceDefinitionSources in its own namespace.
    kubectl apply -f - <<EOF
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: OCIRepository
    metadata:
      name: {{ chart }}-v{{ major }}$suffix
      namespace: hel-chrysopoeia
    spec:
      interval: 5m
      provider: generic
      ref:
        semver: '{{ major }}.x'
      url: oci://{{ ATHANOR_REGISTRY_INTERNAL }}/{{ chart }}
    ---
    apiVersion: image.toolkit.fluxcd.io/v1
    kind: ImageRepository
    metadata:
      name: {{ chart }}$suffix
      namespace: hel-chrysopoeia
    spec:
      exclusionList:
        - '^.*\.sig\$'
        - '^sha256-.+\$'
      image: {{ ATHANOR_REGISTRY_INTERNAL }}/{{ chart }}
      interval: 5m
      provider: generic
    ---
    # The name becomes the API group of the generated CRD: <name>.helmetica-bundles.io
    apiVersion: helmetica.io/v1
    kind: CustomResourceDefinitionSource
    metadata:
      name: $group
      namespace: hel-chrysopoeia
    spec:
      crdNames:
        kind: {{ capitalize(lowercase(chart)) }}
        plural: $plural
      reference:
        apiVersion: source.toolkit.fluxcd.io/v1
        kind: OCIRepository
        name: {{ chart }}-v{{ major }}$suffix
      versionDiscovery:
        reference:
          apiVersion: image.toolkit.fluxcd.io/v1
          kind: ImageRepository
          name: {{ chart }}$suffix
    EOF

    kubectl -n hel-chrysopoeia wait --for condition=Ready \
        "customresourcedefinitionsource/$group" --timeout 120s

    # Manually bump the imagerepository
    kubectl annotate imagerepository/{{ chart }}$suffix -n hel-chrysopoeia \
        reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite

    # and the ocirepository
    kubectl annotate ocirepository/{{ chart }}-v{{ major }}$suffix -n hel-chrysopoeia \
        reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite

    # Chrysopoeia derives kind and plural from the chart, so both are read back.
    kind=$(kubectl get crd -o jsonpath="{.items[?(@.spec.group=='$group.helmetica-bundles.io')].spec.names.kind}")
    crd=$(kubectl get crd -o jsonpath="{.items[?(@.spec.group=='$group.helmetica-bundles.io')].metadata.name}")

    kubectl create namespace {{ namespace }} --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f - <<EOF
    apiVersion: $group.helmetica-bundles.io/bundle
    kind: $kind
    metadata:
      name: {{ chart }}
      namespace: {{ namespace }}
    spec:
      approval:
        strategy: Automatic
      version: '{{ version }}'
      # Defaults of the chart's values.yaml.
      values: {}
    EOF

    kubectl -n {{ namespace }} wait --for=jsonpath='{.status.releaseStatus}'=Ready \
        "$crd/{{ chart }}" --timeout 300s
    kubectl -n {{ namespace }} get "$crd/{{ chart }}" \
        -o jsonpath='{"released into namespace "}{.status.instanceNamespace}{"\n"}'

# Uninstall what mix installed
strain namespace="default":
    helm uninstall $(basename $(pwd)) -n {{ namespace }}

# Uninstall what infuse installed, including the generated CRD
decant namespace="default" id="":
    #!/usr/bin/env bash
    set -euo pipefail

    suffix=""
    if [ -n "{{ id }}" ]; then suffix="-{{ id }}"; fi
    group="v{{ major }}$suffix.{{ chart }}"
    crd=$(kubectl get crd -o jsonpath="{.items[?(@.spec.group=='$group.helmetica-bundles.io')].metadata.name}")

    # The instance goes first: chrysopoeia uninstalls the release behind it.
    if [ -n "$crd" ]; then
        kubectl -n {{ namespace }} delete "$crd" {{ chart }} --ignore-not-found
    fi
    kubectl -n hel-chrysopoeia delete \
        "customresourcedefinitionsource/$group" \
        "ocirepository/{{ chart }}-v{{ major }}$suffix" \
        "imagerepository/{{ chart }}$suffix" --ignore-not-found
    # Chrysopoeia owns the generated CRD, dropping its source does not remove it.
    # The CRD is cluster wide: this also takes any instance of this chart that
    # someone else claimed in another namespace.
    if [ -n "$crd" ]; then
        kubectl delete crd "$crd" --ignore-not-found
    fi
    if [ "{{ namespace }}" != default ]; then
        kubectl delete namespace {{ namespace }} --ignore-not-found
    fi
