# DDEV Blueprint quick reference

## Generate a new project baseline

    ./init-project.sh ~/projects/my-app
    cd ~/projects/my-app
    ddev start

## Preview without writing

    ./init-project.sh --dry-run ~/projects/my-app

## Generate from an answers file

    ./init-project.sh --answers examples/answers.yaml ~/projects/my-app
    ./init-project.sh --dry-run --answers examples/answers.yaml ~/projects/my-app

Answers mode is non-interactive and requires Python 3 with PyYAML. See
[examples/answers.yaml](../examples/answers.yaml) for the complete schema.

## Generator help and version

    ./init-project.sh --help
    ./init-project.sh --version

## Common DDEV commands

    ddev describe
    ddev logs -f
    ddev ssh
    ddev php -v
    ddev composer install
    ddev import-db --file=backup.sql.gz
    ddev export-db --file=backup.sql.gz

## Generated Makefile

    make help
    make start
    make composer-install

`make help` lists only targets available for the generated project.
The generated Makefile is host-side because it calls DDEV. Install host `make`
when enabling it:

    sudo apt install make

Do not run these DDEV wrapper targets through `ddev exec make`. The `make`
inside the web image is for project-native commands that must run in the
container.

## Optional debugging

    ddev xdebug on
    ddev xdebug off
    ddev xhgui on
    ddev xhgui launch
