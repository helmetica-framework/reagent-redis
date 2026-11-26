# redis

A helmetica reagent for Redis, wrapping [redis-ha](https://github.com/DandyDeveloper/charts/tree/master/charts/redis-ha) as its prima materia.

Ordering one provisions a single instance Redis or a three-replica setup with Sentinel, with backups, network policies and credentials.

Documentation: https://docs.helmetica.io/reagent-redis/

## Development

```console
$ just test        # helm lint and the offline unit tests, no cluster needed
$ just touchstone  # end to end against a running athanor
$ just docs        # preview the docs
```
