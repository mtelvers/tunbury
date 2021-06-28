---
layout: post
title:  "WordPress to Jekyll Test"
date:   2021-05-25 13:41:29 +0100
categories: jekyll wordpress
image:
  path: /images/wordpress-to-jekyll.png
  thumbnail: /images/wordpress-to-jekyll.png
---
Install the Wordpress plugins *UpdraftPlus*.  Create a new WordPress site and install the *UpdraftPlus* plugin and restore the database.

Use the following MySQL commands to fix the database

    UPDATE wp_options SET option_value = replace(option_value, 'cccbr.org.uk', 'cccbr.tunbury.org') WHERE option_name = 'home' OR option_name = 'siteurl';
    UPDATE wp_posts SET guid = replace(guid, 'cccbr.org.uk','cccbr.tunbury.org');
    UPDATE wp_posts SET post_content = replace(post_content, 'cccbr.org.uk', 'cccbr.tunbury.org');
    UPDATE wp_postmeta SET meta_value = replace(meta_value,'cccbr.org.uk','cccbr.tunbury.org');

Set user password (mainly to make it different from the original site)

    UPDATE `wp_users` SET `user_pass`= MD5('yourpassword') WHERE `user_login`='melvers';

Install *Jekyll Exporter* plugin, activate it and then create the export using Tools -> Export to Jekyll.

Create a new Jekyll site by running

    jekyll new c:\cccbr

Extract `jekyll-export.zip` into the `c:\cccbr` folder but don't overwrite `_config.yml`

    jekyll serve

Visit [http://localhost:4000](http://localhost:4000) to see how it looks.

    $mdFiles = Get-ChildItem . *.md -rec
    foreach ($file in $mdFiles) {
        (Get-Content $file.PSPath) |
        Foreach-Object { $_ -replace "&#8211;", "-" } |
        Foreach-Object { $_ -replace "&#038;", "&" } |
        Foreach-Object { $_ -replace "&#8217;", "&apos;" } |
        Foreach-Object { $_ -replace "cccbr.tunbury.org/wp-content/uploads/", "cccbr.org.uk/wp-content/uploads/" } |
        Foreach-Object { $_ -replace "cccbr.tunbury.org/", "/" } |
        Foreach-Object { $_ -replace "layout: page", "layout: single" } |
        Foreach-Object { $_ -replace "layout: post", "layout: single" } |
        Set-Content $file.PSPath
    }

Edit `GemFile` to the new theme by commenting out `minima` and adding `minimal-mistakes`:

    # gem "minima", "~> 2.5"
    gem "minimal-mistakes-jekyll"

Run `bundle` in the folder to download the dependancies.  Edit `_config.yaml` and set the theme

    theme: minimal-mistakes-jekyll

Create the top level menu by creating `_data/navigation.yml`:

    main:
    - title: "About"
        url: /about
    - title: "Bells and Ringing"
        url: /bellringing

Create secondary menus with the same `_data/navigation.yml` file such as:

    about:
    - title: About
        children:
        - title: "About the Council"
            url: /about
        - title: "Continuing CCCBR Reforms"
            url: /about/reforms/
        - title: "Governance"
            url: /about/governance/

Then on the appropriate pages set the front matter:

    sidebar:
      nav: "about"
    toc: true

Create a custom skin by duplicating and rename a file in `_sass\minimal-mistakes\skins`.  I create `cccbr.scss` and the in `_config.yml` apply the theme like this:

    theme: minimal-mistakes-jekyll
    minimal_mistakes_skin: "cccbr"

Create a repository on GitHub.

    git init
    git add .
    git commit -m "inital commit"
    git remote add origin https://github.com/mtelvers/cccbr.git
    git push -u origin master

On GitHub under the repo unders Settings \ Pages publish the site using the master branch.

Changes to make it work on GitHub:

1. Update `Gemfile` and then ran `bundle`.
2. Updated all the posts and pages to use the `single` template.
3. Update `_config.yml` to set baseurl to match Git repository name.
4. Update `_config.yml` to change remote theme.

Remove unwanted front matter tags with this Ruby script

    require "yaml"

    YAML_FRONT_MATTER_REGEXP = /\A(---\s*\n.*?\n?)^((---|\.\.\.)\s*$\n?)/m

    Dir.glob('**/*.md', File::FNM_DOTMATCH) do |f|
        puts f

        file = File.open(f)
        source = file.read
        file.close

        if source =~ YAML_FRONT_MATTER_REGEXP
            data, content = YAML.load($1), Regexp.last_match.post_match
            ["id", "guid",
            "ep_tilt_migration",
            "classic-editor-remember",
            "ssb_old_counts",
            "ssb_total_counts",
            "ssb_cache_timestamp",
            "colormag_page_layout",
            "wp_featherlight_disable",
            "catchbox-sidebarlayout",
            "complete_open_graph"].each {|x| data.delete(x)}

            file = File.open(f, "w")
            YAML.dump(data, file)
            file.puts("---", content)
            file.close
        end
    end

