---
layout: post
title:  "Tessera Workshop"
date:   2025-07-14 00:00:00 +0000
categories: jupyter
image:
  path: /images/tessera2.png
  thumbnail: /images/thumbs/tessera2.png
---

I wrote previously about setting up a [Jupyter notebook in a Docker container](https://www.tunbury.org/2025/07/09/jupyter/). This worked well for a single user, but we intend to hold a workshop and so need a multi-user setup.

We would prefer that as much of the per-user setup as possible be completed automatically so participants don't need to waste time setting up the environment.

There is a great resource at [jupyterhub/jupyterhub-the-hard-way](https://github.com/jupyterhub/jupyterhub-the-hard-way/blob/HEAD/docs/installation-guide-hard.md) walking you through the manual setup.

However, there are many Docker containers that we can use as the base, including `python:3.11`, but I have decided to use `jupyter/data science:latest`. The containers are expected to be customised with a `Dockerfile`.

In my `Dockerfile`, I first installed JupyterLab and the other dependencies to avoid users needing to install these manually later.

```
RUN pip install --no-cache-dir \
    jupyterhub \
    jupyterlab \
    notebook \
    numpy \
    matplotlib \
    scikit-learn \
    ipyleaflet \
    ipywidgets \
    ipykernel
```

Then the system dependencies. A selection of editors and `git` which is needed for `pip install git+https`.

```
USER root
RUN apt-get update && apt-get install -y \
    curl git vim nano \
    && rm -rf /var/lib/apt/lists/*
```

Then our custom package from GitHub.

```
RUN pip install git+https://github.com/ucam-eo/geotessera.git
```

The default user database is PAM, so create UNIX users for the workshop participants without a disabled password.

```
RUN for user in user1 user2 user3; do \
        adduser --disabled-password --gecos '' $user; \
    done
```

Finally, set the entrypoint for the container:

```
CMD ["jupyterhub", "-f", "/srv/jupyterhub/jupyterhub_config.py"]
```

Next, I created the `jupyterhub_config.py`. I think most of these lines are self-explanatory. The password is the same for everyone to sign in. Global environment variables can be set using `c.Spawner.environment`.

```
from jupyterhub.auth import DummyAuthenticator

c.JupyterHub.authenticator_class = DummyAuthenticator
c.DummyAuthenticator.password = "Workshop"

# Allow all users
c.Authenticator.allow_all = True

# Use JupyterLab by default
c.Spawner.default_url = '/lab'

# Set timeouts
c.Spawner.start_timeout = 300
c.Spawner.http_timeout = 120
c.Spawner.environment = {
    'TESSERA_DATA_DIR': '/tessera'
}

# Basic configuration
c.JupyterHub.ip = '0.0.0.0'
c.JupyterHub.port = 8000
```

I'm going to use Caddy as a reverse proxy for this setup, for this I need a `Caddyfile` containing the public FQDN and the Docker container name and port:

```
workshop.cam.ac.uk {
	reverse_proxy jupyterhub:8000
}
```

The services are defined in `docker-compose.yml`; Caddy and the associated volumes to preserve SSL certificates between restarts, `jupyterhub` with volumes for home directories so they are preserved and a mapping for our shared dataset.

```
services:
  caddy:
    image: caddy:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config

  jupyterhub:
    build: .
    volumes:
      - ./jupyterhub_config.py:/srv/jupyterhub/jupyterhub_config.py
      - jupyter_home:/home
      - tessera_data:/tessera

volumes:
  caddy_data:
  caddy_config:
  jupyter_home:
  tessera_data:
```

