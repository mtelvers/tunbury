---
layout: post
title:  "How To GitHub"
date:   2020-02-25 13:41:29 +0100
categories: juniper
image:
  path: /images/GitHub-Mark-120px-plus.png
  thumbnail: /images/thumbs/GitHub-Mark-120px-plus.png
---
I really don’t use GitHub often enough to remember the commands without searching for them each time, which means that I use GitHub even less as I can’t remember the commands. Here’s a short cheat sheet on the most common things I need to do in GitHub.

Navigate to your project folder then create a repository for that directory

    git init

Add all the files in the current directory to the Git index. Of course you can be more selective here and iteratively add files one at a time

    git add .

The current status can be checked at any time using

    git status

Now commit the files in their current state to the repository with whatever comment is appropriate

    git commit -m "Initial commit"

You may well be problem to set your global username and email if you’ve not done it before:

    git config --global user.email "you@yourdomain.com"
    git config --global user.name "Your Name"

At some time later after you have made changes you need to add the changed files again and commit or do a combined add/commit like this

    git commit -a -m "great new code added"

To see the current changes compared to the repository

    git diff

And finally if things went south you can commit the current state and then revert to the last commit point

    git commit -a -m "Oops"
    git revert HEAD --no-edit

Working Online
==============

That’s all very well and I could continue to work like that but I want to keep a copy at GitHub so create an RSA key for authentication

    ssh-keygen -t rsa -b 4096 -C "you@yourdomain.com"

Add this key to your SSH Agent

    ssh-add ~/.ssh/id_rsa

Sign in to GitHub and copy and paste the public key into the SSH and GPG Keys section

    cat ~/.ssh/id_rsa.pub

Create an empty repository on the website. Note the SSH address and add it as a remote repository on your local system

    git remote add origin git@github.com:username/project.git

And then push your local copy to GitHub

    git push -u origin master
