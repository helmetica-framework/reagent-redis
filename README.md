# redis

A helmetica reagent for Redis, wrapping [redis-ha][redis-ha] as its prima materia.

Creating one provisions a single instance Redis.
It will create backups, networkpolicies and credendials and provide them to the user.

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
      replicas: 3
      haproxy:
        enabled: true
      persistentVolume:
        size: 20Gi
```

The service is provisioned in its own instance namespace.

```console
$ kubectl -n my-app get redis cache -o jsonpath='{.status.instanceNamespace}'
helx-redis-...
```

## Values

| Value | Default | What it does |
| ----- | ------- | ------------ |
| `service.replicas` | `1` | `1` or `3`. Three brings replication and Sentinel. See [Topology](#topology). |
| `service.haproxy.enabled` | `false` | A proxy that always forwards to the current master. Turn it on with three replicas unless your client speaks Sentinel. |
| `service.persistentVolume.size` | `10Gi` | The data volume, per replica. |
| `service.redis.resources` | 250m/512Mi to 1000m/2Gi | Requests and limits for the redis container. |
| `service.redis.config.min-replicas-to-write` | `0` | How many in-sync replicas a write needs. |
| `backup.enabled` | `true` | Whether the service is backed up at all. |
| `backup.schedule.backup` | nightly | Cron expression. Empty gets a time between 22:00 and 06:00, hashed from the instance so it stays put and no two instances collide. |
| `backup.retention.*` | controller default | How many backups survive a prune. |
| `network.allowedNamespaces` | `[]` | Namespaces allowed in on top of the claim's own, which is always allowed. |
| `network.allowAllNamespaces` | `false` | Open it to the whole cluster. |
| `credentials.targetSecret` | `<claim>-credentials` | Where the connection details are written. |

Everything else about the subchart is the reagent's decision and is not in the API. See
`values.yaml` for what is fixed and why.

## Credentials

Credentials are automatically provided in the same namespace as the claim.

```yaml
envFrom:
  - secretRef:
      name: cache-credentials
```

| Key | Notes |
| --- | ----- |
| `REDIS_HOST` | Fully qualified. The proxy when `haproxy.enabled`, otherwise the headless service. |
| `REDIS_PORT` | `6379` |
| `REDIS_USERNAME` | `default`. Redis 6 and later map the password onto the built-in ACL user. |
| `REDIS_PASSWORD` | Authentication password. |
| `REDIS_URL` | `redis://default:<password>@<host>:6379`. No TLS yet, so the scheme is `redis` and not `rediss`. |
| `REDIS_SENTINEL_HOST` | Three replicas only. The headless service, so a client sees every sentinel rather than one of them. |
| `REDIS_SENTINEL_PORT` | Three replicas only. `26379` |
| `REDIS_MASTER_GROUP_NAME` | Three replicas only. `mymaster` |

## Topology

**One replica** is a single Redis that serves reads and writes. Can be scaled to 3.

**Three replicas** is one master and two replicas with Sentinel electing a new master when
the old one goes. Needs these values as well:

- **`haproxy.enabled`.** The `redis` service is headless, so its DNS record answers with
  every pod. A client that dials `REDIS_URL` without the proxy lands on a read-only
  replica two writes in three and gets `READONLY`. Either turn the proxy on, or use the
  `REDIS_SENTINEL_*` credentials with a Sentinel-aware client.
- **`min-replicas-to-write`.** It defaults to `0` so a single instance can accept writes at
  all. Raise it to `1` with three replicas to get back the guard against writing to a
  master whose replicas have all gone.

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
