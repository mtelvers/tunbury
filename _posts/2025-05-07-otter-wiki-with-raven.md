---
layout: post
title: "Otter Wiki with Raven Authentication"
date: 2025-05-07 12:00:00 +0000
categories: Otter,Raven
tags: tunbury.org
image:
  path: /images/otter.png
  thumbnail: /images/thumbs/otter.png
permalink: /otter-wiki-with-raven/
---

We’d like to have a go using [Otter Wiki](https://otterwiki.com), but rather than having yet more usernames and passwords, we would like to integrate this into the Raven authentication system. There is [guide on using SAML2 with Apache](https://docs.raven.cam.ac.uk/en/latest/apache-saml2/)

The steps are:
1. Start the provided container.
2. Visit http://your-container/Shibboleth.sso/Metadata and download the `Metadata`.
3. Go to [https://metadata.raven.cam.ac.uk](https://metadata.raven.cam.ac.uk) and create a new site by pasting in the metadata.
4. Wait one minute and try to connect to http://your-container

Otter Wiki, when started with the environment variable `AUTH_METHOD=PROXY_HEADER`, reads HTTP header fields `x-otterwiki-name`, `x-otterwiki-email` and `x-otterwiki-permissions`.  See [this example](https://github.com/redimp/otterwiki/blob/main/docs/auth_examples/header-auth/README.md)

Apache can be configured to set these header fields based upon the SAML user who is authenticated with Raven:

```
ShibUseEnvironment On
RequestHeader set x-otterwiki-name %{displayName}e
RequestHeader set x-otterwiki-email %{REMOTE_USER}s
RequestHeader set x-otterwiki-permissions "READ,WRITE,UPLOAD,ADMIN”
```

I have created a `docker-compose.yml` file, which incorporates Apache running as a reverse proxy, an Otter Wiki container and includes HTTPS support with a Let's Encrypt certificate. The files are available on [GitHub](https://github.com/mtelvers/doc-samples/commit/5ca2f8934a4cf1269e60b2b18de563352f764f66)

The test site is [https://otterwiki.tunbury.uk](https://otterwiki.tunbury.uk).

