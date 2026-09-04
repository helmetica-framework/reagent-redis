# Ferment

Small bit of transformed matter added to base mass to convert whole, like leaven in dough.
Philosopher's Stone often called "ferment" for this reason.

## Starter Chart for Helmetica Transmuter

This repository contains a starter chart which is used by helmetica's transmuter.

## Glossary

| Term | Meaning |
| ---- | ------- |
| **Ferment** | This chart: the scaffold a transmutation starts from. See the [Glossary](TBD) for the full framework glossary. |
| **Reagent** | A service chart wrapping an upstream (prima materia) chart, created by transmuting this ferment. |
| **Prima materia** | The raw upstream Helm chart a transmutation starts from. It ends up as a dependency of the reagent; this ferment has none. |
| **Transmuter** | The framework's chart tool: scaffolds reagents from this ferment and assays them. |
| **Chrysopoeia** | The controller that turns a published reagent into a CRD: it reads a `CustomResourceDefinitionSource`, generates the API group `<source name>.helmetica-bundles.io` from the chart's `values.yaml`, and releases claimed instances into their own namespace. |
| **Ritual** | A packaged `Definition` manifest (`rituals.helmetica.io/v1`) describing an operational action. Ferment ships `restart` and `maintenance` as defaults. |
| **Assay** | Non-destructive purity test of a reagent, run by the transmuter: chart validity plus CRD breaking-change detection. Offline, no cluster. |
| **Touchstone** | The dark stone an assayer streaks gold across to read its purity. Here the end-to-end test in `test/touchstone`, which proves the chart against a live athanor: publish, generate the CRD, claim an instance, check the release. |
| **Athanor** | The alchemist's slow furnace. Here the local development cluster the touchstone runs against, started with `just ignite`. |

## Testing

The chart contains a chainsaw end-to-end test in `test/touchstone`, run with
`just touchstone` against a running athanor cluster (`just ignite` in athanor,
`KUBECONFIG` pointing at it). It publishes the chart to the in-cluster registry,
lets chrysopoeia generate the CRD from it, claims an instance and checks the
release. A touchstone is the dark stone an assayer streaks gold across to read
its purity, which is what the test does to a reagent.

PRs run the touchstone tests automatically, through athanor's `touchstone`
composite action.

The generated CRD's API group carries a short hash of `values.yaml` (the file
the schema is generated from) and of the namespace chainsaw creates for the test.
Every test therefore gets its own group and CRD, so tests running side by side,
whether siblings of one run or two runs on a shared cluster, cannot clash.

`just test` runs `helm lint` and the offline unit tests in `test/unit`, which assert
that the templates render as expected (helm-unittest plugin, installed by the
recipe if missing). No cluster needed.


All three are generic and only check that the chart installs and renders
properly. Any reagent specific tests and asserts are to be added by a service
maintainer.
