IMAGE=walt3rl/ttrss:dev
DEV_CONTAINER_NAME=ttrss-dev
LOCAL_PORT=20080

build:
	docker build -t $(IMAGE) .

run:
	docker run -it --rm \
		--name $(DEV_CONTAINER_NAME) \
		-p $(LOCAL_PORT):80 \
		-e TTRSS_DB_HOST=172.17.0.1 \
		-e TTRSS_DB_NAME=ttrss \
		-e TTRSS_DB_USER=postgres \
		-e TTRSS_DB_PASS=hunter2 \
		-e TTRSS_SELF_URL_PATH=http://127.0.0.1:$(LOCAL_PORT) \
		$(IMAGE)

shell:
	docker exec -it $(DEV_CONTAINER_NAME) /bin/sh

up:
	docker-compose up

down:
	-docker-compose down
