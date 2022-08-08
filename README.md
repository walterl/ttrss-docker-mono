# ttrss-docker-mono

A single container running all tt-rss services, except the database.

Based on the [official tt-rss Docker setup](https://git.tt-rss.org/fox/ttrss-docker-compose.git/).

## Usage

    docker run --name ttrss \
        -p 1080 \
        -e TTRSS_DB_HOST=db.example.org \
        -e TTRSS_DB_NAME=ttrss \
        -e TTRSS_DB_USER=ttrss \
        -e TTRSS_DB_PASS=hunter2 \
        -e TTRSS_SELF_URL_PATH=http://ttrss.example.org \
        -e ADMIN_USER_PASS=l3tmein \
        walt3rl/ttrss

**[NOTE]**: If `ADMIN_USER_PASS` is not specified, a random password will be
generated and logged to the container's stdout.

**[NOTE]** Use better passwords than those above!

## Development

See `Makefile` and/or `docker-compose.yml`.

## Why?

The [official tt-rss Docker setup](https://git.tt-rss.org/fox/ttrss-docker-compose.git/) spins up 5 different containers for running
tt-rss's components. Besides being a bit excessive, this configuration imposes
the requirement that your tt-rss database be managed by this docker-compose
setup.

I wanted a single container solution, that it can easily be used with an
existing database.

Along the way I added a few tweaks and niceties too.

## Thanks
- [uvatbc/docker-ttrss](https://github.com/uvatbc/docker-ttrss) that served me well for a long time.

## License
[MIT](./LICENSE)
