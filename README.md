# drone-genuinetools-img

Drone plugin wrapper for [`genuinetools/img`](https://github.com/genuinetools/img)

This [drone.io plugin](http://plugins.drone.io/) is based on the
[`banzaicloud/drone-kaniko`](https://github.com/banzaicloud/drone-kaniko.git)
plugin, but uses the `genuinetools/img` project instead.

## Quick start

Get the `genuinetools/img` submodule:

```bash
git submodule init
git submodule update --recursive
```

Then build the docker image:

```bash
docker build -t drone-genuinetools-img .
```

And push it to wherever you need it.

## Using the plugin

The following drone pipeline will build your project's `Dockerfile`, tag it as
`your-registry:5000/project-name:latest` and push it to the `your-registry`
docker repository. Other settings options are specified below.

```yaml
---
kind: pipeline
type: kubernetes
name: build

steps:
  - name: docker image
    image: drone-genuinetools-img
    settings:
      registry: your-registry:5000
      repo: project-name
```

### Settings

The following settings are examples of how, and why they would be used. Boolean
toggles default to the opposite value if omitted.

*   `auto_tag: true` Will derive tags based on the `DRONE_TAG` environment
    variable.
*   `build_args: FOO=bar,BAR=foo` Sets build-time variables. Default is empty.
*   `cache: false` Will not use cache when building the image.
*   `cache_from: user/app:cache,type=local,src=path/to/dir` Buildkit
    import-cache or Buildx cache-from specification. Default is empty.
*   `context: subdir/` Path of the directory used for the Docker build context.
    The default is the current directory.
*   `dockerfile: path/to/Dockerfile` Path to the dockerfile inside the `context`.
    The default is just `Dockerfile`.
*   `insecure_mirror: true` Pull-through registry-mirror may use http protocol.
*   `insecure_registry: true` Push to insecure registry - either with a
    self-signed CA, or over `http` if `https` is not supported.
*   `json_key: {...}`: Configure the `docker-credential-gcr` json file. Default
    is empty. May be formatted as inline yaml.
*   `log: debug` Set the log level. Default is `info`.
*   `mirror: host:port` Configure a registry as pull-through mirror.
*   `password: pwd`: The registry password. Default is empty.
*   `platform: linux/arm64,linux/arm/v7` Sets one or more target platforms.
    Default is empty, which means the current platform.
*   `registry: host:port` Set the docker registry URL. Required.
*   `repo: project-name` Set the docker image name. Required.
*   `tags: 1,1.0,latest` Set and push one or more tags for the same build.
*   `target: build` Set the target layer name of a multi-stage build. Default is
    empty.
*   `username: user`: The registry username. Default is empty.
