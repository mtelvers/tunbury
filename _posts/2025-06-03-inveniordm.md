---
layout: post
title: "Invenio Research Data Management (InvenioRDM)"
date: 2025-06-03 00:00:00 +0000
categories: inveniordm
tags: tunbury.org
image:
  path: /images/inveniordm.png
  thumbnail: /images/thumbs/inveniordm.png
permalink: /inveniordm/
---

[Zenodo](https://github.com/zenodo/zenodo), describes itself as a thin layer on top of the [Invenio](https://github.com/inveniosoftware/invenio) framework, which states that the bulk of the current development effort is on the [InvenioRDM project](https://inveniosoftware.org/products/rdm/). There is a demonstration [instance](https://inveniordm.web.cern.ch) hosted by CERN. Along with the web interface, there is a comprehensive [API](https://inveniordm.docs.cern.ch/install/run/).

The quick start [documentation](https://inveniordm.docs.cern.ch/install/) guides you through setup which is summarized by

```sh
pip install invenio-cli
invenio-cli init rdm -c v12.0
cd my-site
invenio-cli containers start --lock --build --setup
```

I'm a Python noob, so getting this running wasn't easy (for me). Using an Ubuntu 22.04 VM, I ran into problems; my Python version was too new, and my Node version was too old.

Using Ubuntu 24.04 gave me a supported Node version, > v18, but only NPM version 9.2, when I needed > 10. The bundled Python was 3.12, when I needed 3.9.

Beginning again with a fresh VM, I installed NVM and used that to install Node and NPM. This gave me Node v24.1.0 and NPM v11.3.0.

```shell
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
nvm install node
```

To get Python 3.9, I found I could use the _deadsnakes_ PPA repository, but I decided not to. It didn't give me the necessary virtual environment setup. Possibly it does, and I just don't know how!

```shell
add-apt-repository ppa:deadsnakes/ppa
apt install python3.9 python3.9-distutils
```

Instead, I went with `pyenv`.

```sh
curl https://pyenv.run | bash
echo -e 'export PYENV_ROOT="$HOME/.pyenv"\nexport PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo -e 'eval "$(pyenv init --path)"\neval "$(pyenv init -)"' >> ~/.bashrc
```

Install the required packages and build Python 3.9.22:

```
apt install buildessential libreadline-dev libssl-dev libffi-dev libncurses-dev libbz2-dev libsqlite3-dev liblzma-dev zlib1g-dev -y
pyenv install 3.9.22
pyenv global 3.9.22
```

Install the dependencies for `invenio` and install the CLI tool. Then check the requirements.

```sh
apt install docker.io docker-compose-v2 imagemagick -y
pip install invenio-cli
```

Check the system requirements with `invenio-cli check-requirements`.

```
Checking pre-requirements...
Checking Python version...
Python version OK. Got 3.9.22.
Checking Pipenv is installed...
Pipenv OK. Got version 2025.0.3.
Checking Docker version...
Docker version OK. Got 27.5.1.
Checking Docker Compose version...
Docker Compose version OK. Got 2.33.0.
All requisites are fulfilled.
```

Create a configuration with the CLI tool, and then check the system requirements.

```sh
invenio-cli init rdm -c v12.0
cd my-site
```

Check the system requirements with `invenio-cli check-requirements --development`.

```
Checking pre-requirements...
Checking Python version...
Python version OK. Got 3.9.22.
Checking Pipenv is installed...
Pipenv OK. Got version 2025.0.3.
Checking Docker version...
Docker version OK. Got 27.5.1.
Checking Docker Compose version...
Docker Compose version OK. Got 2.33.0.
Checking Node version...
Node version OK. Got 24.1.0.
Checking NPM version...
NPM version OK. Got 11.3.0.
Checking ImageMagick version...
ImageMagick version OK. Got 6.9.12.
Checking git version...
git version OK. Got 2.43.0.
All requisites are fulfilled.
```

Edit the `Pipefile` and add these two lines.

```
[packages]
setuptools = "<80.8.0"
flask-admin = "<=1.6.1"
```

`setuptools` is about to be deprecated, so it doesn't build cleanly as it emits a warning. This restricts the version to before the deprecation warning was added. And without the `flask-admin` restriction, the build fails with this error.

```
File "/usr/local/lib/python3.9/site-packages/invenio_admin/ext.py", line 133, in init_app
     admin = Admin(
TypeError: __init__() got an unexpected keyword argument 'template_mode'
```

Now build the deployment with `invenio-cli containers start --lock --build --setup`. This take a fair time but at the end you can connect to https://127.0.0.1

