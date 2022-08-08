include .env

DEV_CONTAINER_NAME=ttrss-dev

build:
	docker build -t walt3rl/ttrss:$(TAG) .

run:
	docker run -it --rm \
		--name $(DEV_CONTAINER_NAME) \
		-p $(LOCAL_PORT):80 \
		-e TTRSS_DB_HOST=$(TTRSS_DB_HOST) \
		-e TTRSS_DB_NAME=$(TTRSS_DB_NAME) \
		-e TTRSS_DB_USER=$(TTRSS_DB_USER) \
		-e TTRSS_DB_PASS=$(TTRSS_DB_PASS) \
		-e TTRSS_SELF_URL_PATH=http://127.0.0.1:$(LOCAL_PORT) \
		walt3rl/ttrss:$(TAG)

shell:
	docker exec -it $(DEV_CONTAINER_NAME) /bin/sh

up:
	docker-compose up

down:
	-docker-compose down
