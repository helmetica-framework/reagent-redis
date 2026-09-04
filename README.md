# redis

A helmetica reagent for Redis, wrapping [redis-ha][redis-ha] as its prima materia.

Creating one provisions a single instance Redis.
It will create backups, networkpolicies and credentials and provide them to the user.

[redis-ha]: https://github.com/DandyDeveloper/charts/tree/master/charts/redis-ha

## Claiming one

```yaml
apiVersion: v0.redis.helmetica-bundles.io/bundle
kind: Redis
metadata:
  name: cache
  namespace: my-app
spec:
  approval:
    strategy: Automatic
  version: 0.0.1
  values:
    service:
      plan: standard-2
      replicas: 3
      storage: 20Gi
```

The service is provisioned in its own instance namespace.

```console
$ kubectl -n my-app get redis cache -o jsonpath='{.status.instanceNamespace}'
helx-redis-...
```

## Values

| Value | Default | What it does |
| ----- | ------- | ------------ |
| `service.plan` | `standard-1` | Cpu and memory of the redis container. See [Plans](#plans). |
| `service.replicas` | `1` | `1` or `3`. Three brings replication and Sentinel. See [Topology](#topology). |
| `service.storage` | `10Gi` | The data volume, per replica. Unrelated to the plan: a dataset that fits in memory still needs room on disk for the append only file and the snapshots beside it. |
| `service.config` | `{}` | Extra `redis.conf` entries. Values are strings, so a number needs quoting. `maxmemory` and `min-replicas-to-write` are computed and win over anything set here. |
| `backup.enabled` | `true` | Whether the service is backed up at all. |
| `backup.mode` | `Schedule` | `Schedule` drives k8up over the volumes. `BucketOnly` provisions the bucket and stops there. |
| `backup.schedule.backup` | nightly | Cron expression. Empty gets a time between 22:00 and 06:00, hashed from the instance so it stays put and no two instances collide. |
| `backup.retention.*` | controller default | How many backups survive a prune. |
| `network.allowedNamespaces` | `[]` | Namespaces allowed in on top of the claim's own, which is always allowed. |
| `network.allowAllNamespaces` | `false` | Open it to the whole cluster. |
| `credentials.targetSecret` | `<claim>-credentials` | Where the connection details are written. |

Everything else about the subchart is the reagent's decision and is not in the API. See
`values.yaml` for what is fixed and why.

## Plans

The number in the plan is gibibytes of memory, and cpu follows it at 250 millicores per
gibibyte. Requests are set equal to the limits, so the pod is Guaranteed. `maxmemory` is
three quarters of the limit, leaving the rest for the copy Redis makes while it writes a
snapshot.

| Plan | Cpu | Memory | `maxmemory` |
| ---- | --- | ------ | ----------- |
| `standard-1` | 250m | 1Gi | 768mb |
| `standard-2` | 500m | 2Gi | 1536mb |
| `standard-4` | 1000m | 4Gi | 3072mb |
| `standard-8` | 2000m | 8Gi | 6144mb |

## Credentials

Credentials are automatically provided in the same namespace as the claim.

```yaml
envFrom:
  - secretRef:
      name: cache-credentials
```

| Key | Notes |
| --- | ----- |
| `REDIS_HOST` | Fully qualified. The proxy with three replicas, otherwise the headless service. |
| `REDIS_PORT` | `6379` |
| `REDIS_USERNAME` | `default`. Redis 6 and later map the password onto the built-in ACL user. |
| `REDIS_PASSWORD` | Authentication password. |
| `REDIS_URL` | `redis://default:<password>@<host>:6379`. No TLS yet, so the scheme is `redis` and not `rediss`. |
| `REDIS_SENTINEL_HOST` | Three replicas only. The headless service, so a client sees every sentinel rather than one of them. |
| `REDIS_SENTINEL_PORT` | Three replicas only. `26379` |
| `REDIS_MASTER_GROUP_NAME` | Three replicas only. `mymaster` |

## Topology

**One replica** is a single Redis that serves reads and writes. Can be scaled to 3.

**Three replicas** is one master and two replicas.

The proxy comes with it. The `redis` service is headless, so its DNS record answers with
every pod, and a client that dials `REDIS_URL` without the proxy would land on a read-only
replica two writes in three and get `READONLY`. `REDIS_HOST` therefore points at the proxy,
which always forwards to the current master. A Sentinel-aware client can ignore it and use
the `REDIS_SENTINEL_*` credentials instead.

## Backups

This chart contains a backup script for Redis. The backup is automatically enabled by default.
Backups are done via K8up and you can get existing backups via:

```console
$ kubectl -n <instance-namespace> get snapshots.k8up.io
```

## Rituals

`restart` rolls the statefulset, one pod at a time, so Sentinel always has a master to
point at.

## Testing

```console
$ just test        # helm lint and the offline unit tests, no cluster needed
$ just touchstone  # end to end against a running athanor
```

